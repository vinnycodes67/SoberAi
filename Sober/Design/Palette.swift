import SwiftUI

/// Black, grey, and one vibrant orange.
///
/// The app is dark, always. It is opened at night by someone deciding whether
/// to drive, and a light page would be hostile in that moment. Locking the
/// appearance also means every value here is chosen against one known ground
/// rather than compromised across two.
///
/// The orange carries exactly one meaning: **attention**. It fills the primary
/// action, and it marks a measure that fell outside someone's usual range.
/// Nothing else is coloured, so anywhere orange appears is somewhere the eye is
/// meant to go. That single rule is what stops a high-chroma accent from
/// reading as a logo.
///
/// Text is verified against the page: 17.9 / 8.3 / 4.9, and black-on-orange
/// at 6.9.
enum Palette {

  // MARK: - Grounds
  //
  // Near-black rather than pure. True black leaves no room to raise a surface
  // without a border, and borders everywhere is the look this system avoids.

  static let background = Color(hex: 0x0B0B0C)
  /// A card, a grouped row, a field.
  static let surface = Color(hex: 0x161617)
  /// A plane above a plane, or a pressed row.
  static let surfaceRaised = Color(hex: 0x212123)

  // MARK: - Text

  static let textPrimary = Color(hex: 0xF5F4F1)
  static let textSecondary = Color(hex: 0xA9A8A4)
  static let textMuted = Color(hex: 0x807F7B)

  // MARK: - Lines

  static let separator = Color(hex: 0xF5F4F1).opacity(0.11)

  // MARK: - Attention

  static let accent = Color(hex: 0xFF6B1F)
  /// Content on a filled accent surface.
  static let onAccent = Color(hex: 0x0B0B0C)
  /// A wash for a block that needs lifting without a border.
  static let accentWash = Color(hex: 0xFF6B1F).opacity(0.12)

  // MARK: - Measurement state
  //
  // Only one state is coloured. A measure inside the usual range is the common
  // case and gets no colour at all: the absence of attention is the message.

  static let withinRange = Color(hex: 0xA9A8A4)
  static let outsideRange = accent
  /// Could not be read. Never orange, because an absent reading is not a
  /// finding.
  static let unmeasured = Color(hex: 0x6B6A66)

  // MARK: - Task stimuli
  //
  // Functional colours for the choice-reaction task, which asks someone to
  // match a colour. These are stimuli, not brand.
  //
  // Blue and magenta stay separable under deuteranopia and protanopia, where
  // red and green do not. They are also separated by *luminance* (about
  // 2.5:1), so they remain distinguishable to someone who sees no colour at
  // all. Colour is never the sole cue regardless: every symbol carries a shape
  // as well, and its accessibility label states both.

  static let stimulusBlue = Color(hex: 0x2F7FD4)
  static let stimulusMagenta = Color(hex: 0xFFB3E2)

  // MARK: - Legacy aliases

  static let ink = background
  static let panel = surface
  static let panelHigh = surfaceRaised
  static let raised = surface
  static let raisedActive = surfaceRaised
  static let cardBackground = surface
  static let elevated = surface
  static let surfaceSecondary = surfaceRaised
  static let line = separator
  static let lineStrong = separator
  static let separatorStrong = separator
  static let textTertiary = textMuted
  static let primary = accent
  static let secondary = textMuted
  static let accentBright = accent
  static let accentText = accent
  static let accentSoft = accentWash
  static let accentDeep = accent
  static let error = accent
  static let critical = accent
  static let warning = unmeasured
  static let accentGlow = Color.clear

  static let item0 = accent
  static let item1 = accent
  static let item2 = accent
  static let item3 = accent
  static let primaryHue = 0.0611
  static let item0Hue = 0.0611
  static let item1Hue = 0.0611
  static let item2Hue = 0.0611
  static let item3Hue = 0.0611

  static let lightPrimary = accent
  static let lightSecondary = surfaceRaised
  static let lightAccent = accent
  static let lightCardBackground = surface
  static let lightSurface = background
  static let lightTextPrimary = textPrimary
  static let lightTextSecondary = textSecondary

  static let backgroundGradient = LinearGradient(
    colors: [background, background], startPoint: .top, endPoint: .bottom)
  static let rimLight = LinearGradient(
    colors: [.clear, .clear], startPoint: .top, endPoint: .bottom)

  static func instrumentGradient(_ hue: Double) -> LinearGradient {
    LinearGradient(colors: [surface, surface], startPoint: .top, endPoint: .bottom)
  }
}

extension Color {
  fileprivate init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }
}
