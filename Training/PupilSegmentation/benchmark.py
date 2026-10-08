"""
Robustness benchmark: every model, every test frame, every condition in
`phone_domain.PERTURBATIONS`.

Reports, per condition:

- iris and pupil IoU over the whole set (the numbers the README has used);
- pupil miss rate: frames where the predicted pupil overlaps the true one by
  less than half, or is absent;
- pupil diameter error in millimetres. This is what the app computes:
  `PupilCaptureService` divides the pupil's diameter by the iris's (iris
  meaning iris-or-pupil pixels) and multiplies by a 11.7 mm reference iris.
  Diameters here are area-equivalent rather than ellipse fits, so absolute
  values differ slightly from the app's, but errors are comparable between
  models. Median and 90th percentile. A frame with no pupil found counts as
  the largest possible error, 11.7 mm.

    python3 benchmark.py --model shipped=finetuned_pupil_segmentation.pt \\
        --model candidate=/tmp/pupil_run/epoch6.pt \\
        --data openeds_test=/tmp/openeds_prepared/val_test \\
        --data kaggle_cross=/tmp/kaggle_eyes --out /tmp/benchmark.json

A Core ML package can be passed as `--model name=path.mlpackage`; it is run
through coremltools, so it scores exactly what the app bundles.
"""

from __future__ import annotations

import argparse
import json
import math
import time

import numpy as np
import torch

from dataset import OpenEDSSegmentationDataset
from phone_domain import PERTURBATIONS

REFERENCE_IRIS_MM = 11.7


def _merge(labels: torch.Tensor) -> torch.Tensor:
    out = torch.zeros_like(labels)
    out[labels == 2] = 1
    out[labels == 3] = 2
    return out


class CoreMLRunner:
    def __init__(self, path: str):
        import coremltools as ct
        from PIL import Image
        self.model = ct.models.MLModel(path)
        self.Image = Image
        spec = self.model.get_spec()
        self.input_name = spec.description.input[0].name
        self.output_name = spec.description.output[0].name

    def __call__(self, images: torch.Tensor) -> torch.Tensor:
        outs = []
        for frame in images.cpu():
            pil = self.Image.fromarray((frame[0].numpy() * 255).round().astype(np.uint8), mode="L")
            out = self.model.predict({self.input_name: pil})[self.output_name]
            outs.append(torch.from_numpy(np.asarray(out, dtype=np.float32)).reshape(3, *frame.shape[1:]))
        return torch.stack(outs)


@torch.no_grad()
def score(model, dataset, conditions, device, every: int = 1, batch_size: int = 4) -> dict:
    """Scores one model on one dataset under each named condition. `model` is
    a torch module or a callable taking (B,1,H,W) in [0,1] to (B,3,H,W)."""
    is_torch = isinstance(model, torch.nn.Module)
    if is_torch:
        model.eval()
    indices = list(range(0, len(dataset), every))
    results = {}
    for name in conditions:
        perturb, held_out = PERTURBATIONS[name]
        inter = torch.zeros(3, dtype=torch.float64)
        union = torch.zeros(3, dtype=torch.float64)
        misses, frames, mm_errors = 0, 0, []
        for start in range(0, len(indices), batch_size):
            batch = [dataset[i] for i in indices[start:start + batch_size]]
            images = torch.stack([b[0] for b in batch]).to(device if is_torch else "cpu")
            labels = torch.stack([b[1] for b in batch]).to(images.device)
            images, labels = perturb(images, labels, indices[start])
            probs = model(images) if is_torch else model(images.cpu())
            preds = probs.to(labels.device).argmax(dim=1)
            truth = _merge(labels)
            for c in range(3):
                inter[c] += ((preds == c) & (truth == c)).sum().item()
                union[c] += ((preds == c) | (truth == c)).sum().item()
            for k in range(preds.shape[0]):
                p_pupil, t_pupil = preds[k] == 2, truth[k] == 2
                t_area = t_pupil.sum().item()
                if t_area == 0:
                    continue
                frames += 1
                u = (p_pupil | t_pupil).sum().item()
                if u == 0 or (p_pupil & t_pupil).sum().item() / u < 0.5:
                    misses += 1
                p_eye, t_eye = (preds[k] >= 1).sum().item(), (truth[k] >= 1).sum().item()
                p_area = p_pupil.sum().item()
                if p_eye > 0 and p_area > 0 and t_eye > 0:
                    ratio_p = math.sqrt(p_area / p_eye)
                    ratio_t = math.sqrt(t_area / t_eye)
                    mm_errors.append(abs(ratio_p - ratio_t) * REFERENCE_IRIS_MM)
                else:
                    # No pupil or no eye found: the worst error that can be
                    # reported, the whole reference iris.
                    mm_errors.append(REFERENCE_IRIS_MM)
        iou = (inter / union.clamp(min=1)).tolist()
        finite = np.array(mm_errors) if mm_errors else np.array([REFERENCE_IRIS_MM])
        results[name] = {
            "held_out_of_training": held_out,
            "frames": frames,
            "iou_iris": round(iou[1], 4),
            "iou_pupil": round(iou[2], 4),
            "pupil_miss_rate": round(misses / max(frames, 1), 4),
            "pupil_mm_error_median": round(float(np.median(finite)), 3),
            "pupil_mm_error_p90": round(float(np.percentile(finite, 90)), 3),
        }
    return results


def load_model(path: str, device):
    if path.endswith(".mlpackage"):
        return CoreMLRunner(path)
    from model import PupilSegmentationModel
    model = PupilSegmentationModel()
    state = torch.load(path, map_location="cpu", weights_only=True)
    model.load_state_dict(state["model"] if isinstance(state, dict) and "model" in state else state)
    return model.to(device)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--model", action="append", required=True, help="name=path (.pt or .mlpackage)")
    p.add_argument("--data", action="append", required=True, help="name=prepared_dir")
    p.add_argument("--conditions", default=",".join(PERTURBATIONS))
    p.add_argument("--every", type=int, default=1)
    p.add_argument("--device", default="mps" if torch.backends.mps.is_available() else "cpu")
    p.add_argument("--out", required=True)
    args = p.parse_args()

    conditions = args.conditions.split(",")
    report = {"conditions": conditions, "every": args.every, "results": {}}
    for data_spec in args.data:
        data_name, data_dir = data_spec.split("=", 1)
        dataset = OpenEDSSegmentationDataset(data_dir)
        report["results"][data_name] = {"frames_in_set": len(dataset),
                                        "subjects": len(dataset.subject_set)}
        for model_spec in args.model:
            model_name, model_path = model_spec.split("=", 1)
            t0 = time.time()
            model = load_model(model_path, args.device)
            res = score(model, dataset, conditions, args.device, every=args.every)
            report["results"][data_name][model_name] = res
            print(f"{data_name} / {model_name}: {time.time() - t0:.0f}s", flush=True)
            for cond, r in res.items():
                print(f"  {cond:18s} iris {r['iou_iris']:.4f}  pupil {r['iou_pupil']:.4f}  "
                      f"miss {r['pupil_miss_rate']:.3f}  mm med {r['pupil_mm_error_median']:.3f} "
                      f"p90 {r['pupil_mm_error_p90']:.3f}", flush=True)
            with open(args.out, "w") as f:
                json.dump(report, f, indent=2)


if __name__ == "__main__":
    main()
