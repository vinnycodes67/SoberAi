# DesignKit

A self-contained visual system for Sober. Every type is prefixed `DS`, so it
sits alongside the existing `Palette`, `SoberCard`, and friends **without
colliding with anything**. Nothing in the app currently uses it.

Adopt it one screen at a time, and delete the old equivalent once a screen has
moved.

> **Not yet compiled.** This was written on a machine without Xcode.
> Verification stopped at `swiftc -parse`, which checks syntax only. Build it
> before relying on it, and expect a few type errors.

## See it first

`DSGallery` renders every component on a real device. It has no dependency on
app state:

```swift
.sheet(isPresented: $showingGallery) { DSGallery() }
```

Or open `DSGallery.swift` and use the Xcode preview.

## Files

| File | Contains |
| --- | --- |
| `DSTokens.swift` | `DSSpace`, `DSRadius`, `DSHit`, `DSMotion` |
| `DSPalette.swift` | Colour roles |
| `DSFont.swift` | Type scale, `DSEyebrow` |
| `DSComponents.swift` | Buttons, `DSCard`, `DSRow`, `DSRows`, `DSSection`, `DSSeparator`, `DSBadge`, `DSStepMeter`, `DSEmptyState`, page modifiers |
| `DSTabBar.swift` | Floating Liquid Glass tab bar |
| `DSBaselinePortrait.swift` | The baseline portrait and its legend |
| `DSGallery.swift` | Live gallery, `DEBUG` only |

## The four rules

1. **Black and grey, with one orange that means _attention_.** It fills the
   primary action and marks a measure outside someone's usual range. Nothing
   else is coloured. If a screen has no orange, nothing on it needs you.
2. **Every dimension comes from `DSSpace` or `DSRadius`.** An audit of the
   previous UI found 21 spacing values and 7 radii in ad-hoc use, which is why
   nothing looked deliberate.
3. **Type is chosen by role, not by look.** A row title is `DSFont.body` on
   every screen; a group heading is `DSFont.caption` on every screen. Same job,
   same token, so nothing drifts.
4. **Matte.** No gradients, no glows, no decorative shadows. The exceptions are
   the tab bar, which is a real material, and `DSCard(highlighted: true)`,
   which is meant for one hero surface per screen.

## Typical screen

```swift
struct SomeView: View {
  @State private var tab: DSTab = .home

  var body: some View {
    ZStack(alignment: .bottom) {
      ScrollView {
        VStack(alignment: .leading, spacing: DSSpace.xl) {
          DSCard(highlighted: true) {
            Text("Nothing unusual.")
              .font(DSFont.hero)
              .dsHeroTracking()
              .foregroundStyle(DSPalette.textPrimary)
          }

          Button("Start check") {}
            .buttonStyle(DSPrimaryButtonStyle())

          DSSection("Recent", action: ("All", { })) {
            DSRows {
              DSRow("No signals detected", detail: "11:42 PM") {}
              DSSeparator()
              DSRow("Signals detected", detail: "Feb 2") {}
            }
          }
        }
        .padding(.horizontal, DSSpace.margin)
        .padding(.bottom, DSSpace.tabBarClearance)   // clears the bar
      }
      .dsPageBackground()

      DSTabBar(selection: $tab).padding(.bottom, DSSpace.xs)
    }
  }
}
```

## The portrait

`DSBaselinePortrait` draws five measures, each as a band showing that person's
usual range with a tick where a check landed. It takes the same `[String:
Double]` shape `ScreeningOutcome` already produces:

```swift
DSBaselinePortrait(
  tracks: DSBaselinePortrait.tracks(fromRisks: outcome.signalRisks),
  isEstablished: model.baselineReady
)
DSPortraitLegend()
```

**Always caption it.** Shown bare it is a diagram with no legend and nobody can
tell what the bar, the block, or the tick mean. This was tried as a bare hero
on Home and it did not communicate.

To feed it from a stored session you need per-signal positions persisted
alongside the result. That is a small addition to `ScreeningOutcome`:

```swift
var signalRisks: [String: Double] {
  details.reduce(into: [:]) { result, detail in
    if let risk = detail.risk { result[detail.id] = risk }
  }
}
```

…which needs `SignalDetail` to carry the engine's per-signal risk. The engine
already computes it; it just is not surfaced. Storing it matters because
re-scoring an old check against a baseline that has since moved would show
someone a result they were never given.

## The typeface

Anthropic's brand face is **Styrene** (Commercial Type), paired with Tiempos.
Both are commercial licences that cannot ship in a repository, so this bundles
**Satoshi** (Indian Type Foundry) as the closest free substitute: same high
x-height, tight apertures, and even colour.

Satoshi ships under the Fontshare Free Font Licence, which explicitly permits
commercial use in apps. The full EULA is in `Sober/Resources/Fonts/`.

**To switch to Styrene:** buy the licence, drop the `.otf` files into
`Resources/Fonts`, add them to `UIAppFonts` in `project.yml`, and change the
four constants in `DSFont.Face`. Nothing else in the app names a font.

## Accessibility

- Every text colour verified against the page: 17.9 / 8.3 / 4.9, accent 6.9,
  black-on-orange 6.9. Measured, not eyeballed.
- Every token declares `relativeTo:`, so the bundled face still scales with
  Dynamic Type.
- `accessibilityReduceMotion` removes all entrance animation and the tab
  transition. `accessibilityReduceTransparency` replaces the glass with a
  solid surface.
- Touch targets are at least 44pt; the primary action is 56.
- Stimulus colours for the choice-reaction task are separated by luminance as
  well as hue, so they work under deuteranopia, protanopia, and total colour
  blindness. Shape is always a second cue.

## Safety invariants this system preserves

- **No green anywhere.** There is no success colour, because the app never
  signals that anyone is clear to drive.
- **No composite figure.** The portrait is strictly per-measure. A single
  number describing a person is the score this product refuses to produce.
- A measure that could not be read is `unmeasured` grey, never orange: an
  absent reading is not a finding.
