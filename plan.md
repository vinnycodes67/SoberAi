# Sober Research Build 0.2 — Execution Plan

Last updated: 2026-08-04

## UI Motion + Liquid Glass Pass

### Goal

Make the founder build feel like a polished native iOS product while preserving every safety, privacy, refusal, and alert invariant. The first half-second should read as a calm luminous signal halo floating above one decisive action.

### Research findings

- Apple positions Liquid Glass as a floating navigation and control layer, not a general content-card material.
- Native iOS 26 APIs are `glassEffect`, `.glass` / `.glassProminent`, `GlassEffectContainer`, and `glassEffectID`; adjacent glass should share a container for correct sampling and performance.
- Interactive glass provides native scale, bounce, and shimmer. Tint is reserved for meaningful primary actions.
- SwiftUI `phaseAnimator`, `keyframeAnimator`, `symbolEffect`, `contentTransition`, and spring animations support the remaining state motion.
- `accessibilityReduceMotion` must remove large or spatial animation; strengthened solid fallbacks are required when transparency is reduced.

### Design direction

- **Aesthetic:** Nocturnal instrument: deep blue-black field, restrained cyan light, serif hero type, and precise data typography.
- **Safe choices:** Native navigation and sheets, familiar single-column tasks, one accent hue, minimum 54 pt primary actions.
- **Creative risks:** A living orbital halo, a slow atmospheric background, and grouped glass controls that materialize on iOS 26.
- **Restraint:** No confetti, celebratory concern states, nested glass, glass-filled scrolling lists, or green pass language.

### Implementation sequence

- [x] Research current Apple SwiftUI Liquid Glass, animation, performance, and accessibility guidance with Agent Reach.
- [x] Record the visual and motion rules in `DESIGN.md`.
- [x] Add reusable motion tokens, entrance transitions, atmospheric background, and transparency fallbacks.
- [x] Add availability-gated iOS 26 Liquid Glass button and floating-control styles with iOS 17 material fallbacks.
- [x] Refine the signal halo, progress, and changing-number motion.
- [x] Apply entrance and control treatments to Home, onboarding, Safety Circle, screening, and result flows without touching scoring or alert behavior.
- [x] Run project generation, all iOS and backend tests, `git diff --check`, and simulator screenshot review.

### Acceptance criteria

- The project still targets iOS 17 and compiles with Xcode 26.
- iOS 26 uses real Liquid Glass APIs for key interactive controls; older versions render a deliberate material fallback.
- Reduce Motion removes continuous orbit, positional entrance travel, and decorative background movement.
- Reduce Transparency produces readable opaque surfaces.
- Result semantics, parent-alert timing, camera capture, storage, and the no-safe-to-drive language are unchanged.
- No nested glass or high-frequency scrolling glass is introduced.

## Goal

Turn the founder MVP into a research-ready prototype that visibly uses the front camera, refuses unusable captures, records versioned sessions, and stores real sober baselines without claiming clinical accuracy.

This build remains an impairment-awareness prototype. It must not claim to determine sobriety, driving safety, BAC, or an official NHTSA field sobriety result.

## Team and ownership

| Lane | Owner | Scope | Status |
| --- | --- | --- | --- |
| Product and failure-mode review | Claude Code | Independent review plus P0/P1 fixes | Complete; see `Docs/CLAUDE_REVIEW.md` |
| Repository map | Codex explorer | Existing architecture, gaps, safety bugs, test surface | Complete |
| Camera and ocular integration | Root Codex | ARKit preview, live capture quality, expanded ocular task, screening flow integration | Complete; physical-device QA remains |
| Research data and baseline engine | Codex worker | Versioned session models, local store, robust baseline summaries, unit tests | Complete |
| Alert reliability | Codex worker | Stable event IDs, durable per-recipient coordination, rate limiting, retry/provider failure tests | Complete; deployment test remains |
| Final integration | Root Codex | Home/Research UI, AppModel wiring, docs, project generation, full verification | Complete |

All agents share this worktree. Workers own only the files named in their assignments and must preserve existing uncommitted MVP work.

## Build sequence

### 1. Safety correction and capture contract

- [x] Unsupported or unavailable face tracking returns unusable quality, never demo-clear data.
- [x] Separate founder sample behavior from live capture behavior.
- [x] Represent capture readiness with structured quality fields and explicit failure reasons.
- [x] Add tests proving unsupported, interrupted, or low-sample capture cannot produce `NO_SIGNALS_DETECTED`.

Acceptance: a live check without a supported, usable capture is `INCONCLUSIVE` unless the self-report safety gate already yields `SIGNALS_DETECTED`.

### 2. Visible camera calibration and ocular battery

- [x] Display a mirrored front-camera preview backed by the same ARKit session used for measurements.
- [x] Show face presence, centering, lighting, head stability, and sample readiness.
- [x] Replace manual environment toggles with a live calibration gate on supported devices.
- [x] Add fixation, horizontal pursuit, vertical pursuit, and a structured saccade sequence.
- [x] Preserve only bounded numeric landmarks/features in memory; do not persist raw frames.
- [x] Keep unsupported-device founder demonstrations explicitly labeled as samples.

Acceptance: supported physical devices show the user’s face during setup, block progression until capture is usable, and produce an ocular summary with structured quality. Simulator/live unsupported runs cannot be presented as measured results.

