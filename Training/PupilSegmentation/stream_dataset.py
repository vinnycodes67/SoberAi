"""
Streams prepared shards a few at a time instead of holding them all.

All 65 OpenEDS2020 train shards are about 22,000 masked frames: 11 GB of uint8
images plus 11 GB of labels, more than a 16 GB machine can hold.
`OpenEDSSegmentationDataset` loads everything up front, which is right for the
small evaluation sets and wrong here. This keeps `group` shards in memory
(about 350 MB each), shuffles frames within the group, and reshuffles which
shards are grouped together every epoch.
"""

from __future__ import annotations

import numpy as np
import torch
from torch.utils.data import IterableDataset

from dataset import shard_paths


class ShardStream(IterableDataset):
    def __init__(self, prepared_dir: str, group: int = 3, seed: int = 0,
                 exclude_subjects=()):
        self.paths = shard_paths(prepared_dir)
        self.group = group
        self.seed = seed
        self.epoch = 0
        self.exclude = set(exclude_subjects)
        self._length = 0
        self.subject_set: set[int] = set()
        for path in self.paths:
            with np.load(path) as data:
                subjects = data["subjects"]
                keep = ~np.isin(subjects, list(self.exclude)) if self.exclude else np.ones(len(subjects), bool)
                self._length += int(keep.sum())
                self.subject_set |= set(subjects[keep].tolist())

    def set_epoch(self, epoch: int) -> None:
        self.epoch = epoch

    def __len__(self) -> int:
        return self._length

    def __iter__(self):
        rng = np.random.default_rng(self.seed + 1000 * self.epoch)
        order = rng.permutation(len(self.paths))
        for start in range(0, len(order), self.group):
            images, masks = [], []
            for i in order[start:start + self.group]:
                with np.load(self.paths[i]) as data:
                    keep = (~np.isin(data["subjects"], list(self.exclude))
                            if self.exclude else slice(None))
                    images.append(data["images"][keep])
                    masks.append(data["masks"][keep])
            images = np.concatenate(images)
            masks = np.concatenate(masks)
            for j in rng.permutation(len(images)):
                yield (
                    torch.from_numpy(images[j].astype(np.float32) / 255.0).unsqueeze(0),
                    torch.from_numpy(masks[j].astype(np.int64)),
                )
            del images, masks
