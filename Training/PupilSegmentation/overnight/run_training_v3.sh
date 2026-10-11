#!/bin/bash
# Run 4: ResNet34 U-Net from its ImageNet encoder, on all of OpenEDS2020 plus
# every synthetic render that passes the physics checks and the judge (/tmp/synth_judged).
# Restarts after crashes, gives up after 10 attempts.
#
#   overnight/run_training_v3.sh /tmp/pupil_run4 8
set -uo pipefail
out_dir="${1:-/tmp/pupil_run4}"
epochs="${2:-8}"
cd "$(dirname "$0")/.." || exit 1
mkdir -p "$out_dir"
for attempt in $(seq 1 10); do
  if grep -q '"event": "finished"' "$out_dir/metrics.jsonl" 2>/dev/null; then echo "training finished"; exit 0; fi
  echo "=== attempt $attempt $(date)" | tee -a "$out_dir/supervisor.log"
  caffeinate -dimsu python3 -u train_phone.py --arch resnet34 --init none \
    --train-dir /tmp/openeds_prepared/train --select-dir /tmp/openeds_prepared/val_select \
    --extra-train /tmp/synth_judged/train --extra-select /tmp/synth_clean/select --extra-prob 0.35 \
    --out-dir "$out_dir" --epochs "$epochs" --lr 3e-4 --accum 2 --dice-weight 0.5 \
    --ema-decay 0.999 --cooldown-epochs 1 --cooldown-augment-prob 0.4 --resume \
    >>"$out_dir/train.log" 2>&1
  echo "exit $? $(date)" | tee -a "$out_dir/supervisor.log"
  sleep 30
done
echo "gave up after 10 attempts" | tee -a "$out_dir/supervisor.log"
exit 1
