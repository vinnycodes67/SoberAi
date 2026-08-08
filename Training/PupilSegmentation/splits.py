"""Subject-disjoint train/eval split so held-out numbers aren't inflated
by evaluating on the same person's eye seen (nearly identically) during
fine-tuning — different frames of the same subject's eye are highly
correlated."""

from streaming import LocalDataset

from dataset import OpenEDSSegmentationDataset

# 10 subjects are present across the 4 downloaded shards; holding out 2
# entire subjects for eval keeps the split honest at this sample size.
HELD_OUT_SUBJECTS = {106, 107}


def make_splits(local_dir: str):
    stream = LocalDataset(local=local_dir)
    train_indices = []
    eval_indices = []
    for i in range(len(stream)):
        subject = stream[i]["subject"]
        (eval_indices if subject in HELD_OUT_SUBJECTS else train_indices).append(i)

    train_set = OpenEDSSegmentationDataset(local_dir, indices=train_indices)
    eval_set = OpenEDSSegmentationDataset(local_dir, indices=eval_indices)
    return train_set, eval_set