### 3. Research session capture and personal baselines

- [x] Add a versioned `Codable` research-session envelope.
- [x] Record pseudonymous participant/session IDs, timestamps, device/app/protocol versions, context, task metrics, ocular quality, and optional breath-reference metadata.
- [x] Store sessions locally under Application Support with file protection where available.
- [x] Provide export and delete controls behind explicit Research Mode consent.
- [x] Store actual high-quality baseline metrics instead of only a counter.
- [x] Compute median and median absolute deviation summaries while excluding incomplete or poor-quality baselines.
- [x] Keep baseline deltas research-only; do not silently retune the safety scorer.

Acceptance: a completed eligible session survives relaunch, round-trips through JSON, can be exported/deleted, and contributes to the baseline only when complete and high quality.

### 4. Stronger divided-attention task

- [x] Upgrade reaction testing from a single target to randomized color/shape choices.
- [x] Record per-trial latency, incorrect choices, anticipations, misses, and variability.
- [x] Reduce the result into backwards-compatible screening metrics plus research detail.

Acceptance: deterministic task-summary tests cover correct, incorrect, missed, and early responses.

### 5. Parent-alert reliability

- [x] Keep one stable event ID across retries.
- [x] Add backend duplicate-event suppression and tests.
- [x] Distinguish provider acceptance from confirmed carrier delivery in UI copy.
- [x] Cover provider rejection, malformed provider responses, and transient failures.

Acceptance: retrying the same concerning event cannot create multiple provider sends during the relay’s deduplication window.

### 6. Integration and verification

- [x] Add a founder-only Research Center showing consent, session count, baseline quality, export, and delete.
- [x] Update `README.md` and founder-review documentation with new capabilities and remaining limits.
- [x] Regenerate the Xcode project from `project.yml`.
- [x] Run all iOS and backend tests.
- [x] Review the final diff for safety language, privacy, unsupported-device behavior, and accidental raw-data persistence.
- [x] Complete an independent Claude safety, privacy, and correctness review.

## Verification baseline

Before this plan was written:

- iOS: 11 tests passed, 0 failed.
- Backend relay: 4 tests passed, 0 failed.
- Worktree already contained uncommitted founder-MVP and parent-alert changes; they are preserved.

## Deliberately out of scope

- Training or calibrating an impairment model without clinical ground truth.
- BAC estimation or a sober/safe-to-drive verdict.
- Official HGN/SFST claims.
- Unsupervised production retraining.
- Raw face-video storage or upload.
- Real carrier-delivery confirmation without deployed provider webhooks.
- Controlled alcohol data collection without an approved research protocol and appropriate oversight.

## Execution log

- 2026-08-03: Codex repository audit completed.
- 2026-08-03: Critical unsupported-camera demo-data fallback identified.
- 2026-08-03: Claude consult attempted and blocked by missing authentication.
- 2026-08-03: Clean verification baseline established: 11 iOS tests and 4 backend tests passing.
- 2026-08-03: Live camera calibration, 25-second ocular protocol, divided-attention reaction task, and unsupported-camera fail-safe completed.
- 2026-08-03: Versioned local research sessions, five-session robust baseline, Research Center export/delete controls, and context capture completed.
- 2026-08-03: Stable parent-alert IDs and best-effort relay deduplication completed; UI now says relay acceptance is not carrier confirmation.
- 2026-08-03: Final verification passed: 28 iOS tests and 10 backend tests, 0 failures. Physical TrueDepth QA remained external.
- 2026-08-03: Simulator launch smoke test completed; the old three-session founder-preview state was migrated to the new five-session display.
- 2026-08-03: Claude completed an independent review and fixed two P0 and four P1 defects.
- 2026-08-04: Codex continued the review plan: corrected anticipation archives, research quality semantics, participant-ID rotation, consent copy, empty Safety Circle defaults, legacy protocol decoding, and result-screen accessibility.
- 2026-08-04: Replaced isolate-local relay deduplication with a SQLite-backed per-recipient Durable Object, constant-time token verification, a 24-hour deduplication window, a three-per-ten-minute rate limit, and fail-closed uncertain-delivery handling.
- 2026-08-04: Final continuation verification passed: project generation, 49 iOS tests, 13 backend tests, Cloudflare Worker bundle dry-run, and `git diff --check`, all with zero failures.
- 2026-08-04: Final Codex review fixed missing ocular telemetry semantics, capture-wide quality refusal, and exact parent-alert receipt validation; 53 iOS tests and 13 backend tests passed with zero failures.
- 2026-08-04: Agent Reach research confirmed Apple's iOS 26 Liquid Glass hierarchy, grouping, interaction, performance, and Reduce Motion guidance.
- 2026-08-04: Added the nocturnal-instrument design system, availability-gated native glass controls, iOS 17 material fallbacks, an atmospheric background, a refined signal halo, entrance/progress/state motion, and accessibility-aware motion/transparency behavior.
- 2026-08-04: UI verification passed on the iPhone 17 Pro iOS 26.5 simulator at default and Accessibility Medium Dynamic Type. Final verification passed: 53 iOS tests, 13 backend tests, Cloudflare dry-run, and `git diff --check` with zero failures.
