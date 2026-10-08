"""
Degradations that make OpenEDS frames look more like what Sober feeds the
model on a phone.

OpenEDS is sharp near-infrared footage from a headset camera a few
centimetres from the eye. On an iPhone, `PupilCaptureService` finds the eye
with Vision landmarks in a front-camera frame, crops it with a 30% margin and
scales that crop to 640x400 (`scaleFill`, so the aspect ratio stretches). At
arm's length the eye is perhaps 80-250 px wide in the frame, so the model sees
a heavily upscaled, noisy, compressed crop. In visible light a dark iris is
nearly as dark as the pupil, which never happens in infrared.

None of this turns infrared into visible light. It trains the network not to
depend on what only infrared and a close-up camera give it: fine texture, a
bright iris, and a sharp pupil edge. Whether that transfers to real iPhone
captures still has to be measured on real iPhone captures.

Two families live here:

- `augment_batch`: random, batched, on-device training augmentation. Labels
  follow every geometric change; photometric changes never touch labels.
- `PERTURBATIONS`: fixed-severity, deterministic test conditions for
  `benchmark.py`. Two of them (JPEG and defocus) are deliberately never used
  in training, so the benchmark also measures conditions the model has not
  been taught.

Labels use the OpenEDS convention: 0 background, 1 sclera, 2 iris, 3 pupil.
Images are float tensors in [0, 1], shape (B, 1, H, W).
"""

from __future__ import annotations

import io
import math

import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image

IRIS, PUPIL = 2, 3


# MARK: - Building blocks (all batched, all differentiable-free)


def _gaussian_kernel(sigma: float, device) -> torch.Tensor:
    radius = max(1, int(math.ceil(3 * sigma)))
    x = torch.arange(-radius, radius + 1, device=device, dtype=torch.float32)
    k = torch.exp(-(x ** 2) / (2 * sigma ** 2))
    return k / k.sum()


def gaussian_blur(img: torch.Tensor, sigma: float) -> torch.Tensor:
    if sigma <= 0.05:
        return img
    k = _gaussian_kernel(sigma, img.device)
    r = (k.numel() - 1) // 2
    img = F.conv2d(F.pad(img, (r, r, 0, 0), mode="replicate"), k.view(1, 1, 1, -1))
    return F.conv2d(F.pad(img, (0, 0, r, r), mode="replicate"), k.view(1, 1, -1, 1))


def motion_blur(img: torch.Tensor, length: int, angle_deg: float) -> torch.Tensor:
    if length <= 1:
        return img
    size = length if length % 2 else length + 1
    kernel = torch.zeros(size, size, device=img.device)
    c = size // 2
    a = math.radians(angle_deg)
    for t in torch.linspace(-c, c, steps=size * 2):
        x = int(round(c + float(t) * math.cos(a)))
        y = int(round(c + float(t) * math.sin(a)))
        kernel[y, x] = 1.0
    kernel /= kernel.sum()
    return F.conv2d(F.pad(img, (c, c, c, c), mode="replicate"), kernel.view(1, 1, size, size))


def disk_blur(img: torch.Tensor, radius: int) -> torch.Tensor:
    """Defocus. Held out of training."""
    if radius <= 0:
        return img
    y, x = torch.meshgrid(
        torch.arange(-radius, radius + 1, device=img.device),
        torch.arange(-radius, radius + 1, device=img.device),
        indexing="ij",
    )
    kernel = ((x ** 2 + y ** 2) <= radius ** 2).float()
    kernel /= kernel.sum()
    return F.conv2d(
        F.pad(img, (radius,) * 4, mode="replicate"),
        kernel.view(1, 1, 2 * radius + 1, 2 * radius + 1),
    )


def low_resolution(img: torch.Tensor, width: int, noise: float = 0.0,
                   generator: torch.Generator | None = None) -> torch.Tensor:
    """The crop the phone actually has, upscaled back. Sensor noise is added
    at the low resolution, where it happens, so upscaling smears it."""
    _, _, h, w = img.shape
    width = max(16, min(width, w))
    small_h = max(10, int(round(h * width / w)))
    # Anti-alias by hand, then resample: "area" interpolation to arbitrary
    # sizes is not implemented on MPS.
    factor = w / width
    small = F.interpolate(gaussian_blur(img, 0.45 * factor) if factor > 1.5 else img,
                          size=(small_h, width), mode="bilinear", align_corners=False)
    if noise > 0:
        small = add_noise(small, noise, generator)
    return F.interpolate(small, size=(h, w), mode="bilinear", align_corners=False).clamp(0, 1)


