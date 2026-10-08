#!/bin/bash
# Runs train_phone.py until it reports "finished", resuming after any crash.
# caffeinate keeps the Mac awake for as long as training runs (it must stay
# plugged in). Gives up after 8 restarts so a deterministic failure does not
# loop all night; the watcher reports it.
#
#   Training/PupilSegmentation/overnight/run_training.sh /tmp/pupil_run 8

set -uo pipefail

out_dir="${1:-/tmp/pupil_run}"
epochs="${2:-8}"
cd "$(dirname "$0")/.." || exit 1
mkdir -p "$out_dir"

for attempt in $(seq 1 9); do
  if grep -q '"event": "finished"' "$out_dir/metrics.jsonl" 2>/dev/null; then
    echo "training finished"
    exit 0
  fi
  echo "=== attempt $attempt $(date)" | tee -a "$out_dir/supervisor.log"
  caffeinate -dimsu python3 -u train_phone.py \
    --train-dir /tmp/openeds_prepared/train \
    --select-dir /tmp/openeds_prepared/val_select \
    --init finetuned_pupil_segmentation.pt \
    --out-dir "$out_dir" --epochs "$epochs" --resume \
    >>"$out_dir/train.log" 2>&1
  echo "exit $? $(date)" | tee -a "$out_dir/supervisor.log"
  sleep 60
done

echo "gave up after 9 attempts" | tee -a "$out_dir/supervisor.log"
exit 1
