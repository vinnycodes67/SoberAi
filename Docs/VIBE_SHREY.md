# Vibe-coding cards — Shrey

Paste-ready prompts for `SHREY 1–5` in [`RESUBMISSION_PLAN.md`](RESUBMISSION_PLAN.md).

**Start every AI session with this**, then paste one card:

```text
Read Docs/SOBER_CONTEXT_BRIEF.md and Docs/RESUBMISSION_PLAN.md before writing
any code. Follow the safety invariants in the first and the file ownership in
§7 of the second — I own Sober/Services/FaceTracking*, the capture path,
Sober/Services/Curfew/ and CurfewExtensions/. Do not edit Sober/DesignKit/ or
Sober/Features/History/ (Aadi's) or Sober/App/ and Sober/Features/Screening/
(Vinay's).
One card per session. Run the tests before telling me you're done.
```

---

## Why SHREY 1 blocks everyone

A baseline session only counts when `completedAllTasks` is true **and**
`qualityScore >= 0.72`. `completedAllTasks` includes the gaze task, which needs
the TrueDepth camera.

**Nobody has ever run this on a real iPhone.** If real sessions score 0.6, the
counter never moves, no check can ever run, and the app looks broken — which is
very likely why App Review rejected it.

Vinay cannot decide whether to change the threshold until you produce a number.
This is the long pole in the whole resubmission.

---

## SHREY 1 — Baseline session on a physical iPhone *(needs hardware)*

Not a coding card. Run the app on a real device and write down what happens.

Record in `Docs/PHASE_4_DEVICE_GATES.md`, per session:

| What | Why |
|---|---|
| `qualityScore` for each of the four tasks | The 0.72 threshold is judged against these |
| Whether `completedAllTasks` came back true | One incomplete task disqualifies the session |
| Device model and iOS version | TrueDepth behaviour varies |
| Lighting, distance, glasses on/off | The variables that move the number |
| How many of 5 sessions actually counted | The reviewer's experience, measured |

Do five in a row in ordinary indoor light. If fewer than five count, that is
the finding, and it is the most important thing anyone learns this week.

---

## SHREY 2 — Low-light and glasses runs *(needs hardware)*

Repeat SHREY 1 twice more: once in dim light, once wearing glasses. These are
the two conditions most likely to sink capture quality in a review lab, and a
reviewer will not adjust their room for you.

---

## SHREY 3 — Camera-denied path end to end

```text
Goal: confirm that tapping "Don't Allow" on the camera prompt leads somewhere
useful instead of a dead end.

The states already exist — read FaceTrackingService.swift first:
permissionDenied and unsupported, handled in OcularTaskView and
CameraCalibrationView.

Walk the whole path and report what a person actually sees:
- during onboarding
- when starting a baseline session
- when starting a check

A denied camera must never look like the app is broken, and per
SOBER_CONTEXT_BRIEF.md it must never block the ride and contact actions.

The simulator can test denial. Reset permissions between runs with:
xcrun simctl privacy <device-id> reset camera com.soberprototype.app
```

---

## SHREY 4 — Wire up or cut the pupil model *(start now, no hardware)*

```text
Goal: resolve an unfinished feature sitting in the repo.

Sober/Resources/PupilSegmentation.mlpackage ships, and PupilCaptureService
exists and can load it — but metrics.pupillometry is populated by NOTHING.
ScreeningEngine reads it and always gets nil, so the pupil measure silently
contributes zero to every result.

Confirm that first: grep for "pupillometry:" and show me every place it is
assigned. If nothing assigns it, it is dead weight.

Then pick one and tell me which you chose and why:

(a) WIRE IT UP — populate metrics.pupillometry from the capture path so the
    measure actually contributes. Bigger job; needs device validation.

(b) CUT IT from the scoring path — remove the field from the model and the
    engine, keep the model file and the training pipeline in the repo for
    later. Smaller, honest, and removes a measure that pretends to exist.

The safety rule from SOBER_CONTEXT_BRIEF.md decides it: an unmeasured thing is
never treated as normal. A measure that is always nil but reads as "included"
breaks that rule, so leaving it as-is is not an option.

Run the unit tests after either path.
```

---

## SHREY 5 — Recommend a threshold *(after SHREY 1 and 2)*

Not a coding card. From your recorded numbers, tell Vinay:

- What capture quality real sessions actually achieve.
- Whether `minimumQuality = 0.72` is reachable in an ordinary room.
- Whether five sessions is realistic, or whether the first comparison should
  come sooner with a stated caveat.

He changes `BaselineProfileEngine` — you supply the evidence.
