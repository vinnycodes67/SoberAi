<!-- /autoplan restore point: /Users/vinaypulavarthy/.gstack/projects/vinnycodes67-SoberAi/main-autoplan-restore-20260808-051546.md -->

# Sober App Store Master Plan

Status: implementation-ready planning baseline  
Owner: Founder  
Prepared: 2026-08-08  
Target: first public App Store release  
Planning mode: Codex lead with Claude's three working-tree reviews incorporated

## Executive directive

Sober's first public release should be a local-only safer-ride and private impairment-awareness product. It must not be positioned as a sobriety test, BAC estimator, medical device, safe-to-drive clearance, or proof that can be demanded by another person. Guardian, Circle Map, location, notifications, backend delivery, and research tooling are deferred together to v1.1 or an internal build.

The release is not ready when the screens merely look polished. It is ready when:

1. A person can configure a ride/contact immediately, build a high-quality baseline, complete a check, understand the result, and get home without an account, backend, location, or notifications.
2. Every result is truthful about what was measured, what was unavailable, and what the app cannot conclude.
3. A public user cannot enter founder preview, synthesize baseline readiness, persist sample state, or reach Research/Guardian/Circle functionality.
4. Sensitive data is minimized, local where possible, deletable, and described consistently in product copy, the privacy policy, and App Store privacy answers.
5. Release capabilities match the binary: no location background mode, location usage strings, local-network exception, notification flow, or Guardian endpoint in the public archive.
6. The full release candidate survives automated tests, adverse-state testing, accessibility review, real-device testing, TestFlight, and App Review preparation.

The recommended path is a local-only public v1 with a locked safety core, followed by a separately qualified Guardian v1.1. Do not expand into continuous family surveillance, clinical claims, subscriptions, or research recruitment before the safety core is proven.

## Release definition

### Public v1 promise

> Keep a ride and a trusted contact one tap away tonight. Over your next few sober sessions, Sober learns your steady. Then a short private check can tell you whether it found changes or could not get a reliable reading.

### Public v1 product pillars

| Pillar | User outcome | Release requirement |
| --- | --- | --- |
| Learn your steady | Build a personal comparison range from sober, high-quality sessions. | Five accepted sessions remain a product-development threshold, not a clinical claim. Exclusions and progress are explained. |
| Private check | Complete a short, guided reaction, tracking, timing, and gaze flow. | Refuse to guess when data is incomplete or capture quality is poor. |
| Clear result | See one of exactly three states and the evidence behind it. | `signals detected`, `inconclusive`, or `no signals detected`; never pass, sober, cleared, or safe to drive. |
| Get home | Open a ride provider or contact a trusted person from every result. | Works without Guardian, notifications, background location, or a network-dependent account. |
| History and steady | Review local session summaries and understand accepted/excluded baselines. | No result sharing, result export, verifiable attestation, or composite score. |
| Privacy control | Understand and delete local data. | In-app privacy center, truthful retention copy, camera status, deletion paths, and no backend account. |

### Explicit non-goals for v1

- No BAC estimate, sobriety score, diagnostic label, or safe-to-drive decision.
- No raw camera, audio, or video upload.
- No composite score presented to the user.
- No automatic contact with police, schools, employers, insurers, or parents.
- No hidden tracking, route history, default background location, or guardian-controlled permissions.
- No machine-learning model trained on founder prototype data.
- No research recruitment or human-subject study in the public build without legal, ethics, and consent approval.
- No subscriptions or RevenueCat until a business model, restoration flow, paywall accessibility, and value boundary are approved.
- No Android, watchOS, Critical Alerts, crash detection, or App Clip in the first release.
- No Guardian, Circle Map, check-in notifications, Core Location, Cloudflare production dependency, APNs, SMS, App Attest, or background modes in the public v1 target.
- No share sheet, export, deep link, notification, or authenticated timestamp for an individual result. The app cannot prevent an external camera or screenshot, so result copy must also say it is not evidence for anyone else.

### First-session value rule

Five baseline sessions create a serious activation delay, so the first session must still be useful without inventing a result. Before the starter baseline is ready, a person can:

- configure or skip a ride destination and trusted contact;
- complete one clearly labeled practice/baseline session;
- learn immediately whether the device and environment can support the tasks;
- see why a baseline session was accepted or excluded;
- open ride, call, and message actions from Home at any time.

The public app must not provide a comparison verdict before the required baseline exists. Phase 0 must still challenge whether five sessions is the correct product threshold; changing it requires scientific review, not a growth optimization.

## Premise challenge

### The real problem

The current request sounds like an App Store UI project. The working tree shows that the harder problem is trust under uncertainty: it asks for camera access, still contains location/Guardian code, and can persist a synthetic founder baseline. A beautiful interface that overstates what was compared is more dangerous than an unfinished interface. Public v1 removes the remote/location surface and fixes the baseline truth before visual polish can qualify the build.

### Decisions made

1. **Guardian and Circle move to v1.1 now.** Public v1 has no Guardian route, backend, location, notifications, or conditional launch decision. This gives the privacy policy, App Privacy answers, screenshots, review notes, age rating, support site, and binary one stable scope.
2. **Founder preview is a safety-invariant violation in the public tree.** `completeOnboarding(founderPreview: true)` sets five synthetic sessions, `baselineReady` reports ready, genuine baseline recomputation is suppressed, and delete-all restores the fake value. The scorer correctly falls back to population norms, but the UI falsely claims a personal baseline. Public v1 must make this state unrepresentable and regression-test it.
3. **Public v1 is not the Research build.** Research Center and founder scenario tools move to a separate `SoberInternal` application target with an `INTERNAL_BUILD` Swift condition. They do not appear in the public binary's routes, and sample state never writes to the public baseline store.
4. **No green success semantics.** Orange means attention or primary action. Grey means within range or inactive. Missing data is explicitly unmeasured, not normal.
5. **One canonical visual system.** `Sober/DesignKit` replaces the legacy cyan/serif language across every public screen. Shared components and the screening journey migrate before secondary surfaces so the core route no longer reads new → old → new.
6. **Capabilities follow target scope.** Public Release removes background location modes and both location usage strings. Local networking is Debug-only. `SoberInternal` may carry development-only capabilities explicitly.
7. **Security is layered, not theatrical.** System LocalAuthentication and protected local storage serve v1. Device keys, App Attest, signed requests, rate limits, revocation, and provider controls remain the v1.1 Guardian design. Certificate pinning and a custom pattern lock remain rejected.

## Current-state map

### What is already strong

- Swift 6 and SwiftUI with an iOS 17 deployment target.
- Three-result safety semantics and refusal to score unusable capture.
- Separate consent for biometric processing and retention.
- On-device face and eye landmark processing with no raw-frame persistence in app code.
- Baseline segmentation by protocol variant.
- Safety actions on result screens.
- P-256 signed Guardian requests, nonce/replay handling, Keychain keys, Durable Object coordination, and latest-only Circle location already exist as v1.1 leverage; none belongs in the public v1 route or privacy inventory.
- A canonical matte-black, grey, white, and orange DesignKit used by Home, Result, and Guardian.
- Strong unit coverage for result invariants, Guardian payload minimization, research separation, and capture-quality failures.

### App Store blockers visible in the repository

