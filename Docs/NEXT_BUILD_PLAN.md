# Sober 0.4 Next Build Plan

Last updated: 2026-08-05

## Outcome

Turn the current founder prototype into a trustworthy two-device family safety MVP. The next build should make the existing Circle Map reliable, add a consented Night Out session, support person-owned named Places, and replace foreground polling with production-ready push plumbing.

This plan does not attempt to prove that Sober detects intoxication. The app remains an impairment-awareness prototype. A result may report `SIGNALS_DETECTED`, `INCONCLUSIVE`, or `NO_SIGNALS_DETECTED`; none of those states means “safe to drive.”

## What exists now

| Capability | Verified implementation | Current gap |
| --- | --- | --- |
| Circle Map | `Sober/Features/Guardian/CircleMapView.swift:9` renders one freshness- and accuracy-labeled person marker. | No physical-device reliability evidence, delivery diagnostics, or battery measurements. |
| Location capture | `Sober/Services/GuardianLiveLocationService.swift:34` supports foreground updates and a separate Always Location upgrade. | Failures are mostly silent and the app retains no latest-only retry item across relaunch. |
| Location relay | `Sober/App/AppModel.swift:281` publishes signed samples, while the Worker keeps only the newest accepted location for up to 24 hours. | The guardian still polls every five seconds while the map is open. |
| Scheduled checks | `Sober/Features/Guardian/GuardianModels.swift:95` supports daily and away-from-Home rules with person approval. | There is no temporary “I am out tonight” session or automatic session expiry. |
| Concerning-result alert | `Sober/App/AppModel.swift:321` creates a signed Guardian help request for a live `SIGNALS_DETECTED` result. | Delivery is in-app polling only. APNs registration and provider calls are not implemented. |
| Research export | `Sober/Services/ResearchSessionStore.swift` stores versioned, pseudonymous sessions locally. | There is no offline evaluation pipeline, reference-label import, or leakage-safe train/test split. |

Current verification baseline: 83 iOS tests and 19 backend tests at commit `f54bf43`.

## Product rules that must not change

1. The screened person can see, approve, pause, and revoke every location or scheduled-check rule.
2. No stealth tracking, hidden permission prompts, or guardian-controlled Always Location authorization.
3. A missed, late, or inconclusive check is never described as proof of impairment.
4. Only a live `SIGNALS_DETECTED` result can automatically create the existing concerning-result Guardian event.
5. Camera frames, task samples, result scores, Home coordinates, and distance-from-Home values never enter Guardian APIs.
6. Location retention stays latest-only. No route history is added in this build.
7. Existing refusal-on-bad-data paths, three-state result semantics, and no-safe-to-drive language are regression gates.
8. Research models remain offline and shadow-only until a qualified study produces independent labels and human approval.

## Execution order

```text
M0 Location reliability
        |
        v
M1 Night Out session
        |
        +---------> M2 Named Places and place-based rules
        |
        +---------> M3 APNs and notification deep links
                              |
                              v
                    Founder two-phone pilot

M4 Offline validation tooling can run after M1 data contracts are frozen.
```

M0 comes first because Night Out and Places would amplify any stale-location or background-delivery bug. M1 comes before Places because it gives the app one clear, temporary safety loop without turning Sober into an always-on surveillance product. M3 follows the event contracts so push messages can stay small and stable.

## M0: Make Circle Map trustworthy

### User outcome

The guardian can tell whether a location is fresh, delayed, stale, inaccurate, permission-blocked, offline, or simply not shared. The person sees the same truth and can stop collection immediately.

### Agent-owned work

- Add a pure `GuardianLocationPolicy` that classifies freshness, accuracy, authorization, and publication state.
- Use one shared policy in the map, AppModel, and tests instead of scattered time thresholds.
- Add a protected, latest-only pending upload item. A new sample replaces the old one; successful publication deletes it; items older than 24 hours are discarded.
- Record local diagnostic counters only: capture received, rejected for age/accuracy, publish attempted, publish succeeded, and publish failed. Do not record coordinates in diagnostics.
- Add visible states for Location Services off, permission denied, foreground-only, no network, last publish rejected, and backend sharing expired.
- Keep the existing system background indicator visible.

