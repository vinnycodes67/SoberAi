# Curfew — device gates

Curfew's exit gate is "each milestone in `Docs/CURFEW_SHREY_BRIEF.md` §8 has
been shown on a real phone". This is that checklist. It covers only what a
simulator cannot answer: child authorization, shields, region monitoring, and
Live Activities all need hardware and a Family Sharing group. Everything a
machine can check already runs in `SoberTests` or `Scripts/check-public-binary.sh`.

Record each row in a copy of this file per build: build number, commit, teen
device, guardian device, OS, outcome, and a screenshot or recording. A gate
with no artefact is not passed, it is unrecorded.

The rules being tested are the brief's §2. Two of them shape every row below:
**a check-in unlocks, a Sober result never does** (rule 1), and **never block
the way home** (rule 2).

## What is already automated

Do not re-test these by hand. They gate every commit.

| Gate | Where |
| --- | --- |
| Pause decision: weeknight and weekend windows, grace, hourly re-checks, night ids keyed by the evening date, DST nights | `CurfewEvaluatorTests` |
| Home reading: fresh counts, stale (older than `CurfewPauseEvaluator.homeFreshnessMinutes`, 8 h) or future-dated does not, home outranks a check-in | `CurfewEvaluatorTests` |
| A ride request lifts for the whole night; a check-in from another night is ignored; only `checkInDue` pauses | `CurfewEvaluatorTests` |
| Invalid or missing schedule pauses nothing | `CurfewEvaluatorTests` |
| `CurfewCheckIn` has exactly `id, at, status, latitude, longitude, horizontalAccuracyMeters`; `CurfewSharedState` has no result, score, or took-a-check field; `CurfewStatus` is exactly the four guardian-visible cases | `CurfewContractTests` |
| No Curfew source references `ScreeningOutcome`, `ScreeningEngine`, `CheckHistoryStore`, `signalsDetected`, `requireSoberCheck`, `requiresCheck` | `CurfewContractTests` |
| Contract JSON round-trips; the encoded check-in has exactly six keys | `CurfewContractTests` |
| Shared state records only reportable statuses, resets per night, and delivery removes only delivered ids; App Group store round-trips; an unavailable suite reads empty | `CurfewContractTests` |
| Outbox drains oldest-first, stops at the first failure, drops nothing, never sends `home` or `noCheckInYet`; the unconfigured sender keeps everything queued | `CurfewContractTests` |
| Teen copy has no forbidden word, never lowercase "sober", and every mention of pausing says what still works | `CurfewContractTests` |
| Shield palette equals `DSPalette` and contains no green | `CurfewContractTests` |
| The public test host embeds no `.appex`, declares no `NSSupportsLiveActivities` or `CFBundleURLTypes`, no location strings | `CurfewContractTests` |
| Public Release binary: no Curfew copy, no `PlugIns`, no link against FamilyControls / ManagedSettings / ManagedSettingsUI / DeviceActivity / ActivityKit, no `family-controls` or `application-groups` entitlement, no `NSSupportsLiveActivities` | `Scripts/check-public-binary.sh` ("Curfew stays internal") |
| Those checks can fail: SoberInternal embeds all four `.appex` and links FamilyControls, and both Curfew sentences are detectable in it | `Scripts/check-public-binary.sh` (sensitivity control) |

## Blocked on the founder

None of this can start until someone provides what is listed.

| Blocker | Needed for | Owner |
| --- | --- | --- |
| Apple Developer portal: App Group `group.com.soberprototype.internal.curfew` enabled for `com.soberprototype.internal` and for `com.soberprototype.internal.curfew-monitor`, `.curfew-shield-config`, `.curfew-shield-action`, `.curfew-live-activity` | Any signed SoberInternal device build; the extensions cannot read the shared state without it | Founder |
| Apple Developer portal: Family Controls capability on `com.soberprototype.internal` and on the same four extension identifiers | Milestone 1 onwards; the development entitlement is enough for testing | Founder |
| "Family Controls (Distribution)" request submitted and approved by Apple | TestFlight and any build that leaves the team | Founder — longest lead time, submit first |
| Two iPhones in one Family Sharing group: the guardian's, and one signed in with a 13–17 child Apple ID | Every row below; the simulator cannot grant child authorization or render a shield | Founder |
| Push-to-start credentials from Vinay's backend (iOS 17.2+) | Milestone 4 background start; foreground start works without it | Vinay |
| Legal review of location and face processing for 13–17-year-olds | Anything with a real family | Counsel — nothing ships before this is closed |

## Milestone 1 — authorization, both pickers, debug pause and lift

Done when selected apps show the block screen and Uber, Maps, and Phone still open.

