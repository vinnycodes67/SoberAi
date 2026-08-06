# Design System — Sober

## Product Context

- **What this is:** A private iPhone impairment-awareness and ride-home intervention prototype. It helps someone pause, complete a short quality-gated check, and reach their Safety Circle when signals are concerning.
- **Who it is for:** Someone tired, at night, outside somewhere loud, deciding whether to drive.
- **Boundary:** The visual system must never imply clinical validation, sobriety, or safe-to-drive clearance.

## The object

**Sober's object is your steady:** the accumulated portrait of someone's own
normal across five measures, drawn as `BaselinePortrait`.

This is the only material in the app that belongs to the person using it, and
it is the literal basis of every claim the product makes. A check is nothing
more than the question *does tonight sit inside this shape?*

It is the home screen, it is the evidence on a result, and it is the subject of
its own detail screen. Before a baseline exists it draws as five faint dashed
outlines: the portrait is then honestly incomplete, and that incompleteness is
a better invitation than a progress bar counting to five.

Every great single-purpose app has one object. Wallet has the card, Fitness has
the rings, Journal has the entry. An app without one becomes a menu of
features, which is what this was.

## Navigation

**One surface and a set of sheets. No tab bar.** Sober is opened at a moment of
need, used for two minutes, and closed. A tab bar spends permanent screen
furniture on destinations someone visits twice a year.

Home is the app. The primary action is pinned at thumb height rather than
scrolled to. Setup, history, baseline detail, and past results are all sheets
reached from a single control, and they leave the way they came.

## Aesthetic Direction

**Black, grey, and one vibrant orange.**

The orange carries exactly one meaning: **attention**. It fills the primary
action and it marks a measure that fell outside someone's usual range. Nothing
else in the app is coloured, so anywhere orange appears is somewhere the eye is
meant to go.

That single rule is what stops a high-chroma accent from looking loud. A
vibrant colour used once per screen reads as deliberate; the same colour spread
across ready-states, icon circles, and decoration reads as a startup logo. An
audit found it in roughly fifty places, most of them meaning nothing.

The one exception is the choice-reaction task, whose stimulus colours are
functional rather than brand. They are separated by luminance as well as hue,
so they stay distinguishable to someone who sees no colour at all.

The reference is editorial rather than instrumental: a well-set page, not a dashboard. The app should feel like it was made by people who are careful, and who are not trying to impress anyone in the moment someone opens it.

- **Matte, always.** No gradients, no glows, no glass, no blurs, no shadows used as depth. Surfaces separate by value and by space. The only gradient in the app is the scrim that fades a pinned header; the only shadows are on task targets someone is literally being asked to look at.
- **Warm greys, not cold black.** The scale carries a faint green cast so the turquoise reads as native to the surface rather than dropped onto it.
- **Bone, not white.** Pure white on a dark ground glares at night and reads as a screen. `#EBE9E3` reads as paper.
- **Dark by necessity.** A bright page would be hostile at 1 a.m. outside a bar. This is the one place the aesthetic yields to the use case.
- **Space over rule.** Most separation is whitespace. Hairlines are used sparingly, boxes more sparingly still.

### What this system is guarding against

Each of these was built and removed across earlier passes. They are listed because they are easy to drift back into.

1. **Every group in its own floating card.** A stack of identical framed panels is the strongest tell that no one made a decision. `SoberSection` (a quiet heading over flat rows) is the default; a filled panel appears only where content genuinely needs a boundary, such as a form.
2. **An effect applied to everything.** Rim light on every surface, glow under every accent. Applied uniformly, emphasis stops being emphasis and becomes texture.
3. **An uppercase letterspaced label above every block.** `Eyebrow` appears at most once per screen. Group headings use `SoberType.heading`, which sits *below* body size on purpose: headings organise, they do not announce.
4. **Rows of identical metric boxes.** Three containers for three related numbers implied they were unrelated. `MetricStrip` sets them on one line.
5. **Uniform spacing.** Hierarchy needs variation: 38 pt between sections, 12 pt heading to content, 3 pt inside a row's own text.
6. **Copy assembled from labels.** Screens open with a sentence a person would actually say, not a stack of nouns.

## Tokens

Every dimension, color, and size in the app resolves through a token. The
audit that preceded this system found **21 distinct spacing values, 20 padding
values, and 7 corner radii** in use, none of them on a scale. Nothing looked
deliberate because nothing was.

- **`Space`** — 4 / 8 / 12 / 16 / 24 / 32 / 48 / 64. These are the only legal
  values. A layout needing something between two of them is usually solving
  the wrong problem.
- **`Radius`** — `small` 10 (chips), `medium` 16 (controls), `large` 22 (cards
  and sheets).
