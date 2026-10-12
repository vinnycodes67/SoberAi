# Watcher instructions: run 6 (run 4 fine-tuned without blur and re-cropping augmentation)

Training runs in tmux session `pupil-run6` under `overnight/run_training_v5.sh`;
output in `~/SoberTraining/runs/run6`, code in
`~/Downloads/soberai-fixes/Training/PupilSegmentation`. It starts from run 4's epoch8.pt with equal class weights, a 3 px ring
around the synthetic pupil outline ignored, and the blur and re-cropping
augmentations off, because short tests showed those inflate the pupil
(area ratio 1.107 with every augmentation, 1.027 without blur, 1.029 without
re-cropping). Architecture:
`--arch resnet34` (every model command below needs `@resnet34` or
`--arch resnet34`).

## Hard limits

- Everything is under `~/SoberTraining`, never `/tmp` (a restart wiped `/tmp` once already).

- Never touch a git repository, never commit or push, never edit code.
- Never replace the shipped model or anything under `~/Downloads`.
- Never delete data or checkpoints. Write only inside `~/SoberTraining/runs/run6`.
- Nothing on the GPU while training runs.
- Report numbers exactly as measured. Never round in the model's favour.
- Never pick a checkpoint by looking at a test set (`val_test`,
  `teyed_prepared`, `kaggle_eyes`, `synth_clean/test`).
- To stop a stalled run use exactly `pkill -f "python3 -u train_phone.py"`.

## Each check (every ~2 hours)

Same as before: tail metrics.jsonl / supervisor.log / train.log, check the
process, `df -h /`, stall rule (no `progress` event for 45 minutes while alive
and the Mac was awake), and append a status block to
`~/SoberTraining/runs/run6/STATUS.md` with the newest `selection_eval` (`results` =
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
          --model run6=~/SoberTraining/runs/run6/epochN.pt@resnet34 \
     --data openeds_test=~/SoberTraining/data/openeds/val_test \
     --data synth_test=~/SoberTraining/data/synth/test \
     --data teyed_cross=~/SoberTraining/data/teyed \
     --data kaggle_cross=~/SoberTraining/data/kaggle \
     --out ~/SoberTraining/runs/run6/benchmark.json > ~/SoberTraining/runs/run6/benchmark.log 2>&1
   ```
3. **Export and verify** at float32 and float16 (size matters in an app):
   ```bash
   python3 export_coreml.py --arch resnet34 --weights ~/SoberTraining/runs/run6/epochN.pt --out ~/SoberTraining/runs/run6/Run6.mlpackage
   python3 verify_coreml.py --arch resnet34 --package ~/SoberTraining/runs/run6/Run6.mlpackage \
     --weights ~/SoberTraining/runs/run6/epochN.pt --eval-data ~/SoberTraining/data/openeds/val_test --every 4
   python3 export_coreml.py --arch resnet34 --precision float16 --weights ~/SoberTraining/runs/run6/epochN.pt --out ~/SoberTraining/runs/run6/Run6-fp16.mlpackage
   python3 verify_coreml.py --arch resnet34 --package ~/SoberTraining/runs/run6/Run6-fp16.mlpackage \
     --weights ~/SoberTraining/runs/run6/epochN.pt --eval-data ~/SoberTraining/data/openeds/val_test --every 4
   ```
   Record both packages' sizes (`du -sh`).
4. Write `~/SoberTraining/runs/run6/REPORT.md`: PASS/FAIL per criterion with numbers
   for run 6 against shipped, and against run 4 epoch 1 (`~/SoberTraining/runs/run4/REPORT.md`):
   1. Core ML clean on `val_test` (every 4th frame): iris >= 0.9490 and pupil >= 0.9730.
   2. `openeds_test`: beats shipped on the non-clean mean of (iris+pupil)/2.
   3. `teyed_cross`: beats shipped on clean pupil IoU and clean (iris+pupil)/2.
   4. `kaggle_cross`: same as 3.
   5. `synth_test`: beats shipped on clean and on the non-clean mean.
   Plus: chosen epoch and why, a note that re-cropping robustness is not measured by any benchmark condition and this run trained without it, full tables, verify outputs for both
   precisions, package sizes, and what this does not show. Note that the
   OpenEDS licence is unconfirmed, so no OpenEDS-trained model is cleared to
   ship, whatever it scores.
5. Then delete your scheduled job.

## Extra measurement for the report

Pupil edge bias of the chosen epoch on the selection set (area ratio near 1.00 is the goal; run 4 epoch 8 was 1.073, shipped 1.008):
```bash
python3 ~/SoberTraining/scripts/diag_boundary.py "$PWD" ~/SoberTraining/data/openeds/val_select 4 \
  shipped=finetuned_pupil_segmentation.pt run6=~/SoberTraining/runs/run6/epochN.pt@resnet34
```
