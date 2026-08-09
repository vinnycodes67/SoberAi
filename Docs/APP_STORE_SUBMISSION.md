# App Store submission package

Every answer here is written against the public `Sober` Release artifact, not
against the plan. `Scripts/check-public-binary.sh` re-derives the machine-checkable
ones from the binary on every run, so this document cannot quietly drift from
what ships.

Rows marked **DECISION** need the founder. Rows marked **COUNSEL** need a
qualified lawyer. Nothing here should be submitted until those are filled in.

## What the artifact actually is

Read off the Release build:

| Fact | Value | Source |
| --- | --- | --- |
| Permissions declared | Camera only | `Info.plist` |
| Location | Not declared, not linked | boundary scan |
| Notifications | Not declared | boundary scan |
| Background modes | None | boundary scan |
| Network endpoints | None configured | boundary scan + `NoNetworkInPublicBuildTests` |
| Third-party SDKs | None | boundary scan, no `Frameworks/` |
| Privacy manifest | Present, no tracking, no collected data | `PrivacyInfo.xcprivacy` |
| Required-reason APIs | `UserDefaults` (CA92.1) | privacy manifest |
| Account system | None | there is no sign-in |
| Deployment target | iOS 17 | `project.yml` |
| Devices | iPhone only | `TARGETED_DEVICE_FAMILY = 1` |

## App Privacy questionnaire

**Answer: "Data Not Collected".**

Apple defines collection as transmitting data off the device. Sober transmits
nothing: there is no account, no analytics, no crash reporter, no third-party
SDK, and the only networking code in the app belongs to Guardian, which is not
compiled into a reachable route in v1 and has no configured endpoint.

That answer is only true while it is true. If anything is ever transmitted —
crash reporting included — the questionnaire, `PrivacyInfo.xcprivacy`, and the
in-app Privacy Centre all change together. The boundary scan fails the build if
the manifest starts declaring collected data, which is the tripwire for
remembering the other two.

**Stored on device, and therefore not "collected":** the measured baseline,
check history (90 days / 100 entries, whichever binds first), the Safety Plan,
and the name and age given at onboarding.

**Never stored at all:** camera frames. Face and eye landmarks are processed in
memory during a task and discarded. No image, video, or audio is written to disk
or transmitted.

## Age rating

**DECISION.** The questionnaire asks about alcohol, tobacco, and drug references.
Sober's entire subject is impairment after drinking, so "Infrequent/Mild" is not
defensible — answer honestly and accept the rating that follows.

Do not attempt to rate this 4+. An app about deciding whether you are too
impaired to drive that carries a children's rating is a worse outcome than a
17+ badge.

## Category

**DECISION.** Currently `public.app-category.healthcare-fitness`.

Health & Fitness routes the app to the review team most likely to apply
medical-device scrutiny, to an app that explicitly disclaims being a medical
device, a BAC estimator, or a diagnostic. It also raises the bar on every claim
in the description.

Utilities or Lifestyle describes what this actually is — a private self-check
and a way home — without inviting that reading. Confirm with counsel before
changing, since category and claims interact.

## Metadata

**Name:** Sober

**Subtitle (30 chars max):** `A private check, and a ride`  *(27)*

**Promotional text:** DECISION — leave empty for v1 rather than making a claim
that outruns the product.

**Description draft:**

> Sober is a private check you run on yourself, and a way home.
>
> Over your first few sober sessions, Sober learns your steady — your own usual
> range across reaction, coordination, timing, and guided gaze. After that, a
> short check compares you to that range and tells you one of three things: it
> found changes, it could not get a reliable reading, or it found no changes.
>
> There is no fourth answer. Sober will never tell you that you are sober, that
> you passed, or that it is safe to drive, because a two-minute check on a phone
> cannot know that. The absence of a signal is not evidence that you are fine.
>
> A ride and a trusted contact stay one tap away from every result, and from the
> home screen, whether or not you have run a check.
>
> Everything stays on your iPhone. There is no account, nothing is uploaded, and
> the app makes no network connections at all. Camera frames are used to find
> your eyes during a task and are never saved.
>
> Sober is not a medical device, a breathalyser, or a blood alcohol estimate. It
> cannot diagnose impairment. If you are unsure, do not drive.

