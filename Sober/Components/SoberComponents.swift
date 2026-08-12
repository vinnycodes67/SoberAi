import SwiftUI

// The shared vocabulary used by every screen that has not yet been restructured
// onto DesignKit: onboarding, camera calibration, the tasks, the screening flow
// chrome, Safety Plan, and Circle Map.
//
// The API is unchanged so those screens compile untouched. The rendering is now
// DesignKit: matte surfaces, one orange, Satoshi, ease curves. That is what
// makes the middle of the check journey stop looking like a different app from
// its two ends.
//
// New screens should use `DSCard`, `DSPrimaryButton`, and friends directly.

/// Motion, forwarded to `DSMotion`.
///
/// The originals were springs with bounce. DesignKit uses eases only — motion
/// there confirms that something happened rather than performing — so a spring
/// on one screen and an ease on the next read as two different products.
enum SoberMotion {
  static let press = DSMotion.quick
  static let progress = DSMotion.standard
  static let screen = DSMotion.standard

  static func entrance(order: Int) -> Animation {
    DSMotion.entrance(order)
  }
}

/// The app's name in a screen's top bar.
///
/// "Sober", matching the launch reveal and the Home header. The lowercase
/// "sober." this replaces was left from the serif identity, so someone moving
/// launch → onboarding → Home saw the name spelled two different ways in the
/// first ten seconds.
struct SoberWordmark: View {
  var body: some View {
    Text("Sober")
      .font(DSFont.headline)
      .foregroundStyle(DSPalette.textPrimary)
      .accessibilityAddTraits(.isHeader)
  }
}

/// A grouped surface.
///
/// Was `.thinMaterial` under a three-stop gradient stroke and a drop shadow.
/// DesignKit raises a plane with tone alone, so the card is a flat fill with no
/// border and no shadow: separation here is space, not rule.
struct SoberCard<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View { DSCard { content } }
}

/// The one filled action on a screen.
///
/// Solid orange with near-black content, rather than tinted glass. Glass was
/// dropped for the same reason as the gradients: it changes appearance against
/// whatever sits behind it, which is exactly what a system built on a single
/// known ground is trying to avoid.
struct PrimaryActionButtonStyle: ButtonStyle {
  var tint: Color = DSPalette.accent

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    DSPrimaryButtonStyle().makeBody(configuration: configuration)
  }
}

/// A supporting action. Neutral by default: if it were also orange, the screen
/// would have two things claiming to be the thing to do.
struct SecondaryActionButtonStyle: ButtonStyle {
  var tint: Color = DSPalette.textPrimary

  func makeBody(configuration: Configuration) -> some View {
    DSSecondaryButtonStyle().makeBody(configuration: configuration)
  }
}

struct StepProgress: View {
  let current: Int
  let total: Int

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: DSSpace.xxs) {
      ForEach(0..<total, id: \.self) { index in
        Capsule()
          .fill(index <= current ? DSPalette.accent : DSPalette.separator)
          .frame(height: 3)
          .animation(reduceMotion ? nil : DSMotion.standard, value: current)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Step \(current + 1) of \(total)")
  }
}

/// Eyebrow, title, supporting line.
///
/// The eyebrow is muted grey rather than the old cyan. An eyebrow is structure,
/// not attention, and colouring it would spend the accent on furniture.
struct ScreenHeader: View {
  let eyebrow: String
  let title: String
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: DSSpace.sm) {
      DSEyebrow(eyebrow)
      Text(title)
        .font(DSFont.hero)
        .dsHeroTracking()
        .foregroundStyle(DSPalette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      Text(detail)
        .font(DSFont.callout)
        .foregroundStyle(DSPalette.textSecondary)
        .dsReadingLine()
    }
  }
}

/// Circular and capsule chrome.
///
/// Both were Liquid Glass with a material fallback. They are now plain raised
/// surfaces: the system keeps exactly one real material, the floating tab bar,
/// and spreading glass across incidental chrome is what made the old screens
/// feel busy behind the content.
private struct SoberSurfaceShapeModifier<S: Shape>: ViewModifier {
  let shape: S
  let tint: Color?

  func body(content: Content) -> some View {
    content
      .background(shape.fill(tint ?? DSPalette.surface))
      .foregroundStyle(tint == nil ? DSPalette.textPrimary : DSPalette.onAccent)
  }
}

extension View {
  /// The page ground.
  ///
  /// Replaces an 18 fps `TimelineView` that animated two blurred radial orbs
  /// behind every legacy screen. Beyond the visual mismatch, it kept a
  /// per-frame redraw running during the tasks, where the whole point is that
  /// nothing on screen competes with the stimulus.
  func soberBackground() -> some View { dsPageBackground() }

  func soberEntrance(order: Int = 0) -> some View { dsAppear(order) }

  func soberGlassCircle(tint: Color? = nil) -> some View {
    modifier(SoberSurfaceShapeModifier(shape: Circle(), tint: tint))
  }

  func soberGlassCapsule(tint: Color? = nil) -> some View {
    modifier(SoberSurfaceShapeModifier(shape: Capsule(), tint: tint))
  }
}
