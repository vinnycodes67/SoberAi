# Claude Review — App Store Master Plan

Reviewer: Claude (Opus 5)
Date: 2026-08-08
Scope: the three prepared prompts in `Docs/APP_STORE_MASTER_PLAN.md:959`
Method: read the plan, then verified its claims against the working tree. No code changed.

Verification baseline at review time: **87/87 tests pass** on iPhone 17 Pro / iOS 26.5.
The plan cites 83 (`Docs/APP_STORE_MASTER_PLAN.md` current-state section) — stale by 4.

## Verdict

The plan is unusually good. The staged-safety-core strategy is right, the claims matrix is
right, and the threat-led decisions to *reject* certificate pinning and a custom pattern lock
are better judgment than most security plans show.

Two things are wrong, and one of them is a safety issue the plan has misfiled as UI hygiene.

---

## Prompt 1 — CEO / product challenge

### P0-1 — The founder demo is a public route that makes the app overstate what it compared against

The plan lists this under *"Public/internal features are mixed"* — a hygiene blocker. It is more
than that.

The chain:

| Step | Location |
| --- | --- |
| "Explore founder demo" button, on the onboarding screen every new user sees | `Sober/Features/Onboarding/OnboardingView.swift:54` |
| sets `baselineSessions = 5` with zero measured sessions | `Sober/App/AppModel.swift:709` |
| `baselineReady` short-circuits to true | `Sober/App/AppModel.swift:161` |
| real baseline recomputation is then permanently suppressed | `Sober/App/AppModel.swift:807` |
| even "delete all data" restores the fake 5 | `Sober/App/AppModel.swift:850` |

The scorer itself is honest — `Sober/Services/ScreeningEngine.swift:21` nils out a baseline that
isn't ready and falls back to population norms. That is the correct fail direction and it is why
this is a truthfulness bug rather than a fabricated-score bug.

But the consequence stands: **a public user can reach a state where the UI says their personal
steady is ready, while every result is scored against population norms.** The product's core
promise is "changes from *your* baseline." In this state it silently delivers "changes from
*a* baseline." And because line 807 suppresses recomputation, the user never converges to the
real thing — doing ten genuine sessions changes nothing.

This is precisely the failure the plan's own premise challenge names as the dangerous one:
*"A beautiful interface that overstates certainty is more dangerous than an unfinished
interface."* It should be reclassified from UI hygiene to a safety-invariant violation, and it
needs a regression test, not just a compile flag.

### P0-2 — Guardian cannot be both a v1 pillar and cuttable at the deadline

The pillars table lists Guardian as a v1 pillar. Decision 6 says Guardian gets compiled out if it
misses the gates. Both cannot be planning inputs.

Everything downstream forks on this: App Privacy answers, the privacy policy, screenshots,
review notes, the age rating, the support site, and the metadata. Building those twice is the
single most expensive avoidable outcome in this plan.

**Recommendation:** cut Guardian from the v1 promise now and name it v1.1. Ship the private
check plus get-home. Guardian's gates (production identity, APNs, App Attest, abuse controls,
two-device evidence) are weeks of work with a hard physical-device dependency you do not
control the schedule of. A v1 that ships without it is coherent; a v1 that might ship without it
is two plans.

### P1-3 — Day-one value is "get home," not "the check" — say so

Five baseline sessions is the correct scientific threshold to defend, and the plan is right to
refuse to invent a verdict before it exists. But it means the 11pm download — the actual urgent
moment — yields no comparison that night, by design.

The v1 promise line leads with the check. The first session cannot deliver it. That reads as
bait-and-switch in App Store reviews and shows up as "it doesn't work."

**Revised promise:**

> Keep a ride and a trusted contact one tap away tonight. Over your next few sober sessions,
> Sober learns your steady — then a short private check can tell you whether it found changes
> or couldn't get a reliable reading.

Get-home first (deliverable in session one), the check second (honest about the ramp).

### P1-4 — Coercion risk the plan does not cover

