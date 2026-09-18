# Resubmission plan

Everything remaining before Sober goes back to App Review, with an owner on
every task. Revised 2026-09-18 after an independent Codex audit corrected the
first version — read §3 before picking up a task you already read about.

> **Vibe-coding cards, one file each:** [`VIBE_VINAY.md`](VIBE_VINAY.md) ·
> [`VIBE_AADI.md`](VIBE_AADI.md) · [`VIBE_SHREY.md`](VIBE_SHREY.md)

> **Still needed:** the rejection text from App Store Connect.

---

## 1. Fixed today (`fd156b1`)

| Was | Now |
|---|---|
| Age gate bypassable by swiping past the profile step | Gesture and button pass one gate; UI tests guard it |
| Home and Settings promised "Lyft to Home"; the Lyft link carries no destination | `rideCarriesDestination` decides the wording |
| Home claimed five sessions "build your comparison range" | Says they unlock the first check, which is true |

234 unit tests, 2 new UI tests, all green.

---

## 2. Every remaining task, and whose part it is

| Task | Owner | What | Start now? |
|---|---|---|---|
| **VINAY 1** | Vinay | Reviewer path to a real result — **needs redesign, see §3** | Yes |
| **VINAY 2** | Vinay | Threshold decision — **wider than first scoped, see §3** | After SHREY 1 |
| **VINAY 3** | Vinay | Rewrite App Review notes | After VINAY 1 |
| **VINAY 4** | Vinay | Run the full gates | Yes |
| **VINAY 5** | Vinay | Bump build, archive, upload | Last |
| **VINAY 6** | Vinay | Update the stale submission checklist | Yes |
| **VINAY 7** | Vinay | Failed baseline write reports "Baseline recorded" | Yes |
| **VINAY 8** | Vinay | Dead "Safety Circle paused" toggle — wire it or cut it | Yes |
| **AADI 1** | — | ~~Capture-quality state~~ **already built** | Done |
| **AADI 2** | Aadi | Mark which sessions counted, in History — must call the engine | Yes |
| **AADI 3** | Aadi | DesignKit marker — **smaller than scoped, see §3** | With AADI 2 |
| **AADI 4** | Aadi | Refresh screenshots | After VINAY 1 |
| **AADI 6** | Aadi + Vinay | Reduced Motion unlocks readiness but Your Steady shows the full-protocol profile | Yes |
| **SHREY 1** | Shrey | Baseline session on a real iPhone, record quality | Needs hardware |
| **SHREY 2** | Shrey | Low-light and glasses runs | Needs hardware |
| **SHREY 3** | Shrey | Camera-denied path end to end | Partly |
| **SHREY 4** | — | ~~Pupil model~~ **excluded from the public target already** | Not a blocker |
| **SHREY 5** | Shrey | Recommend a threshold from the numbers | After SHREY 1 |
| **SHREY 6** | Shrey + Vinay | Unsupported iPhones can install an app whose core feature can never unlock | Yes |

**Starting today:** VINAY 1, 4, 6, 7, 8 · AADI 2, 3, 6 · SHREY 3, 6.

---

## 3. What the Codex audit corrected

The first version of this plan got the mechanism wrong. Corrections, with
citations, so nobody rebuilds against the wrong model:

- **`completedAllTasks` does not include gaze.** It is assigned from
  `trackingWasMeasured` alone (`ScreeningFlowView.swift:361`). Gaze is enforced
  separately by the engine.
- **The 0.72 constant is not the real gate.** `OcularSignalAnalyzer` is
  all-or-nothing: it returns a score only when capture is fully usable, else
  zero (`OcularSignalAnalyzer.swift:83,115`). The lowest non-zero accepted score
  is around 0.79, and the binding constraint is the usability test plus a 70%
  capture-history requirement.
- **Eligibility is wider than two conditions** — reaction and timing
  measurements, tracking, gaze, finite values, matching protocol variant,
  current schema, and a completion timestamp (`BaselineProfileEngine.swift:104`).
- **AADI 1 already ships.** "Capture quality was too low" and "This task isn't
  available" exist (`ScreeningFlowView.swift:373`, `ScreeningModels.swift:154`).
  AADI 3 shrinks to whatever AADI 2 actually needs.
- **SHREY 4 is not a blocker.** The pupil model is excluded from the public
  target (`project.yml:23`).
- **VINAY 1 as written was rejected.** Seeding a fake baseline and calling the
  outcome genuine contradicts the measured-personal-baseline claim the whole
  product rests on. It needs an explicitly labelled reviewer/sample mode, not a
  fake baseline dressed as a real one.
- **VINAY 2 is wider than "change the threshold."** The constants are duplicated
  across `BaselineProfileEngine`, `ScreeningEngine`, `ScreeningFlowView`,
  `AppModel`, History, Home and `PersonalBaseline`. Change one and readiness
  disagrees with scoring. Consolidate first, then tune.
- **AADI 2 cannot be UI-only.** "Counted toward baseline" has to come from the
  engine's eligibility decision, or History reimplements part of the rules and
  drifts.

**Still true:** a fresh public install cannot demonstrate its principal result
without five successful TrueDepth captures, and none of this has run on physical
hardware. That is the rejection.

---

## 4. Already done — nobody redo these

| Item | Verified |
|---|---|
| Version is `1.0`; export compliance declared | `project.yml`, `Info.plist` |
| Support and privacy URLs live | both return 200 |
| Privacy manifest, no tracking, no collected data | `PrivacyInfo.xcprivacy` |
| Screenshots at 6.9" and 6.5" | `Design/AppStore/` |
| Public boundary gate, with sensitivity controls | `check-public-binary.sh` |

---

## 5. File ownership

| Area | Owner |
|---|---|
| `Sober/DesignKit/`, `Sober/Features/History/`, `Sober/Features/Steady/` | **Aadi** |
| `Sober/Services/FaceTracking*`, capture, `Sober/Services/Curfew/`, `CurfewExtensions/` | **Shrey** |
| `Sober/App/`, `Sober/Features/Screening/`, `Sober/Features/Onboarding/`, `Scripts/`, `Docs/` | **Vinay** |
| `project.yml`, `Info.plist` | **Vinay** — others request changes |

Own branch each. Pull before starting.

---

## 6. Only a human can decide these

Category (still `healthcare-fitness`), age rating, medical-claim counsel, and
whether unsupported iPhones should be blocked from installing at all (SHREY 6).

---

## 7. Pre-submit verification

```bash
xcodegen generate
xcodebuild -project Sober.xcodeproj -scheme Sober \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
Scripts/check-public-binary.sh
Scripts/check-release-metadata.sh
node --test Scripts/tests/release-ops.test.mjs
```
