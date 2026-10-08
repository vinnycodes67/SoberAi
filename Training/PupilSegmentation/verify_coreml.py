"""Scores an exported `.mlpackage` the way the app runs it, and checks it
agrees with the PyTorch checkpoint it came from.

`evaluate.py` measures the PyTorch model. What ships is a Core ML conversion
of it, and a conversion can change results — precision, an op lowered
differently, an image input scaled differently. This feeds the same frames
through both and reports:

- per-class IoU of the Core ML model against the ground-truth masks, and
- how often the two models pick a different class for the same pixel.

Core ML prediction only runs on macOS.

    python3 verify_coreml.py --package PupilSegmentation.mlpackage \\
        --weights finetuned_pupil_segmentation.pt --eval-data /tmp/openeds_prepared/val
"""

import argparse

import coremltools as ct
import numpy as np
import torch
from PIL import Image

from dataset import OpenEDSSegmentationDataset
from model import PupilSegmentationModel

CLASS_NAMES = ["background", "iris", "pupil"]


def merge(labels: np.ndarray) -> np.ndarray:
    """4-class ground truth to the model's 3 classes: sclera joins background."""
    merged = labels.astype(np.int64)
    merged[merged == 1] = 0
    merged[merged == 2] = 1
    merged[merged == 3] = 2
    return merged


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", required=True)
    parser.add_argument("--weights", required=True)
    parser.add_argument("--eval-data", required=True)
    parser.add_argument("--every", type=int, default=1, help="score every Nth frame")
    args = parser.parse_args()

    mlmodel = ct.models.MLModel(args.package)
    torch_model = PupilSegmentationModel()
    torch_model.load_state_dict(torch.load(args.weights, map_location="cpu", weights_only=True))
    torch_model.eval()

    data = OpenEDSSegmentationDataset(args.eval_data)
    indices = range(0, len(data), args.every)

    intersection = np.zeros(3)
    union = np.zeros(3)
    disagreeing = 0
    total = 0

    for i in indices:
        pixels = data.images[i]
        truth = merge(data.labels[i])

        scores = mlmodel.predict({"eye_image": Image.fromarray(pixels, mode="L")})["class_scores"]
        coreml_pred = np.asarray(scores)[0].argmax(axis=0)

        with torch.no_grad():
            image = torch.from_numpy(pixels.astype(np.float32) / 255.0)[None, None]
            torch_pred = torch_model(image)[0].argmax(dim=0).numpy()

        disagreeing += int((coreml_pred != torch_pred).sum())
        total += coreml_pred.size
        for c in range(3):
            p, t = coreml_pred == c, truth == c
            intersection[c] += (p & t).sum()
            union[c] += (p | t).sum()

    iou = intersection / np.maximum(union, 1)
    print(f"Core ML package scored on {len(indices)} frames "
          f"from {len(data.subject_set)} subjects")
    for c, name in enumerate(CLASS_NAMES):
        print(f"  IoU[{name}]: {iou[c]:.4f}")
    print(f"Mean IoU (iris, pupil): {(iou[1] + iou[2]) / 2:.4f}")
    print(f"Pixels where Core ML and PyTorch disagree: {disagreeing / total:.5%}")


if __name__ == "__main__":
    main()
