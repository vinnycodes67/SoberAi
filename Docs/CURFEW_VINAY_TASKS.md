# Curfew — Vinay's task cards

The guardian side, the backend, and the design system. Shrey's half is in
[`CURFEW_SHREY_BRIEF.md`](CURFEW_SHREY_BRIEF.md) and
[`CURFEW_SHREY_TASKS.md`](CURFEW_SHREY_TASKS.md); the feature and its rules are
described there and apply here too.

**Legend:** **[you]** only you can do it · **[claude]** I can do it in a session
· **[blocks shrey]** he is stuck until it's done.

---

## Do these two first

### V1. Sign off the shared contract · [you] · ~15 min · [blocks shrey]

Shrey's card 1 creates `Sober/Models/CurfewContract.swift` from §7 of his
brief. Read it and agree the field names before he starts card 2 — after that,
changing it costs both of you a day.

The one thing to check: **`CurfewStatus` must not gain a result, a score, or a
"took a check" flag.** That absence is the whole design.

### V2. Shared ride link · [claude] · **done**

`SafetyPlan.rideURL` now lives in `Sober/Models/ScreeningModels.swift`, and
`DSIntegratedResultScreen.openRide()` uses it. Shrey's card 7 depends on this
so his check-in opens the same ride the same way. Covered by
`SoberTests/SafetyPlanRideURLTests.swift`.

---

## Design system

### V3. Two new DesignKit components · [claude] · ~2 hrs

`DSStatusChip` (Home · Checked in · Asked for a ride · No check-in yet) and
`DSCountdownRing` for the curfew countdown. Both in `Sober/DesignKit/`.

**No green.** "Checked in" is white or grey. Green would read as "safe", which
`DESIGN.md` forbids, and this is the exact screen where a parent would want to
read it that way. Orange only for "No check-in yet".

Shrey is told not to fork these — if he needs a variant he asks you.

### V4. Update `DESIGN.md` · [claude] · ~30 min

Its "Migration state" section is out of date — it still says onboarding, task
capture, Safety Plan and Circle Map use the old cyan/serif components, which
we migrated. Add a decisions-log entry for the Curfew rules: no green for a
check-in, one status chip vocabulary, and no result ever rendered on a
guardian surface.

---

## Guardian side

### V5. Family setup · [claude] · ~1 day

Invite and accept, built on the two-sided consent you already shipped in
Guardian v1.1 (`Backend/guardian-relationship-lifecycle.js`,
`guardian-consents.js`). Add the guardian/teen roles.

The teen's accept screen must list, in plain language, exactly what the
guardian will and will not see. It should be possible to screenshot that
screen and have it be a true statement.

### V6. Curfew editor · [claude] · ~1 day

Weeknight and weekend times, grace minutes, re-check cadence. This extends
`GuardianCheckInPlanSnapshot` (`Sober/Features/Guardian/GuardianModels.swift`),
which already carries cadence, local time, time zone, grace and
proposed/decided state — don't build a parallel model.

Keep the existing **waived-at-home** behaviour: no curfew action when the teen
is already home.

### V7. Safe Ride Promise · [claude] · ~half day

The guardian signs the pledge during setup; store it as a consent record
alongside the others, with a version and digest like the existing consents.
The teen sees it on the check-in screen as "Jordan promised: no questions
tonight." If the promise is ever withdrawn, the teen is told.

### V8. Guardian home · [claude] · ~1 day

The family roster with a status chip each, and tonight's timeline. Timestamps
and locations only. No result, no score, no streaks, no "compliance" framing.

### V9. Role-aware Home · [claude] · ~half day

One app, two homes: the teen sees Tonight (Shrey's screen), the guardian sees
the roster. Decide this from the relationship role, not a toggle.

---

## Backend

### V10. Curfew endpoints · [claude] · ~1–2 days

Schedule read/write, plus the three events: `checked_in`, `asked_for_ride`,
`missed`. Extend `Backend/worker.test.js` alongside.

Two constraints worth writing into the schema itself: **no result field**, and
location only on check-in events, with the retention rules already set in
`Docs/GUARDIAN_DATA_GOVERNANCE.md`. Anything that can't be enforced in the
schema, enforce in a test.

### V11. Push-to-start for the countdown · [claude] · ~half day · *after Shrey's card 9*

Shrey's Live Activity can only start itself while the app is open. Starting it
at curfew from the background needs an ActivityKit push-to-start token
(iOS 17.2+). Handle 17.0–17.1 without it.

---

## Before real families

### V12. Governance and legal pack · [claude] drafts · [you] + counsel decide

Update `GUARDIAN_DATA_GOVERNANCE.md` and `GUARDIAN_THREAT_MODEL.md` for what
Curfew adds: minors aged 13–17, location, and a new class of parent-visible
events. The threat model already assumes neither party is trusted to act for
the other — curfew is the first feature where one party configures the other's
phone, so that section needs real work.

Then counsel on location and camera use for minors.

---

## What only you can do

| | Why it blocks |
| --- | --- |
| Sign off V1 | Shrey can't start his card 2 |
| Enable **Family Controls** and **App Groups** on `com.soberprototype.internal` and each extension App ID; create `group.com.soberprototype.internal.curfew` | Shrey's Phase B won't build |
| Submit the **Family Controls (Distribution)** request to Apple | Nothing ships without it; longest lead time |
| A second iPhone and a child Apple ID (13–17) in one Family Sharing group | Neither of you can test the real feature |
| Counsel on minors, location, and face data | Can't go to real families |
| Decide bundle ID, version number, category, age rating, and the two URLs | Still open from the v1 submission |

---

## Order

```text
V1 (you) ──► Shrey cards 1–10 (simulator, no Apple approval needed)
   └► V3, V4 ──► V5 ──► V6 ──► V7 ──► V8 ──► V9
        V10 runs alongside V5–V8
Apple entitlement approved ──► Shrey cards 11–16 ──► V11
V12 + counsel ──────────────► card 17, two phones, real family
```

Curfew stays on its own branch and out of the v1 App Store submission — v1
answers "Data Not Collected" and has no network or location.