| # | Step | Pass criteria | Evidence |
| --- | --- | --- | --- |
| M1.1 | On the teen phone open SoberInternal → Curfew setup → Allow | The Screen Time prompt appears and asks for the guardian's approval; `authorizationStatus` becomes `.approved` | screenshot of prompt and of setup showing approved |
| M1.2 | Deny on the guardian's phone, then retry | Status reads denied; setup explains what to do; nothing is paused | screenshot |
| M1.3 | "What to pause" picker: choose Social, Games, Entertainment | Selection persists across a relaunch (`pauseSelectionData` non-nil) | screenshot after relaunch |
| M1.4 | "Always allow" picker: choose Uber or Lyft and Maps | Selection persists across a relaunch | screenshot after relaunch |
| M1.5 | Tap the debug "pause now" button | Instagram (or any picked app) shows the block screen within seconds | recording |
| M1.6 | With the pause on: open Phone, Messages, Maps, Uber or Lyft, and Sober | All five open normally. Any one of them shielded is a P0 (rule 2) | recording |
| M1.7 | Place a call and send a message while paused | Both go through | recording |
| M1.8 | Tap the debug "lift" button | The picked app opens; the named store is clear (`isShieldApplied` false) | recording |
| M1.9 | Force-quit SoberInternal while paused | The shield stays up; relaunch reports it applied | recording |

## Milestone 2 — schedule, hourly re-checks, home waiver

Done when the pause starts at curfew away from home and not at home.

Set the curfew a few minutes ahead for these; the evaluator does not care what
the wall clock says.

| # | Step | Pass criteria | Evidence |
| --- | --- | --- | --- |
| M2.1 | Save a schedule; count activities in setup | `monitoredActivityCount` equals the nights' hourly slots and is under the device's cap | screenshot |
| M2.2 | Set the home anchor at the current location; grant Always location | Home reading in setup shows `isHome` true with a fresh timestamp | screenshot |
| M2.3 | Wait for curfew plus grace while at home | Nothing pauses; the picked app still opens; the Lock Screen shows no check-in | recording |
| M2.4 | Walk more than 200 m away with the app killed; wait for curfew plus grace | The monitor extension pauses the picked app without the app running | recording with timestamp |
| M2.5 | Airplane mode 30 minutes before curfew, away from home | The pause still starts (schedule and home reading are on-device) | recording |
| M2.6 | Delete the home reading (or set a clock 46 minutes ahead in a debug build) | Stale reading pauses as "not home" (rule 6) | screenshot |
| M2.7 | Check in, then wait one recheck interval away from home | Pause returns at `lastCheckIn + recheckMinutes`; the notification fires | recording |
| M2.8 | Walk home after the pause started | Region entry lifts the pause within a minute of arrival | recording |
| M2.9 | Friday night with the weekend time | Pause starts at 00:30 Saturday, not 23:00 Friday; the night id is Friday's date | screenshot of debug state |
| M2.10 | Sunday night | Uses the weeknight time | screenshot |

## Milestone 3 — block screen, notification tap-through, check-in

Done when "I'm OK" lifts and "I need a ride" lifts for the night.

| # | Step | Pass criteria | Evidence |
| --- | --- | --- | --- |
| M3.1 | Open a paused app | Block screen reads "Check-in due" / "Calls, messages, maps and rides still work. Open Sober to check in." in DesignKit colours; nothing green | screenshot |
| M3.2 | Tap the shield's primary button | A local notification arrives; tapping it opens Sober on the check-in | recording |
| M3.3 | Tap "Not now" | The shield closes; the app stays paused | recording |
| M3.4 | Tap "I'm OK" | Pause lifts within seconds; the picked app opens; status shows next check-in time | recording |
| M3.5 | Tap "I need a ride" | Pause lifts; the ride app opens to home; the Safe Ride Promise line shows the guardian's name | recording |
| M3.6 | After M3.5, wait past the next recheck | Nothing pauses again tonight | recording |
| M3.7 | Check in with location denied | Check-in still succeeds; payload has nil coordinates | screenshot of debug state |
| M3.8 | Run the optional Sober check before checking in, then inspect the queued check-in | Payload is identical to one without a check: same six keys, no extra field (rule 3) | screenshot of debug state |
| M3.9 | Get a "changes detected" result, then tap "I'm OK" | Pause lifts exactly as it did without the check (rule 1) | recording |
| M3.10 | Read every screen in the flow | No "failed", "passed", "cleared", "safe", "sober" as a state, "caught", "violation" (rule 4) | screenshots |

## Milestone 4 — Lock Screen and Dynamic Island countdown

Done when the countdown shows and updates through curfew.

