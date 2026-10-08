# Design System — Sober

## Product context

- **What this is:** A private iPhone impairment-awareness and ride-home intervention prototype.
- **Who it is for:** Someone in a noisy, low-light, time-sensitive moment who needs calm guidance and obvious actions.
- **Boundary:** The UI must never imply clinical validation, sobriety, or safe-to-drive clearance.
- **Canonical implementation:** `Sober/DesignKit` (`DS`-prefixed tokens and components).

## Aesthetic direction

- **Direction:** Matte safety instrument.
- **Mood:** Calm, private, precise, and protective.
- **Hierarchy:** Near-black background, restrained grey surfaces, white type, and one safety orange for attention and primary action.
- **Decoration:** Minimal. No gradients, glows, ornamental shadows, or decorative colour on canonical screens.
- **Liquid Glass:** Reserved for the floating navigation/control layer. Do not nest glass or use it for scrolling content.

## Typography

- **UI face:** Bundled Satoshi through `DSFont`; every style remains relative to a Dynamic Type text style.
- **Data:** Use `monospacedDigit()` for measurements, progress, dates, and timers.
- **Roles:** Hero for the primary state, title/headline for decisions, body for instructions, caption/footnote for evidence and limitations.
- **Rule:** Choose type by semantic role, never by one-off visual preference.

## Colour

- **Background:** `DSPalette.background`.
- **Surfaces:** `DSPalette.surface` and `surfaceRaised`.
- **Text:** `textPrimary`, `textSecondary`, and `textMuted` only.
- **Attention/action:** `DSPalette.accent` orange. It marks the primary action and a measured value outside the usual range.
- **Unmeasured:** Muted grey, never orange.
- **No green:** There is no pass colour because the product never says someone is safe to drive.

## Spacing and shape

- Use `DSSpace`, `DSRadius`, and `DSHit` for canonical screens.
- Primary actions are full width and at least 56 pt high.
- All other controls meet the 44 pt minimum target.
- Use one highlighted surface at most per screen; ordinary content remains matte.
- Prefer a single-column layout with `DSSpace.margin` horizontal padding.

## Motion

- Use `DSMotion` and `dsAppear` for short, calm state transitions.
- Never celebrate a safety result or animate concern states playfully.
- Respect Reduce Motion and Reduce Transparency on every animated or material surface.
- Keep continuously updating visual work out of list rows and scrolling cards.

## Safety invariants

- Never show a safe-to-drive or pass state.
- Never collapse the person into a composite score.
- Explicitly distinguish measured, outside-range, inside-range, and unmeasured values in the data model.
- Every result keeps a ride/contact path and the safety disclaimer visible.
- Guardian messaging shares the minimum alert state, never biometric measurements or the result score.

## Migration state

Every public screen renders through DesignKit. The shared legacy vocabulary (`SoberCard`, `ScreenHeader`, `PrimaryActionButtonStyle`, `soberBackground()`, `soberEntrance()`) no longer has its own implementation — each one now delegates to its `DS` counterpart, so a change to DesignKit reaches those screens instead of drifting away from them. Their layout is tokenised too.

Circle Map and the Research Center are internal-only and still carry bespoke layout; they inherit the components but have not been restructured.

New screens use `DS` components directly. Don't add new styling to the legacy names — they exist only so untouched screens keep compiling.

## Decisions log

| Date | Decision | Rationale |
| --- | --- | --- |
| 2026-08-04 | Preserve iOS 17 support | Founder devices remain supported; newer iOS versions receive availability-gated system effects. |
| 2026-08-04 | Make all motion accessibility-aware | A safety flow must remain usable with Reduce Motion and Reduce Transparency. |
| 2026-08-06 | Adopt matte black, grey, and safety orange as the canonical UI | It creates a quieter hierarchy and makes attention states unmistakable. |
| 2026-08-08 | Treat DesignKit as the source of truth | Home, result, and Guardian now share one tokenized visual language; legacy screens are explicitly transitional. |
| 2026-08-16 | Legacy components delegate to DesignKit rather than being restyled | One implementation each; a padding or press state fixed in `DS` reaches every screen instead of two copies drifting apart. |
| 2026-09-16 | Curfew status is never green, and the countdown ring drains | A green chip on a guardian's screen reads as "they're fine" — the one claim no state in this product may make. A filling ring reads as an achievement; this measures time being spent. See `DSStatusChip` and `DSCountdownRing`. |
| 2026-09-19 | A baseline session that did not count is marked "not added", never "failed" | Someone stuck at "0 of 5" needs to see why the number is not moving; "failed" blames the person for a capture problem. Quiet grey in History, attention orange once on Home where they are looking. Both use `DSStatusChip`, and both ask the engine rather than restating its rules. |
| 2026-09-28 | A camera-free session reads "without eye task", never a capture band | On an iPhone with no TrueDepth camera the eye task never runs, so there is no capture to grade. The detail line previously inherited a default and announced "strong capture" about a recording that never happened. Same quiet, factual register as "not added": it states what the session was, not how the person did. |
| 2026-09-28 | A camera-free check says what it leaves out before it starts | Without the eye task the check has one fewer signal, so "No changes detected" from it covers less. That goes on the self-report screen, in secondary grey, while the person is still deciding how much weight to give the result, not after it. Capture quality reads "Not measured" whenever the eye task did not run, including a check that ended at the self-report question, on the same rule as the gaze row. |
| 2026-09-28 | "No changes detected" never sits above mostly orange rows | The headline came from a composite alone, so one far-out measure averaged against ordinary ones read "No changes detected" above two "Outside usual range" rows. Half or more of the measured rows out of range now says changes were detected; a quiet result with one orange row says beside the rows why that alone is not enough. A reaction row flagged by errors shows the errors. Home's "Ready" counts only the baseline for the version of the check this iPhone runs next. |
| 2026-10-08 | A marginal capture gets one grey line, never a warning | Capture now has three levels. Unusable keeps the orange warning, because the run will not count. Usable-but-marginal (dark, overexposed, soft, slow, brief dropouts) gets a single grey sentence on camera setup saying what would make it clearer: it still counts, so orange would overstate it. A second face in view is unusable, with its own sentence. "Move left / right" exists but stays off until a Face ID iPhone confirms the directions. |
| 2026-10-08 | Several contacts, one lead; the rest wait under "More contacts" | The primary keeps today's Call and Message buttons on a result. Everyone else sits behind one collapsed grey line, with plain white Call/Message text when opened, so the ride stays the only orange action and the card still has one obvious next step. Each contact can be limited to call or message, never neither: a contact with both off would look like a safety net and never appear. Primary is a toggle in the contact editor rather than a flag you can clear; someone always leads. |
| 2026-09-19 | Row accessories move under the text at accessibility sizes | Beside a `DSRow`, a chip or badge took half the width at AX5 and the title wrapped a word per line. Matches `DSValueRow`, which already stacked. |
