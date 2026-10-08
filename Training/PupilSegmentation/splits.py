"""Subject-disjoint train/eval splits, so held-out numbers aren't inflated
by evaluating on the same person's eye seen (nearly identically) during
fine-tuning — different frames of the same subject's eye are highly
correlated.

Two splits:

- **Legacy** — the one the first shipped model was trained and reported on.
  Train shards 0-3 of OpenEDS2020 contain exactly 10 subjects (0, 1, 10,
  101-107) and 1,348 masked frames; subjects 106 and 107 (156 frames) were
  held out. Kept so that model's reported numbers can be reproduced.
- **Official** — train on the dataset's `train` split, evaluate on its `val`
  split. The two contain different people. Evaluating on `val` is also the
  only fair way to compare a new model against the legacy one, because the
  legacy model never saw a `val` subject either.
"""

from dataset import OpenEDSSegmentationDataset, subjects_in

LEGACY_HELD_OUT_SUBJECTS = {106, 107}
# What the shipped legacy model trained on: train shards 0-3 minus the two
# held out. Used to check that an evaluation set is fair to it.
LEGACY_TRAINING_SUBJECTS = {0, 1, 10, 101, 102, 103, 104, 105}


def make_splits(train_dir: str, eval_dir: str | None = None):
    if eval_dir is None:
        train_set = OpenEDSSegmentationDataset(train_dir, exclude=LEGACY_HELD_OUT_SUBJECTS)
        eval_set = OpenEDSSegmentationDataset(train_dir, include=LEGACY_HELD_OUT_SUBJECTS)
    else:
        overlap = subjects_in(train_dir) & subjects_in(eval_dir)
        if overlap:
            raise ValueError(
                f"subjects {sorted(overlap)} appear in both train and eval data; "
                "the split would leak")
        train_set = OpenEDSSegmentationDataset(train_dir)
        eval_set = OpenEDSSegmentationDataset(eval_dir)
    return train_set, eval_set
