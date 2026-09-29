# Sober — what works and what does not

Written against `65b4ec9` on `main`. Supersedes the 2026-09-20 revision, which
predated the camera-free check.

## How this was checked

| Method | Result |
| --- | --- |
| `xcodebuild test`, unit suite | **261 / 261 pass**, 0 failures |
| `xcodebuild test`, `JourneySmokeUITests` | **10 / 10 pass**, 0 failures |
| `Scripts/check-release-metadata.sh` | pass |
| `Scripts/check-public-binary.sh` | pass |
| `Scripts/rehearse-app-store-package.sh` | pass, unsigned archive |
| `node --test Scripts/tests/release-ops.test.mjs` | 18 / 18 |
| iPhone 17 simulator, iOS 27 | app states launched and screenshotted |
| Source audit | every feature traced from UI to the value it reads |

**Still not checked, and not checkable here:** anything needing a TrueDepth
iPhone, and TestFlight itself. This Mac has no distribution certificate, no
provisioning profile, no Apple account in Xcode and no App Store Connect API key.

---

## Fixed since the last revision

| Was | Now |
| --- | --- |
| Phones with no TrueDepth camera could never produce a result: no baseline session counted and every check came back inconclusive | They skip the camera screens, run reaction, tracking and timing, and score against a `.noCamera` baseline that never mixes with camera sessions |
| Reduced Motion could reach "ready" while Your Steady showed an empty baseline (`AADI 6`) | `baselineProfile` follows the partition actually driving readiness instead of being hardwired to `.full` |
| The Safety Circle toggle was wired to nothing in the public build (`VINAY 8`) | `#if INTERNAL_BUILD`; the public build no longer shows a control that does nothing |
| The floating tab bar covered content; text was cut in half on Home and Settings | Opaque backdrop and clearance, with `TabBarClearanceUITests` guarding it |
| A camera-free session stored a gaze figure of 0 and a capture score of 1.0, so History said "strong capture" and the result screen said "100%" about a recording that never happened | Stores `nil` / `0`; History reads "without eye task" and the result screen "Not measured". The engine drops gaze for a `.noCamera` partition structurally |

---

## Works — confirmed running

| Area | Evidence |
| --- | --- |
| Install, launch, app icon | Clean simulator install launches to onboarding |
| Onboarding | Four steps; age gate blocks under 13 and the gesture shares the gate |
| Home, zero baselines | "Learn your steady", "0 of 5 baseline sessions recorded", five empty pips |
| Home, measured baseline | "Ready when you are", **Start Sober check**, five filled pips |
| Camera-free check | Skips camera setup, runs three tasks, scores against its own baseline |
| Get Home row | "Uber to Home" with the contact chip when a plan exists |
| Public tab bar | Home / History / Settings only, with content clearing the bar |
| History | Empty state, populated rows, All/Baseline/Checks filter, capture band or "without eye task", "not added" marker |
| History retention | 90 days and 100 entries, pruned on every write |
| Settings | Every row present; Version reads the shipped build |
| Safety Plan | Destination, ride picker, one-tap place names, contact fields |
| Privacy Lock | Real `LAContext` authenticator, snapshot shield, per-tab gate |
| Result education | Three states as labelled examples that record nothing |
| Public/internal boundary | No FamilyControls, ManagedSettings, DeviceActivity, ActivityKit, no embedded extension, no telemetry SDK |
| Archived permissions | Camera and Face ID only |

---

## Does not work

### 1. A new person still needs five sessions before any real result

A check returns a real comparison only after five accepted baseline sessions.
That is now reachable on hardware with no TrueDepth camera, which it was not
before, but it is still five sessions. There is no reviewer or sample path to a
genuine result: `VINAY 1` was rejected as scoped and has not been rebuilt, and
the seeded-baseline launch arguments are `#if DEBUG` only.

### 2. Nothing in the measurement path has run on real hardware

`SHREY 1` and `SHREY 2` remain open. Guided gaze, capture quality scoring,
low-light and glasses behaviour have never been exercised on a physical iPhone.
Everything known about them comes from tests against synthetic input.

### 3. Guardian and Circle are non-functional

`GuardianAPIClient` reads `SoberGuardianAPIURL`, which the public Info.plist does
not define, so every request fails closed. Circle, the map and Guardian Center
are `INTERNAL_BUILD` only.

### 4. Curfew is internal-only and device-gated

Excluded from the public target. Only the contract, evaluator and App Group store
compile publicly. The real feature needs Screen Time entitlements and a device.

### 5. Research Mode is internal-only

Export and deletion are wired, behind `INTERNAL_BUILD`.

### 6. The decision threshold is not calibrated

`VINAY 2` / `SHREY 5`. The thresholds now have one definition, which was the
prerequisite; choosing the number still needs real measurements.

### 7. TestFlight delivery is blocked on credentials

No signing identity, profile, Xcode account or API key on this Mac. Needs account
authority on team `CPRVLR97XJ`. `Scripts/upload-testflight.sh` is ready for the
moment credentials exist.

---

## Unverified either way

- Ride handoff to Uber or Lyft with a real destination
- Face ID Privacy Lock on real hardware
- Update-over-install preserving baseline and History
- Airplane-mode journey
- Cold-start budget on a real device
- The UI suites other than `JourneySmokeUITests`
