#!/bin/bash
# Run 6: fine-tunes run 4's last epoch without the augmentations that inflate the pupil.
#
# Runs 4 and 5 drew OpenEDS pupils 7-8% too large. Short runs from run 4's
# last epoch (2000 steps, predicted/true pupil area on val_select) found the
# cause: blur and re-cropping each soften the image while the label stays
# sharp, so the network learns to draw the edge further out than it looks.
# Every augmentation 1.107; without blur 1.027; without re-cropping 1.029;
# no augmentation 1.048. Equal class weights (1.107 vs 1.147 at 1 4 8) and the
# ignored synthetic pupil edge are kept from those tests.
# Restarts after crashes, gives up after 10 attempts. Nothing lives in /tmp.
set -uo pipefail
DATA="${DATA:-$HOME/SoberTraining/data}"
out_dir="${RUN_DIR:-$HOME/SoberTraining/runs/run6}"
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
    --extra-ignore-pupil-edge 3 --class-weights 1 1 1 --augment-skip blur reframe \
    --out-dir "$out_dir" --epochs "$epochs" --lr 1e-4 --accum 2 --dice-weight 0.5 \
    --ema-decay 0.999 --cooldown-epochs 1 --cooldown-augment-prob 0.4 --resume \
    >>"$out_dir/train.log" 2>&1
  echo "exit $? $(date)" | tee -a "$out_dir/supervisor.log"
  sleep 30
done
echo "gave up after 10 attempts" | tee -a "$out_dir/supervisor.log"
exit 1
