"""
A larger pupil/iris segmentation model: a U-Net decoder on an
ImageNet-pretrained encoder.

Why: the first three runs showed the 249K-parameter RITnet cannot hold clean
OpenEDS accuracy and visible-light accuracy at once. Each source it learned
cost the other. An ImageNet encoder brings general visual features (edges,
discs, texture) learned from a million varied photographs, which is what
cross-camera generalisation needs, and has the capacity to keep both.

Same contract as `model.PupilSegmentationModel`, so the app and the export
script do not change: grayscale [0, 1] in, (B, 3, H, W) probabilities out in
the order background, iris, pupil. Internally the network predicts the four
OpenEDS classes (background, sclera, iris, pupil) and merges sclera into
background after the softmax, so every training set keeps its labels.

Every op is a standard convolution, pooling, bilinear resize or
concatenation, so it traces to Core ML.

Encoders: "mobilenet_v3_large" (about 4M parameters, built for the Neural
Engine) and "resnet18" / "resnet34" (11-21M, stronger features, heavier).
ImageNet weights come from torchvision (BSD licence).
"""

from __future__ import annotations

import torch
import torch.nn as nn
import torch.nn.functional as F
import torchvision

IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)


class _Encoder(nn.Module):
    """Returns feature maps at strides 2, 4, 8, 16, 32."""

    def __init__(self, name: str, pretrained: bool):
        super().__init__()
        self.name = name
        if name.startswith("resnet"):
            ctor = getattr(torchvision.models, name)
            weights = "IMAGENET1K_V1" if pretrained else None
            net = ctor(weights=weights)
            self.stem = nn.Sequential(net.conv1, net.bn1, net.relu)  # /2
            self.pool = net.maxpool
            self.layers = nn.ModuleList([net.layer1, net.layer2, net.layer3, net.layer4])
            base = 64 if name in ("resnet18", "resnet34") else 256
            self.channels = [64, base, base * 2, base * 4, base * 8]
        elif name == "mobilenet_v3_large":
            weights = "IMAGENET1K_V2" if pretrained else None
            feats = torchvision.models.mobilenet_v3_large(weights=weights).features
            # Split points chosen at the stride changes of torchvision's model.
            self.blocks = nn.ModuleList([feats[0:2], feats[2:4], feats[4:7], feats[7:13], feats[13:17]])
            self.channels = [16, 24, 40, 112, 960]
        else:
            raise ValueError(f"unknown encoder {name}")

    def forward(self, x: torch.Tensor) -> list[torch.Tensor]:
        if self.name.startswith("resnet"):
            f1 = self.stem(x)
            f2 = self.layers[0](self.pool(f1))
            f3 = self.layers[1](f2)
            f4 = self.layers[2](f3)
            f5 = self.layers[3](f4)
            return [f1, f2, f3, f4, f5]
        out = []
        for block in self.blocks:
            x = block(x)
            out.append(x)
        return out


class _Up(nn.Module):
    def __init__(self, in_ch: int, skip_ch: int, out_ch: int):
        super().__init__()
        self.conv = nn.Sequential(
            nn.Conv2d(in_ch + skip_ch, out_ch, 3, padding=1, bias=False),
            nn.BatchNorm2d(out_ch),
            nn.ReLU(inplace=True),
            nn.Conv2d(out_ch, out_ch, 3, padding=1, bias=False),
            nn.BatchNorm2d(out_ch),
            nn.ReLU(inplace=True),
        )

    def forward(self, x: torch.Tensor, skip: torch.Tensor) -> torch.Tensor:
        x = F.interpolate(x, size=skip.shape[-2:], mode="bilinear", align_corners=False)
        return self.conv(torch.cat([x, skip], dim=1))


class PupilSegmentationUNet(nn.Module):
    def __init__(self, encoder: str = "mobilenet_v3_large", pretrained: bool = True, width: int = 1):
        super().__init__()
        self.encoder_name = encoder
        self.encoder = _Encoder(encoder, pretrained)
        c = self.encoder.channels
        d = [w * width for w in (256, 128, 64, 32, 24)]
        self.up4 = _Up(c[4], c[3], d[0])
        self.up3 = _Up(d[0], c[2], d[1])
        self.up2 = _Up(d[1], c[1], d[2])
        self.up1 = _Up(d[2], c[0], d[3])
        self.head = nn.Sequential(
            nn.Conv2d(d[3], d[4], 3, padding=1, bias=False),
            nn.BatchNorm2d(d[4]),
            nn.ReLU(inplace=True),
            nn.Conv2d(d[4], 4, 1),
        )
        self.register_buffer("mean", torch.tensor(IMAGENET_MEAN).view(1, 3, 1, 1), persistent=False)
        self.register_buffer("std", torch.tensor(IMAGENET_STD).view(1, 3, 1, 1), persistent=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        size = x.shape[-2:]
        x = (x.expand(-1, 3, -1, -1) - self.mean) / self.std
        f1, f2, f3, f4, f5 = self.encoder(x)
        y = self.up4(f5, f4)
        y = self.up3(y, f3)
        y = self.up2(y, f2)
        y = self.up1(y, f1)
        logits = F.interpolate(self.head(y), size=size, mode="bilinear", align_corners=False)
        probs = F.softmax(logits, dim=1)
        return torch.cat([probs[:, 0:1] + probs[:, 1:2], probs[:, 2:3], probs[:, 3:4]], dim=1)


def build_model(arch: str) -> nn.Module:
    """'ritnet' for the original model, or a U-Net encoder name."""
    if arch == "ritnet":
        from model import PupilSegmentationModel
        return PupilSegmentationModel()
    return PupilSegmentationUNet(encoder=arch)