| Blocker | Evidence | Required resolution |
| --- | --- | --- |
| Founder preview violates baseline truth | `OnboardingView` exposes “Explore founder demo”; `AppModel.completeOnboarding` stores five fake sessions, suppresses later recomputation, and restores them after delete-all. | Remove the boolean API from public code paths; isolate fixtures in `SoberInternal`; require measured eligible sessions for public readiness; add unit and UI regressions. |
| Guardian is still in the public route | Integrated Home routes to Guardian setup after baseline and Release has no backend. | Public v1 removes the route and enables private checks after a measured baseline. Guardian continues only in internal/v1.1 work. |
| UI is split through the core journey | Home and Result use DesignKit, but launch, onboarding, calibration, screening chrome/tasks, and shared components remain cyan/serif. | Migrate shared components → screening → onboarding → launch before History/Settings polish. |
| No compile-time product boundary | `project.yml` defines no `INTERNAL_BUILD`; founder state is a runtime `UserDefaults` boolean. | Add separate `Sober` and `SoberInternal` application targets/configurations, with internal-only sources/routes and a build-boundary test. |
| Background location ships unconditionally | `UIBackgroundModes: [location]` and location usage strings are in the shared app Info configuration. | Remove them from public v1. Add them only to a future Guardian/internal target when the feature is qualified. |
| Local networking ships in Release | `NSAllowsLocalNetworking` is in the shared plist properties. | Move it to a Debug-only Info overlay and assert it is absent from an archived public Release plist. |
| No UI test target | The project contains unit tests but no XCUITest target or snapshot fixtures. | Add deterministic launch arguments, fixtures, UI tests, and visual-regression coverage. |
| No Convex or RevenueCat integration | The current backend is Cloudflare Worker/Durable Objects and no purchase layer exists. | Do not add either by assumption. Introduce only through a separate architecture/business decision. |
| No App Store package | No final metadata, review notes, screenshots, privacy URL, support URL, age-rating decision, or export-compliance record is represented here. | Build and review the complete submission package. |
| Hardware execution is incomplete | The current review reports 87/87 simulator tests, but simulator execution cannot validate TrueDepth. | Freeze the 87-test baseline, then complete real-device camera and external-action evidence. |

### Architecture and ownership map

```text
SwiftUI shell
  SoberApp / RootView
      |
      +-- Onboarding and permissions
      +-- Home and history
      +-- ScreeningFlowView
      |     +-- reaction / tracking / timing / ocular tasks
      |     +-- ScreeningEngine
      |     +-- baseline and research stores
      |     +-- result and safer-ride actions
      |
      +-- History / Your Steady / Settings / Privacy Center

SoberInternal and v1.1-only modules
  +-- founder scenarios and Research Center
  +-- GuardianCenter / CircleMap
        +-- GuardianAPIClient and relationship keys
        +-- Core Location and notifications
        +-- Cloudflare Worker + Durable Object
        +-- APNs/SMS adapters [not production-ready]
```

`AppModel` currently owns too many unrelated state machines. The release work should introduce focused feature stores/services while keeping a single composition root.

## Dream state

Twelve months after launch, Sober should feel like a calm safety instrument:

- A new user understands the boundary in under 30 seconds and gives permissions only when the related action is visible.
- Baseline sessions explain quality in real time and never waste two minutes before announcing a preventable capture problem.
- A check is usable at night, one-handed, with large text, reduced motion, poor connectivity, and VoiceOver.
- A result communicates the verdict in one glance, evidence in one scroll, and a way home in one tap.
- Guardian status is symmetrical: both people see whether sharing is on, what is shared, when it expires, and how to stop it.
- Location sharing is temporary by default, visibly stale when delayed, and never interpreted as danger or impairment.
- The app has no mystery data. Every stored class has a purpose, location, retention limit, and deletion trigger.
- Releases are routine: deterministic builds, automated contracts, snapshot diffs, two-role UI tests, TestFlight canaries, observability, and a rehearsed rollback.

## Strategy alternatives

| Strategy | Description | Benefit | Cost/risk | Decision |
| --- | --- | --- | --- | --- |
| A. Cosmetic Store shell | Polish Home/Result, hide unfinished areas, and keep runtime founder state. | Fastest screenshots. | Leaves the core truthfulness bug and new → old → new journey intact. | Reject. |
| B. Local safety core | Ship ride/contact first, measured baselines, private checks, truthful results, local History/Privacy, and one coherent UI. | One binary, one privacy story, no backend dependency, all critical work controlled by the team. | Defers Guardian differentiation. | **Recommended for v1.** |
| C. Guardian launch | Add production Guardian, Circle, identity, APNs, App Attest, abuse controls, and two-device evidence to v1. | Larger product story at launch. | Forks every submission artifact and puts external infrastructure/hardware on the critical path. | Commit to v1.1 now. |

## Experience principles and design inspiration

The UI should synthesize principles, not copy screens or brand assets.

| Reference | Pattern to borrow | Pattern to avoid |
| --- | --- | --- |
| Supplied Sober concepts | Matte black hierarchy, one orange action, calm result language, compact evidence bars, Home/Steady/History model. | Treating every mock as implemented behavior or using orange decoratively. |
| Apple Health and Fitness | Permission explanations, progressive disclosure, summaries before details, familiar data typography. | Clinical-looking certainty or dense dashboarding. |
| Apple Find My | Explicit sharing state, identity clarity, visible freshness, native map behavior. | Implying continuous precision when location is stale or approximate. |
| Uber ride handoff | One decisive get-home action, immediate destination context, clear external transition. | Making a provider link look like a guaranteed booked ride. |
| Life360-style family safety | Stable member identity, state-at-a-glance, map freshness, battery/permission awareness. | Surveillance defaults, engagement pressure, or location as proof of behavior. |
| Calm and Headspace | Nonjudgmental tone, breathable pacing, quiet transitions. | Decorative wellness gradients or celebration during a safety event. |
| Timed check-in products | One-tap “I'm OK,” visible deadlines, escalating recovery paths, visible history. | Nag loops, ambiguous missed-check interpretations, or hidden escalation. |
| Apple Human Interface Guidelines | Native navigation, point-of-need permission prompts, accessible controls, platform-consistent notifications. | Custom controls that imitate system permission or security UI. |

### Emotional arc

```text
uncertainty
   -> calm orientation
   -> informed consent
   -> focused tasks with live recovery
   -> truthful result
   -> immediate safe action
   -> quiet evidence and history
```

The app should feel protective and precise, never punitive, clinical, playful, or parental.

## Canonical information architecture

### Public navigation

Use a native `TabView` only when its destinations are real. Public v1 targets three complete tabs and never substitutes a deferred feature for an unfinished one.

```text
Home
  - current state
  - primary baseline/check action
  - get-home shortcuts

History
  - sessions
  - filters: baseline/check
  - result and capture-quality summaries
  - Your Steady detail

Settings
  - privacy and data
  - permissions
  - Safety Plan
  - accessibility
  - help/support/legal
  - app version
```

If History is not implemented by release-candidate freeze, do not substitute Circle or expose a dead tab. Keep a two-tab shell or place local session history under Home until the destination is real.

### Internal-only navigation

- Founder result scenarios
- Research Center
- Raw JSON export
- Guardian, Circle Map, check-in, and location flows until v1.1 qualification
- Debug transport diagnostics
- Test fixture selectors

These belong to a separate `SoberInternal` application target compiled with `INTERNAL_BUILD`. A server flag or persisted `UserDefaults` boolean is insufficient because either can fail open and leaves review-only code and state transitions in the public product. Internal sample baselines use an ephemeral fixture store/factory and never write `baselineSessions` or `isFounderPreview` into the public defaults domain.

## Screen-by-screen design plan

### 1. Launch

- Replace the cyan signal halo and typewriter sequence with a static or sub-600 ms matte wordmark reveal.
- Do not delay entry for brand theater; allow immediate tap-through.
- Respect Reduce Motion and VoiceOver without announcing “Loading” after the app is ready.
- Orange may appear once as a brief cursor/accent, not as a glow.

### 2. Onboarding

Four concise steps:

1. **What it does:** a private comparison against personal sober sessions.
2. **What it cannot do:** no BAC, diagnosis, sobriety, or safe-to-drive result.
3. **Your plan:** ride destination and optional trusted contact; name and age only if they serve a released feature.
4. **Consent:** separate on-device biometric processing, optional research retention, and links to privacy details.

Changes:

