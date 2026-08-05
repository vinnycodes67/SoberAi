# Design System — Sober

## Product Context

- **What this is:** A private iPhone impairment-awareness and ride-home intervention prototype. It helps someone pause, complete a short quality-gated check, and contact their Safety Circle when signals are concerning.
- **Who it is for:** A person in a noisy, low-light, time-sensitive moment who needs calm guidance and large, obvious actions.
- **Space:** Personal safety, health research, and trusted-contact intervention.
- **Project type:** Native SwiftUI mobile app with dashboard, guided task, camera, and result flows.
- **Boundary:** The visual system must never imply clinical validation, sobriety, or safe-to-drive clearance.

## Aesthetic Direction

- **Direction:** Nocturnal instrument.
- **Decoration:** Intentional. A living signal halo and restrained atmospheric field provide identity; task and result content remain quiet and legible.
- **Mood:** Calm, private, precise, and protective. The first half-second is a luminous orbit suspended above a decisive action.
- **References:** Apple Weather's ambient depth, Apple Health's restrained data hierarchy, and Apple's iOS 26 Liquid Glass guidance for floating controls.
- **Liquid Glass rule:** Glass belongs to the top interactive layer. Do not nest glass, fill scrolling content with glass, or use tint as decoration. Use regular glass only; do not mix regular and clear variants.

## Typography

- **Display/Hero:** New York through SwiftUI's serif design. It gives the app a composed editorial voice without bundling a font.
- **Body/UI:** San Francisco through SwiftUI semantic text styles for native Dynamic Type, legibility, and accessibility.
- **Data:** San Francisco with `monospacedDigit()` for changing values and timers.
- **Scale:** `largeTitle` for the primary decision, `title2`/`title3` for supporting hierarchy, `body` for instructions, and `caption` for evidence and limitations.

## Color

- **Approach:** Restrained. One 198° cyan family communicates the product identity; amber and red are reserved for warning and concern states.
- **Primary:** `#2E7A9B` derived from hue 198°. Used for active controls, the signal halo, and selected state.
- **Secondary:** `#657982` for quiet structure and borders.
- **Accent:** `#CE3D5A`, reserved rather than used decoratively.
- **Neutrals:** Deep blue-black surfaces with white primary text and 65% white secondary text.
- **Semantic:** Warning `#E6A31A`; error `#D94141`. There is intentionally no green pass state.
- **Dark mode:** The app stays dark for low-light use. Camera tasks may introduce controlled brightness when the protocol requires it.

## Spacing and Shape

- **Base unit:** 4 pt.
- **Density:** Comfortable, with 18 pt screen and card padding and 10–14 pt vertical gaps.
- **Radius:** 12 pt for compact utilities, 16 pt for controls, 18–22 pt for content surfaces, capsule for progress and floating control groups.
- **Hierarchy:** The halo and primary action dominate; evidence, caveats, and secondary controls sit lower in the visual field.

## Layout

- **Approach:** Grid-disciplined single-column flow with edge-to-edge atmospheric content behind floating controls.
- **Primary action:** One per screen, full width, minimum 54 pt height.
- **Cards:** Content surfaces use a quiet translucent depth treatment. They are not interactive Liquid Glass unless the entire surface is a control.
- **Navigation:** Prefer system `NavigationStack`, toolbars, sheets, and alerts so iOS 26 provides native continuity and glass behavior.

## Motion

- **Approach:** Intentional and calm.
- **Ambient:** The background breathes slowly and the halo orbits continuously only when active.
- **Entrance:** Major blocks rise 8–12 pt and fade in with a short stagger. Never delay the primary action for spectacle.
- **Interaction:** Buttons compress slightly and use a low-bounce spring. On iOS 26, interactive glass supplies native flex, shimmer, and bounce.
- **State change:** Progress fills and numeric values animate in place. Concern results do not bounce, celebrate, or use confetti.
- **Timing:** Micro 100–160 ms; short 220–320 ms; ambient 8–14 s.
- **Accessibility:** Read `accessibilityReduceMotion` and `accessibilityReduceTransparency`. Reduce Motion removes travel, orbit, and stagger; Reduce Transparency strengthens solid backings and borders.
- **Performance:** Keep `TimelineView`/`Canvas` work bounded, avoid glass inside rapidly updating lists, and group adjacent glass elements in one `GlassEffectContainer` on iOS 26.

## Decisions Log

| Date | Decision | Rationale |
| --- | --- | --- |
| 2026-08-04 | Use a nocturnal instrument direction | It fits private low-light use and makes the signal halo the product's memorable shape. |
| 2026-08-04 | Keep Liquid Glass in the interactive layer | This follows Apple's hierarchy and performance guidance while preventing visual noise. |
| 2026-08-04 | Preserve iOS 17 support | The founder build remains installable on older devices; iOS 26 receives native glass through availability-gated enhancements. |
| 2026-08-04 | Make all motion accessibility-aware | A safety flow must remain usable with Reduce Motion and Reduce Transparency enabled. |
