# Newest plan

Supersedes `RESUBMISSION_PLAN.md` and `NEXT_BUILD_PLAN.md` as the list of what
is left. Written 2026-10-07 against `main`, build `1.0 (4)`. The detailed,
file-and-line evidence is in [`ENGINEERING_AUDIT.md`](ENGINEERING_AUDIT.md); this
is the plan that comes out of it.

## Where things stand

The code side is in better shape than the app's history suggests. The crash
surface is clean, the privacy boundary is enforced by a gate on every build,
iPhones without Face ID now run a real check, and the unit suite passes. What
is missing falls into three groups, and only the first is engineering work that
can happen on a laptop:

1. **Vision quality** — eye metrics, calibration and camera-quality depth.
2. **Things that need a real iPhone** — every vision claim, and TestFlight.
3. **Things that need a decision** — the safety-network features (heartbeat,
   offline alerts, parent alerts) and the breath flow.

**Still the rejection reason:** a new person needs five accepted sessions before
the app shows a real result, and there is no reviewer path to one.

### Status words used below

| Word | Means |
| --- | --- |
| **DONE** | Built and verified by a test that would fail without it |
| **BUILT, NEEDS DEVICE** | Built and unit-tested; real-world behaviour unconfirmed |
| **OPEN** | Not built |
| **DECISION** | Cannot start until someone chooses what it should be |
| **BLOCKED** | Needs hardware or credentials this machine does not have |

---

## 1. Done

| What | Evidence |
| --- | --- |
| Camera-free check on iPhones without Face ID | `NoCameraProtocolTests`, `testUnsupportedCameraRunsTheCameraFreeCheck` |
| Camera-free sessions no longer claim a capture that never happened | `NoCameraAppModelTests`, PR #7 |
| Reduced Motion readiness matches the baseline shown (`AADI 6`) | `NoCameraAppModelTests` |
| Dead Safety Circle toggle removed from the public build (`VINAY 8`) | `#if INTERNAL_BUILD` in `SafetyPlanView` |
| Content clears the floating tab bar | `TabBarClearanceUITests` |
| Build number no longer collides with the rejected submission | `1.0 (4)`, archive rehearsal passes |
| Reaction task records median latency, the three error kinds, variability, trial count | `ReactionMetricsTests`, PR #9 |
| Head guidance smoothed and debounced, with hysteresis | `HeadPositionGuideTests` — includes the boundary-flicker case |
| "Too close" and "too far" give opposite instructions | Both used to say "move the phone away" |
| Camera interruption / failure mid-capture invalidates the capture and tells the person | `CaptureInterruptionTests` |
| A rejected capture keeps the reason it was rejected | The analyzer used to strip `.interrupted`, leaving "unusable" with no cause |
| Face ID via `LAContext`, passcode fallback, no biometric data stored | `PermissionStore` |
| Uber link carries the destination, encoded once | `CurfewRideLink` / `SafetyPlan.rideURL` tests |
| No crash-prone constructs | No `fatalError`, `try!`, `as!`; zero `print()` |

## 2. Built, needs a device

None of these can be confirmed on a simulator, because the simulator has no
TrueDepth camera. Each needs one session on a Face ID iPhone.

| What | The check |
| --- | --- |
| **Mirror removed** from `FaceCameraPreview` | Move your head right. The picture should move right, like a mirror. If it moves left, put the transform back and file the finding. |
| **Interruption handlers** | Mid eye-task, swipe down Control Center, or start a FaceTime call and decline. The task should say the camera was interrupted and the result should not count. |
| **Head guidance** | Hold the phone too close, then too far. The instructions should differ and point the right way. Rest your head on the edge of the oval — the message should not flicker. |
| **Distance thresholds** | 0.25–0.75 m was chosen in code, never measured on a person. Note where "too close" starts on a real face. |

---

## 3. Open, in order

### P0 — before anything else in the vision area

**3.1 Left/right and up/down guidance.** The guide already knows which side
the head is off, by ARKit axis. The copy says only "Center your face in the
oval" because which ARKit direction is "your left" depends on world alignment,
and a backwards instruction is worse than a neutral one. One device session
settles it: lean left, read `headPosition`, wire the copy. `HeadPositionGuide`,
`HeadPosition.guidance`.

**3.2 Multiple faces.** `ARFaceTrackingConfiguration` tracks one face by
default and silently picks it. A second person in frame is not detected or
reported. Set `maximumNumberOfTrackedFaces`, count anchors, and treat more than
one as invalid capture. `FaceTrackingService`.

**3.3 Camera-quality verdict.** Today validity is the boolean `isUsable`. Add the
VALID / DEGRADED / INVALID aggregate with one actionable sentence each. Blur and
exposure are not measured at all; ARKit's light estimate is the only lighting
input.

