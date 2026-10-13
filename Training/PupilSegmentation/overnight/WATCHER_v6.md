# Watcher instructions: run 7

Training runs in tmux session `pupil-run7` under `overnight/run_training_v6.sh`;
output in `~/SoberTraining/runs/run7`, code in
`~/Downloads/soberai-fixes/Training/PupilSegmentation`. Run 7 starts from run 6's
epoch4.pt and adds pupil dilation/constriction and close-up re-cropping (see the
script header for why). Every model command needs `@resnet34` or `--arch resnet34`.

## Hard limits

- Everything is under `~/SoberTraining`, never `/tmp`.
- Never touch a git repository, never commit or push, never edit code.
- Never replace the shipped model or anything under `~/Downloads`.
- Never delete data or checkpoints. Write only inside `~/SoberTraining/runs/run7`.
- Nothing on the GPU while training runs.
- Report numbers exactly as measured. Never round in the model's favour.
- Never pick a checkpoint or an offset by looking at a test set
  (`openeds/val_test`, `teyed`, `kaggle_test`, `kaggle`, `synth/test`).
- To stop a stalled run use exactly `pkill -f "python3 -u train_phone.py"`.

## Each check (every ~2 hours)

Tail metrics.jsonl / supervisor.log / train.log, check the process, `df -h /`,
stall rule (no `progress` event for 45 minutes while alive and the Mac was
awake), and append a status block to `~/SoberTraining/runs/run7/STATUS.md` with
the newest `selection_eval` (`results` = OpenEDS selection, `extra_results` =
synthetic selection, `cross_results` = kaggle_select).

## When `metrics.jsonl` has `"event": "finished"`

All commands from `~/Downloads/soberai-fixes/Training/PupilSegmentation`.

1. **Calibrate every epoch** (selection data only):
   ```bash
   for n in 1 2 3 4 5 6; do python3 calibrate.py --weights ~/SoberTraining/runs/run7/epoch$n.pt --arch resnet34 \
     --select ~/SoberTraining/data/openeds/val_select --cross-select ~/SoberTraining/data/kaggle_select \
     --out ~/SoberTraining/runs/run7/calibration_epoch$n.json; done
   ```
2. **Pick an epoch by this rule, fixed before training started**, using each
   epoch's calibrated scores at its `chosen_offset`:
   - Eligible: OpenEDS selection clean pupil >= 0.9629, clean iris >= 0.9445,
     and kaggle_select clean pupil >= 0.65.
   - Among eligible epochs, choose the highest kaggle_select clean (iris+pupil)/2.
   - If none is eligible: among epochs with kaggle_select clean pupil >= 0.65,
     the highest OpenEDS clean pupil; if there are none, the highest OpenEDS
     clean pupil overall. Mark it FAILING ELIGIBILITY.
   Call the epoch N and its offset D.
3. **Benchmark** (D is the number from calibration_epochN.json):
   ```bash
   python3 benchmark.py --model shipped=finetuned_pupil_segmentation.pt \
     --model run4=$HOME/SoberTraining/runs/run4/epoch1.pt@resnet34 \
     --model run6=$HOME/SoberTraining/runs/run6/epoch4.pt@resnet34 \
     --model run7_raw=$HOME/SoberTraining/runs/run7/epochN.pt@resnet34 \
     --model run7=$HOME/SoberTraining/runs/run7/epochN.pt@resnet34:D \
     --data openeds_test=$HOME/SoberTraining/data/openeds/val_test \
     --data teyed_cross=$HOME/SoberTraining/data/teyed \
     --data kaggle_test=$HOME/SoberTraining/data/kaggle_test \
     --data synth_test=$HOME/SoberTraining/data/synth/test \
     --out $HOME/SoberTraining/runs/run7/benchmark.json > $HOME/SoberTraining/runs/run7/benchmark.log 2>&1
   ```
4. **Export and verify** the calibrated model at float32 and float16:
   ```bash
   python3 export_coreml.py --arch resnet34 --pupil-offset D --weights ~/SoberTraining/runs/run7/epochN.pt --out ~/SoberTraining/runs/run7/Run7.mlpackage
   python3 verify_coreml.py --arch resnet34 --pupil-offset D --package ~/SoberTraining/runs/run7/Run7.mlpackage \
     --weights ~/SoberTraining/runs/run7/epochN.pt --eval-data ~/SoberTraining/data/openeds/val_test --every 4
   python3 export_coreml.py --arch resnet34 --pupil-offset D --precision float16 --weights ~/SoberTraining/runs/run7/epochN.pt --out ~/SoberTraining/runs/run7/Run7-fp16.mlpackage
   python3 verify_coreml.py --arch resnet34 --pupil-offset D --package ~/SoberTraining/runs/run7/Run7-fp16.mlpackage \
     --weights ~/SoberTraining/runs/run7/epochN.pt --eval-data ~/SoberTraining/data/openeds/val_test --every 4
   ```
   Record both packages' sizes (`du -sh`).
5. **Edge bias** of the chosen model, raw and calibrated:
   ```bash
   python3 ~/SoberTraining/scripts/diag_boundary.py "$PWD" ~/SoberTraining/data/openeds/val_select 4 \
     run7_raw=$HOME/SoberTraining/runs/run7/epochN.pt@resnet34 run7=$HOME/SoberTraining/runs/run7/epochN.pt@resnet34:D
   ```
6. Write `~/SoberTraining/runs/run7/REPORT.md`: PASS/FAIL per criterion for
   `run7` (calibrated) against shipped, with run4, run6 and run7_raw alongside:
   1. Core ML clean on `val_test` (every 4th frame): iris >= 0.9490 and pupil >= 0.9730.
   2. `openeds_test`: beats shipped on the non-clean mean of (iris+pupil)/2.
   3. `teyed_cross`: beats shipped on clean pupil IoU and clean (iris+pupil)/2.
   4. `kaggle_test`: same as 3.
   5. `synth_test`: beats shipped on clean and on the non-clean mean.
   Plus: the per-epoch calibration table and which epoch/offset was chosen and
   why, full tables, verify outputs, package sizes, edge bias, and what this
   does not show (no real iPhone captures; kaggle_test is near-infrared, not
   visible light; synth_test labels include some wrong frames; one seed). Note
   that the OpenEDS licence is unconfirmed, so no OpenEDS-trained model is
   cleared to ship, whatever it scores.
7. Then delete your scheduled job.
