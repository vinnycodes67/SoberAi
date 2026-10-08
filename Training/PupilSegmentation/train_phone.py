"""
Fine-tunes the shipped pupil model on all of OpenEDS2020 with phone-camera
degradations (`phone_domain.py`). Built to run unattended overnight:

- resumable: `--resume` continues from `<out-dir>/last.pt` after a crash or
  reboot, at the start of the epoch it was in;
- streams shards (`stream_dataset.py`), so memory stays near 1-2 GB;
- logs one JSON line per event to `<out-dir>/metrics.jsonl` for a watcher.

Checkpoint selection uses a *selection* set (val shards 4-16) that is disjoint
by subject from the *test* set (val shards 0-3) the shipped model's numbers
were measured on, so the test numbers stay honest. Nothing here picks a
checkpoint by looking at the test set.

    python3 train_phone.py --train-dir /tmp/openeds_prepared/train \\
        --select-dir /tmp/openeds_prepared/val_select \\
        --init finetuned_pupil_segmentation.pt --out-dir /tmp/pupil_run --epochs 10
"""

from __future__ import annotations

import argparse
import json
import math
import os
import time

import torch
import torch.nn as nn
from torch.utils.data import DataLoader

from benchmark import score
from dataset import OpenEDSSegmentationDataset
from model import PupilSegmentationModel
from phone_domain import augment_batch
from stream_dataset import ShardStream
from train import merge_labels, release_cached_memory, resolve_device

CLASS_WEIGHTS = [1.0, 4.0, 8.0]
SELECTION_CONDITIONS = ["clean", "lowres_120px", "dark_iris", "low_light", "phone_combo"]


def log_event(out_dir: str, **event) -> None:
    event["time"] = time.strftime("%Y-%m-%d %H:%M:%S")
    line = json.dumps(event)
    print(line, flush=True)
    with open(os.path.join(out_dir, "metrics.jsonl"), "a") as f:
        f.write(line + "\n")


def atomic_save(obj, path: str) -> None:
    tmp = path + ".tmp"
    torch.save(obj, tmp)
    os.replace(tmp, path)


def cosine_lr(step: int, total: int, base: float, warmup: int = 300) -> float:
    if step < warmup:
        return base * (step + 1) / warmup
    progress = (step - warmup) / max(1, total - warmup)
    return base * (0.05 + 0.95 * 0.5 * (1 + math.cos(math.pi * min(progress, 1.0))))


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--train-dir", default="/tmp/openeds_prepared/train")
    p.add_argument("--select-dir", default="/tmp/openeds_prepared/val_select")
    p.add_argument("--select-every", type=int, default=4, help="score every Nth selection frame")
    p.add_argument("--init", default="finetuned_pupil_segmentation.pt")
    p.add_argument("--out-dir", default="/tmp/pupil_run")
    p.add_argument("--epochs", type=int, default=10)
    p.add_argument("--lr", type=float, default=5e-5)
    p.add_argument("--batch-size", type=int, default=2,
                   help="2 is fastest per frame on a 16 GB M4; 8 thrashes memory")
    p.add_argument("--augment-prob", type=float, default=0.7)
    p.add_argument("--device", default="auto")
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--max-steps", type=int, default=0, help="stop each epoch early (smoke tests)")
    p.add_argument("--resume", action="store_true")
    args = p.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    device = torch.device(resolve_device(args.device))
    torch.manual_seed(args.seed)
    generator = torch.Generator().manual_seed(args.seed)

    train_set = ShardStream(args.train_dir, seed=args.seed)
    select_set = OpenEDSSegmentationDataset(args.select_dir)
    overlap = train_set.subject_set & select_set.subject_set
    if overlap:
        raise SystemExit(f"subjects {sorted(overlap)} are in both train and selection data")

    model = PupilSegmentationModel()
    model.load_state_dict(torch.load(args.init, map_location="cpu", weights_only=True))
    model.to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
    weights = torch.tensor(CLASS_WEIGHTS, device=device)

    steps_per_epoch = len(train_set) // args.batch_size
    if args.max_steps:
        steps_per_epoch = min(steps_per_epoch, args.max_steps)
    total_steps = steps_per_epoch * args.epochs
    start_epoch, global_step = 0, 0

    last_path = os.path.join(args.out_dir, "last.pt")
    if args.resume and os.path.exists(last_path):
        state = torch.load(last_path, map_location="cpu", weights_only=True)
        model.load_state_dict(state["model"])
        optimizer.load_state_dict(state["optimizer"])
        start_epoch, global_step = state["epoch"], state["global_step"]
        generator.manual_seed(args.seed + 7919 * (start_epoch + 1))
        log_event(args.out_dir, event="resumed", epoch=start_epoch, global_step=global_step)
    else:
        log_event(args.out_dir, event="start", train_frames=len(train_set),
                  train_subjects=len(train_set.subject_set), select_frames=len(select_set),
                  select_subjects=len(select_set.subject_set), steps_per_epoch=steps_per_epoch,
                  epochs=args.epochs, device=str(device), init=args.init, args=vars(args))
        baseline = score(model, select_set, SELECTION_CONDITIONS, device, every=args.select_every)
        log_event(args.out_dir, event="selection_eval", epoch=0, results=baseline)

    for epoch in range(start_epoch, args.epochs):
        train_set.set_epoch(epoch)
        loader = DataLoader(train_set, batch_size=args.batch_size, num_workers=0)
        model.train()
        running, count, t0 = 0.0, 0, time.time()
        for step, (images, labels) in enumerate(loader):
            if step >= steps_per_epoch:
                break
            images, labels = images.to(device), labels.to(device)
            images, labels = augment_batch(images, labels, generator, p=args.augment_prob)
            for group in optimizer.param_groups:
                group["lr"] = cosine_lr(global_step, total_steps, args.lr)
            optimizer.zero_grad()
            probs = model(images)
            loss = nn.functional.nll_loss(torch.log(probs.clamp(min=1e-7)),
                                          merge_labels(labels), weight=weights)
            loss.backward()
            optimizer.step()
            running += loss.item()
            count += 1
            global_step += 1
            if step % 500 == 0:
                elapsed = time.time() - t0
                log_event(args.out_dir, event="progress", epoch=epoch + 1, step=step,
                          of=steps_per_epoch, loss=round(running / count, 5),
                          lr=optimizer.param_groups[0]["lr"],
                          sec_per_step=round(elapsed / max(step, 1), 3))
            if step and step % 3000 == 0:
                atomic_save({"model": model.state_dict(), "optimizer": optimizer.state_dict(),
                             "epoch": epoch, "global_step": global_step - step}, last_path)

        torch.save(model.state_dict(), os.path.join(args.out_dir, f"epoch{epoch + 1}.pt"))
        atomic_save({"model": model.state_dict(), "optimizer": optimizer.state_dict(),
                     "epoch": epoch + 1, "global_step": global_step}, last_path)
        log_event(args.out_dir, event="epoch_done", epoch=epoch + 1,
                  loss=round(running / max(count, 1), 5), seconds=round(time.time() - t0))
        release_cached_memory(device)
        results = score(model, select_set, SELECTION_CONDITIONS, device, every=args.select_every)
        log_event(args.out_dir, event="selection_eval", epoch=epoch + 1, results=results)
        release_cached_memory(device)

    log_event(args.out_dir, event="finished", epochs=args.epochs)


if __name__ == "__main__":
    main()