### Initial policy

| Dimension | State |
| --- | --- |
| Freshness | fresh `<= 2 min`, delayed `> 2 and <= 10 min`, stale `> 10 min`, expired `> 24 h` |
| Accuracy | good `<= 50 m`, approximate `> 50 and <= 200 m`, poor `> 200 and <= 1,000 m`, rejected `> 1,000 m` |
| Publication | idle, waitingForLocation, uploading, uploaded, retryPending, blocked |

These are product display thresholds, not safety or impairment thresholds.

### Files

| File | Change |
| --- | --- |
| `Sober/Services/GuardianLocationPolicy.swift` | New pure state classifier and thresholds. |
| `Sober/Services/GuardianLiveLocationService.swift` | Emit structured errors and capture state. |
| `Sober/Services/GuardianPendingLocationStore.swift` | New one-item protected retry store with 24-hour expiry. |
| `Sober/App/AppModel.swift` | Coordinate retry, diagnostics, lifecycle, and truthful UI state. |
| `Sober/Features/Guardian/CircleMapView.swift` | Render the shared policy and recovery actions. |
| `SoberTests/GuardianModeTests.swift` | Add policy, retry, replacement, expiry, and revocation tests. |

### Acceptance criteria

1. Turning sharing off stops Core Location before the network call and prevents every later publish attempt.
2. At most one pending coordinate exists locally, and it is protected, replaced by newer data, and deleted after success, revocation, reset, or 24 hours.
3. A stale point is never labeled live or current.
4. Every authorization and network failure has a distinct, actionable UI state.
5. At least 10 new iOS tests cover threshold boundaries, retry, relaunch, expiry, and stop-sharing races.
6. Existing 83 iOS and 19 backend tests remain green.

### Human gate

Two physical iPhones must complete a 60-minute foreground/background/locked-screen route with timestamps every five minutes. The team records update age, accuracy, battery change, permission state, force-quit behavior, and recovery after network loss. Simulator tests cannot close this gate.

## M1: Add consented Night Out Mode

### User outcome

The person can start a temporary safety session, or accept one proposed by their guardian, with an expected return time. The session can temporarily enable Circle sharing, remind the person to take a Sober check when due and away from Home, and automatically stop its temporary sharing grant when the session ends.

### Product contract

- A person-created session becomes active after an explicit confirmation screen.
- A guardian-created session remains `pendingPersonConsent` until the person accepts it.
- Only one active Night Out session may exist per relationship.
- Duration is 15 minutes to 18 hours. Grace is 0 to 120 minutes.
- Temporary sharing has its own consent version and expiry. It never converts into persistent sharing.
- If persistent Circle sharing was already on, ending Night Out does not turn it off.
- At the expected return time, the app asks the person to open Sober. Away-from-Home evaluation happens on the person’s phone using the existing private Home anchor.
- `SIGNALS_DETECTED` reuses the existing immediate Guardian help event.
- `INCONCLUSIVE` shows ride, call, message, and retry actions. It does not tell the guardian that the person “failed.”
- An overdue session may show “check not completed” after grace. It must not imply intoxication, danger, or deliberate noncompliance.

### Server snapshot

```json
{
  "sessionId": "night_<uuid>",
  "version": 1,
  "state": "pendingPersonConsent | active | ended | cancelled | expired",
  "createdBy": "person | guardian",
  "startsAt": "ISO-8601",
  "expectedEndAt": "ISO-8601",
  "graceMinutes": 15,
  "checkCondition": "always | awayFromHome",
  "temporaryLocationSharing": true,
  "temporarySharingExpiresAt": "ISO-8601 | null",
  "participantConsentVersion": "night-out-participant-v1 | null",
  "endedAt": "ISO-8601 | null"
}
```

