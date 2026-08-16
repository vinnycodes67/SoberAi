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
| Permissions declared | Camera; optional system authentication for Privacy Lock | `Info.plist` |
| Location | Not declared or initialized in public runtime; deferred Guardian source still links Core Location | boundary scan + launch log |
| Notifications | Not declared | boundary scan |
| Background modes | None | boundary scan |
| Network endpoints | No Sober endpoint configured; ride/call/message actions open only after a tap | boundary scan + `NoNetworkInPublicBuildTests` |
| Third-party SDKs | None | boundary scan, no `Frameworks/` |
| Privacy manifest | Present, no tracking, no collected data | `PrivacyInfo.xcprivacy` |
| Required-reason APIs | `UserDefaults` (CA92.1), system boot time (35F9.1) | privacy manifest |
| Account system | None | there is no sign-in |
| Deployment target | iOS 17 | `project.yml` |
| Devices | iPhone only; live guided gaze requires compatible TrueDepth face tracking | `TARGETED_DEVICE_FAMILY = 1` + capture implementation |
| Experimental pupil model | Excluded from public; retained in `SoberInternal` | target source exclusion + boundary scan |

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
and the optional name and age given at onboarding. Depending on the person's
Apple settings, iOS may include app-container data in an iCloud or computer
backup. Sober does not receive or control those backups, so this does not turn
the data into developer collection, but the in-app and web privacy policies
disclose the backup behavior and the limits of in-app deletion.

**Never stored at all:** camera frames. Face and eye landmarks are processed in
memory during a task and discarded. No image, video, or audio is written to disk
or transmitted.

## Age rating

**DECISION.** Complete Apple's current age-rating questionnaire against the
submitted build. Sober's entire subject is impairment after drinking, so the
alcohol-reference answers must describe the real frequency and prominence of
that content. Accept the computed regional ratings, then use Apple's higher
rating override if founder and counsel decide the computed result understates
the product's context. Do not hard-code an old single-number expectation:
Apple's current ratings can vary by operating system version and region.

An unrated app cannot be published. Record the completed questionnaire and the
regional result in `PHASE_5_RELEASE_CHECKLIST.md`.

## Category

**DECISION.** Currently `public.app-category.healthcare-fitness`.

Health & Fitness routes the app to the review team most likely to apply
medical-device scrutiny, to an app that explicitly disclaims being a medical
device, a BAC estimator, or a diagnostic. It also raises the bar on every claim
in the description.

Utilities or Lifestyle may describe what this actually is — a private
self-check and a way home — without inviting that reading. Confirm with counsel
before changing, since category and claims interact. If Health & Fitness is
kept, also answer App Store Connect's regulated-medical-device status honestly;
the app currently disclaims that status and has no validation supporting a
medical-device claim.

## Metadata

**App Store name:** `Sober.` The founder confirmed the reserved App Store name
with the trailing period for v1. The installed display name remains `Sober`.

**Subtitle (30 chars max):** `A private check, and a ride`  *(27)*

**Promotional text:** Leave empty for v1. Founder-approved August 15, 2026.

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
> The guided-eye task requires a TrueDepth-capable iPhone. On an unsupported
> iPhone, Sober labels the camera capture as limited and returns no clear read;
> it does not invent a comparison from missing camera data.
>
> There is no account, and the public app has no configured Sober server.
> Measurements and camera frames are never uploaded to Sober. Camera frames are
> used to find your eyes during a task and are never saved. Other app data may be
> included in an iCloud or computer backup according to your Apple settings.
>
> Sober is not a medical device, a breathalyser, or a blood alcohol estimate. It
> cannot diagnose impairment. If you are unsure, do not drive.

**Keywords:** `personal safety,reaction time,coordination,ride home,private check,safety plan,steady`

Continue to avoid "breathalyzer", "BAC", "sobriety test", and "drunk test".
Each is a claim the product refuses to make, and buying traffic on them sets up
exactly the misunderstanding the three-state design exists to prevent.

**Support URL:** `https://vinnycodes67.github.io/SoberSupport/`

**Privacy Policy URL:** `https://vinnycodes67.github.io/SoberSupport/privacy.html`

The founder confirmed `pulavarthyvinay@gmail.com` as the monitored public
support address. The hosted copy and in-app policy must change together.

**Copyright:** `2026 Ravi Pulavarthy`

**Pricing and initial availability:** Free; United States only. Expand territory
availability only after the corresponding legal, age-rating, and DSA review.

## Review notes

Draft for App Review. The reviewer needs to reach a result without a baseline
and without drinking.

