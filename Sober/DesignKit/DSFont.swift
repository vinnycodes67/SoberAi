import SwiftUI

/// The type scale.
///
/// ## The typeface
///
/// Anthropic's brand face is **Styrene** (Commercial Type), paired with
/// Tiempos. Both are commercial licences that cannot ship in a repository, so
/// this bundles **Satoshi** (Indian Type Foundry) as the closest free
/// substitute: same high x-height, tight apertures, and even colour.
///
/// Satoshi ships under the Fontshare Free Font Licence, which explicitly
/// permits commercial use in apps. The full EULA is in
/// `Sober/Resources/Fonts/Satoshi-LICENSE.txt`.
///
/// **To switch to real Styrene:** buy the licence, drop the `.otf` files into
/// `Resources/Fonts`, add them to `UIAppFonts` in `project.yml`, and change
/// the four constants in `Face` below. Nothing else in the app names a font.
///
/// ## The scale
///
/// Sizes track Apple's own ramp (34 / 28 / 22 / 17 / 16 / 15 / 13 / 12 / 11)
/// so Dynamic Type maps cleanly and the app sits correctly beside system UI.
///
/// Each token is defined by **role**, not appearance. A row title is `body` on
/// every screen; a group heading is `caption` on every screen. That is the
/// mechanism that keeps sizes uniform: the same job always draws the same
/// token, so nothing can drift screen to screen.
enum DSFont {

  /// The single point of control for the app's typeface.
  private enum Face {
    static let regular = "Satoshi-Regular"
    static let medium = "Satoshi-Medium"
    static let semibold = "Satoshi-Bold"
    static let bold = "Satoshi-Black"
  }

  // MARK: - Display
  // One per screen at most. Two things in display type means neither is the
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

  /// 17 medium. A row title carrying weight, a button, a nav title.
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
  /// 12 regular. Dense sentence-case labels.
  static let caption2 = Font.custom(Face.regular, size: 12, relativeTo: .caption)
  /// 11 medium, uppercase. Group headings, via `DSEyebrow`.
  static let caption = Font.custom(Face.medium, size: 11, relativeTo: .caption2)

  /// Tabular figures. Medium: a number should be legible, not loud.
  static func figure(_ size: CGFloat) -> Font {
    Font.custom(Face.medium, size: size, relativeTo: .title).monospacedDigit()
  }
}

extension View {
  /// Display type needs tightening; geometric grotesques set loose at large
  /// optical sizes. Body text is left alone, because tracking hurts reading.
  func dsHeroTracking() -> some View { tracking(-0.7) }
  func dsTitleTracking() -> some View { tracking(-0.35) }

  /// Leading for running copy, read by someone tired.
  func dsReadingLine() -> some View {
    lineSpacing(4).fixedSize(horizontal: false, vertical: true)
  }
}

/// An uppercase group heading. The only uppercase text in the system, used at
/// most once or twice per screen: set everywhere, it stops being structure and
/// becomes a tic.
struct DSEyebrow: View {
  let text: String
  var tint: Color = DSPalette.textMuted

  init(_ text: String, tint: Color = DSPalette.textMuted) {
    self.text = text
    self.tint = tint
  }

  var body: some View {
    Text(text.uppercased())
      .font(DSFont.caption)
      .tracking(0.7)
      .foregroundStyle(tint)
  }
}
