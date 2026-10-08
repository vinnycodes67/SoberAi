# Handoff: what is not done, not tested, or unchanged

Written 2026-10-07 by Aadi for Vinay and Shrey. This lists only what is
**left**. What is done, with evidence, is in
[`NEWEST_PLAN.md`](NEWEST_PLAN.md) section 1. File-and-line detail is in
[`ENGINEERING_AUDIT.md`](ENGINEERING_AUDIT.md).

## State at handoff

- `main` includes PRs #9, #10 and #11, plus the commit that adds this file.
  Build `1.0 (4)`.
- **Updated 2026-10-07 by Shrey** after reviewing #9–#12, on Xcode 27:
  **308 unit tests and 40 UI tests pass** (1 UI test skips on the simulator
  because camera calibration needs a TrueDepth camera). Metadata check,
  `check-public-binary.sh`, the archive rehearsal and `release-ops` (18/18)
  all pass. Fixed in review:
  - A camera lost mid eye-task now shows in live quality, so the recovery
    screen appears instead of the task running on with no way to end it.
  - Head guidance no longer sticks on "Hold that position" when one axis is
    clearly out and the other hovers on its limit.
  - Home "Ready" counts only the baseline for the version of the check this
    iPhone runs next.
  - "No changes detected" can no longer sit above mostly orange rows.
- **App Store status unchanged.** It is still rejected, for the same reason
  (section 4.1 below).

Owners follow `RESUBMISSION_PLAN.md` §5. **Shrey**: face tracking, capture, the
model. **Vinay**: App, Screening, engine, Scripts, release.

---

## 1. Built but never run on a real iPhone (Shrey)

The simulator has no TrueDepth camera, so none of this has been seen working.
Use a Face ID iPhone, with the internal build for the model items.

| # | Change | How to check it | If it fails |
|---|---|---|---|
| 1.1 | Mirror transform removed, `FaceCameraPreview.swift` | Move your head right. The picture should move right, like a mirror. | Restore `view.transform = CGAffineTransform(scaleX: -1, y: 1)` and record what you saw |
| 1.2 | ARKit interruption and failure handlers, `FaceTrackingService.swift` | During the eye task, pull down Control Center, or take a FaceTime call and decline it. You should see "Camera interrupted…", the recovery screen within about 3 s, and the result should not count. | Check `sessionWasInterrupted` actually fires; these are only unit-tested by calling the handlers directly |
| 1.3 | Head guidance, `HeadPositionGuide.swift` | Hold the phone too close, then too far: the two messages should differ and be correct. Rest your head on the edge of the oval: the message should not flicker. | Tune `Thresholds`, `smoothing` and `framesToSwitch` |
| 1.4 | Distance band 0.25–0.75 m | Note the real distance where "too close" and "too far" start | Adjust both `HeadPositionGuide.Thresholds` and the gate in `FaceTrackingService.ingest`, keeping them in step |
| 1.5 | Float32 pupil model, `Sober/Resources/PupilSegmentation.mlpackage` | Time one inference in `PupilCaptureService`. Float32 may run on the GPU instead of the Neural Engine. | If it's too slow, re-export at `--precision float16`. That costs about 2 points of iris IoU (see the model README). |
| 1.6 | Pupil model on real iPhone eye images | **Never measured.** Every published number comes from infrared VR-headset footage. | See section 3 |
| 1.7 | Second face, `FaceTrackingService` (tracks up to 3, follows the nearest) | During the eye task, have someone lean into frame for a few seconds. "Only you should be in view…" should appear and the run should not count. A one-frame glimpse should not end it. | Check `trackedFaceCount` really exceeds 1; ARKit needs an A12 or later for more than one face |
| 1.8 | Directional words, `DirectionalGuidance` (built, **off**) | Set `isEnabled = true` in a local build, move your head to your right: it must say "Move left". Then up/down. | If backwards, flip the sign in `mirroredOffset`, record why, and update `CaptureDiagnosticsTests` |
| 1.9 | Image brightness/sharpness thresholds, `CaptureImageStats` | Note the verdict line on camera setup in a dim room, facing a window, and with a smudged lens | Tune `darkMeanLuma`, `clippedLimit`, `blurLimit`. They only ever mark a capture *degraded* |
| 1.10 | Capture benchmark, Research screen (internal build) | After a few eye tasks it shows detection rate, tracking losses, recovery time and processing delay | Those are the first real vision numbers; quote nothing before it shows them |

## 2. Not built (open work, in priority order)

### P0 (built 2026-10-08; each needs the device check in section 1)
- **2.1 "Move left / right" wording.** Built in `DirectionalGuidance`, from
  where the face appears on the mirrored preview rather than ARKit's world
  axes. **Off** until 1.8 confirms it.
- **2.2 More than one face in frame.** Built: up to 3 faces tracked, the
  nearest followed; another face in more than 5% of frames makes the capture
  unusable. Needs 1.7.
- **2.3 Camera-quality verdict.** Built: `CaptureAssessment` gives VALID /
  DEGRADED / INVALID with one sentence, using new brightness, clipping and
  sharpness measures (`CaptureImageStats`). Thresholds are guesses until 1.9.

### P1: measurement depth
- **2.4 Score reaction time by median, not mean.** Both are now recorded
  (`reactionMedianMilliseconds`). Don't switch until enough sessions carry
  both values. Switching straight away scores median sessions against
  baselines built from means, and bumping the schema empties everyone's
  baseline instead (`ReviewRegressionTests` guards against that). The error
  types (`reactionIncorrectChoices` / `Anticipations` / `MissedResponses`) are
  recorded but not used in scoring yet.
