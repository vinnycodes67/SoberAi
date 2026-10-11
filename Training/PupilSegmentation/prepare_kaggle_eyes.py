"""
Cleans the Kaggle "Pupil Eye and Iris Segmentation" set into a cross-dataset
test set, written in the same `.npz` shard format as `prepare_data.py`.

Source: kaggle.com/datasets/itguides/pupil-eye-and-iris-segmentation (MIT
licence on Kaggle, 1,275 labelled frames). It is **not** visible light: the
frames are 640x480 near-infrared iris-camera images with a single LED glint,
most likely re-hosted from a CASIA iris database. Its provenance is unclear,
so it is used to *test* only, never to train. Its value is that it is a
different camera, subject pool and framing from OpenEDS -- a whole eye with
lids and lashes, closer to a phone crop than a headset close-up -- so a model
that only memorised OpenEDS shows it here.

Kaggle labels: 0 background, 1 eye region, 2 pupil, 3 iris. Converted to the
OpenEDS convention: 0 background, 1 sclera, 2 iris, 3 pupil.

The labels are noisy, so each frame is cleaned and some are dropped:

- pupil: largest connected component, holes filled (the glint left a hole
  in many pupils), stray "pupil" speckles on eyelashes removed;
- iris: largest component of iris-or-pupil, holes filled, minus the pupil;
- dropped: no pupil, pupil not inside the iris, pupil under 150 px, the
  eye cut by the 640x400 crop, a pupil label that is not disc-like (solidity
  under 0.9, the off-centre crescents), or one that is not dark in the image
  (its mean brightness not clearly below the iris's) -- a label that misses
  the visible pupil scores every model as wrong.

    python3 prepare_kaggle_eyes.py --src "/tmp/datasets/kaggle-pei/x/IRIS + PUPIL + EYE" \\
        --out /tmp/kaggle_eyes
"""

from __future__ import annotations

import argparse
import glob
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

OUT_H, OUT_W = 400, 640


def largest_component(mask: np.ndarray) -> np.ndarray:
    labelled, n = ndimage.label(mask)
    if n == 0:
        return mask
    sizes = ndimage.sum(mask, labelled, range(1, n + 1))
    return labelled == (int(np.argmax(sizes)) + 1)


def solidity(mask: np.ndarray) -> float:
    """Area over convex-hull area; a disc is near 1, a crescent well below."""
    from scipy.spatial import ConvexHull
    ys, xs = np.nonzero(mask)
    if len(xs) < 10:
        return 0.0
    hull = ConvexHull(np.column_stack([xs, ys]))
    return float(mask.sum() / max(hull.volume, 1.0))


def clean(raw: np.ndarray, image: np.ndarray | None = None) -> tuple[np.ndarray | None, str]:
    pupil = largest_component(raw == 2)
    pupil = ndimage.binary_fill_holes(pupil)
    if pupil.sum() < 150:
        return None, "pupil_missing_or_tiny"
    if solidity(pupil) < 0.9:
        return None, "pupil_not_disc_like"
    eye_disc = ndimage.binary_fill_holes(largest_component((raw == 3) | pupil))
    if (pupil & ~eye_disc).sum() > 0.02 * pupil.sum():
        return None, "pupil_outside_iris"
    iris = eye_disc & ~pupil
    if image is not None and iris.sum() > 0:
        # Glints are bright inside a real pupil, so compare medians.
        if np.median(image[pupil]) > 0.75 * np.median(image[iris]):
            return None, "pupil_label_not_dark"
    out = np.zeros(raw.shape, np.uint8)
    out[(raw >= 1)] = 1
    out[iris] = 2
    out[pupil] = 3
    return out, "ok"


def crop_rows(mask: np.ndarray) -> int | None:
    """Top row of a 400-row window centred on the iris, or None if the iris
    would be cut."""
    rows = np.where((mask >= 2).any(axis=1))[0]
    centre = int((rows.min() + rows.max()) / 2)
    top = int(np.clip(centre - OUT_H // 2, 0, mask.shape[0] - OUT_H))
    if rows.min() < top or rows.max() >= top + OUT_H:
        return None
    return top


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--src", required=True)
    p.add_argument("--out", default="/tmp/kaggle_eyes")
    args = p.parse_args()
    os.makedirs(args.out, exist_ok=True)

    images, masks, subjects, frames, reasons = [], [], [], [], {}
    paths = sorted(glob.glob(os.path.join(args.src, "*", "image", "*.png")))
    for i, path in enumerate(paths):
        seg_path = path.replace(f"{os.sep}image{os.sep}", f"{os.sep}segmentation{os.sep}")
        if not os.path.exists(seg_path):
            reasons["no_mask"] = reasons.get("no_mask", 0) + 1
            continue
        image = np.asarray(Image.open(path).convert("L"))
        raw = np.asarray(Image.open(seg_path))
        if image.shape != raw.shape or image.shape[1] != OUT_W:
            reasons["unexpected_size"] = reasons.get("unexpected_size", 0) + 1
            continue
        mask, why = clean(raw, image)
        if mask is None:
            reasons[why] = reasons.get(why, 0) + 1
            continue
        top = crop_rows(mask)
        if top is None:
            reasons["cut_by_crop"] = reasons.get("cut_by_crop", 0) + 1
            continue
        images.append(image[top:top + OUT_H])
        masks.append(mask[top:top + OUT_H])
        subjects.append(int(os.path.basename(path).split("_")[0]))
        frames.append(i)
        reasons["ok"] = reasons.get("ok", 0) + 1

    np.savez_compressed(
        os.path.join(args.out, "shard_00000.npz"),
        images=np.stack(images), masks=np.stack(masks),
        subjects=np.array(subjects, np.int32), frames=np.array(frames, np.int32))
    summary = {"source_frames": len(paths), "kept": len(images),
               "subjects": len(set(subjects)), "reasons": reasons}
    with open(os.path.join(args.out, "summary.json"), "w") as f:
        json.dump(summary, f, indent=2)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
