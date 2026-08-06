import SwiftUI

// DesignKit
// =========
//
// A self-contained visual system for Sober. Every type here is prefixed `DS`
// so it can sit alongside the existing `Palette`, `SoberCard`, and friends
// without collision. Nothing in the app currently depends on it: adopt it one
// view at a time, and delete the old equivalents once a screen has moved.
//
// The rules it encodes, in short:
//
//   1. Black and grey, with a single orange that means "attention" and
//      nothing else. If a screen has no orange, nothing on it needs you.
//   2. Every dimension comes from `DSSpace` or `DSRadius`. An audit of the
//      previous UI found 21 spacing values and 7 radii in ad-hoc use.
//   3. Type is chosen by *role*, not by look. A row title is `DSFont.body`
//      on every screen, so nothing drifts.
//   4. Matte. No gradients, no glows, no decorative shadows. The one
//      exception is the Liquid Glass tab bar, which is a real material.

/// Spacing. These are the only legal values; a layout needing something
/// between two of them is usually solving the wrong problem.
enum DSSpace {
  /// 4. Between a label and the value it names.
  static let xxs: CGFloat = 4
  /// 8. Inside a tightly related pair.
  static let xs: CGFloat = 8
  /// 12. Between rows in a group.
  static let sm: CGFloat = 12
  /// 16. Standard internal padding.
  static let md: CGFloat = 16
  /// 20. The screen margin.
  static let margin: CGFloat = 20
  /// 24. Card padding, and the gap between blocks of one idea.
  static let lg: CGFloat = 24
  /// 32. Between distinct sections.
  static let xl: CGFloat = 32
  /// 48. Between unrelated regions.
  static let xxl: CGFloat = 48
  /// 64. Around a screen's single focal element.
  static let xxxl: CGFloat = 64

  /// Bottom clearance for content sitting under the floating tab bar.
  static let tabBarClearance: CGFloat = 116
}

/// Corner radii, chosen by the size of the thing being drawn.
enum DSRadius {
  /// 10. Chips and badges.
  static let small: CGFloat = 10
  /// 16. Buttons and inline controls.
  static let medium: CGFloat = 16
  /// 22. Cards and sheets.
  static let large: CGFloat = 22
}

/// Touch targets. 44 is Apple's floor. The primary action is larger because
/// it is pressed by someone tired, in poor light, in a hurry.
enum DSHit {
  static let minimum: CGFloat = 44
  static let control: CGFloat = 52
  static let primary: CGFloat = 56
}

/// Motion. Every curve is an ease; nothing springs or overshoots. Motion
/// confirms that something happened, it does not perform.
enum DSMotion {
  /// 0.18s. A press, a toggle.
  static let quick = Animation.easeOut(duration: 0.18)
  /// 0.28s. A value changing, a section appearing.
  static let standard = Animation.easeInOut(duration: 0.28)
  /// 0.4s. A screen transition.
  static let deliberate = Animation.easeInOut(duration: 0.4)

  /// Staggered fade for a screen's blocks, capped so a long screen never
  /// makes someone wait on choreography.
  static func entrance(_ order: Int) -> Animation {
    standard.delay(min(Double(order) * 0.04, 0.16))
  }
}