- **2.5 Eye metrics.** No fixation duration, gaze transitions or per-eye
  consistency, and no valid / low-confidence / covered-eye labelling of
  samples. `OcularSignalAnalyzer` scores all-or-nothing.
- **2.6 Eye calibration.** `CameraCalibrationView` only checks framing and
  light. There's no follow-the-target calibration, no per-person profile, and
  no calibration quality bar.
- **2.7 Outlier sessions.** Ineligible sessions are excluded, but there's no
  statistical outlier rule and no allowance for people improving with
  practice over their first sessions.
- **2.8 Further cognitive tasks** (visual search, sustained attention). Each
  needs a cited method and must be labelled an engineering measure, not a
  clinical one.

### P2: app completeness
- **2.9 Several guardian contacts** (add / edit / remove, a primary contact,
  per-contact preferences). `SafetyPlan` holds one contact.
- **2.10 "Use current location as Home".** It's typed in today. This needs
  location permission and reverse geocoding (network), so it's tied to 4.2.
- **2.11 Uber fallbacks.** Nothing handles "Uber isn't installed", and
  nothing handles the return to the app.
- **2.12 Benchmark harness.** Built: every eye-task capture records detection
  rate, tracking losses, recovery time, processing delay, second-face frames
  and image quality (`CaptureTelemetry`, kept with the session on the phone),
  summarised on the internal Research screen. **Still don't quote vision
  numbers until real captures have filled it (1.10).**

## 3. Pupil model: unfinished work (Shrey)

- **The retrain was stopped, and the shipped weights are unchanged.** The
  pipeline now trains on 24 subjects (3,405 frames), up from 8, but this
  Mac (8.6 GB RAM) only managed about 18 s per step on CPU, roughly 8 hours
  an epoch. The GPU path swaps at any batch size above 1. Run it on a
  machine with ≥16 GB, or on a cloud GPU:
  ```bash
  cd Training/PupilSegmentation
  python3 prepare_data.py --split train --shards 0-9
  python3 prepare_data.py --split val --shards 0-3
  python3 train.py --data /tmp/openeds_prepared/train --eval-data /tmp/openeds_prepared/val \
      --epochs 6 --skip-baseline --out new.pt
  # export and score in the torch 2.7 environment (README explains why)
  python3 export_coreml.py --weights new.pt --out New.mlpackage
  python3 verify_coreml.py --package New.mlpackage --weights new.pt \
      --eval-data /tmp/openeds_prepared/val --every 4
  ```
  **Bar to beat**, from the shipped float32 package on the same 10 val
  subjects (scored on every 4th frame): **iris IoU 0.9490, pupil IoU
  0.9730.** Ship only if the new package beats both, and update the README
  table if it does. Score it with `--every 4` as above, so both numbers come
  from the same frames. The PyTorch row in the README (0.9478 / 0.9729) is on
  all 1,349 frames, so it is not directly comparable with the Core ML rows.
  That is why float32 Core ML appears to beat its own weights.
- **The real gap is the domain.** OpenEDS is infrared headset footage. Sober
  sees visible-light iPhone selfie-camera crops. More OpenEDS data won't close
  that gap; collecting and hand-labelling iPhone eye images will. Until that
  happens, the model **stays out of the public build**
  (`check-public-binary.sh` enforces this, and `ScreeningEngineTests` checks
  it).
- `train.py --device mps` is unusable on 8 GB machines (swaps at batch ≥2).
  `--device cpu` works but is slow.

## 4. Waiting on a decision (founders, and counsel for 4.2)

- **4.1 A reviewer path to a real result** (`VINAY 1`). **This is still why
  the app is rejected.** A new user needs five accepted sessions before seeing
  a result, so App Review never sees one. A labelled sample mode was proposed
  and turned down as scoped. Something has to replace it.
- **4.2 Heartbeat, phone-offline and parent alerts.** These need a server and
  push notifications. That changes the App Privacy answer from "Data Not
  Collected", requires changing `check-public-binary.sh`, and needs a privacy
  policy covering continuous location reporting for minors. Note that iOS
  cannot tell that a phone is *off*; the most it can honestly say is "hasn't
  checked in recently".
- **4.3 What "breath" means.** `BreathReferenceMetadata` exists but is always
  `nil`. It models a breathalyzer reading the user types in. Decide: manual
  entry, a paired device, or drop it.
- **4.4 Should iPhones without Face ID be able to install the app?**
  (`SHREY 6`) They now run a camera-free check, so this is less urgent.

## 5. Blocked

| What | Needs |
|---|---|
| TestFlight | An App Store Connect API key for team `CPRVLR97XJ`, then `Scripts/upload-testflight.sh` |
| Calibrating the score thresholds (`VINAY 2` / `SHREY 5`) | Real sessions from real people |
| All of section 1 | A Face ID iPhone |

## 6. Checks to re-run before the next submission

All passed on 2026-10-07 (see the state section). Re-run them on the commit
you submit:

```bash
xcodebuild ... test
Scripts/check-public-binary.sh           # needs an archive
Scripts/rehearse-app-store-package.sh
node --test Scripts/tests/release-ops.test.mjs
```

`check-public-binary.sh` takes a derived-data path, e.g. the one the test
run used.

## 7. Machine notes

- **Disk:** a full build uses about 2.3 GB of derived data. The disk filled
  during this work and stopped everything. Keep ≥5 GB free.
- **Tests under `~/Downloads`:** tests that read source through `#filePath`
  hang there. Copy the tree elsewhere and build from the copy.
- **Load:** run UI suites only when load average is under about 30, and only
  one simulator at a time.
- **Model export:** coremltools 9 crashes (segfault) under torch 2.12. Export
  from a torch 2.7 virtual environment.
