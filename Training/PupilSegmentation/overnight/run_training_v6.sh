#!/bin/bash
# Run 7: run 6's last epoch, trained on dilated/constricted pupils and on
# close-up crops (re-cropping back on, zoom 0.5-1.25, labels resampled with
# the image's interpolation), blur still off.
#
# 2000-step tests from run 6's last epoch (OpenEDS val_select clean pupil /
# kaggle_select clean pupil / kaggle pupil miss rate):
#   run 6 settings          0.9374 / 0.2359 / 0.78
#   + pupil resize          0.9375 / 0.4714 / 0.50
#   + close-up re-crop      0.9607 / 0.4889 / 0.42
#   + both (this run)       0.9554 / 0.7069 / 0.17
# Restarts after crashes, gives up after 10 attempts. Nothing lives in /tmp.
set -uo pipefail
DATA="${DATA:-$HOME/SoberTraining/data}"
out_dir="${RUN_DIR:-$HOME/SoberTraining/runs/run7}"
init="${INIT:-$HOME/SoberTraining/runs/run6/epoch4.pt}"
epochs="${EPOCHS:-6}"
cd "$(dirname "$0")/.." || exit 1
mkdir -p "$out_dir"
for attempt in $(seq 1 10); do
  if grep -q '"event": "finished"' "$out_dir/metrics.jsonl" 2>/dev/null; then echo "training finished"; exit 0; fi
  echo "=== attempt $attempt $(date)" | tee -a "$out_dir/supervisor.log"
  caffeinate -dimsu python3 -u train_phone.py --arch resnet34 --init "$init" \
    --train-dir "$DATA/openeds/train" --select-dir "$DATA/openeds/val_select" \
    --extra-train "$DATA/synth/train_judged" --extra-select "$DATA/synth/select" --extra-prob 0.35 \
    --cross-select "$DATA/kaggle_select" \
    --extra-ignore-pupil-edge 3 --class-weights 1 1 1 --augment-skip blur \
    --zoom 0.5 1.25 --soft-reframe --pupil-resize-prob 0.4 \
    --out-dir "$out_dir" --epochs "$epochs" --lr 1e-4 --accum 2 --dice-weight 0.5 \
    --ema-decay 0.999 --cooldown-epochs 1 --cooldown-augment-prob 0.4 --resume \
    >>"$out_dir/train.log" 2>&1
  echo "exit $? $(date)" | tee -a "$out_dir/supervisor.log"
  sleep 30
done
echo "gave up after 10 attempts" | tee -a "$out_dir/supervisor.log"
exit 1
