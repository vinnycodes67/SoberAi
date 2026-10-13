#!/bin/bash
# Run 8: one gentle epoch on run 7's chosen checkpoint (epoch 5).
#
# Run 7 passed criteria 2-5 but drew pupils about 3% too large even after
# calibration (val_test Core ML clean pupil 0.9648, bar 0.9730). Earlier
# 2000-step tests put that bias on augmentation (every augmentation 1.107,
# none 1.048). One epoch at augment_prob 0.2 (run 7 used 0.7, cool-down 0.4)
# and a lower learning rate, keeping every augmentation type, is meant to
# tighten the edge without unlearning close-ups and dilated pupils.
#
# Kept only if, after calibrate.py: OpenEDS select clean pupil > 0.9648 and
# iris >= 0.9445, and kaggle_select clean (iris+pupil)/2 >= 0.81795 (run 7
# epoch 5's 0.82795 minus 0.01). Otherwise run 7 epoch 5 stands.
set -uo pipefail
DATA="${DATA:-$HOME/SoberTraining/data}"
out_dir="${RUN_DIR:-$HOME/SoberTraining/runs/run8}"
init="${INIT:-$HOME/SoberTraining/runs/run7/epoch5.pt}"
cd "$(dirname "$0")/.." || exit 1
mkdir -p "$out_dir"
for attempt in $(seq 1 10); do
  if grep -q '"event": "finished"' "$out_dir/metrics.jsonl" 2>/dev/null; then break; fi
  echo "=== attempt $attempt $(date)" | tee -a "$out_dir/supervisor.log"
  caffeinate -dimsu python3 -u train_phone.py --arch resnet34 --init "$init" \
    --train-dir "$DATA/openeds/train" --select-dir "$DATA/openeds/val_select" \
    --extra-train "$DATA/synth/train_judged" --extra-select "$DATA/synth/select" --extra-prob 0.35 \
    --cross-select "$DATA/kaggle_select" \
    --extra-ignore-pupil-edge 3 --class-weights 1 1 1 --augment-skip blur \
    --zoom 0.5 1.25 --soft-reframe --pupil-resize-prob 0.4 --augment-prob 0.2 \
    --out-dir "$out_dir" --epochs 1 --lr 3e-5 --accum 2 --dice-weight 0.5 \
    --ema-decay 0.999 --resume >>"$out_dir/train.log" 2>&1
  echo "exit $? $(date)" | tee -a "$out_dir/supervisor.log"
  sleep 30
done
python3 calibrate.py --weights "$out_dir/epoch1.pt" --arch resnet34 \
  --select "$DATA/openeds/val_select" --cross-select "$DATA/kaggle_select" \
  --out "$out_dir/calibration.json" > "$out_dir/calibration.log" 2>&1
python3 ~/SoberTraining/scripts/diag_boundary.py "$PWD" "$DATA/openeds/val_select" 4 \
  "run8_raw=$out_dir/epoch1.pt@resnet34" > "$out_dir/edge_bias.log" 2>/dev/null
echo RUN8_DONE >> "$out_dir/supervisor.log"
