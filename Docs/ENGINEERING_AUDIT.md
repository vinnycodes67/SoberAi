# Engineering audit

Against `efe7c67` on `main`, build `1.0 (4)`. 18,554 lines of Swift.

Status vocabulary, per the audit brief: **WORKS** (verified running), **PARTIAL**
(built, with a named gap), **MODEL ONLY** (type exists, nothing populates it),
**MISSING**, **BLOCKED** (cannot be built here, reason given).

---

## 1. The three findings that matter most

### 1.1 Trial-level data is captured, stored, and then ignored

`ChoiceReactionSummary` (`Models/TaskModels.swift:61`) holds per-trial latencies
and derives mean, standard deviation, incorrect choices, anticipations
(premature responses) and misses. `AppModel` persists the whole thing into
`ResearchSessionEnvelope.choiceReaction`.

Neither `ScreeningEngine` nor `BaselineProfileEngine` ever reads it. Both consume
only two collapsed scalars off `ScreeningMetrics`:

```swift
// ScreeningFlowView.swift:146-147
reactionTime   = summary.averageMilliseconds
reactionMisses = summary.totalErrors
```

Two distinct defects fall out of those two lines:

- **`averageMilliseconds` is the mean.** A single slow trial drags the whole
  session. The baseline engine then computes a *robust* median across sessions —
  so the pipeline is median-of-means, and the non-robust half is the one closest
  to the noise. Reaction-time distributions are right-skewed; the within-session
  median is the standard summary.
- **`totalErrors` conflates three different things.** `incorrectChoices`,
  `anticipations` and `misses` are computed separately and then summed into one
  `Int`. Those are a wrong choice, a premature response, and a non-response —
  different constructs with different causes. The brief asks for false
  positives, false negatives, missed and premature responses as separate
  measures. The data exists; the collapse throws it away.

**This is the cheapest large win in the codebase.** No new capture, no new UI —
widen `ScreeningMetrics` and wire through data already on disk.

**Done, deliberately in two halves.** The median, the three error kinds,
latency variability and trial count are now recorded on every session and
persisted. Scoring still uses the mean. Switching it was tried and reverted:
scoring new sessions by median against baselines built from means compares two
different numbers, and the clean alternative — bumping the research schema so
mean-derived sessions stop counting — retires every existing baseline, which
`ReviewRegressionTests.testLegacyResearchSessionDecodesAsFullProtocolVariantAndRemainsEligible`
exists to prevent. Once enough sessions carry both values, the switch can be
evaluated against real data instead of guessed.

### 1.2 The preview is mirrored; the tracking coordinates are not

`Components/FaceCameraPreview.swift:13`:

```swift
view.transform = CGAffineTransform(scaleX: -1, y: 1)
```

The whole `ARSCNView` is flipped for the selfie convention. The face-anchor
coordinates feeding `headPosition.x` are not flipped.

This is currently invisible, and only by luck: centering uses
`abs(Double(headPosition.x)) <= 0.13`, and `abs()` erases the sign. **The moment
directional guidance is added — "move left", "move right" — it will tell the
user to move the wrong way.** Fixing centering (below) without fixing this first
would ship a backwards instruction.

### 1.3 §19–21 cannot be built without reversing the app's privacy posture

Device-offline detection, heartbeats and a parent alert engine need a server
that knows when a device stopped checking in, plus push to reach the parent. The
shipping app deliberately has none of that: no network endpoints, no
notifications, no background modes, and an App Privacy answer of **"Data Not
Collected"** that `check-public-binary.sh` enforces on every build.

Building it means a backend, push entitlements, background modes, a new App
Privacy questionnaire, and a privacy policy that describes continuous location
and liveness reporting for a minor. That is a product and legal decision, not a
coding task. **Not started. Flagged rather than half-built.**

---

## 2. Area by area

