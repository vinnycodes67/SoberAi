"""Checks the augmentations do what `phone_domain.py` says, on synthetic eyes.

    python3 -m pytest test_phone_domain.py -q     (or: python3 test_phone_domain.py)
"""

import torch

from phone_domain import PERTURBATIONS, augment_batch, darken_iris, reframe


def synthetic_eyes(n=4, h=400, w=640):
    yy, xx = torch.meshgrid(torch.arange(h).float(), torch.arange(w).float(), indexing="ij")
    labels = torch.zeros(n, h, w, dtype=torch.long)
    images = torch.full((n, 1, h, w), 0.7)
    for i in range(n):
        cx, cy = 280 + 20 * i, 190 + 5 * i
        d = ((xx - cx) ** 2 + (yy - cy) ** 2).sqrt()
        labels[i][d < 150] = 1
        labels[i][d < 90] = 2
        labels[i][d < 35] = 3
        images[i, 0][labels[i] == 2] = 0.45
        images[i, 0][labels[i] == 3] = 0.05
    return images, labels


def test_augmentation_keeps_range_shape_and_label_values():
    images, labels = synthetic_eyes()
    g = torch.Generator().manual_seed(3)
    for _ in range(20):
        out, lab = augment_batch(images, labels, g, p=1.0)
        assert out.shape == images.shape and lab.shape == labels.shape
        assert out.min() >= 0 and out.max() <= 1 and torch.isfinite(out).all()
        assert set(lab.unique().tolist()) <= {0, 1, 2, 3}


def test_labels_follow_the_image_through_a_reframe():
    """The dark pupil pixels must still be labelled pupil after the warp."""
    images, labels = synthetic_eyes()
    n = images.shape[0]
    out, lab = reframe(
        images, labels,
        scale=torch.full((n,), 0.8), aspect=torch.full((n,), 1.4),
        shift=torch.full((n, 2), 0.1), rotation_deg=torch.full((n,), 8.0),
        flip=torch.tensor([True, False, True, False]),
    )
    dark = out[:, 0] < 0.1
    agreement = (lab[dark] == 3).float().mean()
    assert agreement > 0.97, agreement


def test_photometric_changes_never_touch_labels():
    images, labels = synthetic_eyes()
    darkened = darken_iris(images, labels, 0.8)
    iris = labels == 2
    assert darkened[:, 0][iris].mean() < images[:, 0][iris].mean() - 0.2
    for name in ["sensor_noise", "low_light", "overexposed", "jpeg_q25", "defocus_4px"]:
        _, lab = PERTURBATIONS[name][0](images, labels, 0)
        assert torch.equal(lab, labels), name


def test_benchmark_conditions_are_deterministic():
    images, labels = synthetic_eyes(2)
    for name, (fn, _) in PERTURBATIONS.items():
        a, _ = fn(images, labels, 11)
        b, _ = fn(images, labels, 11)
        assert torch.allclose(a, b), name


def test_clean_fraction_is_respected():
    images, labels = synthetic_eyes(64, 40, 64)
    g = torch.Generator().manual_seed(0)
    out, _ = augment_batch(images, labels, g, p=0.0)
    assert torch.equal(out, images)


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