- **`Hit`** — `minimum` 44 (Apple's floor), `control` 52, `primary` 56. The
  primary action is largest because it is pressed by someone tired, in poor
  light.
- **`Motion`** — `quick` 0.18s, `standard` 0.28s, `deliberate` 0.4s. Every
  curve is an ease. Nothing springs, overshoots, or bounces.

## Typography

**Every piece of text resolves through `SoberType`.** No screen calls `.font(.headline)` or `.system(size:)` for text; SF Symbols are the only thing sized directly.

- **Family:** General Sans (Indian Type Foundry), bundled at Regular / Medium / Semibold / Bold under the Fontshare Free Font License, which explicitly permits commercial use in apps. The EULA ships in `Resources/Fonts`.
- **Swapping the face:** change the four constants in `SoberType.Face`. That is the only edit required app-wide, including to drop in a licensed Styrene.
- **Dynamic Type:** every token declares `relativeTo:`, so the bundled face still scales.
- **Weights stay low.** Display is semibold, not bold. Figures are medium. The app should sound calm rather than emphatic.

| Token | Size / weight | Use |
| --- | --- | --- |
| `display` | 30 semibold | The sentence a screen opens with. |
| `title` | 22 semibold | Screen titles. |
| `heading` | 14 medium | A group heading, in tertiary grey. |
| `label` / `labelStrong` | 16.5 regular / medium | Row titles and buttons. |
| `body` | 16 regular | Running copy, with `readingLine()`. |
| `detail` | 14.5 regular | The secondary line under a row. |
| `caption` / `captionStrong` | 13.5 regular / medium | Captions and footnotes. |
| `micro` | 12 medium, uppercase | At most once per screen. |
| `numeral(_:)` | medium, tabular | Measured values. |

Running copy uses `readingLine()` (5 pt leading). Paragraphs here are read by someone tired, so they get more air than a typical interface allows.

## Color

Semantic roles only. No view names a color; it names what the color is for.
The app adapts to light and dark: warm on both sides, bone and graphite rather
than white and black, so night reads as paper and day reads as printed stock.

The one screen that stays dark regardless is the check itself. The ocular and
light-reflex tasks control screen luminance as part of the protocol, so a light
page would corrupt the capture; the reason is recorded at the call site.

- **Surfaces:** `ink` is the page; `panel` holds grouped rows and fields; `panelHigh` marks a pressed row.
- **Text:** `textPrimary` bone, `textSecondary`, `textTertiary`.
- **Accent:** one matte turquoise. `accent` fills the primary action, `accentBright` marks text and small indicators, `accentSoft` washes a highlighted block. It never glows and never gradients.
- **Accent budget:** at most one or two turquoise elements per screen.
- **Semantic:** ochre `warning` for caution and low capture quality; terracotta `error` for signals detected. Both muted to sit inside the palette rather than shout over it.
- **No green, anywhere.** There is no success color, because the app never signals that anyone is clear to drive. `ResultView`'s `noSignalsDetected` uses a neutral dash rather than a checkmark for the same reason.

## Spacing and Shape

- **Base unit:** 4 pt. **Screen margin:** 24 pt.
- **Rhythm:** 38 pt between sections, 12 pt heading to content, 15 pt row padding, 3 pt inside a row's text.
- **Radius:** 7 pt for pills, 12–13 pt for controls, 14 pt for panels. Nothing rounder: large radii read as soft rather than considered.

## Layout

- **Approach:** Single column, left-aligned. Centered layouts only where a task warrants focus.
- **Primary action:** One per screen, full width, minimum 54 pt.
- **Sections:** `SoberSection` is the default container, and it draws nothing.
- **Rows:** `SoberRow` inside `SoberList`, separated by `SoberDivider`. `SoberCard` only for forms and measurement blocks.
- **Metrics:** `MetricStrip` sets related values on one line. It never shows a composite figure.
- **The deviation plot:** `SignalDeviationRow` is the app's one piece of real information design and the only place a measurement is drawn rather than printed. A band marks the person's own usual range; a marker shows tonight. It reads `SignalDetail.risk`, a per-signal personal z-score the engine already computes. This is the product's central claim made visible: every row compares someone only to themselves, and no row summarises the others. `DeviationLegend` explains the band once per group. The composite `riskScore` is never drawn or printed anywhere.
- **Navigation:** `SoberTabBar`, a matte bar under a hairline: Home · Circle · Guardian. Safety Circle and Guardian Mode accept `showsDoneButton: false` so the sheet-only Done control disappears when they are tabs. History opens as a sheet from the Last check heading: it is somewhere you go to review, not one of the three places you live in.

## Writing

- **No em dashes.** Use a comma, a colon, or a full stop.
- **Write sentences, not labels.** A screen should be readable aloud.
- **Never imply clearance.** No copy may suggest someone is sober, safe, cleared, or fine to drive. The load-bearing disclaimers live on the result screen where the decision is made, plus onboarding's boundaries page and About.
- **Say it once.** Explain at the group, not under every element.

## Motion

- Entrance is opacity only, 0.3 s, staggered to 0.16 s. No travel.
- Buttons change opacity. No bounce, no spring overshoot.
- Numeric values use `contentTransition(.numericText())`.
- `accessibilityReduceMotion` removes all of it.

## Decisions Log

| Date | Decision | Rationale |
| --- | --- | --- |
| 2026-08-04 | Preserve iOS 17 support | The founder build stays installable on older devices. |
| 2026-08-04 | Make all motion accessibility-aware | A safety flow must remain usable with Reduce Motion and Reduce Transparency enabled. |
| 2026-08-05 | Bundle General Sans, route all text through `SoberType` | Typography was inconsistent across 111 ad-hoc call sites. One family, one scale, one file. |
| 2026-08-05 | Persist `resultState` on the research envelope | History needed the outcome, which was computed and shown but never stored. Optional and `decodeIfPresent`, so existing records stay readable. |
| 2026-08-06 | The hero ring measures task progress, never the person | A number in a ring reads as "you are 85% sober". `ProgressRing` counts tasks; Home has no ring. |
| 2026-08-06 | History is a log, not a trend | A chart across checks composes individual results into a running figure, which is the score this product refuses to produce. |
| 2026-08-06 | Added `SignalDeviationRow` | The app's claim is "compared to your own normal", and it was only ever asserted in prose. It now has a visual form, using a per-signal risk the engine already computed but never surfaced. Being domain-specific, it is also the one element here that could not be lifted from a template. |
| 2026-08-06 | Scrapped the cold dark tech palette for warm graphite, bone, and matte turquoise | Successive passes chased dashboard aesthetics and kept landing on something generated. The reference is now editorial and calm: warm greys, paper-toned text, one low-saturation accent, and nothing that glows. Dark is retained solely because of night use. |
| 2026-08-06 | Made the baseline portrait the app's object and its home screen | Home previously held a sentence, a button, and three settings rows: nothing on it belonged to the person using it. The portrait is real personal material, it accumulates, and it makes a result a comparison against a shape someone already recognises. |
| 2026-08-06 | Removed the tab bar in favour of one surface and sheets | Tabs are for apps people live in. Nobody visits Safety Circle regularly. |
| 2026-08-06 | Persisted `signalRisks` per session | The portrait needs to draw a past check without re-scoring it against a baseline that may since have moved, which would show someone a result they were never given. |
| 2026-08-06 | Reordered the result: statement, way home, then evidence | The previous screen put a metric row directly beneath the verdict, asking someone to read statistics in the second after being told not to drive. |
| 2026-08-06 | Stripped the check to one close control and five dots | A step counter tells someone how much longer they must endure, which is the wrong frame for a task that asks for attention. |
| 2026-08-06 | Verified every text colour at 4.5:1 on both grounds | The previous palette's muted greys were chosen because they looked restrained in a mockup; several failed contrast outright. |
| 2026-08-06 | Introduced `Space`, `Radius`, `Hit`, and `Motion` tokens; snapped every screen to them | The audit found 21 spacing values, 20 padding values, and 7 radii in use. Now 7 spacing values, 8 padding values, and 3 radii, all on scale. |
| 2026-08-06 | Rebuilt the type scale on Apple's ramp and corrected the pyramid | The most-used token was `caption`, followed by two more small sizes: a flat slab of 13 to 16 pt text with almost no display type. That is why the app had no hierarchy. `body` is now 17 and carries the app; the top of the scale is used where a screen has something to say. |
| 2026-08-06 | Home holds no measurements | Reaction times, capture quality, and session counts are outcomes of the engineering, not information anyone needs while deciding whether to run a check. They live on the result and in History. |
| 2026-08-06 | Founder tools moved behind About | Preview scenarios and the Research Center used the same components as consumer screens, so the app read as an internal tool a user had wandered into. They remain fully functional, one level down, and visually quieter. |
| 2026-08-06 | The check draws no progress of its own | `FlowContainer` and the flow header both showed position. Two elements saying the same thing is exactly the noise a timed task cannot afford. |
| 2026-08-06 | Light mode enabled | Every token is adaptive and the forced `.preferredColorScheme(.dark)` is gone everywhere except the check. |
| 2026-08-06 | Removed every gradient, glow, glass surface, and decorative shadow | "Matte" is a hard rule now, not a preference. One gradient remains, for the header scrim; four shadows remain, all on task targets the person is being asked to look at. |
