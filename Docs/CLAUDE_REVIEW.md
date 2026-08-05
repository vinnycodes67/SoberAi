# Claude Review — Sober Research Build 0.2

Date: 2026-08-03
Reviewer: Claude Code (independent safety, privacy, and correctness review)
Scope: uncommitted working tree at review time (camera/ocular capture, screening flow,
research data, parent alerts, product claims and UI)

> This build is an impairment-**awareness** prototype. Nothing in this review should be read as
> saying it is clinically validated or ready for public testing. It is not either of those things.
>
> **Status note — 2026-08-04:** The verdict immediately below describes Claude's review snapshot.
> Codex subsequently continued the plan and resolved the code-addressable P2/P3 items listed in
> [Post-review continuation](#post-review-continuation--2026-08-04). Physical-device and deployed-provider checks remain open.

---

## Verdict

**NEEDS WORK**

Two P0 defects and four P1 defects were found and fixed in this pass. The remaining blockers are
not code defects — they are external checkpoints that cannot be closed from this machine:

1. No physical TrueDepth device QA has been performed. Every ocular measurement path in this build
   is verified only against synthetic samples and the simulator. The simulator cannot run
   `ARFaceTrackingConfiguration`, so the entire live capture path is **unexecuted code**.
2. The parent-alert relay has never run against a deployed Worker or a real provider account.
3. At review time, relay deduplication was isolate-local and could not guarantee one provider
   submission per event (see P2-6). Durable coordination has since been implemented but not deployed.

Ship to a co-founder review meeting: yes, as a demo of product behaviour and safety posture.
Ship to any real user, including a friendly teenager: no.

---

## Phase 1 — Areas found sound

Stated explicitly, as requested. These were checked and no defect was found.

| Area | Finding |
| --- | --- |
| Preview / measurement session identity | Sound. `FaceCameraPreview` hands the `ARSCNView`'s own session to `FaceTrackingService.attach(to:)` ([FaceCameraPreview.swift:14](../Sober/Components/FaceCameraPreview.swift#L14), [FaceTrackingService.swift:60](../Sober/Services/FaceTrackingService.swift#L60)). The visible preview and the measured samples come from one `ARSession`. There is no second capture pipeline. |
| Raw frame persistence | Sound. Nothing writes `CVPixelBuffer`, `ARFrame`, `UIImage`, or video anywhere. Only bounded numeric `OcularSample` values are retained, capped at 1 800 samples and cleared at the start of every capture ([FaceTrackingService.swift:39-40, 128, 251](../Sober/Services/FaceTrackingService.swift#L39)). The research archive stores derived scalars only. |
| Reported use overrides task performance | Sound. `selfReport == .yes` returns `signalsDetected` with `riskScore` floored at the threshold before any task metric is consulted ([ScreeningEngine.swift:40-47](../Sober/Services/ScreeningEngine.swift#L40)). Covered by `testReportedUseCanNeverReturnNoSignals` across clean, perfect, and degraded metrics. |
| Simulator / unsupported live path | Sound. Unsupported capture yields `qualityScore == 0`, which fails the `minimumQuality` gate and returns `INCONCLUSIVE`. A live check on the simulator cannot present as a measured result. |
| Founder previews never send | Sound. `ParentAlertPolicy.shouldSend` requires `!isSample`, and the flow short-circuits sample scenarios to `.preview` before any relay call. |
| Provider acceptance vs carrier delivery | Sound. The success copy reads "Alert accepted for sending … Carrier delivery is not yet confirmed" ([ResultView.swift:196](../Sober/Features/Results/ResultView.swift#L196)). No state claims the parent received anything. |
| Baseline exclusion, median/MAD | Sound. `isEligible` requires current schema, a `completedAt`, `completedAllTasks`, quality ≥ 0.72, and finite metrics. Median and raw (unscaled) MAD are correct, including the even-count average; the docstring correctly notes the 1.4826 factor is omitted. |
| Research data does not retune the scorer | Sound. `BaselineProfileEngine` output flows only to `AppModel.baselineProfile` for display. `ScreeningEngine` takes no baseline input and holds fixed constants. |
| Exported JSON identifiers | Sound. The envelope carries a random `participant_<uuid>` and no name, phone, contact, or precise device model (`UIDevice.model` is the generic `"iPhone"`). Locale is the only mild fingerprint. |
| Product claim language | Sound. No "sober", "passed", "cleared", "safe to drive", "clinically validated", or BAC claim survives anywhere in shipping copy. The ocular screen explicitly says "not an official HGN test"; the no-signals state carries a mandatory disclaimer that is pinned by a test. |

---

## Phase 2 — Findings

### P0-1 — The non-visual motor-tracking path fabricated a favourable score

- **File:** [Sober/Features/Screening/TaskViews.swift:290](../Sober/Features/Screening/TaskViews.swift#L290) (pre-fix)
- **Failure scenario:** A VoiceOver user reaches the motor tracking task, which requires a
  continuous drag along a curved path and is not operable non-visually. The provided accessibility
  action `"Use prototype alternative"` called `onComplete(0.22)` — a hardcoded value that is *good*
  performance (`trackingRisk` 0.13 against a 0.55 concern threshold). The flow then set
  `completedAllTasks: true`.
- **User impact:** A blind or motor-impaired user could receive `NO_SIGNALS_DETECTED` on a check
  where a quarter of the risk weight was invented rather than measured — the single most dangerous
  falsely reassuring state this product can produce. The fabricated value was also written into the
  research archive indistinguishable from a real measurement, and could count toward a sober
  baseline.
- **Fix:** `MotorTrackingTaskView` now emits `MotorTrackingOutcome` carrying `wasMeasured`. The
  accessibility action returns `.notMeasured` (error 1, `wasMeasured` false) and is relabelled
  "Skip tracing — result will be inconclusive". `ScreeningFlowView` maps `wasMeasured` onto
  `completedAllTasks`, so the engine returns `INCONCLUSIVE`, and baseline sessions are rejected.
- **Test:** `testUnmeasuredMotorTrackingIsNeverScoredAsGoodPerformance`,
  `testMeasuredMotorTrackingStillCompletesTheCheck`.

### P0-2 — Parent-alert event ID was regenerated on every SwiftUI view rebuild

- **File:** [Sober/Features/Screening/ScreeningFlowView.swift:38](../Sober/Features/Screening/ScreeningFlowView.swift#L38) (pre-fix)
- **Failure scenario:** `private let parentAlertService = ParentAlertService()` was a stored property
  on a `View` **struct**, and `ParentAlertService.init` defaults `eventID: UUID = UUID()`. SwiftUI
  re-initialises a view struct's stored properties on every rebuild, so the "Try automatic alert
  again" button generally sent a **different** event ID than the original attempt.
- **User impact:** The relay deduplicates on event ID. With a fresh ID per retry, dedup never
  matched and each retry produced a **new SMS to the parent**. A user tapping retry after a
  transient failure could send a parent several copies of an alarming message about their child.
  The plan's "one stable event ID across retries" guarantee was true of `ParentAlertService` in
  isolation — which is all `ParentAlertReliabilityTests` covered — and false of the shipping app.
- **Fix:** Added `ParentAlertCoordinator`, a `@MainActor ObservableObject` holding the event ID,
  timestamp, delivery state, and a single in-flight task. `ScreeningFlowView` holds it as
  `@StateObject`, which survives view rebuilds. The coordinator also refuses a second submission
  while one is in flight and after one has succeeded.
- **Test:** `testRetriesReuseASingleEventIDForTheWholeRun`, `testASucceededAlertIsNotResentOnRetry`,
  `testConcurrentSendsProduceOnlyOneSubmission`, `testConcerningLiveResultStartsSendingImmediately`,
  `testSamplePreviewsNeverContactTheRelay`, `testNonConcerningResultNeverSends`.

### P1-3 — A skipped or blocked ocular task was archived as a 25-second high-quality capture

- **Files:** [Sober/Services/FaceTrackingService.swift:110](../Sober/Services/FaceTrackingService.swift#L110),
  [Sober/App/AppModel.swift:123](../Sober/App/AppModel.swift#L123) (pre-fix)
- **Failure scenario:** `unusableSummary(issue:)` started from `var snapshot = quality` — the
  snapshot left over from the *calibration* step, which has typically just passed and therefore
  reports face present, centred, well-lit, stable, ~30 fps. Only `.unsupported` and
  `.permissionDenied` cleared those fields; the Reduced Motion "Skip eye task" path uses
  `.interrupted` and cleared nothing. Separately, `AppModel` hardcoded
  `trackingDurationMilliseconds: OcularProtocolSchedule.totalDuration * 1_000` — always 25 000 ms,
  regardless of what actually happened.
- **User impact:** Research integrity. A session where the eye task was skipped outright was
  exported as a completed 25-second capture with a high `signalQualityScore`, full tracking
  coverage, and a real frame rate. Any downstream analysis of this dataset would be reasoning about
  measurements that were never taken. (The live *safety* result was not affected: `qualityScore` was
  correctly 0, so the check returned `INCONCLUSIVE` and the baseline correctly excluded it.)
- **Fix:** `unusableSummary` now zeroes every measurement field for *every* issue and always merges
  in `.insufficientSamples`, guaranteeing `isUsable == false`. `GazeCaptureSummary` gained
  `capturedDurationMilliseconds`, set from the actual sample span by the analyzer and to 0 for
  unusable captures; `AppModel` reads it instead of assuming the full protocol ran. The field decodes
  as 0 for pre-existing schema-1 records.
- **Test:** `testSkippedOcularTaskReportsNoCaptureDespiteGoodCalibration`,
  `testAnalyzerReportsTheDurationItActuallyMeasured`,
  `testGazeSummaryDurationSurvivesJSONRoundTripAndDefaultsForLegacyRecords`,
  `testSkippedOcularTaskIsExcludedFromTheBaseline`.

### P1-4 — Deleted research data survived in the exported JSON file

- **Files:** [Sober/App/AppModel.swift:185](../Sober/App/AppModel.swift#L185),
  [Sober/Features/Research/ResearchModeView.swift:48](../Sober/Features/Research/ResearchModeView.swift#L48) (pre-fix)
- **Failure scenario:** "Prepare JSON export" wrote the full archive to
  `tmp/sober-research-export-<participantID>.json`. "Delete local research data" removed the store
  and set the in-memory `exportURL` to nil, but never deleted that file. The confirmation said
  "It cannot be undone", implying the data was gone.
- **User impact:** A user who exported once and then deleted believed their research data was
  erased while a complete plaintext copy remained on the device until iOS reclaimed the temporary
  directory.
- **Fix:** `AppModel` tracks `lastExportURL`, applies
  `.completeUntilFirstUserAuthentication` protection to the export, and `deleteAllResearchData()`
  removes the file via `discardPreparedExport()`. Confirmation copy now names the export file.
- **Test:** `testDeletingResearchDataAlsoRemovesThePreparedExportFile`.

### P1-5 — "Reset prototype" destroyed all research data behind copy that said "setup state"

- **Files:** [Sober/Features/Home/HomeView.swift:344](../Sober/Features/Home/HomeView.swift#L344),
  [Sober/Features/Onboarding/OnboardingView.swift:223](../Sober/Features/Onboarding/OnboardingView.swift#L223) (pre-fix)
- **Failure scenario:** `resetPrototype()` calls `deleteAllResearchData()`, irreversibly removing
  every stored session and the measured baseline. The confirmation read only "This removes locally
  stored prototype setup state", and the retention policy said reset "removes onboarding and
  baseline state stored by this build".
- **User impact:** Unrecoverable loss of the participant's entire research archive — potentially
  weeks of baseline sessions — with no informed confirmation and no prompt to export first.
- **Fix:** The alert is retitled "Reset the prototype and delete research data?", names the exact
  session count, tells the user to export first, and states it cannot be undone. The retention
  policy section was corrected to match actual behaviour.
- **Test:** covered behaviourally by `testDeletingResearchDataAlsoRemovesThePreparedExportFile`
  (shared deletion path). The copy itself is not asserted.

### P1-6 — Denied camera permission was an unrecoverable dead end

- **File:** [Sober/Features/Screening/CameraCalibrationView.swift:80](../Sober/Features/Screening/CameraCalibrationView.swift#L80) (pre-fix)
- **Failure scenario:** On a supported device with camera permission denied, `quality.isUsable`
  can never become true, so `hasHeldReady` never flips and the continue button stayed disabled
  permanently. The "Continue with limited capture" affordance and its explanatory caption were both
  gated on `!service.isSupported`, so neither appeared. There was no link to Settings. In
  `OcularTaskView` the same state left "Begin 25-second eye task" enabled, so the user could sit
  through the full protocol collecting zero samples.
- **User impact:** The user is stranded mid-check with no way forward and no explanation, and the
  only escape is the exit X that discards the session.
- **Fix:** Both screens now treat denied permission like an unsupported device: continue-with-limited
  capture is offered (the result is correctly `INCONCLUSIVE`), the caption explains why, an
  "Open Settings" link is shown, and the 25-second task is replaced by the inconclusive exit.
- **Test:** not directly unit-testable (SwiftUI view state). The underlying invariant — a
  permission-denied summary is never usable and scores 0 — is asserted in
  `testSkippedOcularTaskReportsNoCaptureDespiteGoodCalibration`.

---

### P2 — Reported, not fixed

| # | File | Issue |
| --- | --- | --- |
| P2-1 | [OcularSignalAnalyzer.swift:140](../Sober/Services/OcularSignalAnalyzer.swift#L140) | `correlationError` returns `1 - abs(correlation)`, so gaze moving *exactly opposite* to the target scores as perfect tracking. This is a defensible hedge against an unknown eye-vector sign convention, but it means the metric cannot distinguish following from anti-following. Establish the sign empirically during calibration on real hardware, then drop `abs`. Changing it blind would be worse than leaving it. |
| P2-2 | [TaskViews.swift:152](../Sober/Features/Screening/TaskViews.swift#L152) | An anticipation (tap during `.waiting`) records `expected: target`, which still holds the *previous* round's symbol — or `.blueCircle` on round 1. `isCorrect` is false regardless, so scoring is unaffected, but the archived `expected` field is wrong. Record `nil` for anticipations. |
| P2-3 | [AppModel.swift:130-132](../Sober/App/AppModel.swift#L130) | `bothEyesVisibleFraction`, `headStabilityScore`, and `illuminationScore` are booleans cast to 0/1 but named and typed as fractions. Either compute real fractions from the sample buffer or rename them. |
| P2-4 | [AppModel.swift:210](../Sober/App/AppModel.swift#L210) | `resetPrototype()` does not clear `Keys.participantID`. After a full reset the same pseudonymous ID is reused, so a previously exported dataset remains linkable to all future sessions. Rotate the ID whenever the archive is deleted. |
| P2-5 | [AppModel.swift:104](../Sober/App/AppModel.swift#L104) | Baseline sessions are stored regardless of `researchConsent`; only *check* sessions require it. Enabling consent later retroactively includes those earlier baselines in the export. Defensible for a local personal baseline, but the consent card should say so plainly. |
| P2-6 | [Backend/worker.js:8](../Backend/worker.js#L8) | **What remains unsafe about isolate-local dedup:** `recentSubmissions` is a plain `Map` in one Worker isolate. Cloudflare runs many isolates across many colos, evicts them freely, and cold-starts new ones. A retry can therefore land on an isolate with no record of the first submission and send a second SMS — the dedup window is best-effort only, exactly as the comment says. It also cannot survive a deploy, and `submissionResponse` reports `deduplicated` only within one isolate's memory. A durable KV or Durable Object keyed by event ID is required before treating this as a delivery guarantee. Twilio's own `idempotency-key` header is forwarded but Twilio does not honour it on the Messages endpoint. |
| P2-7 | [Backend/worker.js:32](../Backend/worker.js#L32) | Shared-token comparison is not constant time, and there is no per-recipient rate limit. The recipient allowlist bounds the blast radius; add a rate limit before any wider deployment. |
| P2-8 | [FaceTrackingService.swift:173](../Sober/Services/FaceTrackingService.swift#L173) | `startOcularProtocol` re-runs the session with `.resetTracking`, but the on-screen target begins moving immediately from `Date()`. ARKit face reacquisition after a reset typically costs several hundred ms, which eats into the 3-second fixation phase. Measure the real reacquisition cost on device and either delay the target or extend fixation. |
| P2-9 | [ScreeningModels.swift:98-107](../Sober/Models/ScreeningModels.swift#L98) | The default `SafetyPlan` ships a prefilled name and phone number that already satisfy `canAutomaticallyAlertParent` validation. The number is a reserved fictional 555 range, so nothing can actually be sent, but shipping a pre-populated recipient is a bad default. Ship empty and force explicit entry. |

### P3 — Polish

| # | File | Issue |
| --- | --- | --- |
| P3-1 | [Docs/FOUNDER_REVIEW.md:21](FOUNDER_REVIEW.md), [plan.md:40](../plan.md#L40) | Both describe "randomized saccades". `OcularProtocolSchedule` uses a fixed 8-position sequence in a fixed order. Either randomise the order per session or correct the wording. |
| P3-2 | [OcularSignalAnalyzer.swift:59](../Sober/Services/OcularSignalAnalyzer.swift#L59) | `blinkRatePerMinute` is computed and archived but contributes nothing to any score. Fine as a research feature; worth a comment saying so. |
| P3-3 | [ResultView.swift:68](../Sober/Features/Results/ResultView.swift#L68) | The 4-second countdown gating "Return home" is not announced to VoiceOver; the button simply reads as disabled. Add an accessibility value or a live-region announcement. |

---

## Phase 3 — Fixes made

All P0 and P1 findings were fixed. No P2 or P3 item was changed.

| File | Change |
| --- | --- |
| `Sober/Models/TaskModels.swift` | Added `MotorTrackingOutcome` with `wasMeasured` and a `.notMeasured` constant. |
| `Sober/Features/Screening/TaskViews.swift` | Motor tracking emits `MotorTrackingOutcome`; the accessibility action returns `.notMeasured` instead of a hardcoded 0.22 and is relabelled. |
| `Sober/Features/Screening/ScreeningFlowView.swift` | Tracks `trackingWasMeasured` into `completedAllTasks`; baseline acceptance now also requires it; parent-alert logic delegated to `ParentAlertCoordinator` held as `@StateObject`. |
| `Sober/Services/ParentAlertService.swift` | Added `ParentAlertCoordinator` owning a run-stable event ID, delivery state, in-flight suppression, and a `makeService` seam for tests. |
| `Sober/Services/FaceTrackingService.swift` | `unusableSummary` zeroes all measurement fields for every issue and always merges `.insufficientSamples`. |
| `Sober/Models/OcularModels.swift` | `GazeCaptureSummary.capturedDurationMilliseconds` with backwards-compatible decoding. |
| `Sober/Services/OcularSignalAnalyzer.swift` | Reports the measured duration on both usable and unusable paths. |
| `Sober/App/AppModel.swift` | Ocular quality derived from the summary rather than a hardcoded 25 s; export file tracked, protected, and deleted with the archive. |
| `Sober/Features/Screening/CameraCalibrationView.swift` | Denied permission offers limited-capture continue plus an Open Settings link. |
| `Sober/Features/Screening/OcularTaskView.swift` | Denied permission disables the 25-second task and offers the inconclusive exit. |
| `Sober/Features/Home/HomeView.swift` | Reset confirmation names the data being destroyed and the session count. |
| `Sober/Features/Onboarding/OnboardingView.swift` | Retention policy corrected to describe actual reset behaviour. |
| `Sober/Features/Research/ResearchModeView.swift` | Delete confirmation mentions the export file. |
| `SoberTests/ReviewRegressionTests.swift` | New — 13 regression tests. |

Deliberately **not** done, per the brief: no trained model, no BAC estimate, no HGN or clinical
accuracy claim, no raw face video storage, no visual-direction changes, no commit and no push.

---

## Phase 4 — Test results

```
xcodegen generate
xcodebuild -project Sober.xcodeproj -scheme Sober -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```
**Executed 41 tests, with 0 failures (0 unexpected)** — `** TEST SUCCEEDED **`
(baseline before this review: 28 tests, 0 failures; +13 new regression tests)

```
cd Backend && npm test
```
**tests 10 · pass 10 · fail 0** (unchanged — no backend code was modified)

```
git diff --check
```
Clean — no whitespace or conflict-marker errors.

---

## Post-review continuation — 2026-08-04

Codex continued from Claude's findings without changing the product's non-clinical boundary.

| Finding | Current status |
| --- | --- |
| P2-1 — sign-blind gaze correlation | Open pending empirical eye-vector sign calibration on physical TrueDepth hardware. Changing the sign convention from simulator data would be unsafe. |
| P2-2 — stale expected target on anticipation | Fixed. Anticipations now archive `expected: nil`; correctness remains false. |
| P2-3 — booleans labeled as fractions | Fixed for new records. Explicit completion-state booleans replace fabricated 0/1 fractions; legacy fraction fields remain optional for decoding old exports. |
| P2-4 — participant ID survived deletion | Fixed. Deleting the research archive rotates and persists a new pseudonymous participant ID. |
| P2-5 — baseline/export consent ambiguity | Clarified in Research Center: baseline sessions are stored for the personal baseline and earlier baselines are included if research export is enabled later. |
| P2-6 — isolate-local deduplication | Fixed in code. Alerts route to a SQLite-backed Durable Object selected by recipient; an event reservation is persisted before contacting Twilio and retained for 24 hours. The Worker fails closed if provider status becomes uncertain. Deployment remains unverified. |
| P2-7 — token comparison and rate limiting | Fixed in code. Token digests are compared without an early exit, and each recipient defaults to at most three new alerts per ten minutes. |
| P2-8 — ARKit reacquisition delay | Open pending measurement on physical hardware. |
| P2-9 — prefilled Safety Circle | Fixed for new installs. Names and phone numbers start empty and must be entered explicitly. |
| P3-1/P3-2/P3-3 | Fixed: docs say structured saccades; blink rate is explicitly exploratory; the result hold exposes countdown/acknowledgement state and announces completion to VoiceOver. |

The Reduced Motion route now runs an 11-second measured fixation-and-jump-target variant instead of
skipping ocular capture. Full and Reduced Motion sessions carry an explicit protocol variant and are
never pooled into one baseline. Legacy records without a variant decode as the full protocol.

Final Codex review verification passed 53 iOS tests and 13 relay tests. That review also made missing
blink telemetry optional end to end, required exact relay receipts before showing a successful alert,
and prevented one good final camera frame from rescuing a mostly poor capture. The actual Cloudflare
bundle also passes `wrangler deploy --dry-run` with the `AlertCoordinator` Durable Object binding present.

---

## Remaining risks

1. **The live capture path has never executed.** `ARFaceTrackingConfiguration.isSupported` is false
   on the simulator, so every line inside `ingest(face:timestamp:ambientIntensity:)` and the entire
   analyzer input path is verified only against synthetic samples. Thresholds — 0.13/0.18 centring,
   0.25–0.75 m distance, ambient ≥ 180 lux, 0.025 head-stability, 20 fps — are guesses until
   measured on hardware.
2. **The scorer's constants are unvalidated.** Every weight and boundary in `ScreeningEngine` was
   chosen by hand with no ground truth. The output is a transparent heuristic, not evidence.
3. **Parent alert delivery is unproven end to end.** No deployed Worker, no real Twilio account, no
   status callbacks. "Accepted for sending" is the strongest claim the system can currently support,
   and the UI correctly says only that.
4. **Durable relay behavior is not proven in deployment.** The coordinator now survives isolate
   churn and deploys by design, but cross-region retries, Durable Object failure injection, and the
   provider-accepted/storage-write-failed path still need operational testing. Carrier delivery is
   not exactly-once and remains unknown without provider callbacks.
5. **`abs(correlation)`** (P2-1) leaves the pursuit and saccade metrics sign-blind.
6. **The Reduced Motion measured variant is synthetic-test-only.** Its 11-second fixation and jump
   target route and separate baseline need the same physical-device repeatability and accessibility
   testing as the full protocol.
7. The ocular protocol remains an experimental research input. It is not HGN, not a standardised
   field sobriety test, and not a validated impairment measure.

---

## Physical TrueDepth iPhone test checklist

Run on a Face ID-capable iPhone. Simulator results do not substitute for any line below.

**Capture and permissions**
- [ ] First launch: camera prompt appears; denying it lands on the limited-capture path with a
      working Open Settings link, and the check completes as `INCONCLUSIVE`.
- [ ] Granting permission mid-flow recovers without a relaunch.
- [ ] Revoke camera access in Settings while the app is backgrounded; return mid-check and confirm
      no crash and no usable-capture claim.
- [ ] Preview shows the user's face, mirrored, and the face actually tracks in the guide oval.
- [ ] Each of the six calibration tiles flips independently and truthfully (occlude the face, move
      off-centre, move too close and too far, dim the lights, shake the phone, cover one eye).
- [ ] "Hold steady…" requires a genuine ~0.9 s of continuous readiness and resets when broken.

**Ocular protocol**
- [ ] Measure ARKit face reacquisition time after `startOcularProtocol` and confirm how much of the
      3 s fixation phase is lost (P2-8).
- [ ] Confirm the on-screen target and the recorded `phase` labels stay aligned across all 25 s —
      compare `ARFrame.timestamp` against the wall-clock `startedAt` driving the animation.
- [ ] Sample count reaches ≥ 600 (~24 fps) over the protocol; `dropoutRatio` stays below 0.3.
- [ ] Deliberately look *away* from the target for the whole horizontal phase and confirm the error
      metric rises — this is the direct test of the `abs(correlation)` concern (P2-1).
- [ ] Deliberately track *inverted* and record whether the score is falsely good.
- [ ] Wearing glasses, then contacts, then neither; note glare behaviour.
- [ ] Dark bar-like lighting, harsh backlight, and moving car interior (as a passenger).
- [ ] Turn on Reduced Motion; confirm the 11-second fixation-and-jump-target variant appears, records
      a usable sample when quality permits, archives `protocolVariant: reducedMotion`, and contributes
      only to the separate Reduced Motion baseline.
- [ ] Background the app mid-protocol; confirm the session pauses and the result is not usable.
- [ ] Take a phone call mid-protocol; confirm the same.

**Data and privacy**
- [ ] Record five clean baselines; confirm the Research Center counter reaches 5/5 and the
      home-screen counter matches.
- [ ] Force-quit and relaunch; confirm sessions and baseline survive.
- [ ] Export JSON and read it end to end: no name, no phone number, no image data, no unexpected
      identifiers; `trackingDurationMilliseconds` matches actual capture time.
- [ ] Delete all data, then confirm the previously prepared export file is gone from Files/tmp.
- [ ] Reset the prototype and confirm the new confirmation copy states what will be destroyed.
- [ ] Profile memory across ten consecutive checks; confirm no `ARSession` or sample-buffer growth.
- [ ] Confirm the camera indicator turns **off** during the reaction, tracking, and timing tasks.

**Accessibility**
- [ ] Full VoiceOver pass of the screening flow.
- [ ] Confirm the motor tracking accessibility action now reads "Skip tracing — result will be
      inconclusive" and produces `INCONCLUSIVE`.
- [ ] Dynamic Type at the largest accessibility size on every screen.
- [ ] Confirm the result screen's countdown state is comprehensible without sight.

---

## Deployed parent-alert relay checklist

**Before first deploy**
- [ ] `ALERT_SHARED_TOKEN` is ≥ 20 chars, randomly generated, and stored only as a Worker secret.
- [ ] `ALERT_ALLOWED_RECIPIENTS` contains only real, consenting test numbers.
- [ ] Twilio credentials are secrets, never in `wrangler.toml`.
- [ ] `SoberParentAlertAPIURL` / `SoberParentAlertToken` resolve in the build (not left as `$(...)`).
- [ ] Confirm the relay never logs message bodies, phone numbers, or the shared token.

**Functional**
- [ ] Concerning live result sends exactly one SMS to an allowlisted number.
- [ ] The received SMS contains no score, no camera reference, and no BAC-like claim.
- [ ] Non-`SIGNALS_DETECTED` payloads are rejected with 422.
- [ ] A non-allowlisted recipient is rejected with 403.
- [ ] A wrong or missing bearer token is rejected with 401.
- [ ] Body event ID mismatching the `Idempotency-Key` header is rejected with 409.
- [ ] Same event ID with different content is rejected with 409.

**Reliability — the part that actually needs proving**
- [ ] Tap "Try automatic alert again" repeatedly after a forced failure and confirm the **same**
      event ID is sent every time (this is the P0-2 regression).
- [ ] Confirm only one SMS arrives per event across those retries.
- [ ] Retry from a different network/region and confirm both requests route to the same durable
      recipient coordinator and only one provider submission occurs.
- [ ] Redeploy the Worker between two retries of the same event and confirm the durable receipt survives.
- [ ] Submit four distinct events to one recipient within ten minutes and confirm the fourth receives 429.
- [ ] Simulate Twilio 429 and 5xx and confirm the app shows a retryable failure, never "sent".
- [ ] Simulate a malformed Twilio response and confirm the app never claims success.
- [ ] Confirm the result screen never says "delivered" — only "accepted for sending".
- [ ] Force a storage failure after provider acceptance and confirm the event remains fail-closed as
      status unknown rather than automatically sending again.

---

## Verdict

**NEEDS WORK** — the code-addressable review findings are resolved except the two ocular items that
require physical measurement (P2-1 and P2-8). Physical TrueDepth QA, deployed relay/provider testing,
delivery callbacks, and clinical validation remain open. This build is appropriate for co-founder
demo review, not public testing.