- Remove “Explore founder demo” and the public `completeOnboarding(founderPreview:)` choice entirely. The public onboarding completion API has no preview boolean.
- Move camera permission to the first calibration attempt, not onboarding.
- Public v1 never asks for notifications or location because it has no feature that needs them.
- Add “Not now” to every optional permission-backed feature.
- Reconsider collecting age at all. Keep it only if age-gating or reviewed safety copy requires it.
- Use DesignKit typography, spacing, controls, and surfaces throughout.

Permission timing is part of the design contract:

| Permission | Ask when | If declined | Never do |
| --- | --- | --- | --- |
| Camera | The person starts the first live calibration after seeing the explanation. | Offer Settings and a truthful inconclusive/safety-action route. | Ask on first launch or imply the app cannot open without it. |
| Notifications (v1.1 only) | The person enables a reminder or Guardian notification in a Guardian-capable target. | Keep local check and manual contact fully available. | Include the prompt, entitlement, or usage story in public v1. |
| Location (v1.1 only) | The person explicitly enables a released Circle/Home feature in a Guardian-capable target. | Keep check and manual contact fully available. | Include Core Location code paths, usage strings, or background modes in public v1. |
| Local Authentication | The person enables Privacy Lock in Settings. | Keep ordinary device-unlocked access and all safety actions. | Use a custom pattern/PIN fallback or block Ride/Call. |

### 3. Home: first run

- Hero: “Learn your steady.”
- Explain why five sessions exist and what causes exclusion.
- Primary action: “Record a baseline session.”
- Show a five-step meter with accepted vs excluded detail.
- No Guardian or Circle card appears in the public target.
- Get-home setup is visible but not mandatory.

### 4. Home: baseline ready

- Primary action becomes “Start check.”
- Secondary row: “Record another sober session.”
- Status card reports the last check without saying “safe.”
- Recent history uses truthful result labels and timestamps.

### 5. Pre-check readiness

- One screen confirms two minutes, good lighting, stable phone position, and no driving during the check.
- If the person self-reports drinking/substance use or concern, skip measurement and go straight to a safety-first result.
- Do not demand a network, location, notifications, or any second person.

### 6. Camera calibration

- Explain camera use immediately before the system prompt.
- Show a clear recording/capture indicator while the camera is active.
- Provide live, singular recovery instructions: face, distance, light, stability, frame rate.
- Never show five simultaneous warnings.
- Provide a “Camera unavailable” path that yields `inconclusive` and preserves ride/contact actions.
- Detect unsupported TrueDepth hardware before entering an impossible flow.

### 6A. Live capture recovery

- Show one dominant correction at a time for poor light, face position, distance, or stability.
- Keep the active camera/capture indicator visible.
- Actions: `Try again`, `Use a brighter place` where actionable, and `End check`.
- Do not show a score, blame language, or several simultaneous warnings.
- If recovery cannot succeed within the bounded calibration window, explain why and move to the truthful inconclusive/safety-action path.

### 7. Tasks

- One instruction, one target, one progress indicator, one exit affordance.
- Use DesignKit black/grey/orange; avoid glow, score, game celebration, and failure sounds.
- Use sensory feedback only to confirm a completed interaction, not quality or correctness.
- Reduced Motion route is explicit and semantically equivalent.
- On interruption, offer `Resume`, `Restart task`, and `End check`; do not silently continue with corrupted timing.

### 7A. Resume after interruption

- State which task was interrupted and that the invalid partial timing was discarded.
- `Restart task` is the primary action when measurement integrity requires it; `Resume` appears only when the task state can be resumed without changing semantics.
- `End check` remains available and leads to an inconclusive result with ride/contact actions.
- VoiceOver focus lands on the interruption explanation, then the primary recovery action.

### 8. Analyzing

- No fake percent progress.
- Use a short indeterminate state with copy such as “Comparing this check with your usual range.”
- If processing exceeds a threshold, show “Still working” and keep `End check` available.
- On internal failure, move to a recoverable inconclusive result; never leave a spinner indefinitely.

### 9. Result

Hierarchy:

1. Verdict and safety boundary.
2. Primary get-home action.
3. Trusted-contact action.
4. Evidence compared with baseline.
5. Limitations and next step.

Rules:

- `signals detected`: orange verdict rule and outside-range ticks; no alarmist red.
- `inconclusive`: neutral state with why capture could not support a conclusion.
- `no signals detected`: neutral state; explicitly says the check cannot determine sobriety or driving safety.
- Never use confetti, green, checkmarks that imply clearance, or a composite numeric score.
- External ride button must say “Open Uber”/“Open Lyft” rather than “Book ride” unless booking is confirmed in app.

### 10. Your Steady

- Explain baseline quality, protocol variants, accepted sessions, and exclusions.
- Show ranges only when sample count is sufficient.
- Show each measure as range + last reading + measurement state.
- Provide “How this works,” “Record another session,” and “Reset baseline.”
- Baseline reset requires confirmation and explains downstream consequences.

### 11. History

- Local-first list of sessions with result, timestamp, mode, and capture quality.
- Detail shows what was measured; no sensitive raw samples.
- Excluded baseline sessions show the exact reason.
- Empty state points to the primary action.
- Deletion supports one session where technically safe and “Delete all data” from Privacy Center.

### 12. Guardian setup

**v1.1 design target. Not present in the public v1 target, screenshots, metadata, privacy answers, or review path.**

- Keep the current canonical visual direction.
- Split `Create invite` and `Join as Guardian` into clear role-first routes rather than two dense cards on one page.
- State what is shared before consent: minimal help request, check-in completion, and separately enabled Circle location.
- Show invite expiry, single-use behavior, copy/share action, and retry.
- Pairing failure preserves the typed code and provides a specific recovery action.

### 13. Guardian connected

**v1.1 design target.**

- Same shell, typography, cards, spacing, and nav as the participant UI.
- Prominent state: connected, paused, revoked, request pending, guardian responding, or expired.
- Symmetric privacy summary visible to both roles.
- Check-in and location are separate modules with separate consent and pause controls.
- A missed check says only “No completion recorded.”
- Revocation is immediate locally, queued for server deletion if offline, and visible until reconciled.

### 14. Circle Map

**v1.1 design target.**

- Native Map with one latest-location marker, accuracy circle, and explicit age.
- States: off, foreground only, background enabled, no permission, no point, delayed, stale, expired, offline, and revoked.
- Temporary sharing is the preferred call to action; persistent sharing is secondary and more explicit.
- Never display “live” unless the defined freshness policy supports it.
- No route trails in v1.

### 15. Settings and Privacy Center

Sections:

- Privacy Lock
- Camera status with a deep link to system settings
- Biometric processing and research retention choices
- History/baseline export and deletion
- Privacy policy, terms, support, safety limitations
- App version/build and acknowledgments

Privacy Lock may use Face ID/Touch ID through `LocalAuthentication` to protect History, Your Steady, and Settings after an inactivity window. It must be optional, must fall back to the device passcode through system UI, and must never block Ride or Call actions during a concerning result.

Public v1 does not expose an individual result share sheet, result export, result deep link, or verifiable timestamp receipt. History remains private and local. The UI states that a result is not evidence for an employer, parent, partner, school, insurer, or authority. iOS screenshots cannot be fully prevented, so the product avoids adding authenticity signals that would make a coerced screenshot more useful.

## Design system completion

### Token rules

- `DSPalette`, `DSFont`, `DSSpace`, `DSRadius`, `DSHit`, and `DSMotion` are the only public UI tokens.
- Deprecate `Palette`, `SoberCard`, legacy glass helpers, serif text, and cyan halo after migration.
- Allow no raw RGB/hex colors in feature views.
- Allow no ad hoc spacing except geometry derived from available space.
- Allow no one-off fonts.
- Use SF Symbols unless a bespoke icon has a reviewed accessibility label and asset license.
- Orange has only two meanings: primary action and measured outside-range/attention state.
- Liquid Glass is navigation/control chrome only on supported OS versions; iOS 17 receives a material fallback.

