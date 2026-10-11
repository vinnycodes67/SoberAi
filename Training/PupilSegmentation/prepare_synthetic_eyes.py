"""
Visible-light training and test frames from synthetic human eyes, prepared
the way the app prepares a real crop.

Source: kaggle.com/datasets/allexmendes/synthetic-human-eyes (CC BY 4.0,
"Synthetic Human Eyes" by allexmendes): 50,000 photorealistic 640x360 renders
of a face around one eye, with pupil / iris / sclera / skin segmentation. Face,
skin, eye material and lighting are randomised per render (domain
randomisation), so each render is effectively a different person.

Why it matters: every real dataset this model has seen is near-infrared, from
one or two cameras. Both models failed on a second infrared camera, and the
app's real input is visible light, where a dark iris is nearly as dark as the
pupil. These renders are the only freely licensed visible-light eye images
with pupil masks available without a signed request.

Each render becomes one frame exactly as `PupilCaptureService` would build it:
the eye opening's bounding box grown by 30% on every side, stretched to
640x400 (Vision's `scaleFill`), red channel boosted (1.6, 0.8, 0.8) and
converted to grayscale with Rec. 601 luma, which is what a grayscale Core ML
image input receives.

Splits are by render id, never shuffled across: ids 0-39,999 train,
40,000-44,999 select, 45,000-49,999 test. Renders with the eye closed or
too small to crop are skipped.

**About 40% of this dataset's masks do not match their render**: an open
eye labelled over a closed lid, or the iris labelled on the wrong side of
the eye. Training on them taught the model wrong answers (pupil IoU on
held-out renders stalled near 0.10). They are caught with physics: in
visible light the sclera is always clearly brighter than the iris and
pupil, so a frame is kept only if the labelled sclera's median brightness
exceeds the labelled iris-and-pupil's by `MIN_SCLERA_CONTRAST`, the
labelled pupil is not brighter than the labelled iris, and the dark part of
the eye opening in the image (Otsu threshold) overlaps the labelled iris and
pupil by at least `MIN_ALIGNMENT` IoU. Contrast alone let through labels
shifted or mirrored relative to the eye; the overlap test catches those. `--filter-existing`
applies the same rule to an already prepared directory.

    python3 prepare_synthetic_eyes.py --zip /tmp/ds-synth/synthetic-human-eyes.zip \\
        --out /tmp/synth_prepared --train 9000 --select 1000 --test 1000
"""

from __future__ import annotations

import argparse
import io
import json
import os
import random
import zipfile

import numpy as np
from PIL import Image

OUT_H, OUT_W = 400, 640
MARGIN = 0.3
SPLITS = {"train": range(0, 40000), "select": range(40000, 45000), "test": range(45000, 50000)}

# Mask palette -> OpenEDS labels (0 background, 1 sclera, 2 iris, 3 pupil).
PALETTE = np.array([
    [0, 158, 204],    # skin
    [255, 255, 255],  # background
    [156, 204, 78],   # sclera
    [41, 141, 132],   # iris (its edge is a soft gradient into the sclera)
    [41, 255, 62],    # pupil
], dtype=np.float32)
PALETTE_LABEL = np.array([0, 0, 1, 2, 3], dtype=np.uint8)


def labels_from_mask(rgb: np.ndarray) -> np.ndarray:
    """Nearest palette colour per pixel, which splits the iris's blurred edge
    at the midpoint between iris and sclera."""
    d = ((rgb[:, :, None, :].astype(np.float32) - PALETTE[None, None]) ** 2).sum(-1)
    return PALETTE_LABEL[d.argmin(-1)]


def app_grayscale(rgb: np.ndarray) -> np.ndarray:
    """`redChannelBoosted` then Rec. 601 luma."""
    f = rgb.astype(np.float32)
    r = np.minimum(f[..., 0] * 1.6, 255)
    g = f[..., 1] * 0.8
    b = f[..., 2] * 0.8
    return np.clip(0.299 * r + 0.587 * g + 0.114 * b, 0, 255).astype(np.uint8)


MIN_SCLERA_CONTRAST = 40
MIN_ALIGNMENT = 0.55


def _otsu(values: np.ndarray) -> int:
    hist, _ = np.histogram(values, bins=256, range=(0, 256))
    p = hist / max(hist.sum(), 1)
    w = np.cumsum(p)
    mu = np.cumsum(p * np.arange(256))
    between = (mu[-1] * w - mu) ** 2 / (w * (1 - w) + 1e-12)
    return int(np.argmax(between))


