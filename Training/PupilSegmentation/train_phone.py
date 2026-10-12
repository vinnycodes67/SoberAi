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
from model_v2 import build_model
from phone_domain import AUGMENT_STEPS, augment_batch
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


def soft_dice_loss(probs: torch.Tensor, labels3: torch.Tensor) -> torch.Tensor:
    """1 - Dice for iris and pupil, averaged. Cross-entropy is per pixel and
    barely notices a pupil edge drawn two pixels out; Dice is an overlap
    measure, the same thing the IoU bar scores. Pixels labelled IGNORE count
    for neither prediction nor truth."""
    valid = (labels3 != IGNORE).float()
    losses = []
    for c in (1, 2):
        p = probs[:, c] * valid
        t = (labels3 == c).float()
        inter = (p * t).sum()
        losses.append(1 - (2 * inter + 1) / (p.sum() + t.sum() + 1))
    return sum(losses) / len(losses)


IGNORE = -100  # nll_loss's default ignore_index


def ignore_pupil_edge(labels3: torch.Tensor, radius: int) -> torch.Tensor:
    """Marks the ring within `radius` pixels of the pupil outline as IGNORE.

    The synthetic renders draw the pupil outline larger than OpenEDS does:
    run 4 learned it and over-drew OpenEDS pupils by about 7% of their area,
    almost every wrong pixel within 2 px of the true edge. Ignoring the ring
    on synthetic batches keeps what that data teaches (where the pupil is in
    visible light) and leaves the edge itself to OpenEDS."""
    pupil = (labels3 == 2).float()[:, None]
    k = 2 * radius + 1
    grown = nn.functional.max_pool2d(pupil, k, 1, radius)
    shrunk = -nn.functional.max_pool2d(-pupil, k, 1, radius)
    ring = (grown - shrunk)[:, 0] > 0
    return labels3.masked_fill(ring, IGNORE)


class WeightAverage:
    """Exponential moving average of the weights. The averaged model is what
    gets evaluated, saved and exported: it is smoother than the last step's
    weights and usually scores a little higher on unseen data."""

    def __init__(self, model: nn.Module, decay: float):
        self.decay = decay
        self.shadow = {k: v.detach().clone() for k, v in model.state_dict().items()}

    @torch.no_grad()
    def update(self, model: nn.Module) -> None:
        for k, v in model.state_dict().items():
            if v.dtype.is_floating_point:
                self.shadow[k].mul_(self.decay).add_(v.detach(), alpha=1 - self.decay)
            else:
                self.shadow[k].copy_(v)

    def state_dict(self) -> dict:
        return {k: v.detach().cpu().clone() for k, v in self.shadow.items()}