### Migration order

1. `SoberComponents.swift`, `SignalHalo.swift`, and any shared typography/button/background helpers.
2. Screening chrome, Camera Calibration, reaction/tracking/timing/ocular tasks, live capture recovery, analyzing, and interruption recovery.
3. Onboarding and consent.
4. Launch reveal, capped below 600 ms and implemented as final polish.
5. Safety Plan, History, Your Steady, Settings, Privacy Center, and About.

This order fixes the longest and most safety-sensitive route first. Home → screening → Result must read as one product before secondary surfaces are polished.

### Responsive and accessible requirements

Every public screen must be reviewed at:

- iPhone SE-class width or the smallest supported simulator size.
- 6.1-inch standard device.
- Pro Max width and height.
- Portrait with content-size categories from Large through AX5.
- Bold Text, Increase Contrast, Reduce Motion, Reduce Transparency, Button Shapes, and VoiceOver.
- 200% zoom screenshots for clipped text and control reachability.

Acceptance rules:

- No fixed-height text container for user-facing copy.
- No truncation of verdict, recovery, consent, or permission text.
- All targets are at least 44 x 44 pt; primary targets are at least 56 pt high.
- Color is never the sole state indicator.
- Reading order matches visual order.
- Focus returns to the initiating control after sheets and errors.
- Timed tasks have an accessible alternative that cannot produce `no signals detected` without measurement.

## State coverage matrix

| Surface | Loading | Empty | Partial/stale | Error | Permission denied | Offline | Success/recovery |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Baseline | load local profile | 0 sessions | some excluded | store corrupt/write failed | camera unavailable | fully usable except external links | accepted/excluded with reason |
| Check | prepare services | no baseline | some tasks unmeasured | analysis failure | camera denied | local check continues | truthful result or inconclusive |
| Ride | app lookup | no destination | provider unavailable | URL cannot open | not applicable | provider handles | call/contact fallback |
| History | load local sessions | no sessions | legacy/migrated record | decode failure | not applicable | fully usable | local detail/delete; no result sharing/export |
| Privacy | load local classes | no stored sessions | migration/deletion in progress | local deletion failed | system settings restriction | fully usable | verified local deletion state |

Guardian setup, alert, check-in, and Circle state coverage remains specified in the v1.1 backlog. It does not expand the v1 route, capability, privacy, screenshot, or QA matrices.

## Core feature improvement tracks

### Track A: baseline and measurement integrity

- Delete the public founder-preview transition. Public `baselineReady` derives only from measured, eligible sessions.
- `delete all`, reset, relaunch, and genuine-session recomputation can never restore or preserve a synthetic session count.
- Internal sample scenarios use an ephemeral fixture model and a separate defaults/container namespace.
- Centralize baseline eligibility and quality policy in pure types.
- Explain exclusions at capture time and in history.
- Validate sensor/hardware availability before starting.
- Persist only bounded summaries required for the released user experience.
- Add schema versioning and migrations for local history and baseline records.
- Keep full and Reduced Motion protocols separated.
- Require an independent scientific/clinical review before changing thresholds, weights, or claims.

### Track B: safer-ride intervention

- Make ride/contact actions available without Guardian.
- Validate ride URLs on physical devices with destination encoding.
- Offer Apple Maps/transit or call-contact fallback if a provider is unavailable.
- Never state that a ride was requested, booked, or arrived unless the app receives that confirmation.
- Preserve actions when the result or network state changes.

### Track C: production Guardian

**v1.1. Not on the v1 critical path.**

Must complete before public exposure:

- Production relationship creation with App Attest assessment, abuse limits, and role-bound device keys.
- Expiring single-use invites with idempotent redemption.
- APNs device registration, rotation, deletion, deep linking, and provider-state classification.
- Minimal notification payloads with no result, score, substance, or location.
- Verified SMS fallback only after legal/privacy approval and explicit participant consent.
- Server-side revocation, relationship expiry, data pruning, and provider token deletion.
- Two-device recovery when one device is replaced. For v1.1, re-pairing is acceptable if stated clearly; silent continuity is not.
- Support and abuse paths for mistaken pairing, coercion, harassment, and lost devices.

### Track D: check-ins and temporary sharing

**Post-v1.1 expansion.**

- First ship a simple, person-approved daily check-in.
- Add Night Out only after location freshness and APNs are proven.
- Prefer temporary location grants with explicit expiry.
- Rate-limit guardian prompts and expose prompt history to both roles.
- Never map overdue/missed/declined to impairment or danger.

### Track E: privacy and data lifecycle

- Publish a data dictionary matching code, privacy policy, and App Store answers.
- Freeze a v1 dictionary containing only on-device measurement/history/preferences and any explicitly approved crash/support data. Guardian/provider/location/research classes are absent from the v1 questionnaire because their features and capabilities are absent from the public target.
- Make local deletion verifiable and prevent reset/delete paths from recreating founder sample state.
- Purge generated internal research exports after share completion, cancellation, expiry, reset, or app relaunch cleanup; public v1 has no result export.
- Add app-switcher privacy shielding for protected screens without obscuring ride/contact actions.
- Prohibit sensitive values in analytics, crash reports, logs, and support attachments. Do not provide app-generated result sharing, export, or authenticated result receipts.

## Security and privacy architecture

### Trust boundaries

```text
person interaction
   |
   v
public v1 iOS UI -- camera permission at point of need
   |
   +-- bounded in-memory samples
   +-- local protected baseline/history/preferences
   +-- optional system LocalAuthentication privacy lock
   +-- external ride/call handoff

v1.1 trust boundary, compiled out of public v1
   +-- signed Guardian API request
   +-- Cloudflare relationship object
   +-- APNs / optional verified SMS / optional location
```

### Required controls

| Layer | Control | Rule |
| --- | --- | --- |
| Local access | Optional LocalAuthentication privacy lock | Protect sensitive history, not emergency ride/contact actions. |
| Local persistence | Protected files/defaults with versioned migrations and explicit deletion | Synthetic internal fixtures never share the public container or defaults domain. |
| Build boundary | Separate application targets and `INTERNAL_BUILD` source/route guards | Public Release cannot construct founder, Research, Guardian, Circle, or location flows. |
| Capability boundary | Public Release plist/capability inspection in CI | No `UIBackgroundModes`, location usage strings, local-network exception, or Guardian URL in the public archive. |
| Result coercion | No share/export/deep link/verifiable receipt | Product does not turn a private result into portable proof. |
| Device identity (v1.1) | P-256 key in Keychain; Secure Enclave when verified compatible | Private key never leaves device. This-device-only protection is preferred. |
| Request/API/auth controls (v1.1) | Canonical signatures, schema validation, App Attest risk, role capability, rate limits, idempotency, revocation | All remain mandatory before Guardian returns to a public target. |
| Transport | ATS for public v1; TLS/HTTPS for v1.1 services | Local HTTP/local-network exception is Debug/internal only. |
| Logging | Structured allowlist | No measurements, result state, names, destinations, or other sensitive values. |
| Secrets (v1.1) | Environment-scoped provider keys and rotation | Staging and production never share APNs, SMS, signing, or encryption secrets. |
| Supply chain | Locked dependencies, license inventory, secret scan, provenance | Build fails on unexpected binary or secret changes. |

### Threat-led decisions

- Do not add custom certificate pinning by default. It introduces certificate-rotation and outage risk; use ATS/TLS, server authenticity, signed request semantics, and a rehearsed key-rotation plan. Revisit only if a specific high-risk threat justifies it.
- Do not add a drawn pattern lock. It is weaker and less accessible than system LocalAuthentication and creates a recovery secret the app must store.
- Do not claim Secure Enclave storage unless the exact key type and access-control flags are verified on supported hardware.
- Do not treat App Attest as perfect identity. Handle unsupported devices, attest service outages, key rotation, and risk scoring.
- Do not include sensitive content in push notifications. The notification should say a person requested help and require an authenticated/open app for details.

