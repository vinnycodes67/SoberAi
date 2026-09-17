# Curfew — Shrey's task cards

Paste-ready prompts for vibe coding the teen side of Curfew. Context and rules
live in [`CURFEW_SHREY_BRIEF.md`](CURFEW_SHREY_BRIEF.md) — every prompt below
tells the AI to read it first.

## How to use these

1. **One card per AI session.** Paste the prompt, let it work, check "Done
   when", commit on `shrey/curfew-device`, start a fresh session for the next.
   Long sessions drift and start inventing APIs.
2. **Do the cards in order.** Each builds on the last.
3. **Run the tests before every commit:**
   `xcodebuild -project Sober.xcodeproj -scheme SoberInternal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
4. **Stop and ask Vinay** if the AI wants to touch `Backend/`,
   `Sober/DesignKit/`, `Sober/Features/Guardian/`, or add any field that
   carries a Sober result.

**Where each card can run:**
- **SIM** — simulator, today. No Apple approval needed.
- **DEVICE** — your iPhone, with the Family Controls *development*
  entitlement (team `CPRVLR97XJ`, bundle `com.soberprototype.internal`).
- **FAMILY** — two iPhones in one Family Sharing group.

**Phase A (cards 1–10) is all SIM.** You can build and demo the entire teen
flow with fake Screen Time before Apple approves anything. That's the point:
by the time the entitlement arrives, only the thin real-API layer is left.

---

## Phase A — the whole teen flow, in the simulator

### 1. Shared contract · SIM · ~1 hr

**Files:** `Sober/Models/CurfewContract.swift`, `SoberTests/CurfewContractTests.swift`

```text
Read Docs/CURFEW_SHREY_BRIEF.md and Docs/SOBER_CONTEXT_BRIEF.md first.

Create Sober/Models/CurfewContract.swift with exactly the types in §7 of the
brief: CurfewSchedule, CurfewStatus, CurfewCheckIn. Codable, Equatable,
Sendable. Add a doc comment on CurfewStatus explaining it deliberately has no
Sober result, score, or "took a check" field.

Add CurfewSchedule.curfewTime(forNightStarting date: Date) -> Date that picks
weeknight vs weekend. Friday and Saturday nights use `weekend`; all others use
`weeknight`. A curfew like 00:30 belongs to the night that started the
previous evening — so Saturday night's 00:30 curfew is at 00:30 on Sunday.
Use the schedule's timeZoneIdentifier, not the device time zone.

Write SoberTests/CurfewContractTests.swift: Codable round-trip for every type,
weeknight vs weekend selection for all 7 nights, the after-midnight case, and
a schedule in a different time zone from the device.

Run `xcodegen generate` after adding files. Don't touch any other file.
```

**Done when:** tests pass; Vinay has read the file and agreed it. **This card
is the seam between you two — don't start card 2 until he's signed off.**

---

### 2. The pause decision function · SIM · ~3 hrs · *most important card*

**Files:** `Sober/Services/Curfew/CurfewPauseEvaluator.swift`, `SoberTests/CurfewPauseEvaluatorTests.swift`

```text
Read Docs/CURFEW_SHREY_BRIEF.md first, especially rules 1, 6 and §6
"One decision function".

Create a pure, synchronous enum CurfewPauseEvaluator in
Sober/Services/Curfew/CurfewPauseEvaluator.swift, modelled on
GuardianCheckInDueEvaluator in Sober/Features/Guardian/GuardianModels.swift.
No UIKit, no SwiftUI, no FamilyControls, no I/O — it must compile inside a
tiny app extension later.

static func evaluate(
  schedule: CurfewSchedule?,
  now: Date,
  home: HomeSnapshot?,          // isHome + capturedAt
  lastCheckInAt: Date?,
  askedForRideAt: Date?,
  nightEndsAtHour: Int = 6      // morning cutoff
) -> CurfewDecision

HomeSnapshot { isHome: Bool, capturedAt: Date }. Treat it as unknown if older
than 15 minutes.

CurfewDecision { shouldPause: Bool, reason: Reason, nextChangeAt: Date? }
Reason: noSchedule, beforeCurfew, withinGrace, home, checkedInRecently,
askedForRide, nightOver, due.

