#!/bin/bash
# Second run: Dice + weight averaging + a cool-down epoch, starting from the
# first run's candidate, with synthetic visible-light eyes mixed in as soon as
# /tmp/synth_clean/train/shard_00000.npz exists. Until then it trains on OpenEDS alone;
# when the synthetic set appears it stops the current attempt and resumes from
# the last checkpoint with the second source added. Restarts after crashes;
# gives up after 12 attempts.
#
#   overnight/run_training_v2.sh /tmp/pupil_run3 8

set -uo pipefail
out_dir="${1:-/tmp/pupil_run3}"
epochs="${2:-8}"
cd "$(dirname "$0")/.." || exit 1
mkdir -p "$out_dir"

for attempt in $(seq 1 12); do
  if grep -q '"event": "finished"' "$out_dir/metrics.jsonl" 2>/dev/null; then
    echo "training finished"; exit 0
  fi
  extra=()
  [ -f /tmp/synth_clean/train/shard_00000.npz ] && extra=(--extra-train /tmp/synth_clean/train
    --extra-select /tmp/synth_clean/select --extra-prob 0.3)
  echo "=== attempt $attempt $(date) synthetic=${#extra[@]}" | tee -a "$out_dir/supervisor.log"
  caffeinate -dimsu python3 -u train_phone.py \
    --train-dir /tmp/openeds_prepared/train --select-dir /tmp/openeds_prepared/val_select \
    --init results/candidate_phone_domain_epoch8.pt --out-dir "$out_dir" --epochs "$epochs" \
    --lr 3e-5 --dice-weight 0.5 --ema-decay 0.999 --cooldown-epochs 2 --cooldown-extra-prob 0.1 --resume ${extra[@]+"${extra[@]}"} \
    >>"$out_dir/train.log" 2>&1 &
  pid=$!
  # Upgrade once: if this attempt started without the synthetic set and it
  # becomes ready, stop and let the next attempt resume with it.
  while kill -0 "$pid" 2>/dev/null; do
    if [ ${#extra[@]} -eq 0 ] && [ -f /tmp/synth_clean/train/shard_00000.npz ]; then
      echo "synthetic set ready $(date); restarting with it" | tee -a "$out_dir/supervisor.log"
      # The python process is caffeinate's child; stop it by name so no
      # orphan keeps training alongside the next attempt.
      pkill -TERM -f "train_phone.py.*--out-dir $out_dir"; wait "$pid"; break
    fi
    sleep 60
  done
  wait "$pid" 2>/dev/null
  echo "exit $? $(date)" | tee -a "$out_dir/supervisor.log"
  sleep 20
done
echo "gave up after 12 attempts" | tee -a "$out_dir/supervisor.log"
exit 1