### Data classification and retention

| Data class | Location | Purpose | Retention target | Delete trigger |
| --- | --- | --- | --- | --- |
| Raw camera frames | memory only | face/eye landmark processing | never persisted by app code | frame consumed/session ends |
| Task samples | bounded memory/local protected file only when required | compute session summary | shortest technically necessary | summary generated/reset |
| Baseline summary | on device | personal comparison | until reset/delete | user reset/delete app |
| History summary | on device | user review | user controlled; define default before launch | per-session/all-data delete |
| Internal fixture/research data | `SoberInternal` container only | labeled development/research tooling | internal protocol only | internal reset/retention expiry |

Guardian relationships, Home, Circle points, APNs tokens, verified phone numbers, and alert state are v1.1 data classes. They must be absent from the public v1 binary's collected-data paths and App Privacy inventory, not merely unused at runtime.

## Target technical architecture

### Client state

Move from one broad `AppModel` to a composition root with focused stores:

```text
AppModel / AppContainer
  +-- OnboardingStore
  +-- BaselineStore
  +-- ScreeningSessionStore
  +-- HistoryStore
  +-- SafetyPlanStore
  +-- PermissionStore
  +-- PrivacyStore

SoberInternal / v1.1 extension
  +-- GuardianStore
  +-- ResearchStore
```

Rules:

- Each store owns one state machine and its error vocabulary.
- Views receive state and intents, not networking or persistence details.
- Services expose protocols for deterministic tests.
- Date, UUID, camera capability, persistence, and external URL opening are injectable. Network/location/notification adapters remain internal/v1.1-only.
- App lifecycle reconciliation is centralized and idempotent.
- Avoid a large rewrite. Extract stores feature-by-feature behind current behavior.

### Backend topology (v1.1 only)

```text
iOS
  |
  +-- GET /healthz and version handshake
  +-- signed /v1/guardian-relationships/*
             |
             v
     Cloudflare Worker router
             |
             +-- validation / rate limit / App Attest adapter
             +-- relationship Durable Object
             |      +-- consent + role devices
             |      +-- current plan + latest point
             |      +-- canonical alert + alarms
             |
             +-- APNs adapter
             +-- SMS adapter [feature flagged]
             +-- allowlisted metrics/log sink
```

### Environment model

| Environment | App ID | Backend | APNs | Data | Access |
| --- | --- | --- | --- | --- | --- |
| Local | `Sober` Debug / `SoberInternal` | none for public flow; Wrangler for internal Guardian | mock | disposable | developers |
| Staging | internal/staging bundle | staging Worker for v1.1 development only | sandbox | synthetic/internal only | team |
| Production v1 | App Store bundle | **none** | **none** | local app data only | public |
| Production v1.1 | future Guardian-capable bundle/version | production Worker | production | approved real-user classes | public after separate gate |

No environment may share secrets, Durable Object namespaces, provider accounts, or analytics projects.

## Reliability and operations

### Service-level objectives for launch

- Local check completion: 99.5% of supported-device sessions that begin with granted camera access reach a result or explicit recoverable inconclusive state.
- Crash-free sessions: at least 99.5% during external TestFlight before submission.

Guardian API, provider, and location SLOs are v1.1 gates and do not block the v1 release.

These are engineering gates, not claims to users.

### Observability

Allowlisted metrics only:

- check started/completed/inconclusive by broad technical reason
- camera authorization and unsupported-hardware counts
- local persistence failure class
- app version, OS major version, device capability class

Never record task measurements, result state, scores, destinations, names, free-form errors, or sensitive user text. Guardian/provider/location metrics remain absent until a separately reviewed v1.1 telemetry inventory exists.

### Incident readiness

- On-call contact and severity definitions.
- Release kill switch only for any approved telemetry/crash provider; the local check cannot depend on remote feature flags.
- Privacy-incident workflow with data-class mapping.
- Support and rollback runbooks for corrupted local data, camera failures, and unsafe copy. Guardian/provider/key-rotation runbooks live in the v1.1 track.

## App Store compliance workstream

Apple requires privacy answers for data collected by the app and third-party partners, a privacy policy in metadata and within the app, accurate permission behavior, an age rating, and complete review information. Camera capture must have explicit consent and visible indication. Notifications must not be required for unrelated core functionality or expose sensitive information. If the app creates accounts, in-app account deletion is required.

Primary references:

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [App Review information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/)
- [Age ratings](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)
- [Screenshots and previews](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots)
- [Account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/)

### Submission package

- Final app name, subtitle, category, keywords, description, promotional text, copyright.
- Privacy policy URL, support URL, terms, and safety limitations page.
- Accurate App Privacy questionnaire for the public v1 binary. It must not list or rely on Cloudflare, APNs, SMS, location, or Guardian because those code paths and capabilities are absent; any crash/analytics provider is included only after its payload is audited.
- Age-rating questionnaire and first-market audience decision.
- Export-compliance review for the cryptography actually present in the public target.
- Medical/health claim and regulated-device determination by qualified counsel.
- Category decision with qualified review of Lifestyle/Utilities versus Health & Fitness; do not default to Health & Fitness merely because the prototype plist currently does.
- Review notes explaining TrueDepth needs, baseline ramp, three-state semantics, camera-only permissions, and the labeled example-results education screen.
- A public “How results work” education screen may show clearly labeled, static examples of all three result states. It never changes baseline readiness, persists a sample session, or enters the screening scorer.
- Screenshots for every required device class using approved, non-misleading states.
- App preview only if it clarifies the two-minute flow without implying diagnostic accuracy.
- Accessibility Nutrition Label answers backed by actual testing.
- Version, build, signing, capabilities, privacy manifests, required-reason APIs, dependency licenses, and acknowledgments.

### Claims matrix

| Avoid | Approved direction |
| --- | --- |
| “Detect intoxication” | “Looks for changes from your personal baseline.” |
| “Know if you're sober” | “Understand whether this check found changes or could not get a reliable reading.” |
| “Safe to drive” | “A result cannot tell you whether it is safe to drive.” |
| “Show/share your result” | No result share sheet or export. “This result is private context for you. It is not evidence for anyone else.” |
| A verified result time/date or authenticity receipt | Ordinary local History for the user, without a portable attestation or verification surface. |
| “Prove you're okay” | “No Sober result can prove sobriety, impairment, honesty, or fitness to drive.” |

Guardian/location/notification claims remain in the v1.1 copy matrix, not the public v1 submission package.

## QA and test strategy

### Test pyramid

```text
                       TestFlight field sessions
                    / physical TrueDepth journeys \
                XCUITest + visual snapshot regression
             integration: services, storage, lifecycle
          target boundary + plist/archive inspection
       unit: policies, state machines, scoring, migrations
    static: Swift 6, warnings, lint, secrets, privacy manifests
```

### Automated suites

1. **Safety invariants:** no safe/pass language, unmeasured never normal, self-report override, bad capture becomes inconclusive, no portable result proof.
2. **Baseline truth:** variant separation, exclusion reasons, migrations, deletion, corrupted-store recovery, readiness false with zero measured eligible sessions, genuine sessions always recompute, and reset/delete never synthesize five sessions.
3. **Screening:** interruptions, timeouts, permission denial, unsupported hardware, slow analysis, background/foreground transitions.
4. **Build boundary:** public archive has no founder/Research/Guardian/Circle routes or symbols intended for navigation, no `INTERNAL_BUILD`, no runtime preview toggle, and no internal defaults/container access.
5. **Capability boundary:** archived public Info.plist has no location background mode, location usage descriptions, local-network allowance, notification capability, or Guardian URL; Debug/internal builds retain only explicitly needed development settings.
6. **Privacy:** forbidden-field logs, local delete/reset, generated internal-export cleanup, app-switcher shielding, and no result share/export/deep link.
7. **UI:** onboarding, measured baseline progress, all three static education examples, live result paths, capture recovery, interruption recovery, Dynamic Type, and public-route exclusion.