No destination address, Home coordinate, location history, camera data, task data, result score, or distance value is stored in this object.

### Signed API changes

| Method and path | Role | Purpose |
| --- | --- | --- |
| `PUT /v1/guardian-relationships/{id}/night-out-sessions/{sessionId}/proposal` | person or guardian | Create an idempotent proposal. Person proposals include participant consent and activate immediately. |
| `PUT /v1/guardian-relationships/{id}/night-out-sessions/{sessionId}/decision` | person | Accept or decline the latest guardian proposal version. |
| `PUT /v1/guardian-relationships/{id}/night-out-sessions/{sessionId}/end` | person | End the session and its temporary sharing grant immediately. |

### Files

| File | Change |
| --- | --- |
| `Sober/Features/Guardian/GuardianModels.swift` | Add session state, snapshot, validation, and evaluation types. |
| `Sober/Services/GuardianAPIClient.swift` | Add signed proposal, decision, and end methods. |
| `Sober/Services/GuardianCheckInServices.swift` | Schedule start/end/check reminders and cancel them safely. |
| `Sober/App/AppModel.swift` | Own session state, lifecycle, relaunch recovery, and result handoff. |
| `Sober/Features/Guardian/NightOutView.swift` | Person and guardian flows with consent and status copy. |
| `Sober/Features/Guardian/GuardianCenterView.swift` | Add the Night Out entry point and current-session card. |
| `Backend/guardian-relationship-core.js` | Validate, authorize, store, expire, and return the current session. |
| `Backend/worker.test.js` | Add role, idempotency, expiry, consent, and revocation coverage. |

### Acceptance criteria

1. A guardian cannot activate, extend, or enable location sharing without the person’s signed decision.
2. Ending or expiring Night Out removes only its temporary sharing grant and clears the visible point if no persistent grant exists.
3. Relaunch reconstructs the active session and schedules no duplicate reminders.
4. Offline end is enforced locally immediately and reconciled with the relay on reconnect.
5. DST changes, time-zone changes, duplicate requests, version races, relationship revocation, and expired proposals have tests.
6. A live `SIGNALS_DETECTED` result creates the existing signed Guardian event once, including after app relaunch.
7. At least 18 new iOS tests and 12 new backend tests cover the complete state machine.

## M2: Add person-owned named Places

### User outcome

The person can rename Home and add places such as School, Work, or a friend’s house. A guardian may propose a check tied to a shared place label, but the person must approve the rule and the exact coordinate stays on the person’s phone.

### Architecture

- `GuardianPlace` stores `id`, `displayName`, coordinate, radius, and enabled state in protected local storage on the person’s device.
- The relay stores only `placeId`, approved display name, latest state (`inside`, `outside`, or `unknown`), observation time, consent version, and rule version.
- The person device evaluates geofences. It never uploads the place coordinate, address, or measured distance.
- Limit active monitored regions to 10 so Sober stays below iOS’s per-app region ceiling and leaves room for system behavior.
- Ambiguous accuracy yields `unknown`, not inside or outside.
- A guardian can propose a place-based reminder only for a place the person deliberately shared.

### Files

| File | Change |
| --- | --- |
| `Sober/Services/GuardianPlaceStore.swift` | Protected local place storage and migration from the current Home anchor. |
| `Sober/Services/GuardianPlaceMonitor.swift` | Region monitoring and accuracy-aware state evaluation. |
| `Sober/Features/Guardian/PlacesView.swift` | Add, rename, disable, delete, and share place labels. |
| `Sober/Features/Guardian/GuardianModels.swift` | Add place and place-rule snapshots. |
| `Sober/Services/GuardianAPIClient.swift` | Add signed place-status and rule endpoints. |
| `Backend/guardian-relationship-core.js` | Store consented label/status only, never coordinates. |
| `SoberTests/GuardianModeTests.swift` | Add migration, radius-boundary, ambiguity, consent, and deletion tests. |
| `Backend/worker.test.js` | Prove extra coordinate/address/distance fields are rejected. |

