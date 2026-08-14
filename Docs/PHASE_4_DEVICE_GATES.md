# Phase 4 — device and TestFlight gates

Phase 4's exit gate is "every manual launch gate has retained evidence". This is
that checklist. It covers only what a simulator cannot answer; everything a
machine can check already runs in CI.

Record each row in a copy of this file per build: build number, commit, device,
OS, outcome, and a screenshot or recording. A gate with no artefact is not
passed, it is unrecorded.

## What is already automated

Do not re-test these by hand. They gate every commit.

| Gate | Where |
| --- | --- |
| Public build exposes no internal route, permission, or relay config | `Scripts/check-public-binary.sh` + `PublicBoundaryUITests` |
| Founder preview cannot fabricate a baseline | `AppModelTests` |
| Stimulus is not reachable from the theme | `StimulusIsolationTests` |
| History retention and deletion | `CheckHistoryTests` |
| Interrupted timed tasks discard their reading | `InterruptionPolicyTests` |
| Primary action and tab bar survive AX5 | `AccessibilityUITests` |
| All four scheme/configuration builds | CI `builds` |

## Blocked on credentials or hardware

None of this can start until someone provides what is listed.

| Blocker | Needed for | Owner |
| --- | --- | --- |
| Apple Developer Program membership and Team ID | Any signed device build, TestFlight | Founder |
| A TrueDepth iPhone | Every camera gate below | Founder |
| A currently supported non-TrueDepth iPhone | Limited-capture fallback and honest compatibility disclosure | Founder |
| A second iPhone | Nothing in v1 — Guardian is v1.1 | — |
| Privacy policy URL and support URL | External TestFlight and submission | Founder + counsel |
| Legal/regulatory determination | External TestFlight recruiting | Counsel |

## Camera and capture

The simulator has no TrueDepth camera. It proves that the limited-capture
control is reachable, but not how the fallback behaves on physical unsupported
hardware. Every physical row here is unverified today, and the ocular protocol
is the app's least-proven surface.

| # | Case | Expected | Evidence |
| --- | --- | --- | --- |
| C0 | Check on a supported iPhone without TrueDepth | Limited-capture action remains reachable; result is inconclusive; safety actions remain available | recording |
| C1 | Calibration in good light | All six tiles reach ready; button enables after the hold | screenshot |
| C2 | Calibration in a dim room | Specific guidance names light; button stays disabled | screenshot |
| C3 | Face too close, then too far | Distance tile drives the guidance | screenshot |
| C4 | Off-centre face | Centering tile drives the guidance | screenshot |
| C5 | Glasses | Capture still reaches usable quality, or says why not | screenshot |
| C6 | Full 25s gaze protocol | Completes; sample count and frame rate plausible | recording |
| C7 | Look away mid-protocol for 4s | Capture-loss recovery appears, offers camera setup again | recording |
| C8 | Look away for 1s | Nothing appears; capture continues | recording |
| C9 | Camera permission denied at first prompt | Routes to inconclusive with safety actions, no prompt loop | screenshot |
| C10 | Permission revoked in Settings mid-session | Handled without a crash | recording |

> C7 and C8 are the two sides of the escalation threshold. If C8 raises the
> recovery screen, the threshold is too aggressive and the check becomes
> unusable in normal conditions.

## Interruption

Wall-clock measurement means these decide whether a result is trustworthy.

| # | Case | Expected | Evidence |
| --- | --- | --- | --- |
| I1 | Incoming call during the reaction task | Reading discarded; interruption screen names the task | recording |
| I2 | Notification pulled into during the timing task | Same | recording |
| I3 | Screen locks mid-gaze | Same | recording |
| I4 | Backgrounded during calibration | Nothing appears; calibration resumes | recording |
| I5 | Backgrounded on the result screen | Result still there on return | screenshot |
| I6 | Redo after an interruption | Task restarts from the beginning, no partial state | recording |
| I7 | Force quit mid-check | No partial session in History | screenshot |

> I4 and I5 are the negative cases. Raising a recovery screen where nothing was
> running would make every notification feel like a crash.

## Baseline and result integrity

| # | Case | Expected | Evidence |
| --- | --- | --- | --- |
| B1 | Five genuine sober baseline sessions | Home moves to ready; Your Steady draws a real range | screenshots |
| B2 | A deliberately poor-quality session | Excluded, and the exclusion is explained | screenshot |
| B3 | A check while sober, after B1 | Any of the three states; never the word safe, pass, or cleared | screenshot |
| B4 | Reduced Motion baseline, then a full-protocol check | Variants do not cross-contaminate | screenshots |
| B5 | Delete all local data | History, Steady, and Safety Plan all gone | screenshot |
| B6 | Relaunch after B5 | Onboarding, zero sessions, no residue | screenshot |

## Accessibility on device

Automated coverage asserts the load-bearing controls survive AX5. A person still
has to use it.

| # | Case | Expected | Evidence |
| --- | --- | --- | --- |
| A1 | Whole flow with VoiceOver | Every control reachable and named; task instructions announced | recording |
| A2 | Whole flow at AX5 | Nothing clipped; primary action always reachable | screenshots |
| A3 | Reduce Motion | No large or spatial animation; function unchanged | recording |
| A4 | Increase Contrast and Bold Text | Legible; no colour-only state | screenshots |
| A5 | The check one-handed, at night, outdoors | Usable; this is the actual context | notes |
| A6 | Smallest supported iPhone | No clipping or truncation | screenshots |

> A5 has no pass/fail. Write down what was awkward.

## Connectivity

Public v1 makes no network requests. These prove that claim rather than assume
it.

| # | Case | Expected | Evidence |
| --- | --- | --- | --- |
| N1 | Airplane mode, whole journey | Everything works, no error, no spinner | recording |
| N2 | Airplane mode from first launch | Onboarding and baseline work | recording |
| N3 | Charles or a proxy across a full session | Zero outbound requests from the public build | proxy log |

> N3 is the strongest evidence for the App Privacy answers. Retain the log.

## External actions

| # | Case | Expected | Evidence |
| --- | --- | --- | --- |
| E1 | Ride app installed | Opens with the destination | recording |
| E2 | Ride app not installed | Falls back without a dead end | recording |
| E3 | Call and message from a result | Both open prefilled | screenshots |
| E4 | Cancel out of the call sheet | Returns to the result intact | recording |

## Lifecycle

| # | Case | Expected | Evidence |
| --- | --- | --- | --- |
| L1 | Cold start | Under the 600ms launch budget to first screen | recording |
| L2 | Low Power Mode | No behavioural change | notes |
| L3 | Low memory during a check | No data loss or crash | recording |
| L4 | Update over an existing install | Baseline and History survive | screenshots |
| L5 | Reinstall | Clean state, no orphaned files | screenshot |

## TestFlight

| # | Case | Expected |
| --- | --- | --- |
| T1 | Internal group, every gate above | Zero open P0 |
| T2 | Crash-free sessions | 99.5% or better before submission |
| T3 | Abandonment during the check | Where and why, recorded |
| T4 | Inconclusive rate and reasons | Broad technical reason only |
| T5 | External group | Only after privacy and legal approval |

## Exit

Phase 4 exits when every row above has an artefact, no P0 is open, no high-risk
P1 is open, and T2 is met. Anything unverified goes to the submission notes as a
known limitation rather than being quietly assumed.
