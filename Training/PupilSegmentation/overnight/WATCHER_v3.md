# Watcher instructions: run 4 (ResNet34 U-Net)

Training runs in tmux session `pupil-train4` under
`overnight/run_training_v3.sh`, output in `/tmp/pupil_run4`, code in
`/tmp/pupil_code4`. Architecture: `--arch resnet34` (every model command below
needs `@resnet34` or `--arch resnet34` for this run's checkpoints).

## Hard limits

- Never touch a git repository, never commit or push, never edit code.
- Never replace the shipped model or anything under `~/Downloads`.
- Never delete data or checkpoints. Write only inside `/tmp/pupil_run4`.
- Nothing on the GPU while training runs.
- Report numbers exactly as measured. Never round in the model's favour.
- Never pick a checkpoint by looking at a test set (`val_test`,
  `teyed_prepared`, `kaggle_eyes`, `synth_clean/test`).
- To stop a stalled run use exactly `pkill -f "python3 -u train_phone.py"`.

## Each check (every ~2 hours)

Same as before: tail metrics.jsonl / supervisor.log / train.log, check the
process, `df -h /`, stall rule (no `progress` event for 45 minutes while alive
and the Mac was awake), and append a status block to
`/tmp/pupil_run4/STATUS.md` with the newest `selection_eval` (`results` =
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
2. **Benchmark** shipped, run 3, and the chosen run-4 epoch:
   ```bash
   cd /tmp/pupil_code4
   python3 benchmark.py --model shipped=finetuned_pupil_segmentation.pt \
     --model run3=/tmp/pupil_run3/epoch6.pt \
     --model run4=/tmp/pupil_run4/epochN.pt@resnet34 \
     --data openeds_test=/tmp/openeds_prepared/val_test \
     --data synth_test=/tmp/synth_clean/test \
     --data teyed_cross=/tmp/teyed_prepared \
     --data kaggle_cross=/tmp/kaggle_eyes \
     --out /tmp/pupil_run4/benchmark.json > /tmp/pupil_run4/benchmark.log 2>&1
   ```
3. **Export and verify** at float32 and float16 (size matters in an app):
   ```bash
   python3 export_coreml.py --arch resnet34 --weights /tmp/pupil_run4/epochN.pt --out /tmp/pupil_run4/Run4.mlpackage
   python3 verify_coreml.py --arch resnet34 --package /tmp/pupil_run4/Run4.mlpackage \
     --weights /tmp/pupil_run4/epochN.pt --eval-data /tmp/openeds_prepared/val_test --every 4
   python3 export_coreml.py --arch resnet34 --precision float16 --weights /tmp/pupil_run4/epochN.pt --out /tmp/pupil_run4/Run4-fp16.mlpackage
   python3 verify_coreml.py --arch resnet34 --package /tmp/pupil_run4/Run4-fp16.mlpackage \
     --weights /tmp/pupil_run4/epochN.pt --eval-data /tmp/openeds_prepared/val_test --every 4
   ```
   Record both packages' sizes (`du -sh`).
4. Write `/tmp/pupil_run4/REPORT.md`: PASS/FAIL per criterion with numbers
   for run 4 against shipped (and run 3 alongside for context):
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
