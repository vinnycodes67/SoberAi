import SwiftUI

/// Layout tokens.
///
/// Every dimension in the app comes from here. The audit that preceded this
/// system found 21 distinct spacing values and 20 padding values in use;
/// nothing snapped to a scale, so nothing felt deliberate. These are the only
/// legal values, and a screen that needs something between two of them is
/// nearly always solving the wrong problem.
enum Space {
  /// 4. Between a label and the value it names.
  static let xxs: CGFloat = 4
  /// 8. Inside a tightly related pair.
  static let xs: CGFloat = 8
  /// 12. Between rows in a group.
  static let sm: CGFloat = 12
  /// 16. Standard internal padding.
  static let md: CGFloat = 16
  /// 20. The screen margin. Twenty-four was chosen because it looked
  /// generous in a mockup; twenty leaves more measure for content and
  /// matches what the system itself uses.
  static let margin: CGFloat = 20
  /// 24. Card padding, and the gap between blocks of one idea.
  static let lg: CGFloat = 24
  /// 32. Between related blocks.
  static let xl: CGFloat = 32
  /// 48. Between sections that are not related.
  static let xxl: CGFloat = 48
  /// 64. Around a screen's single focal element.
  static let xxxl: CGFloat = 64
}

/// Corner radii. Three values, chosen by the size of the thing being drawn.
enum Radius {
  /// 10. Chips, badges, small controls.
  static let small: CGFloat = 10
  /// 16. Buttons and inline controls.
  static let medium: CGFloat = 16
  /// 22. Cards and sheets.
  static let large: CGFloat = 22
}

/// Touch targets. 44 is Apple's minimum; the primary action is deliberately
/// larger because it is pressed in poor conditions by someone who is tired.
enum Hit {
  static let minimum: CGFloat = 44
  static let control: CGFloat = 52
  static let primary: CGFloat = 56
}

/// Motion.
///
/// Every curve is an ease, never a spring. Nothing in this app should
/// overshoot, bounce, or draw attention to the fact that it moved. The
/// interface confirms; it does not perform.
enum Motion {
  /// 0.18s. A press, a toggle.
  static let quick = Animation.easeOut(duration: 0.18)
  /// 0.28s. A value changing, a section appearing.
  static let standard = Animation.easeInOut(duration: 0.28)
  /// 0.4s. A screen transition.
  static let deliberate = Animation.easeInOut(duration: 0.4)

  /// Staggered fade for a screen's blocks. Capped so a long screen never
  /// makes someone wait on choreography.
  static func entrance(_ order: Int) -> Animation {
    standard.delay(min(Double(order) * 0.04, 0.16))
  }
}