| Area | Status | Detail |
| --- | --- | --- |
| Face detection / tracking | **WORKS** | ARKit `ARFaceTrackingConfiguration`, correctly gated on `isSupported` |
| Camera-free fallback | **WORKS** | `.noCamera` variant; verified by `testUnsupportedCameraRunsTheCameraFreeCheck` |
| Head centering | **PARTIAL** | Single threshold `abs(x)<=0.13 && abs(y)<=0.18` (`FaceTrackingService.swift:340`). Boolean only — no LEFT/RIGHT/HIGH/LOW/CLOSE/FAR. Counter-based smoothing exists (`centeredCount`), true hysteresis does not |
| Distance | **PARTIAL** | `distanceAcceptable` tracked, but boolean — cannot say "too close" vs "too far" |
| Multiple faces | **MISSING** | No anchor-count check anywhere. A second face in frame is unhandled |
| Camera quality | **PARTIAL** | `FaceTrackingStatus` covers tracking state, lighting and motion via ARKit. No explicit VALID/DEGRADED/INVALID aggregate; no blur, exposure or frame-rate measure |
| Camera interruption | **MISSING** | `ARSessionDelegate` implements only `didUpdate frame`, `didUpdate anchors`, `cameraDidChangeTrackingState`. **`sessionWasInterrupted`, `sessionInterruptionEnded` and `session(_:didFailWithError:)` are absent** — a call, a backgrounding, or another app taking the camera is not handled |
| Inverted camera | **PARTIAL** | See 1.2 — masked by `abs()`, not fixed |
| Eye tracking | **PARTIAL** | `OcularSignalAnalyzer` is all-or-nothing: a score only when capture is fully usable, else zero. No fixation duration, gaze transitions, blink state, or per-eye consistency |
| Eye calibration | **MISSING** | `CameraCalibrationView` checks framing and lighting. There is no target-following calibration, no per-user profile, no calibration quality gate |
| Reaction / tracking / timing tasks | **WORKS** | Three tasks run and record |
| Test complexity | **PARTIAL** | Choice reaction, motor tracing, time estimation, guided gaze. No visual search, working memory, sustained or selective attention, distraction resistance |
| Metrics depth | **PARTIAL** | Median, error breakdown, variability and trial count now recorded (1.1); scoring still uses the mean |
| Baseline system | **WORKS** | `BaselineProfileEngine` uses median + MAD, filters by protocol variant, requires five eligible sessions |
| Multi-session baseline | **WORKS** | Five sessions required; recomputed from stored sessions on every launch |
| Outlier handling | **PARTIAL** | Ineligible sessions are excluded and surfaced ("not added" in History, counts on Your Steady). No explicit statistical outlier rule, no learning-effect handling |
| Synthetic vs real data | **WORKS** | `UITestConfiguration` / `UITestLaunchConfiguration` are `#if DEBUG`, compiled out of Release. Separation is enforced by the boundary gate |
| Face ID | **WORKS** | `PermissionStore` uses `LAContext` with `.deviceOwnerAuthentication` — passcode fallback included, no biometric data stored. Matches the brief |
| Parent contacts | **PARTIAL** | `SafetyPlan` holds one contact plus `additionalContactPhones`. No add/edit/remove UI for multiple guardians, no primary designation, no per-contact notification preferences |
| Breath / "post breath" | **MODEL ONLY** | `BreathReferenceMetadata` exists; `AppModel.swift:1019` hardcodes `breathReference: nil`. Nothing captures or displays it. It models an *external* breathalyzer reading, not a phone-performed breath test |
| Heartbeat / device offline | **BLOCKED** | See 1.3 |
| Parent alert engine | **BLOCKED** | See 1.3 |
| Home location | **PARTIAL** | Address is typed, with one-tap place names. No "set current location as Home", no reverse geocoding — the public build has no network to geocode with |
| Uber | **WORKS** | Universal link via `URLComponents`, encoded exactly once, with the `%2520` double-encode bug fixed and documented. `rideCarriesDestination` keeps the copy honest about Lyft, which cannot carry a destination without geocoding |
| Uber fallback | **PARTIAL** | No "app not installed" path, no return-to-app handling |
| Permissions | **PARTIAL** | `PermissionStore` covers camera and LocalAuthentication. Location lives in Guardian/Curfew services; notifications and contacts are unused in public |
| Offline / network | **WORKS** | Public build makes no network calls at all. `NoNetworkInPublicBuildTests` enforces it |
| Persistence | **WORKS** | `LocalBaselineStore`, `ResearchSessionStore`, `CheckHistoryStore`; history bounded to 90 days / 100 entries, pruned on write |
| Accessibility | **WORKS** | Reduce Motion, Dynamic Type to AX5, VoiceOver labels, row stacking — covered by `AccessibilityUITests` |
| Crash surface | **WORKS** | No `fatalError`, no `try!`, no `as!`, zero `print()`. Three `precondition`s, all guarded by construction |
| Vision benchmark | **MISSING** | No benchmark harness for detection rate, latency, tracking loss or recovery |

---

## 3. Measured, not estimated

| Gate | Result |
| --- | --- |
| Unit suite | 261 / 261 |
| `JourneySmokeUITests` | 10 / 10 |
| `check-release-metadata.sh` | pass |
| `check-public-binary.sh` | pass |
| Archive rehearsal `1.0 (4)` | pass, `d82d25c2…` |
| `release-ops.test.mjs` | 18 / 18 |

**Vision benchmark numbers: NOT MEASURED.** There is no harness, and no physical
TrueDepth device has ever run this app. Any detection rate, latency or
tracking-loss figure quoted today would be invented.

---

## 4. Recommended order

Ordered by value per unit of risk, not by brief section number.

**P0 — correctness of what already ships**

1. ~~**Split and robustify the reaction metrics** (1.1).~~ Recording half done; scoring switch deferred until sessions carry both values.
2. **Fix the mirror** (1.2) before any directional UI depends on it.
3. **Head-position state machine** — directional states with hysteresis, replacing the single threshold. Pure logic, unit-testable.
4. **ARSession interruption handling** — the three missing delegate methods, with the session pausing and the affected window marked invalid.

**P1 — depth**

5. Multiple-face detection and handling.
6. Camera-quality aggregate (VALID / DEGRADED / INVALID) with actionable copy.
7. Richer eye metrics: fixation duration, gaze transitions, per-eye consistency.
8. Eye calibration with a measurable quality gate.
9. Additional cognitive dimensions (visual search, sustained attention).

**P2 — needs a decision before any code**

10. §19–21 heartbeat, device-offline and parent alerts. Requires a backend and reverses "Data Not Collected". **Founder and counsel decision.**
11. Breath flow — needs a decision on what it actually is: external breathalyzer entry, or something the phone measures.

**Cannot be done on this machine, at any priority**

- Vision benchmarks and §33's device matrix: needs a physical TrueDepth iPhone.
- TestFlight: needs signing credentials for team `CPRVLR97XJ`.

---

## 5. What not to touch

These are correct and should be left alone: the Uber link builder, the Face ID
implementation, the public/internal boundary and its gate, the persistence
layer's retention rules, the `.noCamera` partitioning, and the DEBUG-only
fixture separation. Several are load-bearing for the App Store privacy answers.
