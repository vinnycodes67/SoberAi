"""
Calibrates the pupil decision threshold of a U-Net checkpoint on selection
data only, and writes the chosen offset to JSON.

Runs 4-6 drew pupils a few percent too large on every set, training frames
included, so the bias is the model's, not one dataset's. Subtracting an
offset from the pupil logit moves the pupil edge inwards; `model_v2` bakes
the chosen offset into the exported model.

Rule (fixed before run 7's results were seen):
- candidates: offsets 0 to 4 in steps of 0.25;
- an offset qualifies if, against offset 0, kaggle_select clean pupil IoU
  drops by no more than 0.01 and OpenEDS val_select clean iris IoU by no
  more than 0.005 (calibration must not buy OpenEDS pupil accuracy with
  another camera's or with the iris);
- choose the qualifying offset with the highest OpenEDS val_select clean
  pupil IoU (every 4th frame).
Test sets are never read.

    python3 calibrate.py --weights runs/run7/epoch6.pt --arch resnet34 \\
        --select data/openeds/val_select --cross-select data/kaggle_select \\
        --out runs/run7/calibration.json
"""

from __future__ import annotations

import argparse
import json

import torch

from benchmark import _merge
from dataset import OpenEDSSegmentationDataset
from model_v2 import build_model

OFFSETS = [i * 0.25 for i in range(17)]


@torch.no_grad()
def sweep(model, dataset, every: int, device) -> dict:
    inter = torch.zeros(len(OFFSETS), 3, dtype=torch.float64)
    union = torch.zeros(len(OFFSETS), 3, dtype=torch.float64)
    indices = list(range(0, len(dataset), every))
    for start in range(0, len(indices), 8):
        batch = [dataset[i] for i in indices[start:start + 8]]
        x = torch.stack([b[0] for b in batch]).to(device)
        truth = _merge(torch.stack([b[1] for b in batch])).to(device)
        logp = model(x).clamp_min(1e-8).log()
        for k, d in enumerate(OFFSETS):
            pred = (logp - torch.tensor([0, 0, d], device=device).view(1, 3, 1, 1)).argmax(1)
            for c in (1, 2):
                inter[k, c] += ((pred == c) & (truth == c)).sum().item()
                union[k, c] += ((pred == c) | (truth == c)).sum().item()
    iou = inter / union.clamp(min=1)
    return {d: {"iris": round(iou[k, 1].item(), 4), "pupil": round(iou[k, 2].item(), 4)}
            for k, d in enumerate(OFFSETS)}


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--weights", required=True)
    p.add_argument("--arch", default="resnet34")
    p.add_argument("--select", required=True)
    p.add_argument("--cross-select", required=True)
    p.add_argument("--every", type=int, default=4)
    p.add_argument("--out", required=True)
    args = p.parse_args()

    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    model = build_model(args.arch)
    model.load_state_dict(torch.load(args.weights, map_location="cpu", weights_only=True))
    model.to(device).eval()

    openeds = sweep(model, OpenEDSSegmentationDataset(args.select), args.every, device)
    cross = sweep(model, OpenEDSSegmentationDataset(args.cross_select), 1, device)
    base_iris, base_cross = openeds[0.0]["iris"], cross[0.0]["pupil"]
    qualifying = [d for d in OFFSETS
                  if cross[d]["pupil"] >= base_cross - 0.01 and openeds[d]["iris"] >= base_iris - 0.005]
    chosen = max(qualifying, key=lambda d: openeds[d]["pupil"])
    result = {"weights": args.weights, "chosen_offset": chosen,
              "openeds_select_clean": openeds, "cross_select_clean": cross}
    with open(args.out, "w") as f:
        json.dump(result, f, indent=1)
    print(f"chosen offset {chosen}: OpenEDS select clean iris {openeds[chosen]['iris']} "
          f"pupil {openeds[chosen]['pupil']} (offset 0: {openeds[0.0]['iris']} / {openeds[0.0]['pupil']}); "
          f"kaggle_select clean pupil {cross[chosen]['pupil']} (offset 0: {base_cross})")


if __name__ == "__main__":
    main()
