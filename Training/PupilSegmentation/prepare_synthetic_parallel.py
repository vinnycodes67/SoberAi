"""
Prepares a range of synthetic render ids in parallel, with the same crop,
grayscale and label checks as `prepare_synthetic_eyes.prepare`.

`prepare_synthetic_eyes.py` samples a fixed count per split on one core; this
takes every id in a range across several processes, which is what the full
40,000-render training split needs (about ten minutes on six cores instead of
an hour and a half).

Ranges must respect the split boundaries in `prepare_synthetic_eyes.SPLITS`:
train 0-39999, select 40000-44999, test 45000-49999.

    python3 prepare_synthetic_parallel.py --zip synthetic-human-eyes.zip \\
        --start 0 --end 40000 --out data/synth/train
"""

import argparse
import os
import zipfile
from multiprocessing import Pool

import numpy as np

from prepare_synthetic_eyes import prepare

ARGS = None


def _work(chunk):
    start, ids = chunk
    zf = zipfile.ZipFile(ARGS.zip)
    images, masks, subjects, kept = prepare(zf, ids)
    if images:
        np.savez_compressed(
            os.path.join(ARGS.out, f"shard_{start:05d}.npz"),
            images=np.stack(images), masks=np.stack(masks),
            subjects=np.array(subjects, np.int32), frames=np.array(kept, np.int32))
    return len(ids), len(images)


def _init(args):
    global ARGS
    ARGS = args


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--zip", required=True)
    p.add_argument("--start", type=int, required=True)
    p.add_argument("--end", type=int, required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--workers", type=int, default=6)
    args = p.parse_args()
    os.makedirs(args.out, exist_ok=True)

    ids = list(range(args.start, args.end))
    chunks = [(i, ids[i - args.start:i - args.start + 500]) for i in range(args.start, args.end, 500)]
    seen = kept = 0
    with Pool(args.workers, initializer=_init, initargs=(args,)) as pool:
        for n, k in pool.imap_unordered(_work, chunks):
            seen += n
            kept += k
            print(f"{seen}/{len(ids)} renders, {kept} kept", flush=True)
    print(f"DONE {kept}")


if __name__ == "__main__":
    main()
