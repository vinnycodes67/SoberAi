"""
Loads the OpenEDS2020 (Facebook Research) semantic-segmentation shards
downloaded from the public mirror at
https://huggingface.co/datasets/phorosyne/OpenEDS_2020_Shards (MosaicML
streaming format). Each sample is a 640x400 grayscale eye image plus a
same-size label map with 4 classes: 0=background, 1=sclera, 2=iris,
3=pupil — the same convention RITnet was trained on (OpenEDS2019), so the
pretrained backbone applies directly without a label remap at this layer
(the background/sclera merge happens in model.py, after the network).

Preloads everything into plain in-memory tensors up front (~350MB for
1,348 frames at 400x640) rather than re-decoding JPEG bytes through the
streaming shard reader on every __getitem__ call across every epoch —
that per-sample decode/seek overhead, repeated ~8x for 8 epochs, was the
actual bottleneck in an earlier version of this script, not the model's
own compute.
"""

import io

import numpy as np
import torch
from PIL import Image
from streaming import LocalDataset
from torch.utils.data import Dataset


class OpenEDSSegmentationDataset(Dataset):
    def __init__(self, local_dir: str, image_size: tuple[int, int] = (400, 640), indices=None):
        stream = LocalDataset(local=local_dir)
        self.height, self.width = image_size
        self.subjects: list[int] = []
        images: list[torch.Tensor] = []
        labels: list[torch.Tensor] = []

        index_range = range(len(stream)) if indices is None else indices
        for i in index_range:
            sample = stream[i]
            self.subjects.append(sample["subject"])

            image = Image.open(io.BytesIO(sample["image"])).convert("L")
            if image.size != (self.width, self.height):
                image = image.resize((self.width, self.height), Image.BILINEAR)
            image_array = np.asarray(image, dtype=np.float32) / 255.0
            images.append(torch.from_numpy(image_array).unsqueeze(0))

            mask = sample["mask"]
            if mask.shape != (self.height, self.width):
                mask_image = Image.fromarray(mask).resize((self.width, self.height), Image.NEAREST)
                mask = np.asarray(mask_image)
            labels.append(torch.from_numpy(mask.astype(np.int64)))

        self.images = torch.stack(images)
        self.labels = torch.stack(labels)

    def __len__(self) -> int:
        return self.images.shape[0]

    def __getitem__(self, idx: int):
        return self.images[idx], self.labels[idx]
