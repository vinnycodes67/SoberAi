"""
Drops training frames whose labels a trained model clearly disagrees with.

About a quarter of the synthetic renders that pass `prepare_synthetic_eyes`'s
physics checks still have masks that do not match the image: a closed eye
labelled open, or the iris labelled to one side of where it is drawn. The
renderer's own EyeBlink value does not predict which. A model already trained
on visible-light eyes does: where its predicted iris sits far from the
labelled iris, or barely overlaps it, the label is almost always wrong.

Kept: frames whose predicted iris-or-pupil centroid is within `--max-dist`
(fraction of image width) of the label's AND overlaps it by at least
`--min-iou`. This also drops some hard frames that were labelled correctly;
with noisy labels that is the right trade.

Training data only. Never run this on a selection or test set: the judge
would be grading its own exam.

    python3 filter_with_judge.py --judge /tmp/pupil_run3/epoch6.pt \\
        --src /tmp/synth_full/train --out /tmp/synth_judged/train
"""

import argparse
import glob
import os

import numpy as np
import torch

from model_v2 import build_model
from train import resolve_device


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--judge", required=True)
    p.add_argument("--judge-arch", default="ritnet")
    p.add_argument("--src", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--max-dist", type=float, default=0.06)
    p.add_argument("--min-iou", type=float, default=0.5)
    args = p.parse_args()

    device = resolve_device("auto")
    model = build_model(args.judge_arch)
    model.load_state_dict(torch.load(args.judge, map_location="cpu", weights_only=True))
    model = model.to(device).eval()
    os.makedirs(args.out, exist_ok=True)

    total = kept = 0
    with torch.no_grad():
        for path in sorted(glob.glob(os.path.join(args.src, "shard_*.npz"))):
            with np.load(path) as data:
                arrays = {k: data[k] for k in data.files}
            keep = []
            for start in range(0, len(arrays["images"]), 8):
                x = torch.from_numpy(arrays["images"][start:start + 8].astype(np.float32) / 255).unsqueeze(1).to(device)
                preds = model(x).argmax(1).cpu().numpy()
                for k, pred in enumerate(preds):
                    label = arrays["masks"][start + k] >= 2
                    guess = pred >= 1
                    if label.sum() == 0 or guess.sum() < 200:
                        continue
                    ly, lx = np.nonzero(label)
                    gy, gx = np.nonzero(guess)
                    dist = np.hypot(gx.mean() - lx.mean(), gy.mean() - ly.mean()) / label.shape[1]
                    iou = (label & guess).sum() / max((label | guess).sum(), 1)
                    if dist <= args.max_dist and iou >= args.min_iou:
                        keep.append(start + k)
            total += len(arrays["images"])
            kept += len(keep)
            if keep:
                idx = np.array(keep)
                np.savez_compressed(os.path.join(args.out, os.path.basename(path)), **{k: v[idx] for k, v in arrays.items()})
    print(f"kept {kept} of {total}")


if __name__ == "__main__":
    main()
