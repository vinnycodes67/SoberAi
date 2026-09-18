# Resubmission plan

Everything remaining before Sober goes back to App Review, with an owner on
every task. Verified against the repo on 2026-09-18 — several items in
`APP_STORE_SUBMISSION.md` are stale and already done.

> **Still needed:** the rejection text from App Store Connect — the guideline
> number and any reviewer screenshot. This plan is built on what the code
> shows, and the most likely cause is §3. If they rejected for something else,
> §3 changes and the rest stands.

---

## 1. Every task, and whose part it is

| Task | Owner | What | Start now? |
|---|---|---|---|
| **VINAY 1** | Vinay | Demo path to a real result | Yes |
| **VINAY 2** | Vinay | Decide the baseline threshold | After SHREY 1 |
| **VINAY 3** | Vinay | Rewrite App Review notes | After VINAY 1 |
| **VINAY 4** | Vinay | Run the full gates | Yes |
| **VINAY 5** | Vinay | Bump build, archive, upload | Last |
| **VINAY 6** | Vinay | Update the stale submission checklist | Yes |
| **AADI 1** | Aadi | "Capture quality too low" state | Yes |
| **AADI 2** | Aadi | Per-session quality in History | Yes |
| **AADI 3** | Aadi | DesignKit "didn't count" component | Yes |
| **AADI 4** | Aadi | Refresh screenshots | After VINAY 1 |
| **AADI 5** | Aadi | DesignKit parts Vinay asks for | On request |
| **SHREY 1** | Shrey | Baseline session on a real iPhone, record quality | Needs hardware |
| **SHREY 2** | Shrey | Low-light and glasses runs | Needs hardware |
| **SHREY 3** | Shrey | Camera-denied path end to end | Partly |
| **SHREY 4** | Shrey | Wire up or cut the pupil model | Yes |
| **SHREY 5** | Shrey | Recommend a threshold from the numbers | After SHREY 1 |

**Starting today:** VINAY 1, 4, 6 · AADI 1, 2, 3 · SHREY 4.

---

## 2. Already done — nobody redo these

| Item | Verified |
|---|---|
| Version is `1.0` | `project.yml` MARKETING_VERSION |
| Support URL live | `https://vinnycodes67.github.io/SoberSupport/` → 200 |
| Privacy policy URL live | `.../privacy.html` → 200 |
| Export compliance declared | `ITSAppUsesNonExemptEncryption: false` |
| Privacy manifest | `PrivacyInfo.xcprivacy`, no tracking, no collected data |
| Screenshots | 10 each at 6.9" and 6.5", `Design/AppStore/` |
| Public boundary gate | passes, with sensitivity controls |
| Tests | 231 unit green at `c2ad86d` |
| No stubs in shipping code | no TODO, FIXME or `fatalError` in `Sober/` |

---

## 3. The blocker: the app can get stuck at 0 of 5 forever

`BaselineProfileEngine` counts a baseline session only when **both** hold:

```swift
session.metrics.completedAllTasks,
session.metrics.qualityScore >= minimumQuality   // 0.72
```

`completedAllTasks` includes the gaze task, which needs the TrueDepth camera.
So a reviewer must complete **five** sessions, all four tasks each, every one at
**≥ 72% capture quality**, before the app does anything at all.

If quality lands below 0.72 — poor light, glasses, arm's-length hold, a denied
camera prompt — the counter never moves, Home keeps saying "Record a baseline
session", and no result can ever appear. That is what "not close to being
finished" looks like from a reviewer's desk.

**This has never run on physical hardware.** `PHASE_4_DEVICE_GATES.md` has zero
results recorded, so nobody knows whether 0.72 is achievable in a normal room.

The fix takes two people: **VINAY 1** builds a reviewer path to a real result,
and **SHREY 1** produces real capture numbers so the threshold can be set
honestly.

---

## 4. Vinay's part — the critical path and the release

Owns `Sober/App/`, `Sober/Features/Screening/`, `Scripts/`, `Docs/`,
`project.yml`, `Info.plist`, and App Store Connect.

**VINAY 1 — Demo path to a real result.** *(start now)*
A clearly-labelled mode that seeds a baseline so a reviewer runs one genuine
check and sees one genuine outcome. The "How results work" page shows examples,
not the feature — that is why it did not satisfy them. Highest-value item on
any list.

**VINAY 2 — Decide the baseline threshold.** *(after SHREY 1)*
Five flawless sessions before anything works is harsh for real users too, not
just reviewers. Decide with Shrey's numbers in hand, not before.

**VINAY 3 — Rewrite the App Review notes.** *(after VINAY 1)*
Step by step, in the reviewer's words, around whatever VINAY 1 becomes.

**VINAY 4 — Run the full gates.** *(start now)*
231 unit, 31 UI, `check-public-binary.sh`, `check-release-metadata.sh`,
release-ops, all four build configurations.