def add_noise(img: torch.Tensor, sigma: float, generator: torch.Generator | None = None) -> torch.Tensor:
    """Read noise plus shot noise that grows with brightness."""
    if sigma <= 0:
        return img
    n = torch.randn(img.shape, generator=generator, device="cpu").to(img.device)
    std = sigma * (0.4 + 0.6 * img.clamp(0, 1).sqrt())
    return (img + n * std).clamp(0, 1)


def photometric(img: torch.Tensor, gamma: float, contrast: float, brightness: float) -> torch.Tensor:
    img = img.clamp(1e-4, 1).pow(gamma)
    mean = img.mean(dim=(2, 3), keepdim=True)
    return ((img - mean) * contrast + mean + brightness).clamp(0, 1)


def darken_iris(img: torch.Tensor, labels: torch.Tensor, amount: float) -> torch.Tensor:
    """Visible light: a brown iris is nearly as dark as the pupil. Pulls iris
    pixels towards the pupil's mean brightness, with a softened edge so the
    network cannot find the boundary from a hard seam."""
    if amount <= 0:
        return img
    iris = (labels == IRIS).float().unsqueeze(1)
    pupil = (labels == PUPIL).float().unsqueeze(1)
    pupil_mean = (img * pupil).sum(dim=(2, 3), keepdim=True) / pupil.sum(dim=(2, 3), keepdim=True).clamp(min=1)
    soft = gaussian_blur(iris, 2.0)
    target = img * (1 - amount) + (pupil_mean + 0.08 * (img - img.mean(dim=(2, 3), keepdim=True))) * amount
    return (img * (1 - soft) + target * soft).clamp(0, 1)


def add_glints(img: torch.Tensor, labels: torch.Tensor, count: int,
               generator: torch.Generator, radius_range=(3, 22)) -> torch.Tensor:
    """Specular reflections of a window or screen on the cornea."""
    if count <= 0:
        return img
    b, _, h, w = img.shape
    yy, xx = torch.meshgrid(
        torch.arange(h, device=img.device, dtype=torch.float32),
        torch.arange(w, device=img.device, dtype=torch.float32),
        indexing="ij",
    )
    out = img.clone()
    for i in range(b):
        eye = ((labels[i] == IRIS) | (labels[i] == PUPIL)).nonzero()
        if len(eye) == 0:
            continue
        for _ in range(count):
            p = eye[int(torch.randint(len(eye), (1,), generator=generator))]
            r = float(torch.empty(1).uniform_(*radius_range, generator=generator))
            aspect = float(torch.empty(1).uniform_(0.5, 1.5, generator=generator))
            d = ((yy - p[0]) / (r * aspect)) ** 2 + ((xx - p[1]) / r) ** 2
            # Solid core out to the radius, then a short soft edge.
            spot = ((1.3 - d) / 0.6).clamp(0, 1) * float(
                torch.empty(1).uniform_(0.6, 1.0, generator=generator))
            out[i, 0] = torch.maximum(out[i, 0], spot)
    return out


def jpeg(img: torch.Tensor, quality: int) -> torch.Tensor:
    """Compression. Held out of training; CPU, so benchmark use only."""
    out = []
    for frame in img.detach().cpu():
        buf = io.BytesIO()
        Image.fromarray((frame[0].numpy() * 255).round().astype(np.uint8)).save(
            buf, format="JPEG", quality=quality)
        buf.seek(0)
        out.append(torch.from_numpy(np.asarray(Image.open(buf), dtype=np.float32) / 255.0))
    return torch.stack(out).unsqueeze(1).to(img.device)


def reframe(img: torch.Tensor, labels: torch.Tensor, scale, aspect, shift, rotation_deg, flip):
    """Re-crops each frame the way a landmark-driven crop would: a wider or
    tighter box, a different aspect ratio stretched back to 640x400, a little
    rotation, and either eye. Per-sample parameters are 1-D tensors."""
    b, _, h, w = img.shape
    theta = torch.zeros(b, 2, 3, device=img.device)
    rot = torch.deg2rad(rotation_deg)
    sx = scale * aspect.sqrt()
    sy = scale / aspect.sqrt()
    sx = torch.where(flip, -sx, sx)
    theta[:, 0, 0] = sx * torch.cos(rot)
    theta[:, 0, 1] = -sy * torch.sin(rot)
    theta[:, 1, 0] = sx * torch.sin(rot)
    theta[:, 1, 1] = sy * torch.cos(rot)
    theta[:, :, 2] = shift
    grid = F.affine_grid(theta, (b, 1, h, w), align_corners=False)
    # Reflection rather than border padding: border smears the edge row into
    # long streaks the network could learn to key on.
    img = F.grid_sample(img, grid, mode="bilinear", padding_mode="reflection", align_corners=False)
    lab = F.grid_sample(labels.unsqueeze(1).float(), grid, mode="nearest",
                        padding_mode="reflection", align_corners=False)
    return img, lab.squeeze(1).round().long()