The plan protects the screened person from the guardian thoroughly: consent, pause, revoke, no
stealth, no guardian-controlled permissions. All good.

It does not address the reverse: **a parent, partner, or employer who requires someone to run a
check and show the result.** Nothing in the app resists that, and a "no signals detected" screen
becomes social currency — which is exactly the safe-to-drive inference the whole product refuses
to make.

**Mitigations to add to the claims matrix:** no share sheet or export on a result, no timestamp
attestation that would make a screenshot verifiable, and explicit copy that a result is not
evidence for anyone else.

### P1-5 — App Store category invites the scrutiny you're avoiding

`project.yml:41` sets `LSApplicationCategoryType: public.app-category.healthcare-fitness`. For an
alcohol-adjacent app that explicitly disclaims medical status, Health & Fitness is the category
most likely to draw medical-claims review, and it interacts with the alcohol-reference age-rating
questions. Utilities or Lifestyle is a better fit for what this actually is. Confirm with counsel.

### Revised cutline

**In v1:** onboarding, baseline, private check, three-state result, get-home actions, history,
settings/privacy center, full DesignKit migration.
**Out of v1:** Guardian, Circle Map, location entirely, notifications, research tooling.
**Consequence:** v1 needs no backend, no APNs, no App Attest, no two-device pilot, and no
location privacy answers. The submission package shrinks by roughly half, and every remaining
item is under your control.

---

## Prompt 2 — Design review

The plan's design direction is sound and its inspiration table is well-reasoned (particularly
"avoid: making a provider link look like a guaranteed booked ride"). Findings are about the gap
between plan and tree.

### D1 — The middle of the funnel is still legacy

Home and Result are genuinely migrated — `Sober/Features/Home/HomeView.swift:16` is a thin
wrapper over `DSIntegratedHomeScreen`, and `ScreeningFlowView.swift:113` routes to
`DSIntegratedResultScreen`. The plan is accurate there.

Everything between them is not:

| Still legacy | File |
| --- | --- |
| Launch | `Sober/App/SoberApp.swift:52` (cyan cursor animation) |
| Onboarding | `Sober/Features/Onboarding/OnboardingView.swift:90` (serif largeTitle) |
| Camera calibration | `Sober/Features/Screening/CameraCalibrationView.swift` |
| Tasks | `Sober/Features/Screening/TaskViews.swift` |
| Ocular task | `Sober/Features/Screening/OcularTaskView.swift` |
| Screening chrome | `Sober/Features/Screening/ScreeningFlowView.swift:481,510` |
| Safety Plan | `Sober/Features/Plan/SafetyPlanView.swift` |
| Circle Map | `Sober/Features/Guardian/CircleMapView.swift` |
| Shared components | `Sober/Components/SoberComponents.swift:16,194`, `SignalHalo.swift` |

The user journey is therefore **new → old → old → old → new**. The screening flow is the longest
and most attention-critical surface in the app and it is entirely on the old system. Migrating
Home and Result first was the wrong order for perceived quality — it makes the app look
half-finished in the middle rather than uniformly early.

**Recommendation:** migrate `SoberComponents.swift` and `SignalHalo.swift` first (they are the
shared dependency under most legacy screens), then the screening flow, then onboarding, then
launch. Launch last because it is cheapest and highest-visibility — good final polish.

### D2 — Two type systems are shipping simultaneously

Serif `largeTitle` in onboarding and screening versus Satoshi in DesignKit. These read as two
different apps. This is the single most visible inconsistency and it is on the first screen after
launch.

### D3 — Two states in the error registry have no screen spec

The error/rescue registry (plan line 746) covers "task interrupted" and "poor light/position,"
but the 15 screen specifications do not include a resume-after-interruption screen or a live
low-light recovery surface. Both are common at night, which is the app's primary context.
Add them to the screen list or the implementer will invent them.

### D4 — Verify the night/one-handed claim
The plan specifies a 54pt minimum for primary actions. Worth measuring against the actual
`DSIntegratedHomeScreen` button rather than assuming; the check is cheap and the claim is in an
accessibility label you will have to defend.

