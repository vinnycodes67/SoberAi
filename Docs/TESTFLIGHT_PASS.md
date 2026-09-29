# TestFlight pass — what works, what doesn't

One copy per build. Fill the result column on the device as you go; leave a row
blank only if you could not reach it, and say why. `PHASE_5_RELEASE_CHECKLIST.md`
is the release gate — this is the exploratory pass that feeds it.

## Build under test

| Field | Value |
| --- | --- |
| Marketing version / build | `1.0 (4)` |
| Archived from | `main` at or after `65b4ec9` |
| Date processed in App Store Connect | |
| iPhone model / iOS | |
| Tester / date | |

Everything in §2 should now be **fixed**. If a §2 row still reproduces, App Store
Connect served an older build and the rest of this document does not apply.

---

## 1. Not in a public build at all

`RootTabView` gives a public build three destinations — Home, History, Settings.
These are `INTERNAL_BUILD` only (`com.soberprototype.internal`), so their absence
is correct:

- Curfew — schedule, paused apps, check-in (Settings section and the whole flow)
- Circle tab, Circle map, Guardian Center
- Research Mode / Research Center
- Founder sample-result controls (`Preview changes detected` and friends)
- The pupil segmentation model (excluded from the public target)

**If any of these is reachable on TestFlight, stop the pass and say so.**
`APP_REVIEW_REHEARSAL.md` lists that as a submission stop condition, not a bug.
The local boundary gate passed on this archive, so reaching one would mean the
uploaded build is not the archive we checked.

Also expected, not broken: the guided gaze task needs a TrueDepth iPhone, and no
check returns a real comparison until five baseline sessions have been accepted.

---

## 2. Fixes that should now be in — confirm each one

Twenty-three commits landed between build `3` and build `4`. These are the
user-visible ones. Confirm the fix, not the bug.

| Confirm | Fixed by |
| --- | --- |
| The age gate cannot be passed by swiping past the profile step | `fd156b1` |
| Home/Settings ride wording matches whether a destination is actually carried | `fd156b1` |
| The ride link arrives with its destination intact, not double-encoded | `9e078c1`, `c2ad86d` |
| A baseline that failed to save does **not** report "Baseline recorded" | `773413e` |
| The Safety Circle label reads correctly | `773413e` |
| Home, History and Your Steady agree on the baseline thresholds | `1e6ebb1`, `8fae259` |
| The three accessibility defects from the design audit are gone | `4a0412e` |
| Safety Plan offers one-tap place names | `15ee0cc` |
| History marks baseline sessions that did not count | `a4a88bc` |
| Your Steady shows the protocol readiness counts | `436a2c3` |
| Home says when the last baseline session was not added | `066aa7f` |
| Row accessories stack at accessibility text sizes | `63057a4` |
| An iPhone with no Face ID runs a real check instead of always returning inconclusive | `b306982` |
| Reduced Motion readiness matches the baseline Your Steady shows | `codex/no-camera-engine` |
| The Safety Circle toggle is gone from the public build | `d824a3c` |
| Content clears the floating tab bar; nothing is cut in half | `d824a3c` |
| A camera-free session reads "without eye task", never "strong capture" | `5076810` |

---

## 3. The pass

Mark each row **works** / **broken** / **not reached**.

### A. Launch and onboarding

| # | What to do | Expected | Result |
| --- | --- | --- | --- |
| A1 | Delete the app, install from TestFlight, launch | Cold start lands on onboarding, under ~600ms to first screen | |
| A2 | Enter an under-18 age | Blocked, and the gesture cannot pass the gate either | |
| A3 | Make both consent choices | No copy claims diagnosis, BAC, sobriety, a pass, or clearance to drive | |
| A4 | Reach the camera prompt | The iOS prompt shows the `NSCameraUsageDescription` text about landmarks not being saved | |

### B. Home

| # | What to do | Expected | Result |
| --- | --- | --- | --- |
| B1 | Land on Home with zero baselines | **Record a baseline session** is the live action | |
| B2 | Look for the get-home action | **Get home** is available with no baseline | |
| B3 | Before a live check → **How results work** | Says *No result is a green light*; shows Changes detected / No clear read / No changes detected, labelled as examples | |
| B4 | Close the examples | History still empty, baseline still zero | |
| B5 | Finish one session, return to Home | Counter moves, and the wording about what five sessions unlock is accurate | |
| B6 | Finish a session that does not count | Home says the last session was not added | |

