# Pupil/iris segmentation model — provenance and how to reproduce

`Sober/Services/PupilCaptureService.swift` has always expected a bundled
`PupilSegmentation.mlmodelc` for the pupillary-light-reflex protocol, and
none existed — the pipeline gracefully degraded to "no reading" for
every trial. This directory documents where the shipped model actually
comes from and how to reproduce or re-run it.

## What this is

- **Architecture**: RITnet, a ~249K-parameter DenseNet/U-Net hybrid for
  real-time eye segmentation (Chaudhary et al., *"RITnet: real-time
  semantic segmentation of the eye for gaze tracking,"* ICCVW 2019).
  `vendor_ritnet/densenet.py` is vendored unmodified from
  [AayushKrChaudhary/RITnet](https://github.com/AayushKrChaudhary/RITnet)
  (MIT License, `vendor_ritnet/RITNET_LICENSE.md`).
- **Pretrained weights**: `vendor_ritnet/ritnet_openeds2019_pretrained.pkl`
  is the authors' own `best_model.pkl`, checked into their repo, trained
  on OpenEDS2019 (95.78% reported validation accuracy across
  background/sclera/iris/pupil).
- **Fine-tuning data**: 4 shards (1,348 frames, 10 subjects) of
  [OpenEDS2020](https://research.facebook.com/publications/openeds2020-open-eyes-dataset/)
  (Facebook Reality Labs), pulled from the public mirror at
  [phorosyne/OpenEDS_2020_Shards](https://huggingface.co/datasets/phorosyne/OpenEDS_2020_Shards)
  on Hugging Face Hub — same 640x400 grayscale, same 4-class label
  convention as OpenEDS2019, a different capture session/subject pool.
  Split by subject (not frame) so held-out numbers aren't inflated by
  near-duplicate frames of the same eye: subjects 106/107 held out for
  eval, the other 8 subjects (1,192 frames) used for fine-tuning.

## Why fine-tuning was necessary, not optional

RITnet's own preprocessing — gamma correction, then OpenCV's CLAHE
(contrast-limited adaptive histogram equalization) — has no Core ML
equivalent; CLAHE is a per-tile classical histogram algorithm, not a
fixed graph of tensor ops, and Vision/Core ML can only run a static
graph on-device. `model.py`'s `LocalContrastNormalize` approximates
CLAHE's effect (local mean/variance normalization over a fixed window)
using only `avg_pool2d`, which *does* trace to Core ML. Swapping that in
with **zero fine-tuning** breaks the pretrained weights outright — see
"Results" below. Fine-tuning re-adapts the network to the substitute
preprocessing that actually ships, at a low learning rate so it mostly
retains the pretrained representation rather than re-learning from the
1,192 fine-tuning frames alone (which would be nowhere near enough data
on its own).

`evaluate.py`/`train.py`/`export_coreml.py` all use the *same*
`PupilSegmentationModel` module, so the reported numbers reflect what
actually ships in `PupilSegmentation.mlpackage` — not a nicer pipeline
that gets swapped out at export time.

All checkpoint loads use PyTorch's `weights_only=True` mode. The files are
tensor state dictionaries, so executable pickle deserialization is neither
needed nor permitted when a developer evaluates, fine-tunes, or exports a
checkpoint.

## Known limitation: domain gap to Sober's actual deployment

**OpenEDS is near-infrared (NIR) imagery from a VR-headset eye-tracking
camera** — extreme close-up, IR illumination with visible glint
reflections, a fisheye-ish lens. Sober's actual input is a **visible-light
iPhone front-camera frame**, cropped to the eye region via Vision face
landmarks and red-channel-boosted (see `PupilCaptureService.swift`'s
`redChannelBoosted`). These look meaningfully different — different
spectrum, different geometry, different noise characteristics. No public
dataset of *paired iPhone-camera eye photos with pixel-level pupil/iris
masks* was found to fine-tune against directly, and collecting one is
out of scope here (a real photography + labeling effort).

**What this means concretely**: the shipped model is a genuinely trained,
evaluated segmentation network — not a placeholder — but its accuracy
numbers below are only representative *on OpenEDS-style NIR imagery*.
On-device accuracy against real iPhone captures has not been measured
and is very likely lower. `ScreeningEngine.swift` already treats the
pupillometry signal this way by design (weight 0.25, quality-gated,
`nil` on a bad reading rather than fabricating one, and deliberately
excluded from the hard INCONCLUSIVE gate other tasks trigger) — the
architecture already assumes this signal can be degraded so it's the
right amount of caution, but it's real and worth re-stating: **this
model's accuracy on the actual deployment domain is unvalidated.**

## Results (held-out subjects 106/107, 156 frames, never seen during fine-tuning)

| Configuration | Pixel accuracy | IoU background | IoU iris | IoU pupil |
|---|---|---|---|---|
| Pretrained + Core ML-compatible substitute preprocessing, **no fine-tuning** | 0.9396 | 0.9396 | 0.0000 | 0.0000 |
| **Fine-tuned, 6 epochs, lr=5e-5 (what ships)** | **0.9967** | **0.9967** | **0.9435** | **0.9545** |

The un-fine-tuned row shows exactly the failure mode class-weighting in
`train.py` exists to fix: 93.96% pixel accuracy by predicting
background everywhere, since background is ~94% of every frame and iris/
pupil are small minorities — a fabricated-looking "high accuracy" number
that means the model detects nothing. `train.py` uses class-weighted
loss (background=1, iris=4, pupil=8) specifically so training can't
coast on that shortcut. Six epochs (1,192 training frames, held out
subjects 106/107 for eval) took ~13 minutes on an Apple M4 (MPS
backend); training loss dropped from 0.081 (epoch 1) to 0.011 (epoch 6)
with no sign of overfitting at this frame count. Per-epoch checkpoints
(`finetuned_pupil_segmentation.pt.epoch1..6`) are kept alongside the
final weights.

### Re-measured 2026-10-07: unseen people, and the package that ships

The table above scores 156 frames from 2 subjects. The official OpenEDS2020
`val` split holds 10 further subjects that appear in no training shard, so
it is a larger held-out set and is fair to both this model and any retrained
one. `verify_coreml.py` scores the exported Core ML package itself, which is
what the app runs, rather than the PyTorch weights it came from.

| Same weights, 1,349 val frames / 10 subjects (Core ML: every 4th frame) | IoU iris | IoU pupil | Pixels differing from PyTorch |
|---|---|---|---|
| PyTorch | 0.9478 | 0.9729 | — |
| Core ML, float16 (shipped until now) | 0.9251 | 0.9688 | 0.29% |
| **Core ML, float32 (ships now)** | **0.9490** | **0.9730** | 0.00002% |

The PyTorch row covers all 1,349 frames; the Core ML rows cover every 4th
frame. Float32 Core ML differs from PyTorch on 0.00002% of pixels, so its
slightly higher IoU comes from the smaller frame set, not from the model being
better than its own weights. Compare a candidate package with the Core ML rows
using `verify_coreml.py --every 4`.

The mlprogram default of float16 cost about 2 points of iris IoU. The model
has ~249K parameters, so float32 only grows the package from 592 KB to
1.0 MB. Float32 may run on the GPU rather than the Neural Engine; latency on
a phone has not been measured. `export_coreml.py` now defaults to float32.

**Tooling changes.** `prepare_data.py` downloads shards and stores them as
compact uint8 `.npz` files, reading the MDS format directly instead of
installing `mosaicml-streaming`, whose import pulls in `transformers`.
`dataset.py` holds frames as uint8: the old float32/int64 storage was about
3 MB a frame, roughly 4 GB at 1,348 frames rather than the ~350 MB its
docstring claimed, which ruled out training on more than four shards.
`splits.py` keeps the legacy 106/107 split so the table above still
reproduces exactly (it does), and adds the train/val split, which refuses to
run if a subject appears on both sides.

Export needs coremltools' tested torch (2.7). coremltools 9 crashed
(SIGSEGV) converting under torch 2.12, so export from a separate environment:

```bash
python3 -m venv /tmp/exportenv
/tmp/exportenv/bin/pip install "torch==2.7.0" "coremltools==9.0" "numpy<2.3" pillow
```

**Read this number correctly**: 94-95% IoU is genuinely strong — *on
OpenEDS-style NIR VR-headset imagery, the same distribution as both the
pretrained backbone's original training data and this fine-tuning set*.
It is not a measurement of accuracy on Sober's actual iPhone-camera
input; see "Known limitation" above for why that number doesn't exist
yet.

## Phone-domain training and the robustness benchmark (2026-10-08)

The numbers above are all on clean infrared frames. The app sees something
else: `PupilCaptureService` crops the eye out of a front-camera frame with a
30% margin and stretches it to 640x400, so the model gets a small, upscaled,
noisy crop, and in visible light a dark iris is nearly as dark as the pupil.

**How the shipped model holds up** (27 OpenEDS `val` subjects never trained
on, every 4th frame, measured before any retraining):

| Condition | IoU iris | IoU pupil | Pupil missed | Pupil error, median |
|---|---|---|---|---|
| clean | 0.9445 | 0.9566 | 1.1% of frames | 0.04 mm |
| eye 120 px wide in the camera frame | 0.8972 | 0.8815 | 4.3% | 0.11 mm |
| dark iris | 0.9316 | 0.8847 | 5.1% | 0.14 mm |
| low light | 0.6923 | 0.6832 | 28.8% | 0.19 mm |
| phone-style crop (all of the above, plus JPEG) | 0.3178 | 0.2317 | 80.2% | 1.31 mm |

"Pupil error" is what the app computes, the pupil-to-iris diameter ratio
times an 11.7 mm reference iris, from area-equivalent diameters. A frame with
no pupil found counts as 11.7 mm.

**What was added:**

- `phone_domain.py`: phone-camera degradations (re-crop and stretch,
  downscale with sensor noise, blur, exposure, darkened iris, corneal
  glints) for training, and 13 fixed benchmark conditions. JPEG and defocus
  are never used in training, so the benchmark also covers conditions the
  model was not taught. `test_phone_domain.py` checks labels follow every
  geometric change and are never touched by photometric ones.
- `stream_dataset.py` + `train_phone.py`: trains on all 65 OpenEDS2020 train
  shards (21,917 frames, 149 people, against 1,192 frames and 8 people
  before) while holding about three shards in memory. Resumable, logs JSON
  lines, picks checkpoints on `val_select` only.
- `make_val_splits.py`: `val_test` is val shards 0-3, the 10 subjects the
  0.9490 / 0.9730 bar was measured on; `val_select` is the other 27 subjects.
- `prepare_kaggle_eyes.py`: a second, independent test set from Kaggle's
  "Pupil Eye and Iris Segmentation" (1,158 frames, 85 people, after cleaning
  noisy labels). It is infrared iris-camera footage, not visible light, and
  of unclear provenance, so it is used to test only. It matters because it is
  a different camera and framing from OpenEDS.
- `benchmark.py`: scores any number of `.pt` or `.mlpackage` models on any
  prepared set under every condition.
- `overnight/`: the supervisor script and the instructions for the watcher
  session that ran the first long training run.

No public dataset of visible-light phone eye images with pupil masks can be
downloaded without a signed request (MOBIUS, I-SOCIAL-DB, MICHE-I). Until one
is obtained, nothing here measures accuracy on real iPhone captures.

```bash
python3 prepare_data.py --split train --shards 0-64
python3 prepare_data.py --split val --shards 0-16
python3 make_val_splits.py --val /tmp/openeds_prepared/val
python3 train_phone.py --out-dir /tmp/pupil_run --epochs 8
python3 benchmark.py --model shipped=finetuned_pupil_segmentation.pt \
    --model candidate=/tmp/pupil_run/epoch8.pt \
    --data openeds_test=/tmp/openeds_prepared/val_test --data kaggle_cross=/tmp/kaggle_eyes \
    --out benchmark.json
```

## Reproducing

```bash
cd Training/PupilSegmentation
pip install torch numpy pillow zstandard

# download and compact the data (about 65 MB per shard)
python3 prepare_data.py --split train --shards 0-9
python3 prepare_data.py --split val --shards 0-3

# fine-tune, scoring on people never trained on
python3 train.py --data /tmp/openeds_prepared/train --eval-data /tmp/openeds_prepared/val \
    --epochs 6 --out finetuned_pupil_segmentation.pt

# evaluate any checkpoint (omit --eval-data for the legacy 106/107 split)
python3 evaluate.py --weights finetuned_pupil_segmentation.pt --eval-data /tmp/openeds_prepared/val

# score the exported package the app actually runs (export environment, see above)
python3 verify_coreml.py --package PupilSegmentation.mlpackage \
    --weights finetuned_pupil_segmentation.pt --eval-data /tmp/openeds_prepared/val --every 4

# export to the .mlpackage Xcode compiles into PupilSegmentation.mlmodelc
python3 export_coreml.py --weights finetuned_pupil_segmentation.pt --out PupilSegmentation.mlpackage
```

## Citation

```
@inproceedings{chaudhary2019ritnet,
  title={RITnet: real-time semantic segmentation of the eye for gaze tracking},
  author={Chaudhary, Aayush K and Kothari, Rakshit and Acharya, Manoj and Dangi, Shusil and Nair, Nitinraj and Bailey, Reynold and Kanan, Christopher and Diaz, Gabriel and Pelz, Jeff B},
  booktitle={2019 IEEE/CVF International Conference on Computer Vision Workshop (ICCVW)},
  pages={3698--3702},
  year={2019},
  organization={IEEE}
}
```

OpenEDS2020: Palmero, C. et al., *"OpenEDS2020: Open Eyes Dataset,"* 2020
(Facebook Reality Labs).