nextChangeAt is the next moment the answer could flip (grace ending, the
re-check coming due, morning) so the scheduler knows when to look again.

IMPORTANT: the function must not take any Sober check result, score, or
"took a check" input. A check-in lifts the pause regardless of anything else.

Write exhaustive tests in SoberTests/CurfewPauseEvaluatorTests.swift. Fix
`now` explicitly in every test, never Date(). Cover at least:
- no schedule → not paused
- before curfew → not paused, nextChangeAt = curfew + grace
- after curfew but within grace → not paused
- after grace, home (fresh) → not paused, reason .home
- after grace, not home → paused, reason .due
- after grace, home snapshot 20 minutes old → treated as unknown → paused
- no home snapshot at all → paused
- checked in at 23:10, recheck 60 → not paused at 23:40, paused at 00:11
- asked for a ride → not paused for the rest of the night, even if never home
- asked for a ride LAST night → does not carry over to tonight
- after 06:00 → nightOver, not paused
- weekend curfew 00:30: Saturday 23:45 → not paused, Sunday 00:45 → paused
- the DST-change nights in March and November (America/Chicago)
```

**Done when:** every case passes. If your AI suggests adding a "require a
check" input, that's rule 5 — say no.

---

### 3. Shared store (App Group) · SIM · ~2 hrs

**Files:** `Sober/Services/Curfew/CurfewSharedStore.swift`, `SoberTests/CurfewSharedStoreTests.swift`

```text
Read Docs/CURFEW_SHREY_BRIEF.md §6 "App Group".

Create CurfewSharedStore in Sober/Services/Curfew/. It wraps a UserDefaults
injected through init (the real app will pass
UserDefaults(suiteName: "group.com.soberprototype.internal.curfew"); tests
pass a throwaway suite). Store:
- schedule: CurfewSchedule?
- home: HomeSnapshot?
- tonight: TonightState { nightID: String, lastCheckInAt: Date?, askedForRideAt: Date? }
- pauseSelection: Data?   and   alwaysAllowSelection: Data?
  (raw encoded FamilyActivitySelection — keep this file free of
  FamilyControls so it compiles in tests and extensions)

nightID identifies the night (the date the evening began, in the schedule's
time zone). When a new night starts, tonight resets automatically on read.
Decode failures must return nil, never crash — extensions can't crash-report.

Tests use UserDefaults(suiteName: UUID().uuidString) and remove it in a
teardown block. Cover round-trips, the nightly reset, and corrupt data → nil.
```

**Done when:** tests pass, including the reset across midnight.

---

### 4. Check-in outbox (offline queue) · SIM · ~2 hrs

**Files:** `Sober/Services/Curfew/CurfewOutbox.swift`, `SoberTests/CurfewOutboxTests.swift`

```text
Read Docs/CURFEW_SHREY_BRIEF.md rule 7 ("A dead phone is not a missed curfew").

Create actor CurfewOutbox that persists pending CurfewCheckIn values to a JSON
file in an injected directory (the App Group container in the real app, a
temp directory in tests).

- append(_:) — dedupes by id, keeps order
- flush(using sender: some CurfewCheckInSending) async — sends oldest first,
  removes each only after it succeeds, stops at the first failure, keeps the
  rest for next time
- drops entries older than 24 hours
- caps at 50 entries, dropping the oldest

protocol CurfewCheckInSending: Sendable { func send(_ checkIn: CurfewCheckIn) async throws }

Include a FakeCurfewCheckInSender for tests that can be told to fail on the
Nth call. A corrupt file must be moved aside and treated as empty, never
crash.
```

**Done when:** tests cover offline → online, partial failure, dedupe, 24-hour
expiry, the cap, and a corrupt file.

---

### 5. Services behind protocols, with fakes · SIM · ~3 hrs

**Files:** `Sober/Services/Curfew/CurfewServices.swift`, `Sober/Services/Curfew/CurfewController.swift`, `SoberTests/CurfewControllerTests.swift`

```text
Read Docs/CURFEW_SHREY_BRIEF.md §5 and §6.

We don't have the Family Controls entitlement yet, so everything that touches
Screen Time goes behind a protocol with a fake. Real implementations come in
Phase B.

