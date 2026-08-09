"""
Wraps RITnet's DenseNet2D with a preprocessing pipeline that's fully
expressible as standard conv/pool ops so the *entire* pipeline — not just
the segmentation network — traces cleanly to Core ML and runs on-device.

RITnet's original preprocessing (dataset.py in vendor_ritnet/) is gamma
correction (power 0.8) -> OpenCV CLAHE (clipLimit=1.5, tileGridSize=8x8)
-> normalize(mean=0.5, std=0.5). CLAHE itself has no Core ML equivalent
(it's a classical per-tile histogram algorithm, not a fixed graph of
tensor ops), so `LocalContrastNormalize` below approximates its effect —
local mean/variance normalization over a fixed-size window — using only
avg_pool2d, which *does* trace to Core ML. Fine-tuning (train.py) runs
with this exact substitute so the network adapts to it rather than to
real CLAHE; evaluate.py and export_coreml.py use the same module, so the
reported accuracy numbers reflect what actually ships, not a nicer
pipeline that gets swapped out at export time.
"""

import torch
import torch.nn as nn
import torch.nn.functional as F

from vendor_ritnet.densenet import DenseNet2D


class LocalContrastNormalize(nn.Module):
    """Approximates CLAHE's local contrast boost with a fixed-window local
    mean/std normalization — every op here is a standard conv/pool, so it
    traces to Core ML without a custom layer."""

    def __init__(self, kernel_size: int = 41):
        super().__init__()
        self.kernel_size = kernel_size
        self.padding = kernel_size // 2

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        local_mean = F.avg_pool2d(
            x, self.kernel_size, stride=1, padding=self.padding, count_include_pad=False
        )
        local_sq_mean = F.avg_pool2d(
            x * x, self.kernel_size, stride=1, padding=self.padding, count_include_pad=False
        )
        local_var = (local_sq_mean - local_mean * local_mean).clamp(min=1e-6)
        local_std = local_var.sqrt()
        normalized = (x - local_mean) / (local_std + 0.15)
        return normalized.clamp(-3.0, 3.0) / 3.0


class GammaCorrect(nn.Module):
    """RITnet's fixed gamma=0.8 power-law LUT, expressed as a tensor op on
    a [0, 1]-range input instead of a 0-255 lookup table."""

    def __init__(self, gamma: float = 0.8):
        super().__init__()
        self.gamma = gamma

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return x.clamp(min=0.0).pow(self.gamma)


class PupilSegmentationModel(nn.Module):
    """End-to-end: grayscale [0,1] image in, 3-channel class score map out.

    Output channel order is (background, iris, pupil) — RITnet/OpenEDS
    natively has 4 classes (background, sclera, iris, pupil); background
    and sclera are merged here (after softmax, so probabilities merge
    correctly rather than raw logits) to match the 3-class contract
    Sober/Services/PupilCaptureService.swift already expects, so no Swift
    changes are needed to consume this model.
    """

    def __init__(self):
        super().__init__()
        self.gamma = GammaCorrect(0.8)
        self.local_contrast = LocalContrastNormalize(kernel_size=21)
        self.backbone = DenseNet2D(in_channels=1, out_channels=4, channel_size=32, dropout=False, prob=0)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.gamma(x)
        x = self.local_contrast(x)
        # RITnet's own final normalize(mean=0.5, std=0.5) on top of the
        # [-1, 1]-ish local-contrast output.
        x = (x - 0.5) / 0.5
        logits = self.backbone(x)  # (B, 4, H, W): background, sclera, iris, pupil
        probs = F.softmax(logits, dim=1)
        background = probs[:, 0:1] + probs[:, 1:2]
        iris = probs[:, 2:3]
        pupil = probs[:, 3:4]
        return torch.cat([background, iris, pupil], dim=1)

    def load_pretrained_backbone(self, path: str, map_location: str = "cpu") -> None:
        state_dict = torch.load(path, map_location=map_location, weights_only=False)
        if hasattr(state_dict, "state_dict"):
            state_dict = state_dict.state_dict()
        self.backbone.load_state_dict(state_dict)
