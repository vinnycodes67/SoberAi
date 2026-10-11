#!/bin/bash
# The whole run-4 pipeline, resumable stage by stage.
#
# Everything lives under $BASE (default ~/SoberTraining), never /tmp: macOS
# empties /tmp on restart, and a dead battery on 2026-10-10 took the first
# run-4 attempt, its data and run 3's checkpoints with it. Each stage writes
# a marker in $BASE/markers when it finishes, so after a crash or restart the
# pipeline picks up at the first unfinished stage. Kaggle rate-limits
# anonymous downloads; the fetch stages retry patiently.
#
#   overnight/pipeline.sh            # run or resume everything
set -uo pipefail

BASE="${BASE:-$HOME/SoberTraining}"
CODE="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$BASE/data"; RAW="$BASE/raw"; RUNS="$BASE/runs"; MARK="$BASE/markers"; LOG="$BASE/pipeline.log"
mkdir -p "$DATA" "$RAW" "$RUNS" "$MARK"
cd "$CODE" || exit 1

log() { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }
done_stage() { touch "$MARK/$1"; log "stage $1 done"; }
need() { [ ! -f "$MARK/$1" ]; }

kaggle_fetch() {  # url out
  for attempt in $(seq 1 40); do
    code=$(curl -sL -o "$2" -w '%{http_code}' "$1")
    [ "$code" = 200 ] && return 0
    log "fetch $1: HTTP $code, retry $attempt in 5 min"; sleep 300
  done
  return 1
}

if need openeds; then
  log "stage openeds"
  python3 -u prepare_data.py --split train --shards 0-64 --out "$DATA/openeds/train" >>"$LOG" 2>&1 \
    && python3 -u prepare_data.py --split val --shards 0-16 --out "$DATA/openeds/val" >>"$LOG" 2>&1 \
    && python3 make_val_splits.py --val "$DATA/openeds/val" >>"$LOG" 2>&1 \
    && done_stage openeds || { log "openeds failed"; exit 1; }
fi

if need synth; then
  log "stage synth"
  zip="$RAW/synthetic-human-eyes.zip"
  if ! unzip -tq "$zip" >/dev/null 2>&1; then
    kaggle_fetch https://www.kaggle.com/api/v1/datasets/download/allexmendes/synthetic-human-eyes "$zip" || { log "synth fetch failed"; exit 1; }
  fi
  python3 -u prepare_synthetic_parallel.py --zip "$zip" --start 0 --end 40000 --out "$DATA/synth/train" >>"$LOG" 2>&1 \
    && python3 -u prepare_synthetic_parallel.py --zip "$zip" --start 40000 --end 45000 --out "$DATA/synth/select" >>"$LOG" 2>&1 \
    && python3 -u prepare_synthetic_parallel.py --zip "$zip" --start 45000 --end 50000 --out "$DATA/synth/test" >>"$LOG" 2>&1 \
    && rm -f "$zip" && done_stage synth || { log "synth prep failed"; exit 1; }
fi

if need teyed; then
  log "stage teyed"
  mkdir -p "$RAW/teyed"
  curl -sL "https://www.kaggle.com/api/v1/datasets/list/shivanshpachnanda/teyed-reduced" -o "$RAW/teyed/list.json"
  python3 -c "import json; print('\n'.join([f['name'] for f in json.load(open('$RAW/teyed/list.json'))['datasetFiles'] if f['name'].endswith('.npz')][:30]))" > "$RAW/teyed/names.txt"
  while read -r f; do
    [ -s "$RAW/teyed/$f" ] && continue
    sleep 4
    kaggle_fetch "https://www.kaggle.com/api/v1/datasets/download/shivanshpachnanda/teyed-reduced/$f" "$RAW/teyed/$f" || true
  done < "$RAW/teyed/names.txt"
  python3 prepare_teyed.py --src "$RAW/teyed" --out "$DATA/teyed" >>"$LOG" 2>&1 && done_stage teyed || log "teyed prep failed (continuing)"
fi

if need kaggle; then
  log "stage kaggle"
  if kaggle_fetch https://www.kaggle.com/api/v1/datasets/download/itguides/pupil-eye-and-iris-segmentation "$RAW/kaggle.zip"; then
    rm -rf "$RAW/kaggle" && unzip -q "$RAW/kaggle.zip" -d "$RAW/kaggle" \
      && python3 prepare_kaggle_eyes.py --src "$RAW/kaggle/IRIS + PUPIL + EYE" --out "$DATA/kaggle" >>"$LOG" 2>&1 \
      && done_stage kaggle || log "kaggle prep failed (continuing)"
  fi
fi

if need judge; then
  log "stage judge (one epoch of the U-Net on physics-filtered data)"
  caffeinate -dimsu python3 -u train_phone.py --arch resnet34 --init none \
    --train-dir "$DATA/openeds/train" --select-dir "$DATA/openeds/val_select" \
    --extra-train "$DATA/synth/train" --extra-select "$DATA/synth/select" --extra-prob 0.35 \
    --out-dir "$RUNS/judge" --epochs 1 --lr 3e-4 --accum 2 --dice-weight 0.5 --ema-decay 0 --resume \
    >>"$RUNS/judge.log" 2>&1 && done_stage judge || { log "judge training failed"; exit 1; }
fi

if need judged; then
  log "stage judged"
  python3 -u filter_with_judge.py --judge "$RUNS/judge/epoch1.pt" --judge-arch resnet34 \
    --src "$DATA/synth/train" --out "$DATA/synth/train_judged" >>"$LOG" 2>&1 \
    && done_stage judged || { log "judge filter failed"; exit 1; }
fi

if need run4; then
  log "stage run4"
  RUN_DIR="$RUNS/run4" DATA="$DATA" "$CODE/overnight/run_training_v3.sh" >>"$LOG" 2>&1 \
    && done_stage run4 || { log "run4 failed"; exit 1; }
fi

log "pipeline complete; the watcher writes $RUNS/run4/REPORT.md"