Guardian contract/provider/location suites remain green as internal v1.1 regression tests, but they are not public v1 release features or field gates.

### Manual device matrix

| Dimension | Required cases |
| --- | --- |
| Hardware | smallest supported iPhone, current standard iPhone, current Pro/TrueDepth device, one older supported device |
| OS | iOS 17 latest patch, current public iOS, release candidate if submission overlaps a major launch |
| Appearance/accessibility | Large through AX5, VoiceOver, Reduce Motion, Reduce Transparency, Increase Contrast, Bold Text |
| Permissions | camera allow/deny/revoke; confirm no notification or location prompt exists |
| Network | offline at launch and throughout the local flow; external ride app unavailable |
| Lifecycle | cold start, warm start, background, locked screen, interruption, low memory, force quit, reinstall, update |
| External actions | Uber/Lyft installed/not installed, Maps fallback, tel/sms cancellation, malformed destination |

### Release evidence

Every gate stores:

- build number and commit
- device/OS
- test case and outcome
- screenshot or video for UI/device behavior
- linked defect and retest evidence
- reviewer and date

## Error and rescue registry

| Failure | User-facing truth | Immediate rescue | Persistence/retry | Owner |
| --- | --- | --- | --- | --- |
| Camera denied | “Camera access is off.” | Open Settings; continue to inconclusive safety actions | no auto-prompt loop | iOS |
| Unsupported face tracking | “This camera cannot complete the gaze step.” | accessible/inconclusive route | capability cached | iOS |
| Poor light/position | one specific live instruction | retry calibration or end check | none | iOS/design |
| Task interrupted | “This task was interrupted.” | resume/restart/end | discard invalid timing | iOS |
| Analysis timeout | “We couldn't finish this comparison.” | inconclusive result + retry | log class only | iOS |
| Local store corrupt | “Some saved history could not be loaded.” | quarantine/reset/export support | never silently erase baseline | iOS |
| No ride app | “That ride app isn't available.” | Maps/call/contact | none | iOS |
| Synthetic founder state found in public defaults | “Your steady is not ready” | rebuild from eligible measured sessions or reset safely | never preserve/restore fake count | iOS |
| Local delete fails | “Some data could not be deleted.” | retry with exact class; support path | do not report success or recreate samples | iOS |

## Failure-mode registry

| Mode | Prevention | Detection | Fail direction |
| --- | --- | --- | --- |
| Measurement missing appears normal | typed measurement states | invariant tests and snapshot states | inconclusive/unmeasured |
| Founder demo says personal steady is ready while scorer uses population norms | separate internal target and measured-readiness policy | zero-session, recomputation, delete/reset, public-route unit/UI tests | baseline not ready; build fails on public exposure |
| Public build exposes founder tools | compile-time target separation | binary/UI route tests | build fails |
| Public archive carries deferred capabilities | target-specific plists/capabilities | archive Info.plist and entitlement assertions | build fails |
| Sensitive telemetry leak | allowlist encoder | forbidden-field tests and log inspection | drop event |
| Result becomes coerced proof | no app share/export/attestation plus explicit copy | route/action tests and copy audit | keep result local and non-verifiable |
| Migration corrupts baseline | versioned copy/migrate/verify | fixture tests | retain original, show recovery |
| App Review cannot test camera | public static “How results work” examples, separate from scorer/baseline | clean-install review rehearsal | education examples without synthetic state |

## Implementation roadmap

### Phase 0 — release contract and branch hygiene (2–3 days)

Goal: freeze what the public app is and protect the current uncommitted audit work.

- Review and commit the existing code-review fixes as a dedicated change set.
- Freeze the verified 87/87 simulator-test baseline and record the exact commit/build environment.
- Create separate `Sober` and `SoberInternal` application targets; only the latter defines `INTERNAL_BUILD` and includes founder/Research/Guardian/Circle routes.
- Remove the public founder-preview transition and make measured eligible sessions the only public readiness source.
- Remove Guardian/Circle routes and the dead Release backend configuration from public v1.
- Remove `UIBackgroundModes`, both location usage descriptions, and any notification capability from public v1. Move `NSAllowsLocalNetworking` to a Debug/internal-only plist overlay.
- Approve the get-home-first v1 promise, forbidden claims, and local-only data dictionary. Guardian is already cut to v1.1.
- Choose the first-market audience and legal/regulatory reviewer.
- Create a release board with the P0/P1/P2 tasks below.
- Capture a known-good unit/backend/build baseline.

Exit gate: clean builds/tests plus archive inspection prove exactly what the public binary contains and cannot reach.

### Phase 1 — one coherent product (1.5–2 weeks)

Goal: finish the public information architecture and visual migration.

- Make the post-baseline primary action start the private check directly; no Guardian card or route exists in public v1.
- Migrate shared components and typography first, then the complete screening journey, then onboarding, then the sub-600 ms launch reveal.
- Add the specified live low-light/position recovery and task-interruption recovery screens.
- Implement History, Your Steady, Settings, Privacy Center, and final Home/History/Settings navigation.
- Add the static “How results work” examples without persisting samples or changing readiness.
- Remove public founder, Research, Guardian, Circle, location, and notification routes.
- Add all loading, empty, partial, error, denied, offline, and recovery states.
- Complete Dynamic Type, VoiceOver, Reduce Motion, and small-device review.
- Align app icon, screenshots, wordmark, and accent with the canonical orange system.

Exit gate: every public screen is reachable, canonical, accessible, and screenshot-ready with fixtures.

### Phase 2 — local safety, privacy, and integrity (1–2 weeks)

Goal: make baseline truth, local persistence, deletion, result privacy, and capability scope safe for public users.

- Extract `BaselineStore`, `PermissionStore`, and `PrivacyStore` first from `AppModel` behind injected protocols.
- Version and migrate baseline/history records; quarantine failed migrations rather than erasing them.
- Implement truthful local deletion and prove reset/delete cannot recreate sample state.
- Add optional LocalAuthentication Privacy Lock without blocking ride/call actions.
- Remove result share/export/deep-link/authenticated-receipt surfaces and add coercion-resistant copy.
- Audit crash/support telemetry payloads or ship without a telemetry provider.
- Add build-time/archive assertions for public routes, compile conditions, Info.plist keys, entitlements, and URL configuration.

Exit gate: synthetic readiness is unrepresentable in public code paths, local deletion is truthful, deferred capabilities are absent from the archive, and every safety invariant has a regression test.

### Phase 3 — automation and release operations (1–2 weeks, overlaps Phase 2)

Goal: convert safety rules into release gates.

- Add XCUITest target, deterministic fixtures, launch arguments, and deep-link helpers.
- Add snapshot tests across device sizes and accessibility settings.
- Keep the existing Worker tests green as v1.1 preservation, but remove backend/provider contracts from the v1 release gate.
- Add CI jobs for public/internal Debug/Release builds, unit tests, UI smoke, snapshots, archive capability inspection, secret scan, license check, privacy-manifest checks, and `git diff --check`.
- Add crash-reporting privacy review, local-data recovery runbooks, and release rollback rehearsal.

Exit gate: a release candidate can be rebuilt and verified without local tribal knowledge.

### Phase 4 — internal and external TestFlight (2 weeks minimum)

Goal: prove the experience on real hardware and with real interruptions.

- Internal dogfood every core flow and permission matrix.
- Run accessibility and low-connectivity sessions.
- Expand to a small consented external TestFlight group after privacy/legal approval.
- Triage crashes, hangs, abandonment, inconclusive reasons, and support confusion.

Exit gate: zero open P0, no high-risk P1, crash-free target achieved, and every manual launch gate has retained evidence.

