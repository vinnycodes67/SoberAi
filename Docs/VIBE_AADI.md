# Vibe-coding cards — Aadi

Paste-ready prompts for `AADI 1–5` in [`RESUBMISSION_PLAN.md`](RESUBMISSION_PLAN.md).

You wrote DesignKit, so all of this is inside your own system.

**Start every AI session with this**, then paste one card:

```text
Read Docs/SOBER_CONTEXT_BRIEF.md, DESIGN.md and Docs/RESUBMISSION_PLAN.md
before writing any code. Follow the safety invariants in the first, the design
rules in the second, and the file ownership in §7 of the third — I own
Sober/DesignKit/ and Sober/Features/History/. Do not edit Sober/App/,
Sober/Features/Screening/ (Vinay's) or Sober/Services/FaceTracking* and
Sober/Services/Curfew/ (Shrey's).
One card per session. Run the tests before telling me you're done.
```

---

## The problem all three cards solve

`BaselineProfileEngine.isEligible` only counts a baseline session when
`completedAllTasks` is true **and** `qualityScore >= 0.72`. A session that
scores 0.70 is recorded in History and then silently ignored — the "0 of 5"
counter simply does not move, and the person is given no reason.

Someone can repeat this five times and conclude the app is broken. **That is
probably why App Review rejected it.**

---

## AADI 1 — The "capture quality too low" state

```text
Goal: when a baseline session does not count, say so and say why.

Where it happens: BaselineProfileEngine.isEligible (Sober/Services/) requires
completedAllTasks AND qualityScore >= 0.72. Read it, don't change it — it is
Vinay's file. You are building the UI that explains its outcome.

Build, in DesignKit and the Home readiness card:
- After a baseline session that did not count, tell the person plainly: the
  capture was too unclear to use, so it was not added.
- Give them something to change: more light, hold the phone at arm's length,
  remove glasses, keep still.
- Show it where the "0 of 5 baseline sessions recorded" line already lives in
  DSIntegratedHomeScreen — that is where the person is looking when the number
  fails to move.

Design rules (DESIGN.md):
- No green anywhere. There is no pass colour in this product.
- Orange is attention only — appropriate here.
- Use DSSpace/DSRadius/DSFont tokens, never hardcoded numbers.
- Never say "failed", "passed", "cleared" or "safe" — the session didn't count,
  the person did not fail.

Check it at the largest accessibility text size before you finish.
```

**Done when:** a session under 0.72 produces a visible, specific explanation
instead of a counter that silently doesn't move.

---

## AADI 2 — Show what counted in History

**Read this first — the plan overstated this task.** `HistoryView` *already*
shows capture quality on every row (`"\(when) · \(qualityLabel) capture"`) and
already handles "not completed". What it does **not** show is whether a session
**counted toward the baseline**. That is the only missing piece.

```text
Goal: make it visible which baseline sessions counted toward the five.

HistoryView.swift already renders quality per row — read lines ~190-220 before
changing anything, and do not rebuild what is there.

Add: a quiet marker on baseline sessions that did NOT count, so someone stuck
at 0 of 5 can see the pattern across five rows instead of guessing.

A session counts only when completedAllTasks is true AND qualityScore >= 0.72
(BaselineProfileEngine.isEligible). Read that rule; do not duplicate the number
— expose it from the engine rather than hardcoding 0.72 in the view.

Rules: not green, not a badge that reads like a penalty, and never the word
"failed". Something closer to "not added to your steady".
```

---

## AADI 3 — The shared DesignKit component

```text
AADI 1 and AADI 2 both need to mark "this session did not count". Build it once
in Sober/DesignKit/ rather than twice in feature code.

Follow the existing component patterns — look at DSBadge and DSStatusChip
first, and match their API shape and token use.

It takes a label and a tone. It has no success/green tone, on purpose: nothing
in this product gets a success colour, and a green marker next to a measurement
would read as "you're fine", which is the one claim the product refuses to make.

Add a #Preview covering every tone.
```

---

## AADI 4 — Refresh the screenshots *(after VINAY 1)*

```text
If AADI 1, AADI 2 or Vinay's demo mode changed any screen that appears in
Design/AppStore/, retake those shots.

Both sets must stay in sync: 10 at 6.9" (1320x2868, iPhone 17 Pro Max) and 10
at 6.5" (1284x2778, iPhone 14 Plus), same states in the same order, same
filenames.

The capture method — fixtures, status bar override to 9:41, settle time — is in
Docs/CURFEW_SHREY_TASKS.md card 8. Reuse it; don't invent a new one.
```

## AADI 5 — DesignKit parts Vinay asks for *(on request)*

He is building demo mode under deadline. If he needs a component, build it in
DesignKit rather than letting him fork one — that is how two versions of a
component start drifting apart.