> **What this app does.** Sober measures reaction time, motor tracking, time
> estimation, and guided eye movement, then compares them to the same person's
> own earlier sober sessions. It reports one of exactly three states: changes
> detected, no clear read, or no changes detected. There is deliberately no
> "pass" or "safe to drive" state anywhere in the app.
>
> **Not a medical device.** Sober does not estimate blood alcohol, diagnose
> impairment, or clear anyone to drive. The onboarding, the result screen, and
> the App Store description all say so.
>
> **TrueDepth camera.** The guided gaze task needs compatible TrueDepth face
> tracking to locate eye and face landmarks. Frames are processed in memory and never saved or
> transmitted. Camera access is requested at the point of use, and declining it
> produces an inconclusive result with the ride and contact actions still
> available — it never blocks the app. On hardware without TrueDepth, the same
> limited-capture path is available and the result is inconclusive.
>
> **Baseline ramp.** A comparison needs five accepted sober sessions. Before
> that the app will not produce a comparison verdict; it says so and still
> offers the get-home actions. This is deliberate: inventing a verdict without a
> reference is the failure mode the design exists to prevent.
>
> **Reviewing without a baseline.** Finish onboarding, then on Home open
> **How results work** under **Before a live check**. This public, read-only
> page shows the exact names and safety explanation for all three result states.
> It is explicitly labelled as examples, invokes neither camera nor scorer, and
> does not create History or baseline data. Tap **Done** to return Home.
>
> **No account or configured Sober server.** There is no sign-in, server setup,
> analytics SDK, or review credential. Ride, call, and message links open only
> after the reviewer taps them.

**REVIEW PATH — implemented locally; clean-device evidence still required.**

The public Home screen now exposes **How results work** before a baseline exists.
Release-binary checks require its safety and sample-data disclosures, and UI
coverage asserts that opening and closing it leaves the baseline at zero and
History empty. The internal build's founder previews remain compiled out of
public navigation; they are not the App Review path.

`ReviewerPathUITests` also enforces the claims matrix on this screen: all three
states present, every card labelled as an example, and no clearance claim
anywhere. It is the surface most likely to drift toward reassurance, and the
check allows a negated mention because "no result is a green light" is the
point of the page.

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

Use between 1 and 10 screenshots per required display size. For a 6.9-inch
iPhone portrait set, App Store Connect currently accepts 1260×2736, 1290×2796,
or 1320×2868 pixels. Capture the highest-resolution source available and let
App Store Connect scale it only where Apple permits. The proposed five-frame
story is:

1. Home: private check plus immediate get-home action.
2. How results work: the three-state, no-green-light explanation.
3. Live task instruction or calibration on a physical TrueDepth iPhone.
4. One real result with its complete safety limitation visible.
5. Privacy Center or incomplete Your Steady state.

Creative export is blocked until the visual/copy freeze and physical-device
capture. Constraints:

- Only real states. No mocked verdicts, no invented numbers.
- Never show a result in a way that implies clearance. "No changes detected"
  needs its full caption or it reads as a pass.
- Include the get-home surface — it is the day-one value.
- Include Your Steady before it is established. The honest incomplete state is
  part of the pitch, not a flaw to hide.
- Do not use internal founder previews as public screenshots.

## Pre-submission checklist

Run `Scripts/rehearse-app-store-package.sh` first; it creates an unsigned device
archive and re-runs the public artifact checks. Then complete the signed and
App Store Connect gates in `PHASE_5_RELEASE_CHECKLIST.md`.

- [x] Local public Release artifact: no internal routes, permissions, or endpoints
- [x] Privacy manifest present, no tracking, no collected data
- [x] No embedded third-party frameworks
- [x] Camera and Face ID usage strings present and accurate
- [x] Public read-only result education path implemented
- [x] Experimental pupil model, fifth measure, and UI-test harness excluded from public Release
- [x] Deploy-ready support and privacy pages match public data handling
- [ ] Version and build incremented
- [ ] Category decided **DECISION**
- [ ] Age rating answered honestly **DECISION**
- [ ] Export compliance answered **DECISION**
- [ ] Support and privacy policy URLs live **DECISION**
- [x] Reviewer can reach an explanation of results without a baseline
- [ ] Medical-claim review complete **COUNSEL**
- [ ] Device gates in `PHASE_4_DEVICE_GATES.md` recorded
- [x] Description contains no forbidden claim from the plan's claims matrix
- [ ] Signed archive validated, uploaded, and processed in App Store Connect

## Official Apple references

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
