#!/bin/bash
# Run 5: fine-tunes run 4's last epoch with the synthetic pupil edge ignored.
#
# Run 4 over-drew OpenEDS pupils by about 7% of their area, almost every wrong
# pixel within 2 px of the true outline, and the overshoot grew the longer it
# trained on synthetic renders: their pupil outline is drawn larger than
# OpenEDS's. --extra-ignore-pupil-edge 3 keeps the synthetic batches (where
# the pupil is, in visible light) but leaves the outline to OpenEDS.
# Restarts after crashes, gives up after 10 attempts. Nothing lives in /tmp.
set -uo pipefail
DATA="${DATA:-$HOME/SoberTraining/data}"
out_dir="${RUN_DIR:-$HOME/SoberTraining/runs/run5}"
init="${INIT:-$HOME/SoberTraining/runs/run4/epoch8.pt}"
epochs="${EPOCHS:-4}"
cd "$(dirname "$0")/.." || exit 1
mkdir -p "$out_dir"
for attempt in $(seq 1 10); do
  if grep -q '"event": "finished"' "$out_dir/metrics.jsonl" 2>/dev/null; then echo "training finished"; exit 0; fi
  echo "=== attempt $attempt $(date)" | tee -a "$out_dir/supervisor.log"
  caffeinate -dimsu python3 -u train_phone.py --arch resnet34 --init "$init" \
    --train-dir "$DATA/openeds/train" --select-dir "$DATA/openeds/val_select" \
    --extra-train "$DATA/synth/train_judged" --extra-select "$DATA/synth/select" --extra-prob 0.35 \
    --extra-ignore-pupil-edge 3 \
    --out-dir "$out_dir" --epochs "$epochs" --lr 1e-4 --accum 2 --dice-weight 0.5 \
    --ema-decay 0.999 --cooldown-epochs 1 --cooldown-augment-prob 0.4 --resume \
    >>"$out_dir/train.log" 2>&1
  echo "exit $? $(date)" | tee -a "$out_dir/supervisor.log"
  sleep 30
done
echo "gave up after 10 attempts" | tee -a "$out_dir/supervisor.log"
exit 1