protocol CurfewPausing: AnyObject { var isPaused: Bool { get }; func pause(); func lift() }
protocol CurfewHomeDetecting: AnyObject { var latest: HomeSnapshot? { get } }

Fakes: FakeCurfewPausing (records calls), FakeCurfewHomeDetecting (settable).
Put the fakes under #if DEBUG in the main target so SwiftUI previews and UI
test fixtures can use them.

Create @MainActor final class CurfewController: ObservableObject that owns a
CurfewSharedStore, CurfewOutbox, CurfewPausing, CurfewHomeDetecting, a
GuardianLocationProviding (existing, Sober/Services/GuardianCheckInServices.swift)
and a clock `() -> Date`.

@Published decision: CurfewDecision
func refresh()                      — runs CurfewPauseEvaluator, then pause()/lift() to match
func checkInOK() async              — records lastCheckInAt, queues a .checkedIn CurfewCheckIn with location if available, lifts
func askForRide() async             — records askedForRideAt, queues .askedForRide, lifts for the night

If location fails, still check in with nil coordinates — never block a
check-in on location.

Tests drive the clock and fakes: due → pause() called; checkInOK → lift()
called and one outbox entry; askForRide → no pause for the rest of the night;
location failure still checks in.
```

**Done when:** you can reason through a whole night in tests without a device.

---

### 6. "Tonight" screen · SIM · ~3 hrs

**Files:** `Sober/Features/Curfew/CurfewTonightView.swift`

```text
Read Docs/CURFEW_SHREY_BRIEF.md §10 and DESIGN.md before any UI.

Build CurfewTonightView (INTERNAL_BUILD only) driven by CurfewController.
Use DesignKit only: DSCard, DSSection, DSRows, DSRow, DSBadge, DSEyebrow,
DSPrimaryButtonStyle, DSSecondaryButtonStyle, DSFont, DSPalette, DSSpace,
dsPageBackground, dsAppear. Don't create new components — if you need one,
write it down for Vinay.

States (one hero card each):
- no curfew set → "No curfew tonight"
- before curfew → "Home by 11:00" + countdown "2 h 10 min" (monospacedDigit)
- due → "Check-in due" + "Apps paused until you check in." + primary "Check in"
- checked in → "Checked in 11:42" + "Next check-in 12:42"
- asked for a ride → "Ride requested" + "Jordan promised: no questions tonight."
- home → "You're home"

Always visible at the bottom, in every state: "Get a ride" and
"Calls, messages, maps and rides still work."

Rules: no green anywhere, orange only for "due" and the primary button. Never
use "failed", "passed", "cleared", "safe", "sober", "caught", "violation".
Add #Preview for every state using the fakes from card 5. Check it at the
largest accessibility text size — the Check in button must stay reachable.
```

**Done when:** every preview renders, AX5 still shows the button, no green.

---

### 7. Check-in screen · SIM · ~2 hrs

**Files:** `Sober/Features/Curfew/CurfewCheckInView.swift`

```text
Read Docs/CURFEW_SHREY_BRIEF.md rules 1–3 first.

Build CurfewCheckInView, presented from the Tonight screen's Check in button.
- Title: "Check in"
- Primary: "I'm OK" → controller.checkInOK()
- Secondary, same size, directly below: "I need a ride" → controller.askForRide(),
  then open the ride
- Tertiary: "Take a Sober check first — only you see the result" → opens the
  existing screening flow. Its result must NOT change what the check-in sends.
- A line under the buttons: "Your guardian sees that you checked in and
  where. Never a Sober result."

For the ride: don't copy the Uber URL logic out of
DSIntegratedResultScreen.openRide(). Ask Vinay to move it into a shared
`SafetyPlan.rideURL` in Sober/Models — a ten-minute change on his side.

After checking in, dismiss back to Tonight showing the new state.
```

**Done when:** both buttons update Tonight correctly with the fakes, and the
Sober check path provably doesn't touch the payload (add a test).

---

### 8. Fixtures, screenshots, and a guard-rail UI test · SIM · ~2 hrs

**Files:** `Sober/App/UITestLaunchConfiguration.swift` (add cases only), `SoberUITests/CurfewUITests.swift`

```text
Read how fixtures work in Sober/App/UITestLaunchConfiguration.swift (the
Fixture enum). Add fixtures, INTERNAL_BUILD only: curfew-before, curfew-due,
curfew-checked-in, curfew-ride, curfew-home. Each seeds CurfewController with
fakes and opens CurfewTonightView directly.

