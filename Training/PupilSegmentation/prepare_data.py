"""Download OpenEDS2020 shards and convert them to compact local arrays.

Replaces the dependency on `mosaicml-streaming`, whose top-level import pulls
in `transformers` — gigabytes of packages to read a simple file format. MDS
is documented and small: a shard is a sample count, an offset table, then each
sample as (sizes of its variable-width columns, then the columns). This reads
it directly, the same way `streaming.base.format.mds.reader` does.

Each shard is decompressed in memory, only frames that carry a segmentation
mask are kept, and the result is written as one `.npz` of uint8 arrays. The
downloaded shard is then discarded. A decompressed MDS shard is ~133 MB and
this dataset has 65 of them; the compact form keeps the same pixels and labels
in a fraction of that, which is what makes more than a handful of shards
usable on a laptop.

    python3 prepare_data.py --split train --shards 0-9
    python3 prepare_data.py --split val --shards 0-3
"""

import argparse
import io
import json
import os
import sys
import time
import urllib.request

import numpy as np
import zstandard
from PIL import Image

REPO = "https://huggingface.co/datasets/phorosyne/OpenEDS_2020_Shards/resolve/main"

# MDS `ndarray` value dtype codes and shape dtype codes, as written by
# streaming.base.format.mds.encodings.NDArray.
_VALUE_DTYPES = {
    8: "uint8", 9: "int8", 16: "uint16", 17: "int16", 18: "float16",
    32: "uint32", 33: "int32", 34: "float32", 64: "uint64", 65: "int64", 66: "float64",
}
_SHAPE_DTYPES = {0: "uint8", 1: "uint16", 2: "uint32", 3: "uint64"}


def decode_ndarray(data: bytes) -> np.ndarray:
    """Dynamic dtype, dynamic shape: [dtype:1][ndim<<2|shape dtype:1][shape][values]."""
    dtype = np.dtype(_VALUE_DTYPES[data[0]])
    ndim, shape_code = data[1] >> 2, data[1] & 3
    shape_dtype = np.dtype(_SHAPE_DTYPES[shape_code])
    shape_end = 2 + ndim * shape_dtype.itemsize
    shape = tuple(int(v) for v in np.frombuffer(data[2:shape_end], shape_dtype))
    return np.frombuffer(data[shape_end:], dtype).reshape(shape)


def decode_column(encoding: str, data: bytes):
    if encoding == "int":
        return int(np.frombuffer(data, np.int64)[0])
    if encoding == "bytes":
        return data
    if encoding == "ndarray":
        return decode_ndarray(data)
    raise ValueError(f"unsupported MDS encoding: {encoding}")


def iter_samples(shard: bytes, info: dict):
    names, encodings, sizes = info["column_names"], info["column_encodings"], info["column_sizes"]
    count = int(np.frombuffer(shard[:4], np.uint32)[0])
    offsets = np.frombuffer(shard[4:4 + (count + 1) * 4], np.uint32)
    for i in range(count):
        data = shard[offsets[i]:offsets[i + 1]]
        widths, cursor = [], 0
        for size in sizes:
            if size:
                widths.append(size)
            else:
                widths.append(int(np.frombuffer(data[cursor:cursor + 4], np.uint32)[0]))
                cursor += 4
        sample = {}
        for name, encoding, width in zip(names, encodings, widths):
            sample[name] = decode_column(encoding, data[cursor:cursor + width])
            cursor += width
        yield sample


def fetch(url: str, attempts: int = 4) -> bytes:
    """Retries, because one stalled read of a 48 MB shard would otherwise end
    a run that has already prepared everything before it."""
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(url, timeout=120) as response:
                return response.read()
        except (TimeoutError, OSError) as error:
            if attempt == attempts:
                raise
            wait = 5 * attempt
            print(f"  fetch failed ({error}); retrying in {wait}s", flush=True)
            time.sleep(wait)


def prepare_shard(index: int, info: dict, out_dir: str, split: str, size=(640, 400)) -> str:
    path = os.path.join(out_dir, f"shard_{index:05d}.npz")
    if os.path.exists(path):
        return path

    compressed = fetch(f"{REPO}/{split}/{info['zip_data']['basename']}")
    shard = zstandard.ZstdDecompressor().decompress(
        compressed, max_output_size=info["raw_data"]["bytes"])
    del compressed

    images, masks, subjects, frames = [], [], [], []
    for sample in iter_samples(shard, info):
        if not sample["has_mask"]:
            continue
        image = Image.open(io.BytesIO(sample["image"])).convert("L")
        if image.size != size:
            image = image.resize(size, Image.BILINEAR)
        mask = np.asarray(sample["mask"], dtype=np.uint8)
        if mask.shape != (size[1], size[0]):
            mask = np.asarray(Image.fromarray(mask).resize(size, Image.NEAREST))
        images.append(np.asarray(image, dtype=np.uint8))
        masks.append(mask)
        subjects.append(sample["subject"])
        frames.append(sample["frame_idx"])
    del shard

    tmp = path + ".tmp.npz"
    np.savez_compressed(
        tmp,
        images=np.stack(images) if images else np.zeros((0, size[1], size[0]), np.uint8),
        masks=np.stack(masks) if masks else np.zeros((0, size[1], size[0]), np.uint8),
        subjects=np.asarray(subjects, np.int32),
        frames=np.asarray(frames, np.int32),
    )
    os.replace(tmp, path)
    return path


def parse_range(spec: str) -> list[int]:
    result = []
    for part in spec.split(","):
        if "-" in part:
            low, high = part.split("-")
            result.extend(range(int(low), int(high) + 1))
        else:
            result.append(int(part))
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--shards", default="0-3", help="e.g. 0-11 or 0,2,5")
    parser.add_argument("--split", default="train", choices=["train", "val"])
    parser.add_argument("--out", default=None, help="defaults to /tmp/openeds_prepared/<split>")
    args = parser.parse_args()

    args.out = args.out or f"/tmp/openeds_prepared/{args.split}"
    os.makedirs(args.out, exist_ok=True)
    index = json.loads(fetch(f"{REPO}/{args.split}/index.json"))
    shards = index["shards"]

    for i in parse_range(args.shards):
        path = prepare_shard(i, shards[i], args.out, args.split)
        with np.load(path) as data:
            subjects = sorted(set(data["subjects"].tolist()))
            print(f"shard {i:2d}: {len(data['subjects']):4d} masked frames, "
                  f"subjects {subjects}, {os.path.getsize(path) / 1e6:.0f} MB", flush=True)


if __name__ == "__main__":
    sys.exit(main())
