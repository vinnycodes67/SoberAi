# DesignKit

The canonical visual system for Sober. Every type is prefixed `DS`, allowing legacy screens to coexist while the app migrates one approved screen at a time.

The DesignKit is compiled and shipping on Home, result, and Guardian Mode. The debug gallery remains available for isolated component review.

## Files

| File | Contains |
| --- | --- |
| `Foundation/DSTokens.swift` | `DSSpace`, `DSRadius`, `DSHit`, `DSMotion` |
| `Foundation/DSPalette.swift` | Semantic colour roles |
| `Foundation/DSFont.swift` | Satoshi type roles and Dynamic Type scaling |
| `Components/DSComponents.swift` | Buttons, cards, rows, sections, badges, progress, and page modifiers |
| `Components/DSTabBar.swift` | Floating, accessibility-aware tab bar |
| `Components/DSBaselinePortrait.swift` | Per-measure baseline portrait and legend |
| `Gallery/DSGallery.swift` | Debug-only live component gallery |
| `Screens/DSIntegratedHomeScreen.swift` | Production Home surface backed by `AppModel` environment state |
| `Screens/DSIntegratedResultScreen.swift` | Production result and intervention surface |

## Rules

1. **Black and grey, with one orange that means attention.** Orange fills the primary action and marks a measured value outside the usual range.
2. **Use tokens.** Screen spacing, radii, motion, and hit targets come from DesignKit primitives.
3. **Type by role.** The same semantic job uses the same `DSFont` style on every screen.
4. **Stay matte.** Gradients, glows, and decorative shadows are outside the canonical system. Material is reserved for the floating control layer.
5. **Model capture state.** Unmeasured values are explicit data, not inferred from display strings, and render in muted grey.

## Accessibility

- Colours meet the documented dark-background contrast targets.
- Type styles scale with Dynamic Type.
- Reduce Motion removes entrance travel and repeated effects.
- Reduce Transparency replaces the floating material with a solid surface.
- Touch targets are at least 44 pt; primary actions are 56 pt.
- Colour is never the only cue for task stimuli or measurement state.

## Safety invariants

- No green or safe-to-drive state.
- No composite person-level score.
- Every data portrait is per measure and captioned.
- An absent reading is unmeasured grey, never an orange concern.

Satoshi ships under the Fontshare Free Font Licence. The bundled licence is in `Sober/Resources/Fonts/`.
