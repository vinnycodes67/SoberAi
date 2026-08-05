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

---

# Sober Finish-Out 0.3 — Guardian, Validation, and Reliability

Last updated: 2026-08-05

## Status and planning inputs

This is the executable plan for the previously proposed steps 3–5:

1. Build Guardian Mode with app-based alerts, acknowledgment, and SMS fallback.
2. Establish a defensible data and validation program before training a model.
3. Harden every camera, network, notification, interruption, and provider failure path.

Codex produced this repository-grounded synthesis. Claude's existing independent findings in
`Docs/CLAUDE_REVIEW.md` are incorporated, especially the open physical-device, deployed-relay,
delivery-callback, and clinical-validation risks. Claude completed the fresh Gate 0 challenge in
`Docs/CLAUDE_FINISH_REVIEW.md` on 2026-08-05. Its three P0 findings blocked the original account/D1
architecture. Codex revised the contracts around relationship-scoped signing capabilities and one
Durable Object consistency boundary. A second code-grounded Claude review then returned
**ACCEPT WITH REQUIRED CHANGES**: the architecture remained accepted, but the original Gate 1 was blocked on
contract-versus-code drift, truthful unknown-delivery handling, relaunch idempotency, a smaller
person-facing state model, and moving sober repeatability evidence ahead of any non-founder alert.
Codex applied those changes and Claude's final read-only re-review returned
**CONTRACT READY FOR FOUNDER-ONLY GATE 1**. See `Docs/CODEX_CLAUDE_GATE0_SYNTHESIS.md`.

## Non-negotiable product boundary

- Sober detects concerning deviation from a person's measured baseline; it does not determine
  sobriety, BAC, fitness to drive, or completion of an official field sobriety test.
- `INCONCLUSIVE` remains a first-class result. Missing, interrupted, contradictory, or poor-quality
  data may never be converted into reassurance.
- Guardian notifications share only the minimum safety message and help request. They never contain
  camera frames, landmarks, task-level scores, inferred substances, or a “sober/drunk” label.
- APNs or SMS provider acceptance is not delivery. Only a signed guardian acknowledgment may be
  shown as “acknowledged.”
- Raw face video remains on-device and unpersisted. Any future raw-video research would require a
  separate build, separate consent, separate retention policy, and separate security review.
