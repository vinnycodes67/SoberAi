import SwiftUI

/// Black, grey, and one vibrant orange.
///
/// The orange carries exactly one meaning: **attention**. It fills the primary
/// action, and it marks a measure that fell outside someone's usual range.
/// Nothing else is coloured, so anywhere orange appears is somewhere the eye
/// is meant to go. That single rule is what stops a high-chroma accent from
/// reading as a logo.
///
/// Dark only. The app is opened at night by someone deciding whether to
/// drive; a light page would be hostile in that moment, and locking the
/// appearance means every value here is chosen against one known ground
/// rather than compromised across two.
///
/// Contrast against the page, measured rather than eyeballed:
/// primary 17.9:1, secondary 8.3:1, muted 4.9:1, orange 6.9:1,
/// and black-on-orange 6.9:1.
enum DSPalette {

  // MARK: - Grounds
  //
  // Near-black rather than pure. True black leaves no room to raise a surface
  // without drawing a border, and borders everywhere is the look this system
  // exists to avoid.

  static let background = Color(dsHex: 0x0B0B0C)
  /// A card, a grouped row, a field.
  static let surface = Color(dsHex: 0x161617)
  /// A plane above a plane, or a pressed row.
  static let surfaceRaised = Color(dsHex: 0x212123)

  // MARK: - Text

  static let textPrimary = Color(dsHex: 0xF5F4F1)
  static let textSecondary = Color(dsHex: 0xA9A8A4)
  static let textMuted = Color(dsHex: 0x807F7B)

  // MARK: - Lines
  //
  // Used sparingly. Most separation in this system is space, not rule.

  static let separator = Color(dsHex: 0xF5F4F1).opacity(0.11)

  // MARK: - Attention

  static let accent = Color(dsHex: 0xFF6B1F)
  /// Content placed on a filled accent surface.
  static let onAccent = Color(dsHex: 0x0B0B0C)
  /// A wash for a block that needs lifting without a border.
  static let accentWash = Color(dsHex: 0xFF6B1F).opacity(0.12)

  // MARK: - Measurement state
  //
  // Only one state is coloured. A measure inside the usual range is the
  // common case and gets no colour at all: the absence of attention is the
  // message. There is no success colour anywhere in this palette, because the
  // product never signals that anyone is clear to drive.

  static let withinRange = Color(dsHex: 0xA9A8A4)
  static let outsideRange = accent
  /// Could not be read. Never orange, because an absent reading is not a
  /// finding.
  static let unmeasured = Color(dsHex: 0x6B6A66)

  // MARK: - Task stimuli
  //
  // Functional colours for the choice-reaction task, which asks someone to
  // match a colour. These are stimuli, not brand, and must never be folded
  // into the accent: an earlier sweep collapsed both to one value and made
  // the task impossible to complete.
  //
  // Blue and magenta stay separable under deuteranopia and protanopia, where
  // red and green do not, and they are separated by luminance (about 2.5:1)
  // so they also work for someone who sees no colour at all. Colour is never
  // the sole cue regardless: every symbol carries a shape, and its
  // accessibility label states both.

  static let stimulusBlue = Color(dsHex: 0x2F7FD4)
  static let stimulusMagenta = Color(dsHex: 0xFFB3E2)
}

extension Color {
  /// Local hex initialiser, named so it cannot clash with any other the app
  /// may already define.
  init(dsHex hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }
}