### Acceptance criteria

1. Home can be renamed without changing the current private-away evaluation behavior.
2. Exact place coordinates, addresses, and distances are absent from every Guardian request and backend state fixture.
3. Deleting or disabling a place stops monitoring and invalidates linked rules.
4. Boundary uncertainty produces `unknown` and no automated “away” conclusion.
5. At least 12 new iOS tests and 10 new backend tests cover storage, migration, consent, role checks, and forbidden fields.

## M3: Replace polling with APNs plumbing

### User outcome

Guardian alerts and relationship changes can reach the linked phone when Sober is not open. The UI still distinguishes provider acceptance from delivery, viewing, and signed guardian acknowledgment.

### Agent-owned work

- Add notification permission education, device-token registration, rotation, deletion, and denied-state handling.
- Implement the signed device-registration contract already documented in `Docs/GUARDIAN_API.md`.
- Add a backend provider interface with a deterministic fake for tests and a real APNs adapter behind environment configuration.
- Send minimal event types only: `guardianAlertChanged`, `relationshipChanged`, `nightOutChanged`, and `checkInChanged`.
- Deep-link into signed reconciliation. Push payloads do not carry results, names, coordinates, addresses, or message copy.
- Keep foreground reconciliation as a fallback. Remove five-second polling only after physical-device push tests pass.

### Files

| File | Change |
| --- | --- |
| `Sober/App/SoberApp.swift` | Register notification delegate and route deep links. |
| `Sober/Services/GuardianPushService.swift` | Permission, token lifecycle, and signed registration. |
| `Sober/Services/GuardianAPIClient.swift` | Add device registration and removal calls. |
| `Backend/guardian-relationship-core.js` | Store role-scoped token metadata and invalidate it on revocation or APNs `410`. |
| `Backend/guardian-push-provider.js` | Fake and APNs provider boundary. |
| `Backend/worker.test.js` | Add token rotation, role, payload, retry, `410`, and revocation tests. |
| `Docs/GUARDIAN_API.md` | Reconcile the written contract with shipped code. |

### Acceptance criteria

1. Push payload tests prove that no name, result, coordinate, address, camera data, or score is present.
2. A token can be registered only by the matching signed role and is deleted on revocation, reset, permission denial, or APNs `410`.
3. APNs acceptance is labeled “sent for delivery,” never delivered, read, or acknowledged.
4. A guardian acknowledgment changes person-facing state only after the backend accepts its signed request.
5. At least 8 new iOS tests and 12 new backend tests cover registration and event handling.

### Human gate

The team must supply an Apple Developer team, push entitlement, APNs key, bundle ID, and provisioning profiles. Two physical phones must prove background receipt, disabled notifications, Focus behavior, token rotation, uninstall/reinstall, revoked relationship, and deep-link recovery. Codex can build and test the code boundary with fakes, but cannot complete live APNs delivery without those credentials.

## M4: Build offline validation tooling

### User outcome

Founders can measure whether the prototype is repeatable and where it abstains before training or shipping any model. Nothing from this milestone changes live screening decisions.

### Agent-owned work

- Define a versioned import format for independent reference measurements and session context.
- Build a local command-line validator under `Analysis/` that checks schema versions, missingness, quality gates, participant leakage, and label timing.
- Split data by participant, never by session.
- Produce repeatability, abstention, missingness, sensitivity/specificity research tables, calibration plots, and subgroup slices with confidence intervals where sample size permits.
- Refuse model training when reference labels are missing, participant IDs overlap across splits, a subgroup is below its pre-registered minimum, or quality exclusions are not frozen.
- If a model is later explored, keep it offline and generate a model card. Do not export Core ML or alter `ScreeningEngine` in this milestone.

### Files

