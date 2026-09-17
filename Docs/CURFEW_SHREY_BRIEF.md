# Curfew — Shrey's brief (teen's phone)

> **Tasks to vibe code, in order:** [`CURFEW_SHREY_TASKS.md`](CURFEW_SHREY_TASKS.md)
>
> **Start every AI coding session with:** "Read `Docs/CURFEW_SHREY_BRIEF.md` and
> `Docs/SOBER_CONTEXT_BRIEF.md` before writing any code. Follow the rules in both."

You own the **teen's iPhone**: Screen Time integration, the curfew schedule,
the block screen, the check-in, and the Lock Screen countdown. Vinay owns the
guardian's side, the backend, and the design system. This document is the
context an AI assistant needs so it does not guess.

---

## 1. What we are building, in one paragraph

A guardian (parent) and a teen (13–17) join a **Family**. The guardian sets a
**Curfew** — "home by 11:00 on weeknights, 12:30 on weekends". At curfew, if
the teen is home, nothing happens. If not, the teen's phone **pauses
distracting apps** (social, games, streaming) and asks for a **check-in**,
repeating every hour until they're home. Checking in — "I'm OK" or "I need a
ride", plus location — lifts the pause. Asking for a ride books one to home and
tells the guardian, under a **Safe Ride Promise** the guardian signed at setup:
no questions tonight.

The guardian sees one of: **Home · Checked in 11:42 · Asked for a ride · No
check-in yet.** Never a Sober result.

---

## 2. Rules that are not negotiable

Your AI will try to "improve" these. Don't let it.

1. **A check-in unlocks. A Sober result never does.** Nothing in the teen's
   phone is ever gated on the outcome of a Sober check. There is no code path
   where "changes detected" keeps apps paused or "no changes" lifts them.
2. **Never block the way home.** Phone, Messages, Maps, ride apps (Uber,
   Lyft), and Sober itself are never paused. If you are unsure whether a
   setting could pause one of them, assume it can and exempt it.
3. **The result never leaves the teen's phone.** Not the state, not a score,
   not *whether a check was taken*. A check-in payload is identical whether or
   not the teen ran a Sober check — otherwise the guardian learns to demand one.
4. **No pass state, no green.** Never write "passed", "cleared", "safe",
   "you're sober", or use green anywhere. This is enforced across the app.
   Checked in is white or grey, never green.
5. **There is no guardian setting to require a Sober check.** Do not add one,
   even as an option. If the shared contract ever grows a field like that,
   stop and talk to Vinay.
6. **Failing is harmless by design — keep it that way.** If the phone can't
   tell whether the teen is home, it pauses social apps and asks for a
   check-in. That's fine *only because* the pause never touches the ride path
   and a check-in takes ten seconds. Don't add anything that makes a wrong
   guess costly.
7. **A dead phone is not a missed curfew.** Phone off, airplane mode, no
   signal → the guardian sees "No check-in yet", never an accusation. Queue
   check-ins locally and send when back online.
8. **Stay out of the public v1 app.** Everything here lives in
   `SoberInternal` (compiled with `INTERNAL_BUILD`) and its extensions. The
   public `Sober` target must not gain the Family Controls entitlement,
   location, or network — v1's App Store privacy answer is "Data Not
   Collected".

---

## 3. What you own, and what you don't touch

