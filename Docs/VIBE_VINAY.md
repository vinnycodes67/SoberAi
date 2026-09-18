# Vibe-coding cards — Vinay

Paste-ready prompts for `VINAY 1–6` in [`RESUBMISSION_PLAN.md`](RESUBMISSION_PLAN.md).

**Start every AI session with this**, then paste one card:

```text
Read Docs/SOBER_CONTEXT_BRIEF.md and Docs/RESUBMISSION_PLAN.md before writing
any code. Follow the safety invariants in the first and the file ownership in
§7 of the second — I own Sober/App/, Sober/Features/Screening/, Scripts/ and
Docs/. Do not edit Sober/DesignKit/ or Sober/Features/History/ (Aadi's) or
Sober/Services/FaceTracking* and Sober/Services/Curfew/ (Shrey's).
One card per session. Run the tests before telling me you're done.
```

---

## VINAY 1 — Demo path to a real result

The item that answers the rejection. A reviewer must be able to run one genuine
check and see one genuine outcome without completing five camera sessions.

```text
Goal: let an App Reviewer reach a REAL result without recording five baseline
sessions.

Context you need:
- BaselineProfileEngine.isEligible requires completedAllTasks AND
  qualityScore >= 0.72. Five eligible sessions are needed before any check runs.
  On a reviewer's device that may be unreachable, so the app can look broken.
- UITestConfiguration.seedBaseline(in:participantID:) ALREADY seeds a baseline,
  but it is gated behind `isActive` (the -sober-ui-testing launch argument) and
  is not reachable in a shipping build. Read it first — the mechanism is right,
  the gate is wrong for this.

Build a "Demo mode" the reviewer can turn on from Settings:
- Seeds a synthetic baseline so a check can run immediately.
- Every screen while it is on is clearly marked as demo — the result screen
  already has an `isSample` flag, use it.
- Turning it off deletes the synthetic sessions and restores the real count.
- The synthetic sessions must NEVER merge into a real baseline. Give them a
  marker and exclude them from the eligibility path when demo mode is off.

Hard rules (from SOBER_CONTEXT_BRIEF.md):
- No pass state, no green, no "safe to drive".
- A demo result is still one of the three states and still shows the ride and
  contact actions.
- Nothing about this may make a real, un-measured baseline look ready.

Write unit tests: demo on -> check runs; demo off -> count returns to its real
value; synthetic sessions never count as eligible.
Then run: xcodebuild -project Sober.xcodeproj -scheme Sober \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

**Done when:** a fresh install can reach a real result in under a minute, and
turning demo off leaves the real baseline count untouched.

---

## VINAY 4 — Run the full gates

```text
Run all of these and report exactly what fails, without fixing anything yet:

xcodegen generate
xcodebuild -project Sober.xcodeproj -scheme Sober \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
Scripts/check-public-binary.sh
Scripts/check-release-metadata.sh
node --test Scripts/tests/release-ops.test.mjs

Expected: 231 unit tests, 31 UI tests (1 skipped — no TrueDepth camera on the
simulator), 18 release-ops tests, both scripts PASSED.

Note: most failures on this machine have been simulator timeouts or a full
disk, not real regressions. Read the failing line before concluding anything.
If the simulator is wedged or missing, recreate it:
xcrun simctl create "Sober-Verify" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5
```

---

## VINAY 6 — Update the stale submission checklist

```text
Docs/APP_STORE_SUBMISSION.md's checklist claims open items that are done.
Verify each against the repo, then tick or leave it:

- Version: project.yml MARKETING_VERSION is "1.0"
- Export compliance: ITSAppUsesNonExemptEncryption is in Sober/Info.plist
- Support + privacy URLs: curl both, confirm 200
- Device gates: Docs/PHASE_4_DEVICE_GATES.md still has zero results recorded
- Category, age rating, medical-claim counsel: still open, leave unticked

Only tick what you verified. Do not tick device gates — nothing has run on
hardware.
```

---

## VINAY 3 — Rewrite the App Review notes *(after VINAY 1)*

```text
Rewrite the "Review notes" section of Docs/APP_STORE_SUBMISSION.md around the
demo mode built in VINAY 1.

It must tell a reviewer, in order and in plain words:
1. How to turn demo mode on, tap by tap.
2. What they will see — the three result states and that there is deliberately
   no pass state.
3. Why the camera is used, and that frames are never saved or transmitted.
4. That declining camera permission does not block the app.

Do not write "see the How results work page" as the answer to "can you test the
core feature" — that page shows examples, not the feature, and that is why the
last submission did not satisfy them.
```

---

## VINAY 2 — Decide the threshold *(after SHREY 1)*

Not a coding card. Shrey reports real capture-quality numbers; you decide
whether `minimumQuality` (0.72) and the five-session requirement stay. Change
them in `BaselineProfileEngine` only with his numbers in hand.

## VINAY 5 — Archive and submit *(last)*

```text
Increment CURRENT_PROJECT_VERSION in project.yml (App Store Connect rejects a
rebuild that reuses a build number), run xcodegen generate, then archive the
Sober scheme for generic/platform=iOS, validate, and upload.
```
