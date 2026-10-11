# Watcher instructions: run 4 (ResNet34 U-Net)

The pipeline runs in tmux session `pupil-pipeline` under
`overnight/pipeline.sh` (downloads, data prep, a one-epoch judge, then run 4); its log is `~/SoberTraining/pipeline.log`, output in `~/SoberTraining/runs/run4`, code in
`~/Downloads/soberai-fixes/Training/PupilSegmentation`. Architecture: `--arch resnet34` (every model command below
needs `@resnet34` or `--arch resnet34` for this run's checkpoints).

## Hard limits

- Everything is under `~/SoberTraining`, never `/tmp` (a restart wiped `/tmp` once already).

- Never touch a git repository, never commit or push, never edit code.
- Never replace the shipped model or anything under `~/Downloads`.
- Never delete data or checkpoints. Write only inside `~/SoberTraining/runs/run4`.
- Nothing on the GPU while training runs.
- Report numbers exactly as measured. Never round in the model's favour.
- Never pick a checkpoint by looking at a test set (`val_test`,
  `teyed_prepared`, `kaggle_eyes`, `synth_clean/test`).
- To stop a stalled run use exactly `pkill -f "python3 -u train_phone.py"`.

## Each check (every ~2 hours)

Same as before: tail metrics.jsonl / supervisor.log / train.log, check the
process, `df -h /`, stall rule (no `progress` event for 45 minutes while alive
and the Mac was awake), and append a status block to
`~/SoberTraining/runs/run4/STATUS.md` with the newest `selection_eval` (`results` =
OpenEDS selection, `extra_results` = synthetic selection).

## When `metrics.jsonl` has `"event": "finished"`

1. **Pick a checkpoint by this rule, fixed before training started:**
   - Eligible: OpenEDS clean pupil IoU >= 0.9629 and clean iris IoU >= 0.9445
     on the selection set (0.9629 is the best clean pupil any earlier model
     reached on this set; 0.9445 is the shipped model's clean iris).
   - Among eligible epochs, choose the highest mean of synthetic (iris+pupil)/2
     over all conditions (clean and degraded) in `extra_results`.
   - If none is eligible, choose the epoch with the highest OpenEDS clean
     pupil, and mark it FAILING ELIGIBILITY in the report.
2. **Benchmark** shipped and the chosen run-4 epoch:
   ```bash
   cd ~/Downloads/soberai-fixes/Training/PupilSegmentation
   python3 benchmark.py --model shipped=finetuned_pupil_segmentation.pt \
          --model run4=~/SoberTraining/runs/run4/epochN.pt@resnet34 \
     --data openeds_test=~/SoberTraining/data/openeds/val_test \
     --data synth_test=~/SoberTraining/data/synth/test \
     --data teyed_cross=~/SoberTraining/data/teyed \
     --data kaggle_cross=~/SoberTraining/data/kaggle \
     --out ~/SoberTraining/runs/run4/benchmark.json > ~/SoberTraining/runs/run4/benchmark.log 2>&1
   ```
3. **Export and verify** at float32 and float16 (size matters in an app):
   ```bash
   python3 export_coreml.py --arch resnet34 --weights ~/SoberTraining/runs/run4/epochN.pt --out ~/SoberTraining/runs/run4/Run4.mlpackage
   python3 verify_coreml.py --arch resnet34 --package ~/SoberTraining/runs/run4/Run4.mlpackage \
     --weights ~/SoberTraining/runs/run4/epochN.pt --eval-data ~/SoberTraining/data/openeds/val_test --every 4
   python3 export_coreml.py --arch resnet34 --precision float16 --weights ~/SoberTraining/runs/run4/epochN.pt --out ~/SoberTraining/runs/run4/Run4-fp16.mlpackage
   python3 verify_coreml.py --arch resnet34 --package ~/SoberTraining/runs/run4/Run4-fp16.mlpackage \
     --weights ~/SoberTraining/runs/run4/epochN.pt --eval-data ~/SoberTraining/data/openeds/val_test --every 4
   ```
   Record both packages' sizes (`du -sh`).
4. Write `~/SoberTraining/runs/run4/REPORT.md`: PASS/FAIL per criterion with numbers
   for run 4 against shipped (run 3's checkpoints were lost in a restart; quote its numbers from its saved report if useful):
   1. Core ML clean on `val_test` (every 4th frame): iris >= 0.9490 and pupil >= 0.9730.
   2. `openeds_test`: beats shipped on the non-clean mean of (iris+pupil)/2.
   3. `teyed_cross`: beats shipped on clean pupil IoU and clean (iris+pupil)/2.
   4. `kaggle_cross`: same as 3.
   5. `synth_test`: beats shipped on clean and on the non-clean mean.
   Plus: chosen epoch and why, full tables, verify outputs for both
   precisions, package sizes, and what this does not show. Note that the
   OpenEDS licence is unconfirmed, so no OpenEDS-trained model is cleared to
   ship, whatever it scores.
5. Then delete your scheduled job.
