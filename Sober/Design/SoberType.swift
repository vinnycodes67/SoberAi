import SwiftUI

/// The type scale.
///
/// ## The typeface
///
/// Anthropic's brand face is **Styrene** (Berton Hasebe, Commercial Type),
/// paired with Tiempos for long-form. Both are commercial licences that
/// cannot be redistributed in a repository, so the app ships the closest free
/// substitute: **Satoshi** (Indian Type Foundry), a geometric grotesque with
/// the same high x-height, tight apertures, and even colour that give Styrene
/// its voice.
///
/// Switching to real Styrene is four lines. Buy the licence, drop the `.otf`
/// files into `Resources/Fonts`, add them to `UIAppFonts`, and change the
/// constants in `Face` below. Nothing else in the app refers to a font name.
///
/// ## The scale
///
/// Sizes track Apple's ramp (34 / 28 / 22 / 17 / 16 / 15 / 13 / 12 / 11) so
/// Dynamic Type maps cleanly and the app sits correctly beside system UI.
///
/// Each token is defined by **role**, not by appearance. A row title is
/// `body` on every screen in the app; a group heading is `caption` on every
/// screen. That is what makes sizes uniform: the same job always gets the
/// same token, so nothing drifts screen to screen.
enum SoberType {

  /// The single point of control for the app's typeface.
  private enum Face {
    static let regular = "Satoshi-Regular"
    static let medium = "Satoshi-Medium"
    static let semibold = "Satoshi-Bold"
    static let bold = "Satoshi-Black"
  }

  // MARK: - Display
  // One per screen, at most. Two things in display type means neither is the
  // focus.

  /// 56 medium, tabular. The one figure that *is* the content.
  static let figureLarge = Font.custom(Face.medium, size: 56, relativeTo: .largeTitle)
    .monospacedDigit()
  /// 34 semibold. The sentence a screen exists to say.
  static let hero = Font.custom(Face.semibold, size: 34, relativeTo: .largeTitle)
  /// 28 semibold. A large navigation title.
  static let largeTitle = Font.custom(Face.semibold, size: 28, relativeTo: .title)
  /// 22 semibold. A section that opens a new idea.
  static let title = Font.custom(Face.semibold, size: 22, relativeTo: .title2)

  // MARK: - Content

  /// 17 medium. A row title carrying weight, a button, a navigation title.
  static let headline = Font.custom(Face.medium, size: 17, relativeTo: .headline)
  /// 17 regular. The default, and the size of every row title.
  static let body = Font.custom(Face.regular, size: 17, relativeTo: .body)
  /// 16 regular. Supporting copy inside a card.
  static let callout = Font.custom(Face.regular, size: 16, relativeTo: .callout)
  /// 15 regular. The secondary line beneath a row title.
  static let subheadline = Font.custom(Face.regular, size: 15, relativeTo: .subheadline)

  // MARK: - Metadata
  // Genuinely peripheral text. A screen set mostly in these has its hierarchy
  // upside down.

  /// 13 regular. Timestamps, footnotes, limitations.
  static let footnote = Font.custom(Face.regular, size: 13, relativeTo: .footnote)
  /// 13 medium. A footnote carrying weight, such as a card's kicker.
  static let footnoteStrong = Font.custom(Face.medium, size: 13, relativeTo: .footnote)
  /// 12 regular. Dense sentence-case labels, such as portrait track names.
  static let caption2 = Font.custom(Face.regular, size: 12, relativeTo: .caption)
  /// 11 medium, uppercase. Group headings, via `Eyebrow`.
  static let caption = Font.custom(Face.medium, size: 11, relativeTo: .caption2)

  /// Tabular figures. Medium: a number should be legible, not loud.
  static func figure(_ size: CGFloat) -> Font {
    Font.custom(Face.medium, size: size, relativeTo: .title).monospacedDigit()
  }
}

extension View {
  /// Display type needs tightening; geometric grotesques set loose at large
  /// optical sizes. Body text is left alone, because tracking hurts reading.
  func heroTracking() -> some View { tracking(-0.7) }
  func titleTracking() -> some View { tracking(-0.35) }

  /// Leading for running copy, read by someone tired.
  func readingLine() -> some View {
    lineSpacing(4).fixedSize(horizontal: false, vertical: true)
  }
}

/// An uppercase group heading. The only uppercase text in the app.
struct Eyebrow: View {
  let text: String
  var tint: Color = Palette.textMuted

  init(_ text: String, tint: Color = Palette.textMuted) {
    self.text = text
    self.tint = tint
  }

  var body: some View {
    Text(text.uppercased())
      .font(SoberType.caption)
      .tracking(0.7)
      .foregroundStyle(tint)
  }
}

extension Text {
  func eyebrowStyle(_ tint: Color = Palette.textMuted) -> some View {
    self.font(SoberType.caption).tracking(0.7).foregroundStyle(tint)
  }
}
