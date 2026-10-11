# Watcher instructions: second pupil run

You are watching an unattended training run of Sober's pupil segmentation
model. Training runs in tmux session `pupil-train3` under
`overnight/run_training_v2.sh`, which restarts after a crash and switches to
mixed training (OpenEDS + synthetic visible-light eyes) once
`/tmp/synth_clean/train` exists. Output: `/tmp/pupil_run3`. Code you run:
`/tmp/pupil_code2`. Data downloads run in tmux session `pupil-data`; their
logs are `/tmp/dl_*.log` and `/tmp/prep_*.log`.

## Hard limits

- Never touch a git repository, never commit or push, never edit code.
- Never replace the shipped model or anything under `~/Downloads`.
- Never delete data or checkpoints. Write only inside `/tmp/pupil_run3`.
- Nothing on the GPU while training runs.
- Report numbers exactly as measured. Never round in the model's favour.
- Never pick a checkpoint by looking at a test set (`val_test`,
  `teyed_prepared`, `kaggle_eyes`, `synth_clean/test`).

## Each check (every ~2 hours)

1. Tail `/tmp/pupil_run3/metrics.jsonl`, `supervisor.log`, `train.log`;
   `pgrep -f train_phone.py`; `df -h /`; and the download/prep logs.
2. **Stalled**: process alive, newest `progress` event over 45 minutes old ->
   `pkill -f "train_phone.py.*pupil_run3"`; the supervisor resumes. Note it.
   (A gap that matches the Mac sleeping is not a stall; say so.)
3. **Gave up**: write the last error from `train.log` into the status file
   and stop. Do not fix code.
4. Disk under 3 GB: warn. Delete nothing.
5. Append to `/tmp/pupil_run3/STATUS.md`: time, epoch/step, s/step, ETA,
   restarts, whether synthetic mixing is on, and the newest `selection_eval`
   (`results` = OpenEDS selection, `extra_results` = synthetic selection):
   iris IoU, pupil IoU and pupil mm error for each condition.

## When `metrics.jsonl` has `"event": "finished"`

1. **Pick a checkpoint** from `selection_eval` events only.
   - Eligible: OpenEDS (`results`) clean iris >= 0.9445 and clean pupil >=
     0.9566 (the shipped model's selection-set values from the first run).
   - Prefer epochs that have `extra_results`. Among eligible ones, choose the
     highest mean of four numbers: OpenEDS clean pupil IoU; OpenEDS mean of
     (iris+pupil)/2 over non-clean conditions; synthetic clean (iris+pupil)/2;
     synthetic mean of (iris+pupil)/2 over non-clean conditions.
   - If none is eligible, say so, and still benchmark the best by that score,
     marked as failing eligibility.
2. **Benchmark** shipped vs chosen, every condition:
   ```bash
   cd /tmp/pupil_code2
   python3 benchmark.py --model shipped=finetuned_pupil_segmentation.pt \
     --model candidate=/tmp/pupil_run3/epochN.pt \
     --data openeds_test=/tmp/openeds_prepared/val_test \
     --data synth_test=/tmp/synth_clean/test \
     --data teyed_cross=/tmp/teyed_prepared \
     --data kaggle_cross=/tmp/kaggle_eyes \
     --out /tmp/pupil_run3/benchmark.json > /tmp/pupil_run3/benchmark.log 2>&1
   ```
   Skip any `--data` whose directory does not exist, and say which.
3. **Export and verify Core ML**, on the bar's frames:
   ```bash
   python3 export_coreml.py --weights /tmp/pupil_run3/epochN.pt --out /tmp/pupil_run3/Candidate.mlpackage
   python3 verify_coreml.py --package /tmp/pupil_run3/Candidate.mlpackage \
     --weights /tmp/pupil_run3/epochN.pt --eval-data /tmp/openeds_prepared/val_test --every 4
   ```
4. Write `/tmp/pupil_run3/REPORT.md` with PASS or FAIL per criterion, with
   numbers:
   1. Core ML clean on `val_test` (every 4th frame): iris >= 0.9490 and
      pupil >= 0.9730.
   2. `openeds_test`: beats shipped on the mean of (iris+pupil)/2 over the
      non-clean conditions.
   3. `teyed_cross` (a camera never trained on): beats shipped on clean pupil
      IoU and on clean (iris+pupil)/2.
   4. `kaggle_cross` (another camera never trained on): same as 3.
   5. `synth_test` (visible light): beats shipped on clean and on the
      non-clean mean.
   Also: the chosen epoch and why, full tables, the verify output, and what
   this does not show (no real iPhone visible-light captures; synthetic
   renders are not real people).
5. Then delete your scheduled job.