### Phase 5 — App Store package and review rehearsal (3–5 days)

Goal: submit an internally consistent binary and story.

- Finalize metadata, screenshots, support/privacy URLs, age rating, export compliance, category, accessibility labels, and privacy answers.
- Reconcile every App Store answer against the archived public binary and inspected Info.plist/entitlements.
- Run the review path on a clean device from first-session get-home value through baseline education, static example results, and local deletion.
- Write precise review notes with TrueDepth limitations, baseline ramp, and static example states.
- Archive, validate, upload, and complete TestFlight processing checks.

Exit gate: founder, engineering, design, privacy/legal, and QA sign the same release checklist.

### Phase 6 — phased release and canary (7–14 days)

Goal: protect users while learning from the first public build.

- Use staged TestFlight cohorts for the first App Store version; Apple's native
  seven-day phased release applies only to later version updates.
- Monitor crash-free sessions, local check completion, baseline exclusions, inconclusive technical reasons, and support issues without collecting measurements/results.
- Pause rollout on any baseline-truth, privacy, data-loss, coercive-copy, or unsafe-result incident.
- Conduct a 7-day and 30-day review before expanding features.

Exit gate: the production canary report says `CONTINUE`, both reviews are
approved, and the final release-readiness command ties every signoff and
artifact to the same version, build, commit, and archived public app.

### v1.1 — Guardian qualification program (starts after v1 stability review)

Guardian is a separate release program, not a dormant v1 launch fork. It may begin implementation in parallel only in isolated internal files/worktrees and cannot change the v1 binary, privacy answers, capabilities, screenshots, or timeline.

Its gates remain:

- production identity/abuse controls and App Attest risk assessment;
- APNs registration, rotation, deep links, ambiguity-safe provider state, and consented fallback decision;
- relationship recovery, revocation, deletion, retention, logs, and incident response;
- Circle freshness, latest-only retry, permissions, background behavior, battery, and coercion review;
- two-device physical pilot and a fresh App Privacy/metadata/age-rating/review-notes package.

## Codex and Claude execution split

The split is by deliverable and file ownership, not by vague “frontend/backend” labels. Only one agent owns a file in a workstream at a time.

### Codex lane A — architecture and implementation

Owns:

- `project.yml`, Xcode target/configuration wiring, Info.plist generation
- `Sober/App`
- feature stores and service protocols
- `Sober/Services`
- `Backend`
- `SoberTests` and future `SoberUITests`
- build scripts, CI, contract fixtures, environment configuration

Deliverables:

- separate public/internal targets and fixture containers
- deletion of the public founder-preview state transition
- measured-only baseline readiness and regression coverage
- public archive capability/plist assertions
- focused stores extracted from `AppModel`
- local deletion, migration, Privacy Lock, and result non-sharing
- tests, builds, canaries, and release automation

### Claude lane B — screen specifications and content system

Owns during its worktree/branch:

- a screen-spec package under `Design/AppStoreV1/`
- `Docs/UX_COPY_MATRIX.md`
- `Docs/APP_STORE_METADATA_DRAFT.md`
- design-review annotations and screenshot storyboards

Deliverables:

- every screen in the public route map at compact/standard/AX5 sizes
- state variants from the coverage matrix
- exact safety, consent, camera permission, coercion, and recovery copy
- interaction and transition notes using existing DesignKit tokens
- screenshot sequence and App Review walkthrough

Claude does not change Swift implementation in this lane. That prevents visual work from silently changing measurement or Guardian behavior.

### Claude lane C — adversarial review

Read-only inputs:

- this plan
- `README.md`, `DESIGN.md`
- Guardian threat, API, and data-governance documents
- public screen specs and copy matrix
- current diff

Deliverables:

- product-premise challenge
- coercion, surveillance, consent, and safety-copy findings
- App Review rejection risks
- missing states and contradiction list
- prioritized P0/P1/P2 review report

### Joint gates

| Gate | Codex provides | Claude provides | Founder decides |
| --- | --- | --- | --- |
| Product freeze | architecture/cost/schedule | user story/copy/state critique | public v1 scope |
| Design freeze | implemented prototypes and accessibility evidence | complete screen/state specification | final visual direction |
| Public target boundary | archive/plist/route evidence | contradiction and coercion review | accept v1 binary scope |
| Submission freeze | clean build/tests/privacy data inventory | metadata/review narrative contradiction check | submit |

### Handoff contract

Every handoff includes:

- commit SHA and branch/worktree
- files owned and files untouched
- assumptions and unresolved questions
- acceptance criteria and test evidence
- screenshots for visual changes
- schema/copy version when behavior or consent changes

No agent edits another lane's owned files until the handoff is accepted or ownership is explicitly transferred.

## Cross-model review record

The three prepared Claude reviews were executed against the actual working tree and are recorded in `Docs/CLAUDE_MASTER_PLAN_REVIEW.md`. This revision accepts their core changes:

1. founder preview is a P0 baseline-truth violation, not UI hygiene;
2. Guardian/Circle/location/notifications/backend move to v1.1 now;
3. the public promise leads with immediate get-home value;
4. results are not shareable/exportable attestations;
5. DesignKit migration begins with shared components and the complete screening journey;
6. public Release capabilities and plist keys are inspected as testable artifacts.

## Dependency graph and parallel work

```text
release promise + claims + data dictionary
          |
          +--> public/internal target split + founder-state removal
          |          |
          |          +--> baseline regressions + archive capability assertions
          |          +--> shared UI --> screening --> onboarding --> launch
          |                                      |
          |                                      +--> UI tests/snapshots --> screenshots
          |
          +--> privacy/legal package --> App Privacy + policy + review notes
          |
          +--> QA infrastructure --> TestFlight evidence --> submission
```

Parallelize only after contracts are frozen:

- UI screen specs and local store/test work can proceed in parallel after the target boundary lands.
- Guardian backend/provider work may continue only as isolated v1.1/internal work with no v1 dependency.
- Metadata can begin early but freezes only after binary/data inventory freeze.
- Screenshots begin only after visual, copy, and public-route freeze.

## Prioritized task backlog

### P0 — blockers

1. Preserve and land the current audited changes with the verified 87/87 simulator-test baseline, Release build, and backend preservation tests.
2. Freeze the get-home-first v1 promise, claims, first-market audience, local-only data dictionary, and Guardian v1.1 decision.
3. Add `Sober`/`SoberInternal` targets and prove founder/Research/Guardian/Circle routes and state are absent from the public archive.
4. Remove the public founder-demo API/state path; public readiness requires measured eligible sessions, and reset/delete/recompute cannot synthesize five.
5. Make the post-baseline Home action start a private check directly; remove Guardian/Circle from public navigation.
6. Remove public location background mode/usage strings and notification capabilities; make local networking Debug/internal-only; add archive assertions.
7. Complete real-device TrueDepth screening and all three result paths.
8. Complete privacy policy, Privacy Center, App Privacy answers, age rating, category/claims, support URL, and legal/regulatory review for the local-only binary.
9. Add static “How results work” education examples and a clean-device review walkthrough without synthetic baseline state.
10. Add XCUITest smoke coverage for onboarding, measured baseline, check, results, capture/interruption recovery, Settings, deletion, and public-route exclusion.

### P1 — should-fix before submission

1. Migrate shared components → screening journey → onboarding → launch, then remaining public screens; remove legacy cyan/serif/glass dependencies.
2. Implement History, Your Steady, Settings, permissions dashboard, and stable tab navigation.
3. Add every state in the coverage matrix.
4. Extract focused stores from `AppModel` behind protocols.
5. Add local schema migrations, corruption recovery, and deletion states.
6. Add result non-sharing/coercion checks and explicit “not evidence for anyone else” copy.
7. Add snapshot regression, public archive/plist assertions, privacy forbidden-field tests, and release CI.
8. Validate external ride/contact links and fallbacks on real devices.
9. Complete accessibility testing and Nutrition Label evidence.
10. Add privacy-reviewed crash metrics if justified, local recovery/incident runbooks, and rollback rehearsal.

