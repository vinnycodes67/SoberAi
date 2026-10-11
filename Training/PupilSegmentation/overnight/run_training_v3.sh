#!/bin/bash
# Run 4: ResNet34 U-Net from its ImageNet encoder, on all of OpenEDS2020 plus
# every synthetic render that passed the physics checks and the judge.
# Called by pipeline.sh; restarts after crashes, gives up after 10 attempts.
# Paths come from the environment so nothing lives in /tmp.
set -uo pipefail
DATA="${DATA:-$HOME/SoberTraining/data}"
out_dir="${RUN_DIR:-$HOME/SoberTraining/runs/run4}"
epochs="${EPOCHS:-8}"
cd "$(dirname "$0")/.." || exit 1
mkdir -p "$out_dir"
for attempt in $(seq 1 10); do
  if grep -q '"event": "finished"' "$out_dir/metrics.jsonl" 2>/dev/null; then echo "training finished"; exit 0; fi
  echo "=== attempt $attempt $(date)" | tee -a "$out_dir/supervisor.log"
  caffeinate -dimsu python3 -u train_phone.py --arch resnet34 --init none \
    --train-dir "$DATA/openeds/train" --select-dir "$DATA/openeds/val_select" \
    --extra-train "$DATA/synth/train_judged" --extra-select "$DATA/synth/select" --extra-prob 0.35 \
    --out-dir "$out_dir" --epochs "$epochs" --lr 3e-4 --accum 2 --dice-weight 0.5 \
    --ema-decay 0.999 --cooldown-epochs 1 --cooldown-augment-prob 0.4 --resume \
    >>"$out_dir/train.log" 2>&1
  echo "exit $? $(date)" | tee -a "$out_dir/supervisor.log"
  sleep 30
done
echo "gave up after 10 attempts" | tee -a "$out_dir/supervisor.log"
exit 1
