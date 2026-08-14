"""Reports per-class IoU/Dice on the held-out subjects, using the exact
preprocessing that ships in the exported Core ML model (see model.py's
module docstring for why this matters)."""

import argparse

import torch
from torch.utils.data import DataLoader

from model import PupilSegmentationModel
from splits import make_splits

CLASS_NAMES = ["background", "iris", "pupil"]


@torch.no_grad()
def evaluate(model: PupilSegmentationModel, loader: DataLoader, device: str) -> dict:
    model.eval()
    intersection = torch.zeros(3, dtype=torch.float64)
    union = torch.zeros(3, dtype=torch.float64)
    pred_area = torch.zeros(3, dtype=torch.float64)
    true_area = torch.zeros(3, dtype=torch.float64)
    correct_pixels = 0
    total_pixels = 0

    for images, labels in loader:
        images, labels = images.to(device), labels.to(device)
        # Merge sclera (1) into background (0) in the ground truth too,
        # to match the model's 3-class output contract.
        labels_merged = labels.clone()
        labels_merged[labels_merged == 1] = 0
        labels_merged[labels_merged == 2] = 1
        labels_merged[labels_merged == 3] = 2

        probs = model(images)
        preds = probs.argmax(dim=1)

        correct_pixels += (preds == labels_merged).sum().item()
        total_pixels += labels_merged.numel()

        for c in range(3):
            pred_c = preds == c
            true_c = labels_merged == c
            intersection[c] += (pred_c & true_c).sum().item()
            union[c] += (pred_c | true_c).sum().item()
            pred_area[c] += pred_c.sum().item()
            true_area[c] += true_c.sum().item()

    iou = intersection / union.clamp(min=1)
    dice = (2 * intersection) / (pred_area + true_area).clamp(min=1)
    return {
        "pixel_accuracy": correct_pixels / total_pixels,
        "iou": {CLASS_NAMES[c]: iou[c].item() for c in range(3)},
        "dice": {CLASS_NAMES[c]: dice[c].item() for c in range(3)},
        "mean_iou_iris_pupil": ((iou[1] + iou[2]) / 2).item(),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", default="/tmp/openeds_data/train")
    parser.add_argument("--weights", default=None, help="fine-tuned checkpoint; omit for pretrained-only")
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args()

    model = PupilSegmentationModel()
    if args.weights:
        model.load_state_dict(torch.load(args.weights, map_location="cpu", weights_only=True))
    else:
        model.load_pretrained_backbone("vendor_ritnet/ritnet_openeds2019_pretrained.pkl")
    model.to(args.device)

    _, eval_set = make_splits(args.data)
    loader = DataLoader(eval_set, batch_size=4, shuffle=False, num_workers=0)
    print(f"Evaluating on {len(eval_set)} held-out frames from subjects not seen during fine-tuning...")
    metrics = evaluate(model, loader, args.device)

    print(f"Pixel accuracy: {metrics['pixel_accuracy']:.4f}")
    for cls in CLASS_NAMES:
        print(f"  IoU[{cls}]: {metrics['iou'][cls]:.4f}   Dice[{cls}]: {metrics['dice'][cls]:.4f}")
    print(f"Mean IoU (iris, pupil): {metrics['mean_iou_iris_pupil']:.4f}")


if __name__ == "__main__":
    main()