### P2 — after first stable release

1. Guardian v1.1 production qualification: identity, APNs, App Attest, abuse controls, revocation, retention, deletion, and two-device evidence.
2. Circle Map and temporary sharing only after freshness, battery, permission, and coercion gates.
3. Temporary Night Out sessions and named Places evaluated on device.
4. Multi-member circles and account-backed recovery only if demand justifies the added lifecycle.
5. Study-grade research tooling and model validation under approved protocol.
6. Watch complications, widgets, App Clips, or Critical Alerts only after evidence and entitlement review.
7. Monetization and RevenueCat only after a non-coercive free safety core is defined.

## Deployment and rollback

### Client release

```text
main
  -> signed Release build
  -> CI + privacy/static/contract tests
  -> internal TestFlight
  -> external TestFlight
  -> App Store review
  -> phased release
  -> full rollout
```

### Backend release (v1.1 only)

```text
backward-compatible schema/API
  -> staging Worker
  -> synthetic signed canary
  -> provider sandbox test
  -> production deploy with feature flags off
  -> canary relationship
  -> gradual flag enable
```

### Rollback rule

- Public v1 rollback is client/local-data only. A rollback or hotfix cannot recreate founder preview, fake baseline readiness, deleted sessions, or legacy schema corruption.
- The public app does not depend on a remote feature flag or backend to start, complete, or interpret a local check.
- Any incident involving false baseline readiness, missing measurement shown as normal, portable/coercive proof, leaked data, or destructive migration pauses rollout immediately.
- Backend compatibility, revocation, provider, and server rollback rules remain mandatory for the separate v1.1 Guardian program.

## Launch scorecard

Ship only when all are true:

- [ ] Public archive contains no founder/Research/Guardian/Circle/debug routes, runtime preview toggle, or internal fixture container access.
- [ ] Public baseline readiness is false without measured eligible sessions; genuine recomputation works; reset/delete never restores five synthetic sessions.
- [ ] Private checks work offline after a measured baseline and route directly from Home.
- [ ] Archived Release plist/entitlements contain no background location mode, location usage strings, notification capability, Guardian URL, or local-network exception.
- [ ] No unresolved P0 safety, privacy, security, crash, data-loss, or App Review issue.
- [ ] At least the frozen 87 Swift tests, internal backend preservation tests, UI smoke, snapshots, public-target boundary checks, and Release builds pass.
- [ ] Real-device TrueDepth paths pass on supported hardware.
- [ ] VoiceOver, AX5, Reduce Motion, Reduce Transparency, and small-device reviews pass.
- [ ] Privacy policy, local-only App Privacy answers, in-app copy, logs, and archived capabilities agree.
- [ ] Legal/regulatory review approves claims, category, age audience, consent, and retention.
- [ ] Review notes and static example-result education work on a clean device without changing baseline state.
- [ ] No result share/export/deep-link/attestation surface exists; coercion-resistant copy is approved.
- [ ] Support, incident response, local recovery, and rollback owners are named.

## Decision audit trail

| Decision | Basis | Revisit trigger |
| --- | --- | --- |
| Local safety core for v1; Guardian v1.1 | A conditional Guardian cutline forks every App Store artifact and adds external dependencies to the critical path. | Revisit only as a separately qualified v1.1 release. |
| Founder preview reclassified as P0 safety bug | UI claims a personal baseline while scorer uses population norms and genuine recomputation is suppressed. | Never permit synthetic state in the public baseline store. |
| Separate `Sober` and `SoberInternal` targets | A runtime defaults flag can fail open and already mutates persistent truth. | Approved internal tooling architecture with equivalent compile-time isolation. |
| Deferred capabilities absent, not disabled | Unused location/background/local-network declarations create review and privacy contradictions. | Add only with a released feature and a fresh review package. |
| Get-home-first promise | First download cannot honestly deliver a comparison before five accepted baselines. | Scientific approval of a different baseline requirement. |
| No portable result proof | Results can be coerced by parents, partners, or employers and misread as clearance. | No revisit without a defensible anti-coercion model and legal/safety approval. |
| DesignKit as sole public system | Current repo explicitly marks legacy surfaces as transitional. | Formal redesign with token migration plan. |
| Shared components and screening migrate first | Current journey reads new → old → new through the longest safety-critical route. | Core journey reaches visual parity. |
| No green/pass/composite score | Product safety invariant and claims boundary. | Only validated evidence plus legal/regulatory approval; still never safe-to-drive. |
| System biometric lock over pattern lock | Accessibility, platform security, recovery, lower secret surface. | New platform capability or concrete threat. |
| No certificate pinning by default | Rotation/outage risk exceeds current threat reduction. | Specific high-risk environment and operational capacity. |
| App Attest as layered v1.1 signal | Service and device limitations prevent sole reliance. | Production Guardian abuse evidence. |
| Re-pairing acceptable recovery for v1.1 | Avoids premature account and deletion complexity. | Material support burden or multi-device demand. |
| Night Out/Places after v1.1 | They depend on qualified location/APNs behavior and expand surveillance risk. | Proven Circle reliability and explicit demand. |
| No subscriptions in v1 | Safety access and product value are not yet validated. | Approved free core and monetization research. |

## Human decisions and external gates

These are not safe for an agent to invent:

1. First-market age audience and whether minors are allowed.
2. App Store category and final medical/regulated-device claim determination.
3. Privacy/legal approval of the local v1 data classes, any crash/support provider, retention, consent, deletion, and anti-coercion copy.
4. Scientific/clinical review of the five-session threshold, tasks, weights, and user-facing interpretation.
5. Named owners for incident response, App Store review communication, and user support.

## GSTACK REVIEW REPORT

### CEO review

- The plan rejects a UI-only premise and defines one public promise.
- It leads with get-home value because a first-session user cannot honestly receive a personal comparison before the baseline exists.
- It commits Guardian, Circle, location, notifications, backend, and research tooling to v1.1/internal now rather than forking the submission at the deadline.
- It treats coercive use of results as a product-safety risk and prohibits portable proof surfaces.
- It documents the human decisions that cannot be auto-decided.

### Design review

- The supplied matte-black/orange concept is promoted to the canonical system.
- Shared components and the complete screening journey migrate before secondary screens, repairing the current new → old → new funnel.
- Live capture recovery and resume-after-interruption now have explicit screen specifications.
- Launch is final polish with a sub-600 ms reveal; the legacy cyan/serif system receives no new styling.

### Engineering review

- The founder demo chain is a named P0 failure mode: synthetic five-session readiness, suppressed recomputation, and reset/delete restoration must all be removed and regression-tested.
- Separate application targets replace the runtime `UserDefaults` product boundary.
- Release archive tests inspect routes, compile conditions, Info.plist keys, entitlements, and deferred capability absence.
- The v1 test strategy spans the verified 87-test baseline, UI/snapshot coverage, local migration/deletion, real-device TrueDepth, and coercion/result-sharing checks. Guardian security remains a separate v1.1 program.

### Developer-experience review

Skipped as a standalone product phase because Sober is a consumer iOS app, not a developer-facing platform. Required build, test, contract, CI, environment, review-fixture, and runbook improvements are included in the engineering workstream.

### Cross-model status

Codex produced the original plan and repository audit. Claude executed all three prepared reviews against the actual working tree in `Docs/CLAUDE_MASTER_PLAN_REVIEW.md`. This revision incorporates the shared conclusions and corrects the original Guardian ambiguity and founder-preview misclassification.

### Final status

`DONE_WITH_CONCERNS`

The roadmap is implementation-ready. Public launch remains gated by the five human/external decisions above, removal of the founder-preview truthfulness defect, verified public-target/capability separation, and physical TrueDepth evidence. Guardian is no longer a v1 gate.
