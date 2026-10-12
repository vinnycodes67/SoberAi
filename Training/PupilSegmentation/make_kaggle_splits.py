"""
Splits the prepared Kaggle eye set into two subject-disjoint sets:

- `kaggle_select`: 25 subjects, drawn with a fixed seed. Scored during
  training (`train_phone.py --cross-select`) so checkpoint choice can see a
  camera, framing and pupil-size range OpenEDS does not have.
- `kaggle_test`: the other subjects. Only ever used for the final comparison.

Run 4's report scored all 85 subjects as `kaggle_cross`; numbers on
`kaggle_test` are not directly comparable with it.

    python3 make_kaggle_splits.py --src data/kaggle
"""

from __future__ import annotations

import argparse
import os

import numpy as np

from dataset import shard_paths

SELECT_SUBJECTS = 25


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--src", required=True)
    p.add_argument("--seed", type=int, default=0)
    args = p.parse_args()

    shards = [dict(np.load(path)) for path in shard_paths(args.src)]
    subjects = sorted({int(s) for d in shards for s in d["subjects"]})
    chosen = set(np.random.default_rng(args.seed).choice(subjects, SELECT_SUBJECTS, replace=False).tolist())
    root = os.path.dirname(args.src.rstrip("/"))
    for name, keep in (("kaggle_select", lambda s: s in chosen), ("kaggle_test", lambda s: s not in chosen)):
        out = os.path.join(root, name)
        os.makedirs(out, exist_ok=True)
        frames = 0
        for i, d in enumerate(shards):
            mask = np.array([keep(int(s)) for s in d["subjects"]])
            if mask.any():
                np.savez_compressed(os.path.join(out, f"shard_{i:03d}.npz"), **{k: v[mask] for k, v in d.items()})
                frames += int(mask.sum())
        print(f"{name}: {frames} frames, {len(chosen) if name == 'kaggle_select' else len(subjects) - len(chosen)} subjects")


if __name__ == "__main__":
    main()
