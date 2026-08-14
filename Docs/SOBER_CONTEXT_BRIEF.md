# Sober — context brief

Written to be pasted into a conversation with an assistant that has no access to
this repository. Everything here was verified against the tree at commit
`486a790`, not recalled.

---

## What Sober is

A native iOS app. Someone who has been drinking runs a short private check on
themselves and gets one of three answers, plus a way home.

It is **not** a breathalyser, a BAC estimate, a medical device, or a
safe-to-drive decision. That is not a disclaimer bolted on — it is the
constraint the whole product is built around.

**How it works.** Over five sober sessions the app learns that person's usual
range across four measures: reaction time, motor tracking, time estimation, and
guided eye movement. After that, a two-minute check compares them against *their
own* range — never against other people, and never combining measures into a
single score.

**Three results, and only three:**

| State | Copy shown |
| --- | --- |
| `signalsDetected` | "Changes detected — This check found changes outside your usual range. Don't drive." |
| `inconclusive` | "No clear read — We couldn't get a clear read. If you've had anything, don't drive." |
| `noSignalsDetected` | "No changes detected — This check did not find changes. It cannot establish sobriety or driving safety." |

There is deliberately no fourth state. No pass, no green, no cleared, no "you're
sober". A ride and a trusted contact are one tap from every result and from the
home screen, whether or not a check has been run.

---

## The rules that must not be broken

These are enforced by tests, not just documented. If you are asked to change
something and it collides with one of these, stop and say so.

1. **No clearance state.** The absence of a signal is not evidence of sobriety.
   Any copy implying otherwise is a defect.
2. **Refuse rather than guess.** Bad capture, an incomplete task, or a
   self-reported drink produces `inconclusive`, never a score.
3. **An unmeasured thing is never "normal".** A measure that could not be read
   is excluded, not counted as fine.
4. **A baseline is measured sessions or it does not exist.** Nothing may
   fabricate readiness.
5. **The stimulus is instrument calibration, not design.** Colours, sizes, and
   timing of the reaction/tracking/gaze targets live in `StimulusPalette` and
   are pinned by tests. Changing them invalidates every stored baseline.
6. **Nothing leaves the device.** No account, no analytics, no crash SDK, no
   third-party SDKs, zero network calls in the public build.
7. **A result is not evidence.** It cannot be shared or exported as proof, and
   the app says so — someone can be pressured to run a check and show it.

---

## Architecture

- **Swift 6 / SwiftUI**, iOS 17 deployment target, iPhone only, dark only.
- **XcodeGen** — `project.yml` is the source of truth; `.xcodeproj` is
  generated. Run `xcodegen generate` after adding files.
- **Two app targets**, and this matters:
  - `Sober` — the public App Store build.
  - `SoberInternal` — separate bundle ID, defines `INTERNAL_BUILD`, carries
    Guardian, Circle Map, the Research Center, and founder result previews.

  The split is **compile-time** (`#if INTERNAL_BUILD`), not a runtime flag. A
  script scans the shipped Release binary to prove internal route copy is absent.
- **No backend in v1.** A Cloudflare Worker exists for Guardian, which is v1.1.
- **DesignKit** (`Sober/DesignKit/`) is the visual system: matte near-black, one
  orange meaning *attention only*, Satoshi type, tokens for every dimension, no
  gradients or glows. Legacy components (`SoberCard`, `ScreenHeader`, …) now
  delegate to their DesignKit equivalents so there is one implementation each.

**Public screens:** Onboarding → Home / History / Settings (tab bar) → the check
journey (self-report → camera calibration → reaction → tracking → timing → gaze
→ analysing → result), plus Your Steady, Privacy Center, and How Results Work.

---

## Current state

`main` is in sync with `origin/main`. Verified green:

- **156 unit tests**, 14 files
- **29 UI tests**, 5 files (1 skips — the simulator has no TrueDepth camera)
- **18 release-ops tests** (`node --test Scripts/tests/release-ops.test.mjs`)
- All four scheme/configuration builds
- `Scripts/check-public-binary.sh` — builds the public Release artifact, scans
  it for internal route copy, asserts forbidden and required `Info.plist` keys
  and the privacy manifest, then builds the internal target to prove each check
  can actually fail

Phases 0 through 6 of the release plan are done to the extent they can be
without hardware and Apple credentials.

### Blocked on the founder, not on engineering

1. **Apple Developer membership + Team ID** — nothing can be signed, no
   TestFlight, no APNs.
2. **A physical TrueDepth iPhone** — the camera and gaze protocol are the
   least-proven surface in the app; a simulator cannot exercise them at all.
   `Docs/PHASE_4_DEVICE_GATES.md` is the checklist.
3. **Privacy policy + support URLs** — both required for submission.
4. **Counsel** on medical claims, and a decision on App Store category (it is
   currently `healthcare-fitness`, which routes to the reviewers most likely to
   apply medical-device scrutiny to an app that disclaims being one).

---

## Landmines — things that already went wrong here

Read this section before changing anything. Each of these shipped or nearly
shipped.

**A theme change silently broke the measurement.** Migrating to DesignKit
repointed `Palette` at the new tokens, where `primary` and `accent` are the same
orange. The reaction task colours its two choices with exactly those two names —
so a colour-discrimination task had nothing to discriminate, and the tracking and
gaze targets changed hue and luminance, invalidating comparison against stored
baselines. Hence `StimulusPalette`, which is deliberately not derived from the
theme.

**Timed tasks measure against the wall clock.** Reaction latency is
`Date().timeIntervalSince(targetAppearedAt)`. Nothing observed `scenePhase`, so
a phone call mid-trial put the interruption inside the measurement and scored it
as the person slowing down — a false "changes detected" manufactured by a
notification. Leaving a timed task now discards the reading.

**A demo button fabricated a baseline.** "Explore founder demo" was the *primary*
button in onboarding, set five sessions with none measured, and permanently
suppressed real recomputation. It is now compiled out of public builds.

**A failed read looked identical to deletion.** A corrupt archive showed "0 of 5
sessions" and "Nothing recorded yet" with no explanation, and the reasonable
response — re-record five sessions — writes over recoverable data. Now
`localDataError` distinguishes them, and `baselineReady` goes false so a check
cannot silently run against population norms.

**A string check that could never fail.** The binary scanner looked for short
strings like `"Circle Map"`, but Swift stores strings of ≤15 UTF-8 bytes inline
in instructions, so `strings` cannot see them. Three of nine checks would have
passed forever while proving nothing. The script now builds the internal target
and asserts every needle *is* detectable there.

**Two agents on one repo.** Work has been split between Claude and Codex. That
has produced a sweep commit that captured another agent's in-flight files, two
broken builds, duplicate parallel implementations of the same feature, and a
`HowResultsWorkView` declared twice at different paths. Check `git log` and
branch state before assuming the tree is yours alone.

---

## Practical notes

- Tests are slow and the simulator is contended. **Several "failures" here have
  been 3–5 second timeouts on `waitForExistence`, or a full disk** — check the
  failing line before assuming a regression.
- `xcodebuild` derived-data directories are ~250 MB each and filled the disk
  once, which itself caused a spurious test failure.
- Guardian code compiles into the public binary but is inert: no route reaches
  it, no endpoint is configured, and the client fails closed on a nil base URL.
  "The public build exposes no Guardian routes, permissions, configuration, or
  network endpoint" is the precise claim — not that the code is absent.
- `Docs/APP_STORE_MASTER_PLAN.md` is the full plan; `Docs/APP_STORE_SUBMISSION.md`
  is the submission package with decisions marked.

---

## Useful commands

```bash
xcodegen generate                      # after adding or removing files
xcodebuild -project Sober.xcodeproj -scheme Sober \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
Scripts/check-public-binary.sh         # the public-boundary gate
node --test Scripts/tests/release-ops.test.mjs
```