Write SoberUITests/CurfewUITests.swift. For every fixture:
- "Get a ride" exists and is hittable
- none of these appear: "passed", "cleared", "safe to drive", "you're sober",
  "failed", "violation". Allow negated mentions — copy the negation check from
  SoberUITests/ReviewerPathUITests.swift.
Use 60-second waitForExistence timeouts; this machine is slow.

Only add cases to the Fixture enum — don't restructure that file.
```

**Done when:** the UI tests pass, and you can screenshot every state for
Vinay's design review.

---

### 9. Lock Screen countdown (Live Activity) · SIM · ~4 hrs

**Files:** new `CurfewLiveActivity/` target, `Sober/Services/Curfew/CurfewLiveActivityController.swift`, `project.yml`

```text
Read Docs/CURFEW_SHREY_BRIEF.md §5 "Countdown" and §6.

Add a widget extension target CurfewLiveActivity in project.yml (type:
app-extension, embedded in SoberInternal only — never Sober). Add
NSSupportsLiveActivities = YES to Sober/Info-Internal.plist only.

Define CurfewActivityAttributes: static curfewTime; dynamic content state
{ phase: before/due/checkedIn/askedForRide, nextCheckInAt: Date? }.
Lock Screen and Dynamic Island (compact, minimal, expanded) views. Use
Text(timerInterval:countsDown:) for the countdown so it ticks without updates.
Colours from DSPalette's values; no green.

CurfewLiveActivityController starts one when Tonight opens before curfew,
updates it on each state change, and ends it at nightOver or home.
Live Activities work in the simulator — test there.

Run xcodegen generate, then build both Sober and SoberInternal.
Then run Scripts/check-public-binary.sh — the public app must not contain it.
```

**Done when:** the countdown shows on the simulator Lock Screen and Dynamic
Island, and the public-binary check still passes.

---

### 10. Keep Screen Time out of the public app · SIM · ~30 min

**Files:** `Scripts/check-public-binary.sh`

```text
In Scripts/check-public-binary.sh, find the loop
  for key in aps-environment com.apple.developer.usernotifications.communication; do
and add com.apple.developer.family-controls and
com.apple.security.application-groups to it, so the public Sober app fails
the check if either ever appears. Also assert the public .app contains no
PlugIns/ directory. Run the script and confirm it passes.
```

**Done when:** the script passes; temporarily adding the entitlement to the
public target makes it fail (then remove it again).

---

## Phase B — real Screen Time on your iPhone

Do these once the development entitlement works on your device. First, in the
Apple Developer portal, enable **Family Controls** and **App Groups** on
`com.soberprototype.internal` and each extension's App ID, and create the group
`group.com.soberprototype.internal.curfew`.

### 11. Extension targets + entitlements · DEVICE · ~3 hrs

```text
Read Docs/CURFEW_SHREY_BRIEF.md §6. In project.yml add three app-extension
targets embedded in SoberInternal only:
- CurfewMonitor       NSExtensionPointIdentifier com.apple.deviceactivity.monitor-extension
- CurfewShieldConfig  NSExtensionPointIdentifier com.apple.ManagedSettingsUI.shield-configuration-service
- CurfewShieldAction  NSExtensionPointIdentifier com.apple.ManagedSettings.shield-action-service
Verify each identifier against Apple's current docs before using it.

Create an .entitlements file for SoberInternal and each extension (including
CurfewLiveActivity for the App Group) with com.apple.developer.family-controls
and the App Group group.com.soberprototype.internal.curfew. Wire them in
project.yml. The Sober (public) target gets nothing.

Compile CurfewContract, CurfewPauseEvaluator and CurfewSharedStore into the
monitor extension too. Keep the extensions tiny: no SwiftUI app code, no
fonts, no networking.
```

**Done when:** SoberInternal installs on your iPhone with all extensions, and
card 10's check still passes for the public app.

### 12. Real authorization + the two pickers · DEVICE · ~3 hrs

```text
Build the teen setup flow in Sober/Features/Curfew/CurfewSetupView.swift:
1. What Curfew does and doesn't do (plain language, what the guardian sees)
2. AuthorizationCenter.shared.requestAuthorization(for: .child)
3. .familyActivityPicker — "What to pause" (guide: Social, Games, Entertainment)
4. .familyActivityPicker — "Always allow" (their ride apps and Maps)
5. Review screen listing both selections with Label(token)