# MARK: - Training augmentation


def augment_batch(img: torch.Tensor, labels: torch.Tensor, generator: torch.Generator,
                  p: float = 0.7) -> tuple[torch.Tensor, torch.Tensor]:
    """Each frame is left clean with probability 1 - p, so the network keeps
    its accuracy on clean input. Otherwise a random subset of degradations is
    applied in capture order: framing, optics, sensor, scene."""
    b = img.shape[0]
    rand = lambda *size: torch.rand(size, generator=generator)  # noqa: E731
    active = rand(b) < p
    if not active.any():
        return img, labels
    idx = active.nonzero().squeeze(1).to(img.device)
    x, y = img[idx], labels[idx]
    n = x.shape[0]

    if float(rand(1)) < 0.8:
        x, y = reframe(
            x, y,
            scale=(0.75 + 0.5 * rand(n)).to(x.device),
            aspect=(0.7 + 0.8 * rand(n)).to(x.device),
            shift=((rand(n, 2) - 0.5) * 0.3).to(x.device),
            rotation_deg=((rand(n) - 0.5) * 20).to(x.device),
            flip=(rand(n) < 0.5).to(x.device),
        )
    if float(rand(1)) < 0.5:
        x = darken_iris(x, y, float(0.2 + 0.65 * rand(1)))
    if float(rand(1)) < 0.4:
        x = add_glints(x, y, int(1 + 2 * rand(1)), generator)
    if float(rand(1)) < 0.8:
        x = photometric(
            x,
            gamma=float(torch.exp((rand(1) - 0.5) * 1.4)),
            contrast=float(0.5 + 0.8 * rand(1)),
            brightness=float((rand(1) - 0.5) * 0.3),
        )
    if float(rand(1)) < 0.45:
        if float(rand(1)) < 0.5:
            x = gaussian_blur(x, float(0.5 + 2.0 * rand(1)))
        else:
            x = motion_blur(x, int(3 + 10 * rand(1)), float(180 * rand(1)))
    if float(rand(1)) < 0.75:
        x = low_resolution(x, int(90 + 230 * rand(1)), noise=float(0.06 * rand(1)), generator=generator)
    elif float(rand(1)) < 0.5:
        x = add_noise(x, float(0.05 * rand(1)), generator)

    img = img.clone()
    labels = labels.clone()
    img[idx] = x
    labels[idx] = y
    return img, labels


# MARK: - Fixed benchmark conditions


def _seeded(frame_seed: int) -> torch.Generator:
    return torch.Generator().manual_seed(frame_seed)


def _phone_combo(x, y, seed):
    g = _seeded(seed)
    n = x.shape[0]
    x, y = reframe(
        x, y,
        scale=torch.full((n,), 1.1, device=x.device),
        aspect=torch.full((n,), 1.25, device=x.device),
        shift=torch.zeros(n, 2, device=x.device),
        rotation_deg=torch.full((n,), 4.0, device=x.device),
        flip=torch.zeros(n, dtype=torch.bool, device=x.device),
    )
    x = darken_iris(x, y, 0.5)
    x = low_resolution(x, 150, noise=0.03, generator=g)
    return jpeg(x, 45), y


# name -> (function(images, labels, seed) -> (images, labels), held_out_of_training)
PERTURBATIONS = {
    "clean": (lambda x, y, s: (x, y), False),
    "lowres_200px": (lambda x, y, s: (low_resolution(x, 200), y), False),
    "lowres_120px": (lambda x, y, s: (low_resolution(x, 120), y), False),
    "gaussian_blur_2px": (lambda x, y, s: (gaussian_blur(x, 2.0), y), False),
    "motion_blur_9px": (lambda x, y, s: (motion_blur(x, 9, 30.0), y), False),
    "sensor_noise": (lambda x, y, s: (add_noise(x, 0.04, _seeded(s)), y), False),
    "dark_iris": (lambda x, y, s: (darken_iris(x, y, 0.6), y), False),
    "low_light": (lambda x, y, s: (add_noise(photometric(x, 1.8, 0.7, -0.05), 0.03, _seeded(s)), y), False),
    "overexposed": (lambda x, y, s: (photometric(x, 0.55, 0.8, 0.08), y), False),
    "glints": (lambda x, y, s: (add_glints(x, y, 2, _seeded(s)), y), False),
    "jpeg_q25": (lambda x, y, s: (jpeg(x, 25), y), True),
    "defocus_4px": (lambda x, y, s: (disk_blur(x, 4), y), True),
    "phone_combo": (_phone_combo, False),
}