| Yours | Vinay's — don't edit |
| --- | --- |
| `Sober/Features/Curfew/` (teen screens) | `Backend/` |
| `Sober/Services/Curfew/` (Screen Time, home detection, shared store) | `Sober/Features/Guardian/` |
| New extension targets (§5) | `Sober/DesignKit/` (ask for a component, don't fork one) |
| Curfew additions to `project.yml` | Guardian-side screens |
| Entitlements files for SoberInternal + extensions | `DESIGN.md` |

**Shared — changes need both of you:** `Sober/Models/CurfewContract.swift`
(see §7). Agree it on day one.

Work on your own branch (e.g. `shrey/curfew-device`). This repo has already
lost work to two agents committing over each other — pull before you start,
and never commit files you didn't mean to.

---

## 4. The teen's flow

```text
Curfew time arrives
  ├─ Home?  (region monitor says inside home radius)  →  nothing happens
  └─ Not home / unknown
       → pause selected categories (never the ride path)
       → notification + Lock Screen countdown: "Check-in due"
       → teen opens Sober → Check in
            ├─ "I'm OK"          → pause lifts; re-checks in 1 hour if not home
            ├─ "I need a ride"   → pause lifts for the rest of the night,
            │                      ride to home opens, guardian notified
            └─ (optional) Sober check — result stays on this phone only
Teen arrives home → pauses stop for the night
```

---

## 5. Apple APIs you'll use

> **Warning for your AI:** Screen Time APIs are thinly documented and AI tools
> routinely invent methods for them. Check every call against Apple's docs or
> Xcode's autocomplete. Anything marked **verify** below needs confirming on a
> real device before you build on it.

**Frameworks:** `FamilyControls`, `ManagedSettings`, `ManagedSettingsUI`,
`DeviceActivity`, `ActivityKit`, `CoreLocation`. Deployment target is iOS 17.

### Authorization — `FamilyControls`
- `try await AuthorizationCenter.shared.requestAuthorization(for: .child)` on
  the **teen's** phone. The guardian approves it through Family Sharing.
- Requires the entitlement `com.apple.developer.family-controls` on the app
  **and on every extension**.
- **Distribution needs Apple's approval.** The development entitlement works
  for testing, but shipping needs the "Family Controls (Distribution)" request
  approved by Apple. **Submit it on day one** — it's the longest lead time.
- **verify:** whether `.child` authorization prevents the teen deleting the
  app without guardian approval.

### Choosing what to pause — `FamilyActivityPicker`
- Tokens are **opaque**. You cannot write "block Social" or "allow Uber" in
  code — the only way to get a category or app token is a user picking it in
  `FamilyActivityPicker`, which returns a `FamilyActivitySelection`
  (`categoryTokens`, `applicationTokens`, `webDomainTokens`). It's `Codable`,
  so persist it.
- You also **cannot read which category a token is**. So you can't
  programmatically stop someone picking "Travel" (where Uber lives).
- Therefore setup runs **two pickers**: "What to pause" (guide them to Social,
  Games, Entertainment) and "Always allow" (their ride apps, Maps). Then pause
  with an exception list:
  `store.shield.applicationCategories = .specific(pauseCategories, except: alwaysAllowApps)`
- Phone and emergency calls can't be blocked by this API. **verify** Messages
  and Maps on device — exempt them explicitly anyway.

### Pausing — `ManagedSettings`
- Use one **named** store so you never clobber anything else:
  `ManagedSettingsStore(named: .init("curfew"))`.
- Apply: set `shield.applicationCategories` (and `shield.webDomainCategories`).
- Lift: `store.clearAllSettings()`.
- Both the main app and the monitor extension write to the same named store.

### Scheduling — `DeviceActivity`
- `DeviceActivityCenter().startMonitoring(name, during: DeviceActivitySchedule(intervalStart:intervalEnd:repeats:))`
- A **DeviceActivityMonitor extension** gets `intervalDidStart(for:)` /
  `intervalDidEnd(for:)` and applies or lifts the pause there.
- `DeviceActivityEvent` thresholds measure **app usage time**, not the clock —
  don't use them for "every hour". For hourly re-checks, register one
  schedule per hour after curfew (`curfew.h23`, `curfew.h00`, …).
- **verify:** the minimum interval (commonly 15 min) and the cap on monitored
  activities (commonly ~20). A six-hour night uses six.
- **verify:** the extension's memory limit is tiny (commonly cited ~6 MB). No
  big models, no DesignKit fonts, no networking in the extension.

### The block screen — `ManagedSettingsUI`
- **ShieldConfiguration extension** (`ShieldConfigurationDataSource`): returns
  icon, title, subtitle, button labels, colours. It is **not SwiftUI** — you
  set `UIColor`/`UIImage`/label text, and the system renders it in its own font.
  Use DesignKit's colour values converted to `UIColor`.
  Suggested copy: **"Check-in due" / "Calls, messages, maps and rides still
  work. Open Sober to check in."**
- **ShieldAction extension** (`ShieldActionDelegate`): handles the buttons with
  `.close`, `.defer`, or `.none`. **It cannot open Sober directly.** The usual
  workaround is posting a local notification that deep-links into the
  check-in — **verify** this works from the action extension.

### Home detection — `CoreLocation`, in the main app
- Extensions can't reliably get location. So the **main app** monitors a
  region around home (`CLCircularRegion`, `startMonitoring(for:)`); iOS
  relaunches the app in the background on enter/exit.
- The app writes `isHome` + timestamp into the **App Group** (below). The
  monitor extension reads it at `intervalDidStart`.
- Stale or missing value → treat as not home. That's safe per rule 6.
- Needs **Always** location permission, with a plain-language reason.
- Reuse the existing radius: `GuardianCheckInDueEvaluator.homeRadiusMeters`
  (200 m) in `Sober/Features/Guardian/GuardianModels.swift`. The home anchor
  is stored in the Keychain (`KeychainGuardianHomeStore`,
  `Sober/Services/GuardianCheckInServices.swift`) — the extension doesn't need
  the anchor, only the derived `isHome`.

### Countdown — `ActivityKit`
- Live Activity for "Home by 11:00 · 42 min" on the Lock Screen and in the
  Dynamic Island. Needs a widget extension and `NSSupportsLiveActivities`.
- Starting one while the app is in the foreground is easy. Starting one from
  the background needs **push-to-start (iOS 17.2+)** from Vinay's backend —
  coordinate with him, and handle iOS 17.0–17.1 without it.
- **verify:** the maximum Live Activity duration (commonly 8 hours).

---

## 6. Architecture

**New targets, added in `project.yml` — never hand-edit the `.xcodeproj`:**

| Target | Type | Purpose |
| --- | --- | --- |
| `CurfewMonitor` | DeviceActivity monitor extension | applies/lifts the pause on schedule |
| `CurfewShieldConfig` | Shield configuration extension | the block screen's look |
| `CurfewShieldAction` | Shield action extension | block screen buttons |
| `CurfewLiveActivity` | Widget extension | countdown |

All four embed in **`SoberInternal` only**. Run `xcodegen generate` after
editing `project.yml`.

**App Group** (e.g. `group.<bundle-id>.curfew`) shared by SoberInternal and all
four extensions. Holds: the curfew schedule, the two picker selections,
`isHome` + timestamp, tonight's state (checked in at / asked for ride), and the
outbound queue of check-ins not yet sent.

**Entitlements:** there are currently **no `.entitlements` files** in the repo.
You'll create one for SoberInternal and one per extension, each with
`family-controls` and the App Group, and wire them in `project.yml`.

**Guard the public build:** add `com.apple.developer.family-controls` to the
forbidden-entitlements loop in `Scripts/check-public-binary.sh` (it currently
lists `aps-environment` and
`com.apple.developer.usernotifications.communication`). Then run the script and
confirm it passes.

**One decision function, shared everywhere.** Put "should the phone be paused
right now?" in a single pure function — inputs: now, schedule, `isHome` +
freshness, last check-in, asked-for-ride — compiled into both the app and the
monitor extension. Model it on `GuardianCheckInDueEvaluator`. That way the
logic is unit-tested in `SoberTests` instead of only testable on a device at
11 p.m.

---

## 7. The shared contract (proposed — agree with Vinay on day one)

```swift
// Sober/Models/CurfewContract.swift — shared. Changes need both owners.

struct CurfewSchedule: Codable, Equatable, Sendable {
  var weeknight: DateComponents      // e.g. 23:00
  var weekend: DateComponents        // e.g. 00:30
  var timeZoneIdentifier: String
  var recheckMinutes: Int            // 60 = "every hour"
  var graceMinutes: Int
}

/// The only thing the guardian ever learns about tonight.
/// Deliberately has no result, no score, and no "took a check" flag.
enum CurfewStatus: String, Codable, Sendable {
  case home
  case checkedIn
  case askedForRide
  case noCheckInYet
}

struct CurfewCheckIn: Codable, Equatable, Sendable {
  let id: UUID
  let at: Date
  let status: CurfewStatus           // .checkedIn or .askedForRide
  let latitude: Double?
  let longitude: Double?
  let horizontalAccuracyMeters: Double?
}
```

`FamilyActivitySelection` stays on the teen's phone — tokens are
device-specific and never go to the server.

---

## 8. Milestones — each done only when it's shown on a real phone

| # | Milestone | Done when |
| --- | --- | --- |
| 0 | Contract agreed, entitlement request submitted, branch created | Vinay has signed off on §7 |
| 1 | Authorization + both pickers + a debug "pause now / lift" button | Selected apps show the block screen; Uber, Maps, Phone still open |
| 2 | Schedule + hourly re-checks + home waiver via App Group | Pause starts at curfew away from home, not at home |
| 3 | Branded block screen, notification tap-through, check-in flow | "I'm OK" lifts; "I need a ride" lifts for the night |
| 4 | Lock Screen / Dynamic Island countdown | Shows and updates through curfew |
| 5 | Wired to Vinay's backend; offline queue | Guardian's phone shows each status; airplane mode shows "No check-in yet" |

Record evidence for each (screen recording or photo) in a short doc — the
project already expects device evidence in `Docs/PHASE_4_DEVICE_GATES.md`.

---

## 9. Testing

- **The simulator can't do this.** Child authorization and shields need real
  hardware: **two iPhones in one Family Sharing group** — the guardian's, and
  one signed in with a teen (13–17) child Apple ID.
- Unit-test the decision function (§6) and the contract in `SoberTests`.
- Existing suites: `xcodebuild -project Sober.xcodeproj -scheme Sober test`
  (~158 unit, ~31 UI). They must stay green.
- Most "failures" on this machine have been simulator timeouts or a full disk
  — read the failing line before assuming you broke something.

---

## 10. Teen-facing copy

- Pause, not lock or punish: **"Apps paused until you check in."**
- Always say what still works: **"Calls, messages, maps and rides still work."**
- Safe Ride Promise, shown when they ask for a ride: **"Jordan promised: no
  questions tonight."**
- Never: "failed", "passed", "cleared", "safe", "sober", "caught", "violation".

---

## 11. Open questions — raise with Vinay, don't decide alone

- Can the teen see the exact pause list and schedule? (Recommended: yes, always.)
- What happens on a guardian's device if the teen revokes Family Sharing?
- Does "asked for a ride" also share live location until home, or one point?
- Legal review for location and face processing of 13–17-year-olds is still
  open — nothing ships to real families before it's done.
