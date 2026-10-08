# Overnight watcher instructions

You are watching an unattended training run of Sober's pupil segmentation
model on this Mac. Training runs in tmux session `pupil-train` under
`overnight/run_training.sh`, which restarts it after a crash. Its output is in
`/tmp/pupil_run`. The code you run is in `/tmp/pupil_code` (a copy of
`Training/PupilSegmentation`).

## Hard limits

- Never touch any git repository, never commit or push, never edit code.
- Never replace the shipped model or anything under `~/Downloads`.
- Never delete data or checkpoints. Write only inside `/tmp/pupil_run`.
- Do not run anything on the GPU while training is still running. A
  benchmark and training together will run out of memory.
- Report numbers exactly as measured. Never round in the model's favour,
  never describe an unmeasured result.

## Each check (every ~2 hours)

1. Read the tail of `/tmp/pupil_run/metrics.jsonl`, `supervisor.log` and
   `train.log`. Check `pgrep -f train_phone.py` and `df -h /`.
2. **Stalled**: the process is alive but the newest `progress` event is more
   than 45 minutes old. Run `pkill -f train_phone.py`; the supervisor resumes
   from the last checkpoint. Note it in the status file.
3. **Gave up**: `supervisor.log` says "gave up". Do not try to fix code. Write
   the last error from `train.log` into the status file and stop.
4. **Disk** under 3 GB free: write a warning in the status file. Delete
   nothing.
5. Append to `/tmp/pupil_run/STATUS.md`: time, epoch and step, seconds per
   step, an ETA, restarts so far, and the newest `selection_eval` beside the
   epoch-0 one (iris IoU, pupil IoU, pupil mm error median for each
   condition).

## When `metrics.jsonl` has `"event": "finished"`

1. **Pick a checkpoint** from the `selection_eval` events only (never the
   test set). Eligible: clean iris IoU and clean pupil IoU each at least the
   epoch-0 value minus 0.003. Among eligible epochs choose the highest mean
   of (iris IoU + pupil IoU) / 2 over the non-clean conditions.

   **If no epoch is eligible**, run one cool-down epoch: mostly clean frames,
   low learning rate, starting from the epoch with the best non-clean mean.
   This is the only training you may start, and only once.
   ```bash
   cd /tmp/pupil_code
   caffeinate -dimsu python3 -u train_phone.py --init /tmp/pupil_run/epochN.pt \
     --out-dir /tmp/pupil_run/cooldown --epochs 1 --lr 1e-5 --augment-prob 0.3 \
     > /tmp/pupil_run/cooldown.log 2>&1
   ```
   It takes about 70 minutes. Then apply the same rule to its
   `/tmp/pupil_run/cooldown/metrics.jsonl` (epoch-0 values still come from `/tmp/pupil_run/metrics.jsonl`). If it
   is still not eligible, say the run failed to keep clean accuracy and
   benchmark the best non-clean epoch anyway, marked as failing that rule.
2. **Benchmark** the shipped model against the chosen one, every condition,
   every frame:
   ```bash
   cd /tmp/pupil_code
   python3 benchmark.py --model shipped=finetuned_pupil_segmentation.pt \
     --model candidate=/tmp/pupil_run/epochN.pt \
     --data openeds_test=/tmp/openeds_prepared/val_test \
     --data kaggle_cross=/tmp/kaggle_eyes --out /tmp/pupil_run/benchmark.json
   ```
3. **Export and verify** the candidate as Core ML, on the same frames as the
   published bar:
   ```bash
   python3 export_coreml.py --weights /tmp/pupil_run/epochN.pt --out /tmp/pupil_run/Candidate.mlpackage
   python3 verify_coreml.py --package /tmp/pupil_run/Candidate.mlpackage \
     --weights /tmp/pupil_run/epochN.pt --eval-data /tmp/openeds_prepared/val_test --every 4
   ```
4. Write `/tmp/pupil_run/REPORT.md`:
   - the chosen epoch and why;
   - a table, shipped vs candidate, per dataset and condition;
   - the Core ML verify output;
   - **verdict** against the bar: the candidate's Core ML clean scores on
     `val_test` (every 4th frame) must be at least iris 0.9490 and pupil
     0.9730, *and* it must beat the shipped model on the mean of the
     non-clean conditions and on `kaggle_cross`. State PASS or FAIL per
     criterion, with the numbers.
   - what this does **not** show: none of these images are visible-light
     iPhone captures.
5. Then stop looping: delete your scheduled job.
