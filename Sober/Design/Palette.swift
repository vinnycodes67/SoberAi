import SwiftUI

/// Compatibility shim mapping the original palette onto `DSPalette`.
///
/// The app had two visual systems: this one (a 198° cyan seed with a magenta
/// accent, serif display type, gradients and glass) and DesignKit (matte black,
/// grey, one orange). Home and Result had migrated; onboarding, calibration,
/// the tasks, the flow chrome, Safety Plan and Circle Map had not. A person
/// moving through a single check saw new, then old, then old, then new.
///
/// Rather than rewrite nine screens at once, every name here now resolves to a
/// DesignKit value. The legacy screens keep their structure and inherit the
/// canonical colour immediately, and each can then be restructured on its own
/// schedule without a second visual jump.
///
/// New code should reference `DSPalette` directly. This exists to retire, and
/// it shrinks every time a screen is properly migrated.
enum Palette {

  /// Was cyan, and named the primary *action*. In DesignKit that role is the
  /// single orange, which means attention and nothing else.
  static let primary = DSPalette.accent
  /// Was a desaturated cyan used for inactive rules and dim text.
  static let secondary = DSPalette.textMuted
  /// Was magenta. Collapses onto the same orange: this system has exactly one
  /// attention colour, and two competing accents is the thing it forbids.
  static let accent = DSPalette.accent

  static let cardBackground = DSPalette.surface
  static let surface = DSPalette.background
  static let textPrimary = DSPalette.textPrimary
  static let textSecondary = DSPalette.textSecondary

  /// Decorative hues from the old chart/item ramp. Nothing in the system may
  /// carry meaning through colour except the accent, so these are now grey.
  static let item0 = DSPalette.textMuted
  static let item2 = DSPalette.textSecondary
  static let item3 = DSPalette.textMuted

  /// There is no separate warning colour. A caution and a primary action are
  /// both "look here", and the palette has one way to say that.
  static let warning = DSPalette.accent

  /// Flat. The gradient it replaces was three cyan stops; DesignKit's ground is
  /// a single near-black so that raising a surface needs no border.
  static let backgroundGradient = LinearGradient(
    colors: [DSPalette.background, DSPalette.background],
    startPoint: .top,
    endPoint: .bottom
  )
}