| File | Change |
| --- | --- |
| `Analysis/README.md` | Reproducible local workflow and non-clinical limits. |
| `Analysis/schema/reference-label-v1.json` | Versioned independent-label contract. |
| `Analysis/sober_eval/` | Validation, participant split, metrics, and report modules. |
| `Analysis/tests/` | Frozen fixtures for leakage, missingness, invalid labels, and deterministic reports. |
| `Sober/Models/ResearchModels.swift` | Add export fields only if the locked analysis contract proves they are required. |
| `Docs/RESEARCH_VALIDATION_PROTOCOL.md` | Pre-registered protocol template and human approval gates. |

### Acceptance criteria

1. The same fixture produces byte-stable metric JSON on repeated runs.
2. Participant overlap between train, validation, or test sets fails the run.
3. Missing or temporally invalid reference labels fail closed.
4. Reports separate `SIGNALS_DETECTED`, `INCONCLUSIVE`, and `NO_SIGNALS_DETECTED`; abstentions are never dropped from denominators.
5. No generated model is linked into the iOS target and no live threshold changes.

### Human gate

A qualified research/statistics lead must define the study, reference instrument, label window, sample-size targets, subgroup minimums, and stopping rules. Legal/privacy review and an IRB or ethics determination may be required. Human participants, controlled measurements, and clinical claims are outside agent authority.

## Work I can complete without new access

1. All Swift and Worker implementation described in M0 through M2.
2. APNs client and backend boundaries using fake credentials and deterministic provider tests.
3. Simulator test automation, backend tests, documentation, privacy regression tests, and accessibility checks.
4. The offline validation toolchain and frozen synthetic fixtures.
5. A co-founder review build with founder-only feature flags and visibly labeled sample states.

## Work that needs the founders or outside experts

| Dependency | Why an agent cannot close it |
| --- | --- |
| Two supported physical iPhones | Background Core Location, TrueDepth, notification, battery, and lock-screen behavior are hardware and OS scheduling questions. |
| Apple Developer access | APNs keys, entitlements, signing, provisioning, and TestFlight require account authority. |
| Deployed relay credentials | Cloudflare production configuration, domains, secrets, and provider billing are external state changes. |
| Consent and privacy decisions | Parent/teen power, revocation, retention, and local law need founder and legal ownership. |
| Research oversight and labeled data | Accuracy cannot be trained or validated without independent reference labels, real participants, and a locked study protocol. |
| Product signoff | The founders must approve the exact alert, overdue, and location-sharing copy before non-founder use. |

## Verification matrix

Every milestone must pass:

```bash
xcodegen generate
xcodebuild \
  -project Sober.xcodeproj \
  -scheme Sober \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test

(cd Backend && npm test)
(cd Backend && npx wrangler deploy --dry-run)
git diff --check
```

Manual review must also cover Dynamic Type, VoiceOver labels, Reduce Motion, Reduce Transparency, denied permissions, no network, stale data, relaunch, and relationship revocation.

## Rollback strategy

- Put Night Out, Places, and APNs behind separate founder feature flags.
- Keep current foreground polling until APNs physical-device evidence passes.
- New backend fields must be optional on read so older iOS builds continue to decode relationship state.
- Reverting a milestone must not require retaining or migrating location history because none is introduced.
- If a new consent or location state cannot be reconciled, fail closed: stop collection locally, show status unknown, and require the person to opt in again.

## Deferred from 0.4

- Multi-member family circles and account recovery
- Sign in with Apple and App Attest production rollout
- SMS fallback and phone verification
- Crash detection, driving detection, route history, speed, or trip scoring
- Automatic police, employer, school, or third-party contact
- Hidden guardian controls or guardian-enforced location permission
- Any claim that Sober measures BAC, proves intoxication, or clears someone to drive
- Any trained model that changes live results

## Definition of done

The 0.4 founder build is done when M0 through M3 pass all automated gates, two physical phones complete the location and notification matrices, Night Out expires and revokes temporary sharing correctly, named Places keep exact coordinates off the relay, and concerning-result alerts reach and reconcile on a closed founder test. M4 may ship as an offline tool in parallel, but it cannot change app behavior.