| # | Step | Pass criteria | Evidence |
| --- | --- | --- | --- |
| M4.1 | Open the app before curfew | Live Activity starts: "Home by 11:00 · 42 min" on the Lock Screen and in the Dynamic Island | screenshot |
| M4.2 | Lock the phone across curfew and grace | Countdown reaches curfew, shows grace, then "Check-in due" without the app being opened | recording |
| M4.3 | Check in from the notification | Activity updates to checked in with the next check-in time | screenshot |
| M4.4 | Ask for a ride | Activity shows the ride state; no further countdown | screenshot |
| M4.5 | Arrive home or reach the end of the night | Activity ends on its own | screenshot |
| M4.6 | iOS 17.0 or 17.1 device, app not opened before curfew | No crash; the notification still carries the check-in (no push-to-start) | recording |
| M4.7 | iOS 17.2+ with Vinay's push-to-start configured | Activity starts from the background at curfew | recording |
| M4.8 | Leave the activity running past the platform maximum | It ends cleanly rather than freezing on a stale time | screenshot |

## Milestone 5 — backend and offline queue

Done when the guardian's phone shows each status and airplane mode shows "No check-in yet".

| # | Step | Pass criteria | Evidence |
| --- | --- | --- | --- |
| M5.1 | Teen at home at curfew | Guardian sees **Home** | screenshot of both phones |
| M5.2 | Teen taps "I'm OK" at 11:42 | Guardian sees **Checked in 11:42** within a minute | screenshot of both phones |
| M5.3 | Teen taps "I need a ride" | Guardian sees **Asked for a ride** and the Safe Ride Promise reminder | screenshot of both phones |
| M5.4 | Teen phone in airplane mode through curfew | Guardian sees **No check-in yet**, never an accusation (rule 7) | screenshot of both phones |
| M5.5 | Teen checks in while offline, then reconnects | Queued check-in delivers in order; `outbox` empties; guardian updates | screenshot of debug state and guardian phone |
| M5.6 | Two offline check-ins, backend rejects the second | First delivers, second stays queued, nothing is lost | screenshot of debug state |
| M5.7 | Proxy the teen phone across a full night | Every payload has exactly `id, at, status, latitude, longitude, horizontalAccuracyMeters`; no result, no score, nothing about a Sober check | proxy log — retain it |
| M5.8 | Teen runs a Sober check and then checks in | The proxied payload is byte-for-byte the same shape as M5.2 | proxy log |
| M5.9 | Public `Sober` build on the same proxy | Zero Curfew requests, zero requests at all | proxy log |

## Verify on device

Every **verify** in the brief §5, with the code that assumes the answer. If
the device disagrees, the code changes, not the brief.

| # | Verify | Assumed by |
| --- | --- | --- |
| V1 | Whether `.child` authorization prevents the teen deleting the app without guardian approval | `Sober/Services/Curfew/ScreenTime/CurfewDeviceController.swift` (`requestAuthorization(for: .child)`); setup copy in `Sober/Features/Curfew/CurfewSetupView.swift` |
| V2 | Messages and Maps are not shielded by a category pause; Phone and emergency calls cannot be | `Sober/Services/Curfew/ScreenTime/CurfewShieldController.swift` (`shield.applicationCategories = .specific(_, except:)`); the "Always allow" picker in `Sober/Features/Curfew/CurfewSetupView.swift` |
| V3 | The minimum DeviceActivity interval (commonly 15 min) and the cap on monitored activities (commonly ~20) | `Sober/Services/Curfew/ScreenTime/CurfewActivityScheduler.swift` (`activities(for:)` registers one activity per hour after curfew); `CurfewSchedule.minimumRecheckMinutes` in `Sober/Models/CurfewContract.swift` |
| V4 | The monitor extension's memory limit (commonly cited ~6 MB) | `CurfewExtensions/Monitor/CurfewMonitorExtension.swift` and its `project.yml` sources (contract + `Services/Curfew/Core` + `ScreenTime` only; no DesignKit, no networking) |
| V5 | A local notification posted from the shield action extension deep-links into the check-in | `CurfewExtensions/ShieldAction/CurfewShieldActionExtension.swift`; `Sober/Services/Curfew/Core/CurfewNotifications.swift`; `CurfewPendingRoute` in `Sober/Services/Curfew/Core/CurfewSharedStore.swift`; the delegate in `Sober/Features/Curfew/CurfewCoordinator.swift` |
| V6 | The maximum Live Activity duration (commonly 8 hours) | `Sober/Services/Curfew/LiveActivity/CurfewLiveActivityController.swift` (`staleDate` and `Activity.request`); `CurfewPauseEvaluator.nightLengthMinutes` (7 h) in `Sober/Services/Curfew/Core/CurfewPauseEvaluator.swift` |

## Decide with Vinay

Open questions from the brief §11, verbatim. Raise them, don't decide alone.

- Can the teen see the exact pause list and schedule? (Recommended: yes, always.)
- What happens on a guardian's device if the teen revokes Family Sharing?
- Does "asked for a ride" also share live location until home, or one point?
- Legal review for location and face processing of 13–17-year-olds is still
  open — nothing ships to real families before it's done.

## Exit

Curfew exits when every milestone row has an artefact, every V row has an
answer written next to it, the Family Controls (Distribution) request is
approved, and legal review is closed. Anything unverified goes into the
release notes as a known limitation rather than being quietly assumed.
