"""
Splits the prepared OpenEDS2020 `val` shards into two subject-disjoint sets:

- `val_test`: shards 0-3, the frames the shipped model's published numbers
  (iris 0.9490, pupil 0.9730 for Core ML, every 4th frame) were measured on.
  Only ever used for the final comparison.
- `val_select`: every other val shard, minus any subject that also appears in
  `val_test`. Used to pick a checkpoint, so picking never sees the test set.

Shards are linked, not copied. A subject split across the boundary is dropped
from the selection side by writing a filtered copy of that one shard.

    python3 make_val_splits.py --val /tmp/openeds_prepared/val
"""

from __future__ import annotations

import argparse
import os

import numpy as np

from dataset import shard_paths

TEST_SHARDS = 4


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--val", default="/tmp/openeds_prepared/val")
    args = p.parse_args()

    paths = shard_paths(args.val)
    root = os.path.dirname(args.val.rstrip("/"))
    test_dir, select_dir = os.path.join(root, "val_test"), os.path.join(root, "val_select")
    os.makedirs(test_dir, exist_ok=True)
    os.makedirs(select_dir, exist_ok=True)

    test_subjects: set[int] = set()
    for path in paths[:TEST_SHARDS]:
        with np.load(path) as data:
            test_subjects |= set(data["subjects"].tolist())
        link = os.path.join(test_dir, os.path.basename(path))
        if not os.path.exists(link):
            os.symlink(path, link)

    select_subjects: set[int] = set()
    dropped = 0
    for path in paths[TEST_SHARDS:]:
        target = os.path.join(select_dir, os.path.basename(path))
        with np.load(path) as data:
            keep = ~np.isin(data["subjects"], list(test_subjects))
            if keep.all():
                if not os.path.exists(target):
                    os.symlink(path, target)
            else:
                dropped += int((~keep).sum())
                np.savez_compressed(target, **{k: data[k][keep] for k in data.files})
            select_subjects |= set(data["subjects"][keep].tolist())

    assert not (test_subjects & select_subjects)
    print(f"val_test: {TEST_SHARDS} shards, {len(test_subjects)} subjects -> {test_dir}")
    print(f"val_select: {len(paths) - TEST_SHARDS} shards, {len(select_subjects)} subjects, "
          f"{dropped} frames dropped for overlapping the test subjects -> {select_dir}")


if __name__ == "__main__":
    main()