**Keywords:** DECISION — avoid "breathalyzer", "BAC", "sobriety test", "drunk
test". Each is a claim the product refuses to make, and buying traffic on them
sets up exactly the misunderstanding the three-state design exists to prevent.

**Support URL / Privacy Policy URL:** DECISION — both required, neither exists.

## Review notes

Draft for App Review. The reviewer needs to reach a result without a baseline
and without drinking.

> **What this app does.** Sober measures reaction time, motor tracking, time
> estimation, and guided eye movement, then compares them to the same person's
> own earlier sober sessions. It reports one of exactly three states: signals
> detected, inconclusive, or no signals detected. There is deliberately no
> "pass" or "safe to drive" state anywhere in the app.
>
> **Not a medical device.** Sober does not estimate blood alcohol, diagnose
> impairment, or clear anyone to drive. The onboarding, the result screen, and
> the App Store description all say so.
>
> **TrueDepth camera.** The guided gaze task needs the front camera to locate
> eye and face landmarks. Frames are processed in memory and never saved or
> transmitted. Camera access is requested at the point of use, and declining it
> produces an inconclusive result with the ride and contact actions still
> available — it never blocks the app.
>
> **Baseline ramp.** A comparison needs five accepted sober sessions. Before
> that the app will not produce a comparison verdict; it says so and still
> offers the get-home actions. This is deliberate: inventing a verdict without a
> reference is the failure mode the design exists to prevent.
>
> **Reviewing without a baseline.** REVIEW PATH — see below.
>
> **No account, no network.** There is no sign-in and no server. The app makes
> no network requests. Nothing needs to be provisioned to review it.

**REVIEW PATH — DECISION, and a P0 blocker.**

There is currently no way for a reviewer to see a result. They would have to
complete five sober baseline sessions before a check does anything, on a device
in a review lab. The plan already calls for "static How results work examples"
with clearly labelled sample data, and that item is still open from Phase 1. It
is now on the critical path for submission, not a nice-to-have.

The internal build's founder previews are the wrong answer — they are compiled
out of public builds on purpose, and shipping them back for review would undo
the boundary.

## Export compliance

**DECISION.** The binary links CryptoKit. Guardian's P-256 signing is compiled
in but unreachable and unconfigured in v1.

Most likely answer: uses encryption, but only exempt encryption (standard
platform cryptography, no proprietary implementation). Confirm before checking
the box — a wrong answer here is a false statement to a government, not a
metadata mistake.

## Accessibility Nutrition Label

Answer from what is actually tested, not from intent.

| Feature | Status | Evidence |
| --- | --- | --- |
| VoiceOver | Partial | controls named and stateful; full-journey pass is a device gate (A1) |
| Larger Text | Yes | primary action and tab bar verified at AX5 in `AccessibilityUITests` |
| Reduce Motion | Yes | honoured throughout; verified startable in UI tests |
| Sufficient Contrast | Yes | palette contrast measured and documented in `DSPalette` |
| Captions / Audio | N/A | no audio content |

Do not claim full VoiceOver support until gate A1 is recorded on a device.

## Screenshots

Blocked until the visual and copy freeze. Constraints:

- Only real states. No mocked verdicts, no invented numbers.
- Never show a result in a way that implies clearance. "No signals detected"
  needs its full caption or it reads as a pass.
- Include the get-home surface — it is the day-one value.
- Include Your Steady before it is established. The honest incomplete state is
  part of the pitch, not a flaw to hide.

## Pre-submission checklist

Run `Scripts/check-public-binary.sh` first; it covers rows 1–5 automatically.

- [ ] Public Release artifact: no internal routes, permissions, or endpoints
- [ ] Privacy manifest present, no tracking, no collected data
- [ ] No embedded third-party frameworks
- [ ] Camera usage string present and accurate
- [ ] Version and build incremented
- [ ] Category decided **DECISION**
- [ ] Age rating answered honestly **DECISION**
- [ ] Export compliance answered **DECISION**
- [ ] Support and privacy policy URLs live **DECISION**
- [ ] Reviewer can reach a result without a baseline **P0, open**
- [ ] Medical-claim review complete **COUNSEL**
- [ ] Device gates in `PHASE_4_DEVICE_GATES.md` recorded
- [ ] Description contains no forbidden claim from the plan's claims matrix