def label_consistent(gray: np.ndarray, labels: np.ndarray) -> bool:
    sclera, iris, pupil = labels == 1, labels == 2, labels == 3
    eye = iris | pupil
    if sclera.sum() < 200 or eye.sum() < 200:
        return False
    if np.median(gray[sclera]) - np.median(gray[eye]) < MIN_SCLERA_CONTRAST:
        return False
    if pupil.sum() >= 50 and iris.sum() >= 50 and np.median(gray[pupil]) > np.median(gray[iris]) + 10:
        return False
    opening = labels >= 1
    dark = opening & (gray <= _otsu(gray[opening]))
    return (dark & eye).sum() / max((dark | eye).sum(), 1) >= MIN_ALIGNMENT


def filter_existing(src: str, dst: str) -> tuple[int, int]:
    import glob
    os.makedirs(dst, exist_ok=True)
    kept = total = 0
    for path in sorted(glob.glob(os.path.join(src, "shard_*.npz"))):
        with np.load(path) as d:
            arrays = {k: d[k] for k in d.files}
        keep = np.array([label_consistent(i, m) for i, m in zip(arrays["images"], arrays["masks"])])
        total += len(keep); kept += int(keep.sum())
        if keep.any():
            np.savez_compressed(os.path.join(dst, os.path.basename(path)), **{k: v[keep] for k, v in arrays.items()})
    return kept, total


def crop_box(labels: np.ndarray) -> tuple[int, int, int, int] | None:
    ys, xs = np.nonzero(labels >= 1)
    if len(xs) < 1500:
        return None
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    w, h = x1 - x0, y1 - y0
    if w < 60 or h < 20:
        return None
    H, W = labels.shape
    x0 = max(0, int(x0 - MARGIN * w)); x1 = min(W, int(x1 + MARGIN * w))
    y0 = max(0, int(y0 - MARGIN * h)); y1 = min(H, int(y1 + MARGIN * h))
    return x0, y0, x1, y1


def prepare(zf: zipfile.ZipFile, ids: list[int]):
    images, masks, subjects, kept = [], [], [], []
    for i in ids:
        try:
            lit = np.asarray(Image.open(io.BytesIO(zf.read(f"lit/{i:05d}.png"))).convert("RGB"))
            seg = np.asarray(Image.open(io.BytesIO(zf.read(f"segmentation/{i:05d}.png"))).convert("RGB"))
        except KeyError:
            continue
        labels = labels_from_mask(seg)
        box = crop_box(labels)
        if box is None:
            continue
        x0, y0, x1, y1 = box
        gray = np.asarray(Image.fromarray(app_grayscale(lit)[y0:y1, x0:x1]).resize((OUT_W, OUT_H), Image.BILINEAR))
        lab = np.asarray(Image.fromarray(labels[y0:y1, x0:x1]).resize((OUT_W, OUT_H), Image.NEAREST))
        if not label_consistent(gray, lab):
            continue
        images.append(gray); masks.append(lab)
        subjects.append(100000 + i)  # every render is its own synthetic person
        kept.append(i)
    return images, masks, subjects, kept


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--zip", default=None)
    p.add_argument("--filter-existing", nargs=2, metavar=("SRC", "DST"),
                   help="apply the label-consistency rule to an already prepared directory")
    p.add_argument("--out", default="/tmp/synth_prepared")
    p.add_argument("--train", type=int, default=9000)
    p.add_argument("--select", type=int, default=1000)
    p.add_argument("--test", type=int, default=1000)
    p.add_argument("--shard-size", type=int, default=500)
    args = p.parse_args()

    if args.filter_existing:
        kept, total = filter_existing(*args.filter_existing)
        print(f"kept {kept} of {total} frames")
        return

    zf = zipfile.ZipFile(args.zip)
    names = set(zf.namelist())
    rng = random.Random(7)
    summary = {}
    for split, count in (("train", args.train), ("select", args.select), ("test", args.test)):
        pool = [i for i in SPLITS[split] if f"lit/{i:05d}.png" in names]
        # Oversample the pool so skipped renders still leave `count` frames.
        ids = rng.sample(pool, min(len(pool), int(count * 1.4)))
        out_dir = os.path.join(args.out, split)
        os.makedirs(out_dir, exist_ok=True)
        total, shard = 0, 0
        for start in range(0, len(ids), args.shard_size):
            if total >= count:
                break
            images, masks, subjects, kept = prepare(zf, ids[start:start + args.shard_size])
            take = min(len(images), count - total)
            if take == 0:
                continue
            np.savez_compressed(
                os.path.join(out_dir, f"shard_{shard:05d}.npz"),
                images=np.stack(images[:take]), masks=np.stack(masks[:take]),
                subjects=np.array(subjects[:take], np.int32), frames=np.array(kept[:take], np.int32))
            total += take; shard += 1
            print(f"{split}: {total}/{count}", flush=True)
        summary[split] = total
    with open(os.path.join(args.out, "summary.json"), "w") as f:
        json.dump({"source": "kaggle.com/datasets/allexmendes/synthetic-human-eyes (CC BY 4.0)",
                   "frames": summary}, f, indent=2)
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
