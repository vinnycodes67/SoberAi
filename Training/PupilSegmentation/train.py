"""Fine-tunes the pretrained RITnet backbone (trained on OpenEDS2019) on
OpenEDS2020 frames, through the Core ML-compatible preprocessing in
model.py, so the network adapts to the substitute preprocessing instead
of the CLAHE it originally expected. Low learning rate, few epochs —
this is domain adaptation to a new preprocessing pipeline and a related
but distinct capture session, not training from scratch.

Saves a checkpoint after every epoch (not just at the end) and flushes
progress immediately, so a slow or interrupted run never loses more than
one epoch of work — the model.py rewrite this script depends on also
switched from a 41px to a 21px local-contrast window specifically to
keep each epoch fast enough that per-epoch checkpointing is meaningful."""

import argparse
import sys
import time

import torch
import torch.nn as nn
from torch.utils.data import DataLoader

from evaluate import evaluate
from model import PupilSegmentationModel
from splits import make_splits


def merge_labels(labels: torch.Tensor) -> torch.Tensor:
    merged = labels.clone()
    merged[merged == 1] = 0  # sclera -> background
    merged[merged == 2] = 1  # iris
    merged[merged == 3] = 2  # pupil
    return merged


def resolve_device(requested: str) -> str:
    if requested != "auto":
        return requested
    if torch.backends.mps.is_available():
        return "mps"
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


def log(message: str) -> None:
    print(message, flush=True)
    sys.stdout.flush()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", default="/tmp/openeds_data/train")
    parser.add_argument("--epochs", type=int, default=8)
    parser.add_argument("--lr", type=float, default=5e-5)
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--device", default="auto")
    parser.add_argument("--out", default="finetuned_pupil_segmentation.pt")
    args = parser.parse_args()

    device = torch.device(resolve_device(args.device))
    log(f"using device: {device}")

    model = PupilSegmentationModel()
    model.load_pretrained_backbone("vendor_ritnet/ritnet_openeds2019_pretrained.pkl")
    model.to(device)

    log("loading + preprocessing dataset into memory...")
    t0 = time.time()
    train_set, eval_set = make_splits(args.data)
    log(f"train frames: {len(train_set)}   held-out eval frames: {len(eval_set)}   "
        f"(loaded in {time.time() - t0:.1f}s)")
    train_loader = DataLoader(train_set, batch_size=args.batch_size, shuffle=True, num_workers=0)
    eval_loader = DataLoader(eval_set, batch_size=8, shuffle=False, num_workers=0)

    # Class-weighted NLL on log-probabilities (the model already ends in
    # softmax) — pupil/iris pixels are a small minority of each frame, so
    # unweighted cross-entropy would let the model coast at ~94% pixel
    # accuracy by predicting background everywhere (exactly the pretrained
    # model's failure mode against the substitute preprocessing above).
    class_weights = torch.tensor([1.0, 4.0, 8.0], device=device)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)

    log("=== Before fine-tuning ===")
    t0 = time.time()
    baseline_metrics = evaluate(model, eval_loader, str(device))
    log(f"Pixel accuracy: {baseline_metrics['pixel_accuracy']:.4f}, "
        f"mean IoU (iris, pupil): {baseline_metrics['mean_iou_iris_pupil']:.4f} "
        f"(eval took {time.time() - t0:.1f}s)")

    for epoch in range(args.epochs):
        model.train()
        running_loss = 0.0
        epoch_start = time.time()
        for step, (images, labels) in enumerate(train_loader):
            images = images.to(device)
            labels = merge_labels(labels).to(device)
            optimizer.zero_grad()
            probs = model(images)
            log_probs = torch.log(probs.clamp(min=1e-7))
            loss = nn.functional.nll_loss(log_probs, labels, weight=class_weights)
            loss.backward()
            optimizer.step()
            running_loss += loss.item()
            if step % 20 == 0:
                log(f"  epoch {epoch + 1} step {step}/{len(train_loader)} loss={loss.item():.4f}")

        avg_loss = running_loss / max(len(train_loader), 1)
        log(f"epoch {epoch + 1}/{args.epochs}  loss={avg_loss:.4f}  "
            f"({time.time() - epoch_start:.1f}s)")

        checkpoint_path = f"{args.out}.epoch{epoch + 1}"
        torch.save(model.state_dict(), checkpoint_path)
        log(f"  saved checkpoint: {checkpoint_path}")

    log("=== After fine-tuning ===")
    final_metrics = evaluate(model, eval_loader, str(device))
    log(f"Pixel accuracy: {final_metrics['pixel_accuracy']:.4f}, "
        f"mean IoU (iris, pupil): {final_metrics['mean_iou_iris_pupil']:.4f}")
    for cls, value in final_metrics["iou"].items():
        log(f"  IoU[{cls}]: {value:.4f}")

    torch.save(model.state_dict(), args.out)
    log(f"saved final fine-tuned weights to {args.out}")


if __name__ == "__main__":
    main()