**VINAY 5 — Bump build, archive, validate, upload.** *(last)*
App Store Connect rejects a rebuild that reuses a build number, so increment
`CURRENT_PROJECT_VERSION`.

**VINAY 6 — Update `APP_STORE_SUBMISSION.md`.** *(start now)*
Its checklist claims open items that are already done.

---

## 5. Aadi's part — the UI surfaces

Owns `Sober/DesignKit/` and `Sober/Features/History/`. You wrote DesignKit, so
every screen here is inside your own system.

**AADI 1 — The "capture quality too low" state.** *(start now)*
Today a session scoring 0.70 silently vanishes and the counter just doesn't
move — the person gets no idea why. Say what happened and what to change:
light, distance, glasses. The biggest user-visible hole in the app.

**AADI 2 — Per-session quality in History.** *(start now)*
Someone stuck at 0 of 5 should see the pattern instead of guessing. A quality
figure per row, and a quiet marker on sessions that didn't count.

**AADI 3 — A DesignKit "didn't count" component.** *(start now)*
AADI 1 and AADI 2 both need it — build it once in `DesignKit/`, not twice in
feature code. Not green; nothing in this product gets a success colour.

**AADI 4 — Refresh the screenshots.** *(after VINAY 1)*
If AADI 1, AADI 2 or VINAY 1 change any pictured screen. Fixtures and capture
method are in `Design/AppStore/` and `Docs/CURFEW_SHREY_TASKS.md` card 8.

**AADI 5 — DesignKit parts Vinay asks for.** *(on request)*
He should not be forking your components under deadline.

---

## 6. Shrey's part — capture and device truth

Owns `Sober/Services/FaceTracking*`, the capture path, `Sober/Services/Curfew/`,
`CurfewExtensions/`, and `PHASE_4_DEVICE_GATES.md`.

**SHREY 1 — Baseline session on a physical iPhone.** *(needs hardware)*
Record every task's quality score into `PHASE_4_DEVICE_GATES.md`. Everything
about the threshold depends on this one number. **Longest pole in the plan.**

**SHREY 2 — Low-light and glasses runs.** *(needs hardware)*
The two conditions most likely to sink quality in a review lab.

**SHREY 3 — Camera-denied path end to end.** *(partly startable)*
The states exist (`permissionDenied`, `unsupported`); confirm "Don't Allow"
reaches something useful rather than a dead end.

**SHREY 4 — Wire up or cut the pupil model.** *(start now)*
`PupilSegmentation.mlmodelc` ships but `metrics.pupillometry` is populated by
nothing. An unfinished feature sitting in the repo.

**SHREY 5 — Recommend a threshold.** *(after SHREY 1)*
From SHREY 1 and SHREY 2, so Vinay can decide VINAY 2.

---

## 7. File ownership — to stop the collisions

This repo has already lost work to two people committing over each other.

| Area | Owner |
|---|---|
| `Sober/DesignKit/`, `Sober/Features/History/` | **Aadi** |
| `Sober/Services/FaceTracking*`, capture, `Sober/Services/Curfew/`, `CurfewExtensions/` | **Shrey** |
| `Sober/App/`, `Sober/Features/Screening/`, `Scripts/`, `Docs/` | **Vinay** |
| `project.yml`, `Info.plist` | **Vinay** — others request changes |

Own branch each. Pull before starting. Never commit a file you didn't mean to.

---

## 8. Only a human can decide these — Vinay

| Item | Status |
|---|---|
| **Category** — still `public.app-category.healthcare-fitness`, which routes to reviewers most likely to apply medical-device scrutiny to an app that disclaims being one | Open |
| **Age rating** — answer the alcohol question honestly; do not attempt 4+ | Open |
| **Medical-claim review** — counsel | Open |
| **The rejection text** — shapes §3 | Not yet shared |

---

## 9. Order

```text
         ┌─ AADI 1, 2, 3 ───────────────────┐
today ───┼─ VINAY 1, 4, 6 ──────────────────┼─► VINAY 3 notes ─┐
         └─ SHREY 4 ────────────────────────┘                  │
                                                               │
device → SHREY 1, 2, 3 ─► SHREY 5 ─► VINAY 2 threshold ────────┤
                                                               ▼
                         AADI 4 screenshots ─► VINAY 4 gates ─► VINAY 5 submit
```

Three lanes start today with no dependency on each other. **SHREY 1 is the long
pole** — get an iPhone into Shrey's hands first, because the threshold decision
cannot be made without his numbers, and the threshold decides whether VINAY 1 is
a convenience or the only way the app is usable at all.

---

## 10. Pre-submit verification — Vinay

All green before archiving:

```bash
xcodegen generate
xcodebuild -project Sober.xcodeproj -scheme Sober \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
Scripts/check-public-binary.sh
Scripts/check-release-metadata.sh
node --test Scripts/tests/release-ops.test.mjs
```