- External human-subject research and user-facing accuracy claims require qualified research,
  legal, privacy, and regulatory review. The FDA's current
  [Digital Health Policy Navigator](https://www.fda.gov/medical-devices/digital-health-center-excellence/digital-health-policy-navigator)
  is an explicit classification checkpoint before public claims change.

## Architecture decision

Use one iOS binary with two roles: **Person being screened** and **Guardian**. A guardian installs
Sober, accepts an expiring invite, grants notification permission, and explicitly acknowledges the
relationship. The existing phone-number-only Safety Circle remains available until the guardian is
linked.

Recommended production path:

- Each role creates a P-256 signing key stored in this-device-only Keychain/Secure Enclave storage.
  The backend stores public keys only and verifies signatures covering the relationship, request,
  event, timestamp, nonce, and idempotency key.
- One `GuardianRelationship` Durable Object stores the relationship, consent, public keys, devices,
  verified phone digests, revocation, alert idempotency, provider state, acknowledgment deadline,
  and SMS alarm. D1 and accounts are deliberately excluded from the founder build.
- Revocation and alert submission serialize through that one object. If revocation commits first,
  no provider is called; if a provider attempt starts first, it may finish but no later fallback or
  acknowledgment proceeds after revocation.
- Signed concerning events coalesce into one recent unacknowledged canonical alert instead of being
  silently dropped by an event-count rate limit. Retry and fallback consume no second reservation.
  One canonical alert may represent multiple concerning checks: one notification is not evidence of
  one incident, and coalescing must never be used as a behavioral or clinical count.
- APNs sends the immediate app notification. Follow Apple's device-token registration lifecycle;
  tokens are variable-length and must be refreshed when iOS changes them. See
  [Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns).
- Guardian pushes are Time Sensitive. A Critical Alerts entitlement is a separate Apple dependency
  if the founders require reliable Focus override; provider acceptance is never shown as delivery.
  If Apple denies that entitlement, the product explicitly treats push as the acknowledgment path
  and the verified 30-second SMS as the reachability path. It does not claim to bypass Focus or DND.
- If no active guardian device exists or APNs rejects the request, send SMS immediately only to a
  separately verified, consented guardian phone. If APNs accepts but no signed acknowledgment arrives
  within 30 seconds, the same object sends one SMS fallback using the canonical event ID.
- Alert status is retained for 24 hours; invite tokens expire after 24 hours; founder relationships
  expire after 90 days and require a fresh two-sided invite. Both roles receive advance expiry
  warnings, and expiry returns the Safety Circle to visibly unconfigured. Exact retention still
  requires counsel.

## Team ownership and conflict boundaries

| Area | Claude Code owner | Codex owner | Shared gate |
| --- | --- | --- | --- |
| Guardian backend | `Backend/**`, backend tests, `Docs/GUARDIAN_API.md`, `Docs/GUARDIAN_THREAT_MODEL.md` | iOS/API integration review | Contract review before either side codes |
| Guardian iOS | Privacy/failure-mode challenge and approval of every person-facing alert-state string | `Sober/Features/Guardian/**`, guardian models/services, entitlements, iOS tests | End-to-end simulator/device review plus copy signoff |
| Validation program | Challenge labels, leakage, claims, subgroup risks, and protocol gaps | Research schema, data dictionary, export validation, analysis harness | Protocol sign-off before collecting study data |
| Failure hardening | Backend chaos cases and adversarial review | iOS state machine, interruption handling, device QA harness | Full failure matrix and joint diff review |
| Integration | No edits to Codex-owned files; return findings in review docs | Own shared project files, resolve API mismatches, run final suite | Claude challenge followed by Codex fixes |

Claude and Codex must work in separate branches or worktrees. Claude does not edit iOS files and
Codex does not edit Claude-owned backend files while parallel work is active. `plan.md`,
`project.yml`, and cross-system contract fixtures are integrated by Codex only.

## Gate 0 — Freeze the contract before implementation

**Claude**

- [x] Authenticate the Claude CLI and review this plan plus `Docs/CLAUDE_REVIEW.md`.
- [x] Produce `Docs/CLAUDE_FINISH_REVIEW.md` covering threat boundaries, notification truthfulness,
  duplicate-alert risks, consent/revocation, research-label leakage, and missing failure cases.
- [x] Challenge whether Sign in with Apple + D1 + Durable Objects is the smallest architecture that can
  safely support two-sided identity and acknowledgment.
- [x] Re-review the capability-based revision of `Docs/GUARDIAN_API.md` and
  `Docs/GUARDIAN_DATA_GOVERNANCE.md`.
- [x] Run a second code-grounded review against the contracts and the shipping alert implementation;
  verdict: **ACCEPT WITH REQUIRED CHANGES**.
- [x] Re-review the required-changes revision; verdict:
  **CONTRACT READY FOR FOUNDER-ONLY GATE 1**.

**Codex**

- [x] Commit the current 53-test green UI/animation checkpoint without staging unrelated files
  (`0ee4e31`).
- [x] Write the guardian API contract and state diagram before adding views
  (`Docs/GUARDIAN_API.md`).
- [x] Record all new data fields, retention, log redaction, and consent-version behavior
  (`Docs/GUARDIAN_DATA_GOVERNANCE.md`).
- [x] Apply every required change in `Docs/CODEX_CLAUDE_GATE0_SYNTHESIS.md` to this plan, the API
  contract, data/validation rules, and test gates.
- [x] Add the Gate 1 threat model (`Docs/GUARDIAN_THREAT_MODEL.md`).

**Exit criteria**

- Both agents agree on API payloads, authentication, idempotency, state names, fallback timing,
  retention, and which claims the UI may display.
- Unresolved one-way security/privacy decisions stop implementation and go to the founders.
- Every claimed control cites a passing code test; prose in a contract never counts as implemented.
- Guardian plumbing may enter founder-only Gate 1, but live alerts to non-founder guardians remain
  disabled until the sober repeatability gate quantifies false-positive and abstention behavior.

Gate 0 is closed for founder-only Gate 1. Contract acceptance is not implementation evidence:
production behavior remains unchanged until the named code tests pass. The App Attest enrollment
wire contract must be frozen and re-reviewed before any non-founder installation can initiate a
verification SMS.

## Workstream 3 — Guardian Mode

### 3A. Backend and notification foundation — Claude owns

- Add a versioned per-relationship Durable Object schema for public-key capabilities, consent,
  invites, devices, verified phone digests, revocation, alerts, aliases, and alarms. Do not add D1.
- Require App Attest (or an equally reviewed installation proof) before the unauthenticated
  relationship-creation endpoint can send a verification SMS. A founder allowlist is allowed only
  while every installation remains founder-controlled.
- Add ES256 request verification with signed body/path/event, timestamp bounds, nonce replay
  prevention, role scoping, and generic non-enumerating failures. Delete the shared-bearer founder
  endpoint before the first guardian build leaves founder-controlled devices; do not run old and new
  alert paths side by side.
- Generate push and SMS text exclusively from versioned server templates. Reject and test every
  client-supplied `message`, score, metric, camera, substance, or provider field.
- Add endpoints to create and verify the person's relationship, redeem an invite once, verify a
  distinct guardian fallback phone, register/rotate/delete role APNs tokens, revoke, query status,
  and submit a signed acknowledgment.
- Add APNs provider-token signing, response parsing, token invalidation, retry classification, and
  zero-sensitive-body logging. Send Time Sensitive notifications and document the optional Critical
  Alerts profile separately.
- Extend the Durable Object state machine:
  `reserved → pushAccepted/fallbackScheduled → guardianAcknowledged`, with explicit
  `pushRejected`, `smsAccepted`, `statusUnknown`, and `expired` states. Keep guardian-open telemetry
  backend-only; never show it to the screened person.
- Schedule one 30-second SMS fallback alarm. Cancel it only after a valid guardian acknowledgment.
  Persist the alarm before APNs contact, reuse the canonical event ID across every channel, and
  serialize the t=30 acknowledgment race inside the same object.
- Add Twilio status callbacks for `queued`, `sent`, `delivered`, `undelivered`, and `failed`, while
  keeping provider delivery separate from guardian acknowledgment.
- Coalesce a recent unacknowledged duplicate-content event into the existing canonical alert. A
  fallback or replay consumes no second reservation, and any abuse-control failure is explicit.
  Remove the shipping three-events-per-ten-minutes rejection from the signed relationship path in
  code; prove that a fourth distinct concerning event is handled rather than silently dropped.
- Map provider-ambiguous `425` outcomes to durable `statusUnknown`, never `failed`, and suppress
  automatic resends on that channel.
- Add contract, signature, replay, invite/phone verification, revocation ordering, APNs error/Focus,
  alarm-race, callback-signature, provider-ambiguity, and idempotency tests.

### 3B. Guardian iOS experience — Codex owns

- Add role selection, P-256 capability-key provisioning, person/guardian phone verification,
  guardian invite creation, universal-link redemption, two-sided consent, notification permission,
  relationship status, expiry, and revocation.
- Add a Guardian home screen with the person's display name, relationship state, a minimal alert
  card, “I'm helping,” call, message, and safe-ride actions. Do not show screening metrics.
- Register for remote notifications at launch only after role/consent setup, send token changes to
  the backend, and remove the token on logout or relationship revocation.
- Add a signed alert-status client that survives app backgrounding, relaunch, network changes, stale
  responses, canonical-event coalescing, and lost/corrupt receipts. Persist only the relationship
  capability, opaque IDs, and minimal pending receipt in Keychain-protected storage. Killing and
  relaunching between reservation and receipt must recover the same event ID and never send again.
- Collapse the screened-person result surface to three understandable actions: **requesting help**,
  **guardian confirmed**, or **contact them yourself now**. Provider-specific push/SMS/unknown states
  stay internal; the third state may explain that automatic status could not be confirmed, but may
  never say “failed” for a possibly-sent request. Never show guardian-opened or delivered.
- If acknowledgment is absent, keep direct Call/Message/Ride actions prominent. Never block those
  actions on network state.
- Add VoiceOver labels, Dynamic Type layouts, Reduce Motion behavior, notification deep-link routing,
  explicit permission-denied recovery, generic revocation notification handling, and foreground
  relationship reconciliation that returns a revoked Safety Circle to unconfigured.

### 3C. Guardian Mode acceptance criteria

- A linked guardian receives an app notification for a live concerning result and can acknowledge
  it from the alert screen.
- The screened person's app displays acknowledgment only after the backend accepts an authenticated
  guardian action for that relationship and event.
- A missing device token, denied notifications, APNs rejection, timeout, app uninstall, expired
  session, or unacknowledged push produces exactly one SMS fallback where allowed.
- A denied Critical Alerts entitlement leaves the app truthful: Time Sensitive push remains the
  acknowledgment channel, verified SMS remains the reachability channel, and no screen promises a
  Focus/DND override.
- Replaying an invite, revoked relationship, wrong capability, mismatched event/signature, or
  duplicate acknowledgment is rejected without exposing whether another relationship exists.
- Samples, founder previews, `INCONCLUSIVE`, and `NO_SIGNALS_DETECTED` never notify a guardian.
- Push and SMS contain no score, camera detail, or substance inference; logs contain no names, phone
  numbers, message bodies, tokens, or raw device tokens.
- The old shared-token endpoint and client-authored message body no longer exist in the compiled
  Worker; contract tests enforce both absences.
- A `425`/possibly-sent provider result is never rendered as failed, relaunch reuses the canonical
  event ID, and no delivery wording exists until a signature-validated provider callback is stored.
- Expiry warning is visible to both roles before 90 days; expiry and revocation both return the
  screened person's Safety Circle to explicitly unconfigured.

## Workstream 4 — Data and validation before model training

### 4A. Define the target — Claude challenges, Codex documents

- Freeze the intended target as **personal performance deviation under usable capture**, not
  “alcohol detected” or “safe to drive.”
- Publish a versioned data dictionary for every input, unit, missing-value meaning, protocol variant,
  quality field, confounder, transformation, and exclusion rule.
- Version the external dictionary independently of the storage envelope. Optionality, units,
  missing-value meaning, or protocol changes require a dictionary-version bump even when storage
  schema decoding is unchanged.
- List Guardian relationship, capability, invite, device, event, provider, delivery, and
  acknowledgment identifiers as prohibited research/export fields and test their absence.
- Pre-register primary metrics, abstention rules, subgroup analyses, and stop conditions with a
  qualified statistician/research partner. Do not select success thresholds after viewing results.
- Define ground truth separately from model inputs. Self-report alone is not a sufficient label.
  Reference instruments and supervised observations must be captured independently and time-aligned.
- Apply that rule to the baseline itself: a self-described “sober” session is an unverified reference,
  not ground truth. Baseline eligibility records confounders and abstains on reported use,
  uncertainty, illness, severe sleep loss, medication change, poor capture, or incomplete protocol.
- Reconcile privacy rotation with participant-held-out evaluation. Formal studies use a stable,
  study-issued subject key held in a separate approved linkage system; app-generated IDs that rotate
  on reset may not be used to prove train/test separation across exports.
- Pre-register a minimum participant count per device and subgroup. Below that count, report
  “insufficient evidence” rather than inferring that no disparity exists.

### 4B. Stage the evidence program — Codex implements tooling

1. **Technical repeatability pilot:** collect at least five controlled-reference sessions per
   participant across
   lighting, time of day, glasses/contacts, supported devices, and both motion protocols. Measure
   missingness, test-retest variability, device effects, capture rejection, baseline stability,
   abstention, and the rate at which ostensibly sober sessions produce `SIGNALS_DETECTED`. Guardian
   plumbing may run only on founder-controlled devices during this pilot; no non-founder guardian
   receives a live alert.
2. **Observational paired pilot:** only after protocol/consent review, collect time-aligned reference
   measures and Sober sessions in a supervised setting. Preserve the reference label separately from
   derived features and app outcomes.
3. **Controlled impairment study:** do not run informally. Proceed only with a qualified clinical or
   academic partner, appropriate ethics/IRB determination, age/consent controls, adverse-event plan,
   transport plan, and legal/regulatory review.

### 4C. Training and evaluation gates

- Do not train until schema, protocol, labels, exclusions, and consent are frozen and versioned.
- Split train/validation/test by participant, never by session. A person's baseline and follow-up
  sessions may not leak across partitions. Dataset ingestion rejects missing study subject keys and
  detects reset/rotation boundaries before splitting.
- Keep a locked final test set. Report sensitivity, specificity, calibration, confidence intervals,
  abstention rate, false-negative cases, device/protocol effects, and subgroup slices.
- Compare every model against simple transparent baselines. Reject a model that adds complexity
  without reproducible out-of-participant improvement.
- Run candidates in silent shadow mode first. They may write research-only comparisons but may not
  alter the user-facing result, parent-alert rule, or safety language.
- Version the model, feature pipeline, protocol, threshold set, and training dataset together. Ship a
  model card, dataset statement, rollback path, and monitoring plan.

### 4D. Validation acceptance criteria

- Export validation proves that every field matches the data dictionary and no prohibited identity
  or raw-image data appears.
- Repeatability and failure rates are quantified on physical supported devices before any accuracy
  claim, threshold change, or live alert to a non-founder guardian.
- Evaluation is participant-held-out and reproducible from immutable scripts/configuration.
- Subgroup or device gaps trigger abstention, more data, or scope reduction; they are not hidden by
  an aggregate score.
- Every subgroup/device slice reports its sample count and confidence interval; slices below the
  pre-registered minimum are labeled insufficient evidence.
- Baseline contamination and participant-ID rotation tests prove that an unverified or reset-linked
  session cannot silently enter both sides of a participant-held-out evaluation.
- No model reaches users until founders, research lead, privacy/legal reviewer, and Claude/Codex
  review all sign off on the evidence and exact user-facing claim.

## Workstream 5 — Failure-mode hardening

### 5A. Codex iOS reliability work

- Replace implicit view-driven progression with an explicit screening state machine whose transitions
  are unit tested: foreground/background, camera denied/revoked, AR session interruption, call/audio
  interruption, thermal pressure, low power, task abandonment, and relaunch.
- Pause or invalidate capture when timestamps, target phases, or camera samples lose alignment.
- Add network state handling for offline start, timeout, reconnect, duplicated responses, stale status,
  and response-after-cancellation.
- Persist a minimal pending-alert receipt so relaunch can recover the same event ID and query status
  instead of creating a new alert.
- Verify the camera indicator and AR session stop outside calibration/ocular phases; run a ten-session
  memory/leak test on hardware.
- Add deterministic fakes for camera quality, clocks, lifecycle events, APNs registration, status
  polling, and guardian acknowledgment.

### 5B. Claude backend chaos and operations work

- Test Durable Object restart, deploy between retries, storage failure before/after provider calls,
  alarm duplication, revocation/send ordering, t=30 acknowledgment races, capability replay, abuse
  limiter unavailability, APNs timeout/410/429/5xx, Focus/silent delivery, and Twilio callback replay.
- Add structured, privacy-safe observability keyed by opaque event IDs: request outcome, state
  transition, latency, retry count, fallback reason, and acknowledgment latency.
- Add alerts for elevated push rejection, fallback rate, unknown-status events, callback signature
  failures, and rate-limit spikes without logging sensitive payloads.
- Write deployment, credential rotation, APNs key rotation, provider outage, rollback, and incident
  runbooks. Add a founder-number allowlist and staging environment before production.

### 5C. Joint failure matrix

Test every combination that can change user truthfulness:

| Domain | Required cases |
| --- | --- |
| Camera | unsupported, denied, revoked, no face, multiple faces, poor light, glare, dropout, interruption |
| Tasks | anticipation, miss, wrong choice, abandonment, backgrounding, clock drift, Reduced Motion |
| Network | offline, timeout, reconnect, duplicate, stale response, cancellation, server 4xx/5xx, and an explicit distinction between automatic status reconciliation and manual send retry |
| Guardian | no app, denied notifications, Critical Alerts denied, Focus/silent push, expired capability, revoked link, wrong key, same device/phone, uninstall, no acknowledgment |
| Providers | APNs accepted/rejected/invalid token; Twilio accepted/delivered/failed; `425` possibly-sent; signed callback replay/forgery; rejection of client-authored message text |
| Storage | Keychain unavailable, corrupt local archive, app killed between reservation/receipt, Durable Object/abuse-limiter failure, restart, post-send write failure |
| Accessibility | VoiceOver, largest Dynamic Type, Reduce Motion, Reduce Transparency, Switch Control path |

### 5D. Reliability acceptance criteria

- Every failure produces one of: safe recovery, explicit `INCONCLUSIVE`, direct-help fallback, or a
  truthful alert failure. No failure silently produces reassurance.
- The same concerning event can never create multiple SMS sends under supported retry/relaunch paths.
- Killing and relaunching the app after server reservation but before receipt recovery reuses the
  canonical event ID and performs status reconciliation before any provider retry.
- A provider-ambiguous `425` is never displayed as failed and never triggers an automatic resend on
  that channel.
- No UI says delivered or acknowledged without the corresponding provider callback or authenticated
  guardian action.
- No UI says a human was reached based on APNs/SMS acceptance; the only human-confirmation state is
  the guardian's signed acknowledgment.
- Physical TrueDepth QA passes on at least two supported iPhones, including glasses, low light,
  background/foreground, camera revocation, full protocol, and Reduced Motion protocol.
- All iOS tests, backend tests, contract tests, Cloudflare dry-run, privacy-log inspection,
  accessibility pass, and `git diff --check` pass before TestFlight distribution.

## Execution order and review gates

1. **Gate 0:** apply the code-grounded Claude requirements, revise the frozen contracts, and obtain
   Claude verification. Checkpoint the accepted plan separately from implementation.
2. **Gate 1 — founder-only build:** Claude implements capabilities/invites/APNs/status while Codex
   implements iOS key handling, guardian screens, the research dictionary, and repeatability-pilot
   tooling against frozen fixtures. Shared-token removal, App Attest, server templates, `425`
   truthfulness, and relaunch idempotency land here.
3. **Gate 2 — founder-only integration:** run end-to-end staging, chaos, privacy, and copy tests only
   with founder-controlled devices and numbers. Claude performs an adversarial code review; Codex
   fixes every P0/P1 finding.
4. **Gate 3 — evidence before escalation:** complete physical-device failure QA and run the sober
   repeatability pilot. Quantify `SIGNALS_DETECTED`, abstention, missingness, device, and subgroup
   behavior. Live alerts to non-founder guardians remain disabled.
5. **Gate 4 — guarded external pilot:** only if the pre-registered repeatability thresholds pass and
   human reviewers approve the protocol may a consenting non-founder guardian receive a live alert.
   Before enrollment opens, freeze and re-review `Docs/GUARDIAN_APP_ATTEST.md`, including attestation,
   assertion, counter, challenge, environment, replay, and recovery semantics. Run the full
   acknowledgment/SMS-fallback reliability matrix during this limited pilot.
6. **Gate 5 — model research:** only after independent labels and formal oversight exist, build
   offline experiments and shadow-mode evaluation. Models still cannot alter alert behavior.
7. **Ship gate:** fresh Claude challenge, Codex review, 100% green verification matrix, founder
   signoff, then a tightly scoped TestFlight. Public release remains blocked on
   legal/privacy/regulatory and evidence review.

## Human dependencies that agents cannot complete

- Apple Developer configuration: associated domains, push entitlement, APNs key, Time Sensitive
  notifications, and TestFlight access. A Critical Alerts entitlement is additionally required if
  reliable Focus override is part of the product promise.
- Cloudflare/Twilio staging credentials, Durable Object migrations, encryption/HMAC secrets,
  callback URL, and consenting allowlisted verification/fallback phone numbers.
- Two or more supported physical TrueDepth iPhones and participating guardians.
- Qualified research/statistics leadership, ethics/IRB determination where applicable, privacy/legal
  review, controlled-study site, reference instruments, and participant recruitment.

## Definition of finished

“Finished” for the next founder build means a real concerning result can notify a linked guardian in
the app, recover through SMS, receive an authenticated acknowledgment, and remain truthful under every
tested failure; the camera/task pipeline has physical-device evidence; and the research system can
collect versioned, consented, quality-audited data without claiming that an unvalidated model works.
It does **not** mean the product is clinically validated or ready to tell anyone they are sober.

## 0.3 execution log

- 2026-08-05: Codex regenerated the project, passed 53 iOS tests, 13 backend tests, the Worker dry
  run, and `git diff --check`, then committed the UI/motion checkpoint as `0ee4e31` without staging
  the finish-out plan.
- 2026-08-05: Claude completed `Docs/CLAUDE_FINISH_REVIEW.md` and blocked the original Sign in with
  Apple + D1 design on shared-token scope, revocation consistency, and notification truthfulness.
- 2026-08-05: Codex revised the API and data-governance contracts to use relationship-scoped ES256
  capabilities and a single relationship Durable Object; added verified distinct-phone fallback,
  pre-APNs alarm persistence, explicit dependency fail directions, safe alert coalescing, visible
  revocation reconciliation, Time Sensitive/Critical Alerts handling, and research-ID exclusion.
- 2026-08-05: Claude authentication became available and the capability contracts received a fresh,
  code-grounded review. Verdict: **ACCEPT WITH REQUIRED CHANGES**. The review preserved the
  one-app/two-role capability architecture but caught contract-versus-code drift, `425` being shown
  as failed, relaunch idempotency, an overly detailed impaired-user status ladder, self-labeled
  baseline and participant-rotation leakage, insufficient subgroup sample gates, and the unsafe
  ordering of live guardian alerts before sober repeatability evidence.
- 2026-08-05: Codex revised the plan so Guardian plumbing stays founder-only until the repeatability
  pilot passes pre-registered thresholds, added the threat model, and kept App Attest wire details as
  a hard non-founder gate. Claude's final verdict was **CONTRACT READY FOR FOUNDER-ONLY GATE 1**.
  Production alert behavior has not changed.
