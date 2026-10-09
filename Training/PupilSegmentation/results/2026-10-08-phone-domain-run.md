# Overnight pupil-segmentation fine-tune: report

Run: /tmp/pupil_run, started 2026-10-08 08:26:57, finished 19:09:18 CDT. 8 epochs, 1 supervisor attempt, 0 restarts.
Init: finetuned_pupil_segmentation.pt (the shipped model). lr 5e-05, batch 2, augment_prob 0.7, seed 0.

## Overall verdict: FAIL

| criterion | bar | candidate (epoch 8) | shipped | result |
|---|---|---|---|---|
| Core ML clean iris IoU, val_test every 4th frame | >= 0.9490 | 0.9662 | n/a | **PASS** |
| Core ML clean pupil IoU, val_test every 4th frame | >= 0.9730 | 0.9685 | n/a | **FAIL** (0.0045 short) |
| Beat shipped on mean of non-clean conditions (openeds_test, every frame, (iris+pupil)/2 over 12 conditions) | > shipped | 0.94518 | 0.84154 | **PASS** |
| Beat shipped on kaggle_cross | > shipped | all-condition (iris+pupil)/2 0.22224; clean 0.20135; non-clean 0.22398 | 0.23218; 0.28135; 0.22808 | **FAIL** (worse on all three summaries) |

The candidate is much more robust to degraded images on OpenEDS. It does not meet the clean pupil bar, and it does not beat the shipped model on kaggle_cross. Do not ship it on this evidence.

## Chosen checkpoint: epoch8.pt

Chosen from the `selection_eval` events in metrics.jsonl (val_select, every 4th frame, 1005 frames, 27 subjects); the test set was not used.
Eligibility: clean iris IoU >= 0.9445 - 0.003 = 0.9415 and clean pupil IoU >= 0.9566 - 0.003 = 0.9536 (epoch-0 values).

| epoch | clean iris | clean pupil | eligible | non-clean mean (iris+pupil)/2 |
|---|---|---|---|---|
| 0 | 0.9445 | 0.9566 | (baseline) | 0.69000 |
| 1 | 0.9543 | 0.9416 | no | 0.90823 |
| 2 | 0.9564 | 0.9550 | yes | 0.92274 |
| 3 | 0.9634 | 0.9625 | yes | 0.93024 |
| 4 | 0.9638 | 0.9633 | yes | 0.92651 |
| 5 | 0.9667 | 0.9573 | yes | 0.92963 |
| 6 | 0.9644 | 0.9608 | yes | 0.93381 |
| 7 | 0.9677 | 0.9588 | yes | 0.93463 |
| 8 | 0.9692 | 0.9629 | yes | **0.93619** |

Epoch 8 is eligible and has the highest non-clean mean, so no cool-down epoch was run.

## Benchmark: shipped vs candidate (PyTorch, every frame, every condition)

Command: benchmark.py with shipped=finetuned_pupil_segmentation.pt, candidate=/tmp/pupil_run/epoch8.pt, data openeds_test=/tmp/openeds_prepared/val_test, kaggle_cross=/tmp/kaggle_eyes. Raw output: benchmark.json, benchmark.log.

### openeds_test (1349 frames in set, subjects 10)

