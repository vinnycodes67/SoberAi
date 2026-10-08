"""
OpenEDS2020 semantic-segmentation frames, from the compact `.npz` files that
`prepare_data.py` writes. Each sample is a 640x400 grayscale eye image plus a
same-size label map with 4 classes: 0=background, 1=sclera, 2=iris, 3=pupil —
the same convention RITnet was trained on (OpenEDS2019), so the pretrained
backbone applies directly without a label remap at this layer (the
background/sclera merge happens in model.py, after the network).

Frames are held in memory as uint8 and converted per item. The previous
version stored float32 images and int64 labels — 3 MB a frame, not the
"~350MB for 1,348 frames" its docstring claimed but about 4 GB, doubled
briefly by `torch.stack`. That was already near the limit of an 8 GB machine
at 4 shards and ruled out training on more. uint8 is 512 KB a frame, and the
arrays are preallocated so there is no stacking peak.
"""
import glob
import os

import numpy as np
import torch
from torch.utils.data import Dataset


def shard_paths(prepared_dir: str) -> list[str]:
    paths = sorted(glob.glob(os.path.join(prepared_dir, "shard_*.npz")))
    if not paths:
        raise FileNotFoundError(
            f"no prepared shards in {prepared_dir}; run prepare_data.py first")
    return paths


def subjects_in(prepared_dir: str) -> set[int]:
    found = set()
    for path in shard_paths(prepared_dir):
        with np.load(path) as data:
            found |= set(data["subjects"].tolist())
    return found


class OpenEDSSegmentationDataset(Dataset):
    """Frames from one prepared directory, optionally filtered by subject.

    `include` keeps only those subjects; `exclude` drops them. Filtering is by
    subject, never by frame, so a split built from these cannot leak one
    person's eye into both sides.
    """

    def __init__(self, prepared_dir: str, include=None, exclude=None):
        include = set(include) if include is not None else None
        exclude = set(exclude or ())

        def keep(subjects: np.ndarray) -> np.ndarray:
            mask = np.ones(len(subjects), dtype=bool)
            if include is not None:
                mask &= np.isin(subjects, list(include))
            if exclude:
                mask &= ~np.isin(subjects, list(exclude))
            return mask

        paths = shard_paths(prepared_dir)
        total, height, width = 0, None, None
        for path in paths:
            with np.load(path) as data:
                total += int(keep(data["subjects"]).sum())
                height, width = data["images"].shape[1:3]

        self.images = np.empty((total, height, width), dtype=np.uint8)
        self.labels = np.empty((total, height, width), dtype=np.uint8)
        self.subjects = np.empty(total, dtype=np.int32)

        cursor = 0
        for path in paths:
            with np.load(path) as data:
                selected = keep(data["subjects"])
                count = int(selected.sum())
                if count == 0:
                    continue
                self.images[cursor:cursor + count] = data["images"][selected]
                self.labels[cursor:cursor + count] = data["masks"][selected]
                self.subjects[cursor:cursor + count] = data["subjects"][selected]
                cursor += count

    @property
    def subject_set(self) -> set[int]:
        return set(self.subjects.tolist())

    def __len__(self) -> int:
        return len(self.subjects)

    def __getitem__(self, idx: int):
        image = torch.from_numpy(self.images[idx].astype(np.float32) / 255.0).unsqueeze(0)
        label = torch.from_numpy(self.labels[idx].astype(np.int64))
        return image, label