### C. A baseline session (needs a TrueDepth iPhone)

| # | What to do | Expected | Result |
| --- | --- | --- | --- |
| C1 | Attestation step | Honest-attempt question, no skip | |
| C2 | Environment / camera calibration | Framing and lighting guidance, then proceeds | |
| C3 | Reaction task | "Match the color and shape" — targets appear, taps register | |
| C4 | Tracking task | "Trace the current" — the path follows your finger; skip action says the result will be inconclusive | |
| C5 | Timing task | "Hold ten seconds in your head" — timer stays hidden, Stop records | |
| C6 | Guided gaze task | Face tracking acquires and the gaze target is followed | |
| C7 | Analyzing → result | A state and a message, no crash, no spinner that never ends | |
| C8 | Baseline complete screen | Says recorded **only** if it actually saved | |
| C9 | Run one in low light, and one wearing glasses | "Capture quality was too low" rather than a silent bad session | |
| C10 | Background the app mid-task, come back | Interrupted-task screen, no data loss, no crash | |
| C11 | Deny camera in iOS Settings, start a check | A clear denied path with a route to Settings, not a dead end | |

### C2. On an iPhone with no Face ID (or a simulator)

| # | What to do | Expected | Result |
| --- | --- | --- | --- |
| C2-1 | Start a check | No camera setup screen at all | |
| C2-2 | Work through it | Reaction, tracking and timing only; no eye task | |
| C2-3 | Finish five of them | They count; Home reaches "Ready when you are" | |
| C2-4 | Run a check | A real state, not a permanent "No clear read" | |
| C2-5 | Open History | Rows read "without eye task", never a capture band | |
| C2-6 | Open the result | Capture quality reads "Not measured", not a percentage | |
| C2-7 | Open Your Steady | Recorded with "Without eye task" | |

### D. After five accepted sessions

| # | What to do | Expected | Result |
| --- | --- | --- | --- |
| D1 | Open Your Steady | Shows a measured baseline and the protocol readiness counts | |
| D2 | Run a check | Returns one of the three states against your own baseline | |
| D3 | Turn on Reduce Motion, then check readiness vs Your Steady | The profile shown matches the variant readiness was scored against — **AADI 6 is still open**, so a mismatch here is expected, not new | |

### E. History

| # | What to do | Expected | Result |
| --- | --- | --- | --- |
| E1 | Open History on a clean install | "Nothing recorded yet" | |
| E2 | After sessions | Entries appear, newest first, with readable summaries | |
| E3 | After a session that did not count | Marked as not counted | |

### F. Safety Plan and get home

| # | What to do | Expected | Result |
| --- | --- | --- | --- |
| F1 | Set a destination, ride app and contact | All three save and survive a relaunch | |
| F2 | One-tap place names | Present and they fill the destination | |
| F3 | Tap the ride link | Opens the ride app, and the destination actually arrives | |
| F4 | Tap call / message | Opens with the contact and prefilled text | |
| F5 | Read the wording around the ride | Matches whether the destination is genuinely carried | |

### G. Settings and privacy

| # | What to do | Expected | Result |
| --- | --- | --- | --- |
| G1 | Turn on Privacy Lock | History, Your Steady and Settings gate behind Face ID | |
| G2 | Swipe to the app switcher while locked | Privacy shield covers the snapshot | |
| G3 | **What Sober stores** | Camera row reflects real permission; Location / Notifications / Contacts all read "Not used" | |
| G4 | Privacy policy and support links | Both open without a sign-in | |
| G5 | Version row | Reads `1.0 (4)` | |
| G6 | **Delete all local data**, relaunch | Onboarding returns; no baseline, History or Safety Plan survives | |

### H. Robustness and accessibility

| # | What to do | Expected | Result |
| --- | --- | --- | --- |
| H1 | Repeat the whole journey in airplane mode | No network error, no waiting spinner | |
| H2 | Low Power Mode | No behavioural change | |
| H3 | Update over an existing install | Baseline and History survive | |
| H4 | Reinstall | Clean state, nothing orphaned | |
| H5 | Largest accessibility text size | Nothing clipped; row accessories stack | |
| H6 | VoiceOver on the result screen and History rows | Every element announced, in a sensible order | |

---

## 4. Report back

- Build tested, device, iOS.
- Rows from §3 that came back **broken**, with a screen recording each.
- Anything from §1 that was reachable — that is a P0.
- Any §2 row that still reproduces, which means App Store Connect served an
  older build than `1.0 (4)`.