Save both FamilyActivitySelection values into CurfewSharedStore as encoded
Data. Handle denied/cancelled authorization with a clear screen — never a
dead end.
```

### 13. Real pausing · DEVICE · ~2 hrs

```text
Implement ManagedSettingsCurfewPausing: CurfewPausing using
ManagedSettingsStore(named: .init("curfew")).
pause(): shield.applicationCategories =
  .specific(pause.categoryTokens, except: allow.applicationTokens)
and the matching shield.webDomainCategories.
lift(): clearAllSettings().
Swap it in for the fake when running on a device. Add an INTERNAL_BUILD debug
screen with Pause now / Lift buttons.
```

**Done when:** a paused app shows the block screen, and Uber, Maps, Messages,
and Phone all still open. Record it — this is the evidence for the brief's
milestone 1.

### 14. The schedule (DeviceActivity) · DEVICE · ~4 hrs

```text
In CurfewMonitor, subclass DeviceActivityMonitor. In intervalDidStart and
intervalDidEnd: read CurfewSharedStore, run CurfewPauseEvaluator with
now = Date(), and pause or lift via ManagedSettingsStore(named: "curfew").

In the app, CurfewScheduler registers one DeviceActivitySchedule per hour
after curfew (curfew.h23, curfew.h00, …) until the morning cutoff, repeating
daily. Re-register whenever the schedule changes (stop all curfew.* first).
Verify the minimum interval and the maximum number of activities before
relying on them. Keep the extension's memory tiny.
```

### 15. Block screen + its buttons · DEVICE · ~3 hrs

```text
CurfewShieldConfig: ShieldConfigurationDataSource returning title
"Check-in due", subtitle "Calls, messages, maps and rides still work. Open
Sober to check in.", DSPalette colours as UIColor, primary button
"Check in", secondary "Not now".

CurfewShieldAction: ShieldActionDelegate. Primary → post a local
notification that deep-links to the check-in screen, then .close. Secondary
→ .close. It can't open Sober directly — verify the notification approach
works from this extension on a real device.
```

### 16. Home detection · DEVICE · ~3 hrs

```text
Implement CurfewHomeDetecting in the main app. Prefer CLMonitor (iOS 17)
with a CircularGeographicCondition around the existing home anchor
(KeychainGuardianHomeStore) using GuardianCheckInDueEvaluator.homeRadiusMeters.
Fall back to CLCircularRegion monitoring if CLMonitor misbehaves. On every
enter/exit, write HomeSnapshot(isHome:capturedAt:) to CurfewSharedStore.

Location permission keys belong in Sober/Info-Internal.plist only (they're
already there) — never Sober/Info.plist. Ask for Always with a reason that
says exactly what it's for.
```

**Done when:** walking out of and back into the home radius flips
`isHome`, and the evaluator waives the check-in at home.

---

## Phase C — two phones

### 17. Wire to Vinay's backend + the family test night · FAMILY

Pair with Vinay: replace the fake `CurfewCheckInSending` with his real
endpoint, then run a full night on two phones in one Family Sharing group:
curfew passes away from home → pause → check in → guardian sees "Checked in"
→ ask for a ride → guardian sees "Asked for a ride" → walk home → pause ends.
Repeat once in airplane mode to prove the guardian sees "No check-in yet" and
the queue sends later. Record every step for the evidence doc.

---

## If the AI goes off the rails

- **It invents a Screen Time method.** Tell it: "That API doesn't exist.
  Check Apple's FamilyControls/ManagedSettings/DeviceActivity docs and use only
  what's there."
- **It adds a result to the check-in, or a "require check" setting.** Rules
  1, 3, 5. Revert.
- **It edits DesignKit or the Guardian files.** Revert and ask Vinay.
- **It hand-edits `Sober.xcodeproj`.** Revert; change `project.yml` and run
  `xcodegen generate`.
- **Tests fail with a timeout.** Probably the simulator, not your code — read
  the failing line, reboot the simulator, try again.
