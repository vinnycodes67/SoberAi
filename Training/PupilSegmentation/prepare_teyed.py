"""
A held-out test set from a third camera: TEyeD's Dikablis eye tracker.

Source: kaggle.com/datasets/shivanshpachnanda/teyed-reduced, an unofficial
reduced fork of TEyeD (Fuhl et al., 2021) published "for testing eye
segmentation models". Used for exactly that: testing only, never training.
Near-infrared, 384x288, looking up at the eye from below; a different camera,
angle and population from both OpenEDS and the Kaggle iris-camera set.

TEyeD draws iris and pupil as full ellipses, including the parts hidden under
the eyelids. The model labels only what is visible, so both are clipped to the
eye opening (`lid` mask); otherwise every model is penalised for not
predicting iris through skin. Frames are stretched to 640x400 like the app's
crop. Every `--every`th frame of each video is kept; subjects are videos.

    python3 prepare_teyed.py --src /tmp/ds-teyed/raw --out /tmp/teyed_prepared
"""

from __future__ import annotations

import argparse
import glob
import json
import os

import numpy as np
from PIL import Image

OUT_H, OUT_W = 400, 640


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--src", default="/tmp/ds-teyed/raw")
    p.add_argument("--out", default="/tmp/teyed_prepared")
    p.add_argument("--every", type=int, default=2)
    args = p.parse_args()
    os.makedirs(args.out, exist_ok=True)

    images, masks, subjects, frames = [], [], [], []
    skipped = 0
    paths = sorted(glob.glob(os.path.join(args.src, "*.npz")))
    for video_index, path in enumerate(paths):
        with np.load(path) as d:
            video = d["video"]
            iris_all, pupil_all, lid_all = (
                d["iris_seg_2D.mp4_path"], d["pupil_seg_2D.mp4_path"], d["lid_seg_2D.mp4_path"])
            for k in range(0, len(video), args.every):
                lid = lid_all[k] > 0
                pupil = (pupil_all[k] > 0) & lid
                iris = (iris_all[k] > 0) & lid & ~pupil
                if pupil.sum() < 30:
                    skipped += 1  # eye closed or pupil hidden: nothing to score
                    continue
                label = np.zeros(lid.shape, np.uint8)
                label[lid] = 1
                label[iris] = 2
                label[pupil] = 3
                gray = video[k][..., 0] if video[k].ndim == 3 else video[k]
                images.append(np.asarray(Image.fromarray(gray).resize((OUT_W, OUT_H), Image.BILINEAR)))
                masks.append(np.asarray(Image.fromarray(label).resize((OUT_W, OUT_H), Image.NEAREST)))
                subjects.append(200000 + video_index)
                frames.append(int(d["frames"][k]))

    np.savez_compressed(
        os.path.join(args.out, "shard_00000.npz"),
        images=np.stack(images), masks=np.stack(masks),
        subjects=np.array(subjects, np.int32), frames=np.array(frames, np.int32))
    summary = {"videos": len(paths), "frames": len(images), "skipped_no_pupil": skipped,
               "source": "kaggle.com/datasets/shivanshpachnanda/teyed-reduced (testing only)"}
    with open(os.path.join(args.out, "summary.json"), "w") as f:
        json.dump(summary, f, indent=2)
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