| condition | held out of training | frames | shipped iris | cand iris | shipped pupil | cand pupil | shipped miss | cand miss | shipped mm med | cand mm med |
|---|---|---|---|---|---|---|---|---|---|---|
| clean | False | 1341 | 0.9478 | 0.9659 | 0.9729 | 0.9681 | 0.0082 | 0.0112 | 0.048 | 0.022 |
| lowres_200px | False | 1341 | 0.9395 | 0.9384 | 0.939 | 0.9447 | 0.0194 | 0.0224 | 0.048 | 0.037 |
| lowres_120px | False | 1341 | 0.9043 | 0.9398 | 0.8904 | 0.9491 | 0.0313 | 0.0142 | 0.103 | 0.051 |
| gaussian_blur_2px | False | 1341 | 0.9398 | 0.9311 | 0.9382 | 0.9416 | 0.0194 | 0.0268 | 0.049 | 0.039 |
| motion_blur_9px | False | 1341 | 0.9442 | 0.9544 | 0.9481 | 0.9603 | 0.0164 | 0.0134 | 0.048 | 0.031 |
| sensor_noise | False | 1341 | 0.9203 | 0.9614 | 0.9014 | 0.9624 | 0.0157 | 0.0112 | 0.093 | 0.023 |
| dark_iris | False | 1341 | 0.9207 | 0.9766 | 0.9155 | 0.9521 | 0.0328 | 0.0112 | 0.127 | 0.057 |
| low_light | False | 1341 | 0.6292 | 0.9285 | 0.6836 | 0.9037 | 0.3199 | 0.0164 | 0.353 | 0.107 |
| overexposed | False | 1341 | 0.9502 | 0.963 | 0.9744 | 0.9706 | 0.0089 | 0.0119 | 0.049 | 0.024 |
| glints | False | 1341 | 0.8923 | 0.9547 | 0.8356 | 0.9353 | 0.0813 | 0.0172 | 0.115 | 0.044 |
| jpeg_q25 | True | 1341 | 0.9206 | 0.9579 | 0.9424 | 0.9588 | 0.0186 | 0.0127 | 0.06 | 0.026 |
| defocus_4px | True | 1341 | 0.9367 | 0.9333 | 0.9378 | 0.9428 | 0.0142 | 0.0246 | 0.055 | 0.04 |
| phone_combo | False | 1341 | 0.2409 | 0.9474 | 0.152 | 0.8765 | 0.9299 | 0.0134 | 1.623 | 0.107 |

openeds_test shipped: non-clean mean iris 0.84489 pupil 0.83820 (iris+pupil)/2 0.84154; all-condition mean (iris+pupil)/2 0.85068 (truncated, not rounded)

openeds_test candidate: non-clean mean iris 0.94887 pupil 0.94149 (iris+pupil)/2 0.94518; all-condition mean (iris+pupil)/2 0.94686 (truncated, not rounded)

### kaggle_cross (1158 frames in set, subjects 85)

| condition | held out of training | frames | shipped iris | cand iris | shipped pupil | cand pupil | shipped miss | cand miss | shipped mm med | cand mm med |
|---|---|---|---|---|---|---|---|---|---|---|
| clean | False | 1158 | 0.414 | 0.2575 | 0.1487 | 0.1452 | 0.8592 | 0.9033 | 4.262 | 4.075 |
| lowres_200px | False | 1158 | 0.3366 | 0.311 | 0.146 | 0.1455 | 0.8713 | 0.9033 | 4.205 | 4.21 |
| lowres_120px | False | 1158 | 0.2509 | 0.2847 | 0.1256 | 0.1352 | 0.8972 | 0.9067 | 4.277 | 4.252 |
| gaussian_blur_2px | False | 1158 | 0.3308 | 0.3139 | 0.1445 | 0.1473 | 0.8739 | 0.9033 | 4.208 | 4.193 |
| motion_blur_9px | False | 1158 | 0.3347 | 0.2998 | 0.1322 | 0.1474 | 0.88 | 0.9093 | 4.416 | 4.094 |
| sensor_noise | False | 1158 | 0.2973 | 0.1755 | 0.2216 | 0.0997 | 0.7824 | 0.9231 | 2.703 | 4.443 |
| dark_iris | False | 1158 | 0.5118 | 0.5073 | 0.1361 | 0.1743 | 0.8782 | 0.8696 | 4.49 | 4.214 |
| low_light | False | 1158 | 0.168 | 0.1368 | 0.1087 | 0.0797 | 0.8877 | 0.9352 | 4.231 | 4.765 |
| overexposed | False | 1158 | 0.3312 | 0.196 | 0.1593 | 0.1314 | 0.8506 | 0.9067 | 4.039 | 4.08 |
| glints | False | 1158 | 0.405 | 0.2798 | 0.1349 | 0.144 | 0.8946 | 0.9059 | 4.079 | 4.108 |
| jpeg_q25 | True | 1158 | 0.2843 | 0.2651 | 0.1001 | 0.1299 | 0.8912 | 0.9085 | 4.739 | 4.256 |
| defocus_4px | True | 1158 | 0.3235 | 0.3104 | 0.1422 | 0.1453 | 0.8739 | 0.9033 | 4.227 | 4.217 |
| phone_combo | False | 1158 | 0.3131 | 0.5553 | 0.0356 | 0.2604 | 0.9896 | 0.6857 | 4.721 | 3.275 |

kaggle_cross shipped: non-clean mean iris 0.32393 pupil 0.13223 (iris+pupil)/2 0.22808; all-condition mean (iris+pupil)/2 0.23218 (truncated, not rounded)