---

## Prompt 3 — Engineering / security review

### Correct decisions worth preserving

- `Sober/Services/ScreeningEngine.swift:21` — an unready baseline becomes `nil`, not a weak
  comparison. Right fail direction.
- `Sober/Services/GuardianAPIClient.swift:10,304` — an empty or unsubstituted API URL becomes
  `nil` and every request guards on it. Guardian fails closed instead of crashing or hitting a
  garbage host. Right fail direction.
- Rejecting certificate pinning and a custom pattern lock. Both would have added recovery and
  outage risk without addressing the real threat model.

### Blockers

**E1 — `INTERNAL_BUILD` does not exist.** The plan requires compile-time separation and states
that a runtime flag "can fail open and leaves review-only code in public navigation." The tree
has exactly the runtime flag the plan forbids: a `UserDefaults` bool (`sober.founder.preview`,
`AppModel.swift:915`) toggled by a button in production onboarding. `project.yml` defines no
such compilation condition. No test asserts the boundary. This is E1 and P0-1 from the product
review — same defect, both lanes.

**E2 — `UIBackgroundModes: [location]` ships unconditionally.** `project.yml:27` declares it and
`Info.plist` carries `NSLocationAlwaysAndWhenInUseUsageDescription`. If location is deferred out
of v1 (recommended above), shipping an unused background mode is a documented rejection trigger
and it forces location into your App Privacy answers for a capability the app does not use.
Remove both for v1, or gate them behind the Guardian build configuration.

**E3 — `NSAllowsLocalNetworking` is in the base Info.plist.** `project.yml:26` puts it in the
shared properties, so it ships in Release. The plan states the local HTTP exception "remains
Debug-only." It does not. Move it to a Debug-only overlay. Low exploitability, but it is a
plan-versus-tree contradiction in the security section, which is where those are most costly.

**E4 — Release has no backend and no user-facing story for it.** `SOBER_GUARDIAN_API_URL` is
`""` in Release. The client handles it safely, but a Release build today has Guardian
permanently dead. Confirm the UI renders "Guardian is unavailable" rather than a pairing
affordance that silently does nothing — the failure is handled at the network layer, not
necessarily at the presentation layer.

**E5 — No UI test target.** Confirmed; matches the plan. Note the ordering dependency: the UI
tests that matter most are the ones asserting public builds cannot reach internal routes, and
those cannot be written until E1 lands.

### Should-fix

- The plan's test baseline (83) is stale; it is 87. The release-evidence process depends on
  accurate baselines — regenerate at Phase 0 freeze.
- `AppModel` owns `isFounderPreview` alongside guardian, baseline, research, and alert state.
  The plan's store extraction is right; do `PermissionStore` and `BaselineStore` first, since
  both are implicated in E1.
- No test locks the "no safe/pass language" invariant against the *founder preview* path
  specifically. The existing safety tests cover the engine, not the demo state.

### Dependency-ordered plan

```text
E1 compile-time internal/public split
     |
     +--> regression test: public build cannot set founderPreview
     +--> regression test: baselineReady is false without measured sessions
              |
              v
E2/E3 Info.plist scope decision (background mode, ATS)
              |
              +--> App Privacy answers can be frozen
              |
              v
E5 UI test target + snapshot fixtures
              |
              v
        screenshots --> submission package
```

E1 comes first because it changes what the UI tests must assert. E2/E3 come before the privacy
answers because they change the data inventory. Screenshots last, after visual freeze.

---

## Three things I'd change in the plan itself

1. Move the founder-preview issue from the UI-hygiene blocker table into the failure-mode
   registry as a safety-invariant violation with a named regression test.
2. Cut Guardian from v1 rather than gating it, and delete location from the v1 data dictionary.
   This removes the backend, APNs, App Attest, and two-device pilot from the critical path.
3. Reorder the DesignKit migration to start with shared components and the screening flow.