### P1 — depth of measurement

**3.4 Switch reaction scoring to the median.** Both values are now recorded.
Once enough sessions carry both, compare them and switch. Doing it earlier
scores median sessions against mean baselines; retiring the old sessions
instead empties every existing baseline, which
`ReviewRegressionTests` guards against. Score the error kinds separately at the
same time.

**3.5 Eye metrics.** `OcularSignalAnalyzer` returns a score only when capture is
fully usable, else zero. Add fixation duration, gaze transitions, per-eye
consistency, and valid / low-confidence / occluded sample classification.

**3.6 Eye calibration.** `CameraCalibrationView` checks framing and lighting.
There is no target-following calibration, no per-person profile, and no
calibration quality bar.

**3.7 Outlier reporting.** Ineligible sessions are excluded and shown as "not
added". There is no statistical outlier rule and no handling of learning
effects across the first sessions.

**3.8 More cognitive dimensions.** Visual search and sustained attention are the
two best-supported additions. Each needs a cited paradigm in developer docs and
must be labelled an engineering measure, not a clinical one.

### P2 — app completeness

**3.9 Guardian contacts.** `SafetyPlan` holds one contact plus extra numbers.
No add/edit/remove for several, no primary, no per-contact preferences.

**3.10 Set current location as Home.** Address is typed today. Needs location
permission in the public build and reverse geocoding, which needs network —
see 4.1.

**3.11 Uber fallbacks.** No "app not installed" path, no return handling.

**3.12 Benchmark harness.** Detection rate, latency, tracking loss and recovery
time, recorded per run. No numbers exist today and none should be quoted until
this does.

---

## 4. Needs a decision

**4.1 The safety network — heartbeat, device offline, parent alerts.** These
need a server that notices when a device stops checking in, plus push
notifications to reach a parent. The public app has no network endpoint, no
notifications, no background modes, and answers App Privacy with **"Data Not
Collected"** — enforced by `check-public-binary.sh`. Building this reverses all
four, needs a privacy policy describing continuous location reporting for
minors, and needs counsel. iOS also cannot report that a phone is *off*; the
honest wording is "has not checked in recently". **Founder and counsel.**

**4.2 What "breath" means.** `BreathReferenceMetadata` exists and is never
filled — `AppModel` passes `nil`. It models an external breathalyzer reading
typed in by the person, not something the phone measures. Decide whether the
feature is manual entry of a breathalyzer result, a paired device, or dropped.

**4.3 A reviewer path to a real result.** `VINAY 1`. A labelled sample mode was
proposed and rejected as scoped. Without one, App Review sees Home, History and
Settings and never a result.

**4.4 Whether unsupported iPhones should install at all.** Less pressing now
that they run a camera-free check, but still `SHREY 6`.

## 5. Blocked

| What | Needs |
| --- | --- |
| Everything in section 2 | A Face ID iPhone |
| Vision benchmark numbers | A Face ID iPhone and 3.12 |
| `SHREY 1` / `SHREY 2` — real captures, low light, glasses | A Face ID iPhone |
| Threshold calibration (`VINAY 2` / `SHREY 5`) | Real sessions from real people |
| TestFlight | An App Store Connect API key for team `CPRVLR97XJ`, then `Scripts/upload-testflight.sh` |

---

## 6. Corrections to earlier reports

- **Camera interruption was not "unhandled".** Backgrounding, phone calls and
  locking were already caught through `scenePhase` with a redo-or-end screen.
  The gap was narrower: ARKit losing the camera while the app stayed in the
  foreground. That is now handled.
- **The reaction median did not replace the mean.** It was tried and reverted;
  see 3.4.
- **The mirror is not a coordinate bug that `abs()` hides.** The view transform
  flips the image and its overlays together, so they stayed consistent with
  each other. The defect was the image itself running the opposite way to a
  mirror — the reported "inverted camera".

## 7. Machine notes

- The disk filled mid-build on 2026-10-07 and stopped all work. Each full build
  uses about 2.3 GB of derived data. Keep at least 5 GB free; delete
  `~/Library/Developer/Xcode/DerivedData` and the session scratchpad between
  runs.
- Heavy local ML jobs push load average past 500, which stalls UI tests. Run UI
  suites when load is under about 30, and never boot two simulators at once.
- Tests that read source through `#filePath` hang when the repo sits under
  `~/Downloads`. Copy the tree elsewhere and build there.

## 8. Verifying a build

```bash
xcodegen generate
xcodebuild -project Sober.xcodeproj -scheme Sober \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
Scripts/check-release-metadata.sh
Scripts/check-public-binary.sh
Scripts/rehearse-app-store-package.sh
node --test Scripts/tests/release-ops.test.mjs
```

Then walk `TESTFLIGHT_PASS.md` on a device.