kaggle_cross candidate: non-clean mean iris 0.30296 pupil 0.14500 (iris+pupil)/2 0.22398; all-condition mean (iris+pupil)/2 0.22224 (truncated, not rounded)

Notes on the benchmark:
- On openeds_test the candidate's clean pupil IoU (0.9681) is below the shipped model's (0.9729), and clean pupil miss rate goes up (0.0112 vs 0.0082). Clean iris improves (0.9659 vs 0.9478). The candidate is also slightly below shipped on overexposed pupil (0.9706 vs 0.9744), lowres_200px iris (0.9384 vs 0.9395), gaussian_blur_2px iris (0.9311 vs 0.9398) and defocus_4px iris (0.9333 vs 0.9367). Its largest gains are phone_combo, low_light, glints and dark_iris.
- "held out of training" is False for 11 of 13 conditions: the training augmentations include those degradations. Only jpeg_q25 and defocus_4px are held out. On those two, openeds_test (iris+pupil)/2 is candidate 0.95835 vs shipped 0.9315 (jpeg_q25) and 0.93805 vs 0.93725 (defocus_4px).
- On kaggle_cross both models largely fail: pupil miss rate is 0.78–0.99 for shipped and 0.69–0.94 for candidate, with median pupil error around 4 mm. The candidate is better only on phone_combo (pupil IoU 0.2604 vs 0.0356) and on a few small differences elsewhere. It is clearly worse on clean iris (0.2575 vs 0.4140), sensor_noise and overexposed. Results this low may reflect a domain or label mismatch in that set rather than ordinary accuracy. This run does not establish which.

## Core ML export and verification

export_coreml.py --weights /tmp/pupil_run/epoch8.pt --out /tmp/pupil_run/Candidate.mlpackage (exit 0; log export.log; warnings about untested scikit-learn 1.7.1 / torch 2.7.1 versions in coremltools).

verify_coreml.py --package /tmp/pupil_run/Candidate.mlpackage --weights /tmp/pupil_run/epoch8.pt --eval-data /tmp/openeds_prepared/val_test --every 4 (exit 0; log verify.log):

```
Core ML package scored on 338 frames from 10 subjects
  IoU[background]: 0.9978
  IoU[iris]: 0.9662
  IoU[pupil]: 0.9685
Mean IoU (iris, pupil): 0.9673
Pixels where Core ML and PyTorch disagree: 0.00001%
```

## What this does not show

- None of these images are visible-light iPhone captures. OpenEDS is near-infrared headset imagery. The "phone_combo", "low_light" and other conditions are synthetic degradations of those images, and most are also used as training augmentations. Nothing here measures performance on real phone camera frames.
- kaggle_cross scores are very low for both models, so it says little about which model generalises better to real-world eyes.
- One run, one seed. No confidence intervals were computed, and differences of a few thousandths may not be meaningful.
- The shipped model was not re-exported or re-verified in Core ML. Its numbers above are PyTorch only.

## Files (all in /tmp/pupil_run)

epoch1–8.pt, last.pt, metrics.jsonl, train.log, supervisor.log, STATUS.md, benchmark.json, benchmark.log, benchmark_table.md, Candidate.mlpackage, export.log, verify.log, REPORT.md. Nothing was deleted; the shipped model and ~/Downloads were not touched.

## Follow-up, 2026-10-09 (Shrey's session): why kaggle_cross fails for both models

`2026-10-08-kaggle-predictions.png` shows four kaggle_cross frames: image,
cleaned label, shipped prediction, candidate prediction. Two things:

- **Both models paint the large black pupil as iris** and mark only a sliver
  as pupil. They learned what a pupil looks like in OpenEDS's headset camera
  (small, ringed by LED glints) and do not recognise one from a different
  camera. The phone-style augmentations made the candidate far more robust
  *within* OpenEDS; they did not teach it a pupil it has never seen.
- **Some kaggle labels are still poor after cleaning** (the first frame's
  "true" pupil is an off-centre crescent), so kaggle_cross IoU understates
  both models somewhat. It does not explain the failure above.

**Decision:** the shipped model stays. The candidate is kept as
`candidate_phone_domain_epoch8.pt`, a better starting point for the next
run, which needs eye images from other cameras (ideally visible-light phone
images such as MOBIUS) rather than more OpenEDS footage.