def mixed_batches(primary, extra_set, batch_size, prob, generator, epoch):
    """(batch, from_extra) pairs: batches from `primary`, each replaced with
    probability `prob` by one from `extra_set`, which restarts whenever it
    runs out. An epoch stays defined by the primary set's step count."""
    extra_iter, restarts = None, 0
    for batch in primary:
        from_extra = extra_set is not None and float(torch.rand(1, generator=generator)) < prob
        if from_extra:
            try:
                if extra_iter is None:
                    raise StopIteration
                batch = next(extra_iter)
            except StopIteration:
                extra_set.set_epoch(epoch * 100 + restarts)
                restarts += 1
                extra_iter = iter(DataLoader(extra_set, batch_size=batch_size, num_workers=0))
                batch = next(extra_iter)
        yield batch, from_extra


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
    p.add_argument("--arch", default="ritnet",
                   help="ritnet, or a U-Net encoder: resnet18, resnet34, mobilenet_v3_large")
    p.add_argument("--init", default="finetuned_pupil_segmentation.pt",
                   help="weights to start from; 'none' starts a U-Net from its ImageNet encoder")
    p.add_argument("--accum", type=int, default=1, help="gradient accumulation steps")
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
    p.add_argument("--extra-train", default=None,
                   help="a second prepared training set mixed into batches, e.g. synthetic visible-light eyes")
    p.add_argument("--extra-prob", type=float, default=0.35)
    p.add_argument("--extra-select", default=None, help="selection set for the extra source")
    p.add_argument("--dice-weight", type=float, default=0.0)
    p.add_argument("--augment-skip", nargs="*", default=[], choices=AUGMENT_STEPS,
                   help="augmentation steps never applied")
    p.add_argument("--class-weights", type=float, nargs=3, default=CLASS_WEIGHTS,
                   metavar=("BG", "IRIS", "PUPIL"), help="NLL weights for background, iris, pupil")
    p.add_argument("--extra-ignore-pupil-edge", type=int, default=0,
                   help="ignore this many pixels either side of the pupil outline in extra-source "
                        "batches, so the pupil edge is learned from the primary set only")
    p.add_argument("--ema-decay", type=float, default=0.0, help="0 disables weight averaging")
    p.add_argument("--cooldown-epochs", type=int, default=0,
                   help="final epochs trained with --cooldown-augment-prob")
    p.add_argument("--cooldown-augment-prob", type=float, default=0.3)
    p.add_argument("--cooldown-extra-prob", type=float, default=None,
                   help="extra-source share during cool-down; defaults to --extra-prob. A lower value "
                        "steers the final weights back towards the primary set's clean accuracy")
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
    extra_set = ShardStream(args.extra_train, seed=args.seed + 1) if args.extra_train else None
    extra_select = OpenEDSSegmentationDataset(args.extra_select) if args.extra_select else None
    if extra_set and extra_select and extra_set.subject_set & extra_select.subject_set:
        raise SystemExit("the extra source's train and selection sets share subjects")

    model = build_model(args.arch)
    if args.init != "none":
        model.load_state_dict(torch.load(args.init, map_location="cpu", weights_only=True))
    model.to(device)
    if args.arch == "ritnet":
        optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
    else:
        # The pretrained encoder moves slower than the freshly initialised decoder.
        encoder = list(model.encoder.parameters())
        encoder_ids = {id(p) for p in encoder}
        decoder = [p for p in model.parameters() if id(p) not in encoder_ids]
        optimizer = torch.optim.AdamW(
            [{"params": encoder, "lr": args.lr * 0.3, "scale": 0.3},
             {"params": decoder, "lr": args.lr, "scale": 1.0}], weight_decay=1e-4)

    def freeze_encoder_norms() -> None:
        """Batches of two give BatchNorm useless statistics; keep the encoder's
        ImageNet running statistics fixed (its affine weights still train)."""
        if args.arch == "ritnet":
            return
        for module in model.encoder.modules():
            if isinstance(module, nn.BatchNorm2d):
                module.eval()
    weights = torch.tensor(args.class_weights, device=device)
    average = WeightAverage(model, args.ema_decay) if args.ema_decay > 0 else None
    eval_model = build_model(args.arch).to(device)

    def evaluate_now(epoch: int) -> None:
        """Scores the averaged weights when averaging is on, else the live ones."""
        eval_model.load_state_dict(average.state_dict() if average else model.state_dict())
        event = {"results": score(eval_model, select_set, SELECTION_CONDITIONS, device,
                                  every=args.select_every)}
        if extra_select is not None:
            event["extra_results"] = score(eval_model, extra_select, SELECTION_CONDITIONS, device,
                                           every=args.select_every)
        log_event(args.out_dir, event="selection_eval", epoch=epoch, **event)

    steps_per_epoch = len(train_set) // args.batch_size
    if args.max_steps:
        steps_per_epoch = min(steps_per_epoch, args.max_steps)
    total_steps = steps_per_epoch * args.epochs
    start_epoch, global_step = 0, 0

    def resume_state(epoch: int, step: int) -> dict:
        state = {"model": model.state_dict(), "optimizer": optimizer.state_dict(),
                 "epoch": epoch, "global_step": step}
        if average is not None:
            state["average"] = average.state_dict()
        return state

    last_path = os.path.join(args.out_dir, "last.pt")
    if args.resume and os.path.exists(last_path):
        state = torch.load(last_path, map_location="cpu", weights_only=True)
        model.load_state_dict(state["model"])
        optimizer.load_state_dict(state["optimizer"])
        if average is not None and "average" in state:
            average.shadow = {k: v.to(device) for k, v in state["average"].items()}
        start_epoch, global_step = state["epoch"], state["global_step"]
        generator.manual_seed(args.seed + 7919 * (start_epoch + 1))
        log_event(args.out_dir, event="resumed", epoch=start_epoch, global_step=global_step)
    else:
        log_event(args.out_dir, event="start", train_frames=len(train_set),
                  train_subjects=len(train_set.subject_set), select_frames=len(select_set),
                  select_subjects=len(select_set.subject_set), steps_per_epoch=steps_per_epoch,
                  epochs=args.epochs, device=str(device), init=args.init, args=vars(args))
        evaluate_now(0)

    for epoch in range(start_epoch, args.epochs):
        train_set.set_epoch(epoch)
        loader = DataLoader(train_set, batch_size=args.batch_size, num_workers=0)
        cooling = epoch >= args.epochs - args.cooldown_epochs
        extra_prob = (args.cooldown_extra_prob if cooling and args.cooldown_extra_prob is not None
                      else args.extra_prob)
        batches = mixed_batches(loader, extra_set, args.batch_size, extra_prob, generator, epoch)
        augment_prob = args.cooldown_augment_prob if cooling else args.augment_prob
        model.train()
        freeze_encoder_norms()
        running, count, t0 = 0.0, 0, time.time()
        optimizer.zero_grad()
        for step, ((images, labels), from_extra) in enumerate(batches):
            if step >= steps_per_epoch:
                break
            images, labels = images.to(device), labels.to(device)
            images, labels = augment_batch(images, labels, generator, p=augment_prob, skip=tuple(args.augment_skip))
            for group in optimizer.param_groups:
                group["lr"] = cosine_lr(global_step, total_steps, args.lr) * group.get("scale", 1.0)
            probs = model(images)
            labels3 = merge_labels(labels)
            if from_extra and args.extra_ignore_pupil_edge > 0:
                labels3 = ignore_pupil_edge(labels3, args.extra_ignore_pupil_edge)
            loss = nn.functional.nll_loss(torch.log(probs.clamp(min=1e-7)), labels3, weight=weights)
            if args.dice_weight > 0:
                loss = loss + args.dice_weight * soft_dice_loss(probs, labels3)
            (loss / args.accum).backward()
            if (step + 1) % args.accum == 0:
                optimizer.step()
                optimizer.zero_grad()
                if average is not None:
                    average.update(model)
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
                atomic_save(resume_state(epoch, global_step - step), last_path)

        # epochN.pt is what selection scores: the averaged weights when on.
        torch.save(average.state_dict() if average else model.state_dict(),
                   os.path.join(args.out_dir, f"epoch{epoch + 1}.pt"))
        atomic_save(resume_state(epoch + 1, global_step), last_path)
        log_event(args.out_dir, event="epoch_done", epoch=epoch + 1,
                  loss=round(running / max(count, 1), 5), seconds=round(time.time() - t0))
        release_cached_memory(device)
        evaluate_now(epoch + 1)
        release_cached_memory(device)

    log_event(args.out_dir, event="finished", epochs=args.epochs)


if __name__ == "__main__":
    main()
