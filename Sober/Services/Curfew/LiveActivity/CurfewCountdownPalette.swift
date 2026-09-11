import SwiftUI

// The countdown's colours, built from the same hex values the shield extension
// uses, so the Lock Screen cannot drift from the app. The widget extension has
// no DesignKit; this is the whole palette it gets.
//
// Orange carries one meaning here as everywhere else: the thing to do next.
// Only the check-in-due call to action wears it. Checked in is grey, never
// green — there is no pass colour in this product.
enum CurfewCountdownPalette {
  static let background = Color(curfewHex: CurfewShieldPalette.background)
  static let textPrimary = Color(curfewHex: CurfewShieldPalette.textPrimary)
  static let textSecondary = Color(curfewHex: CurfewShieldPalette.textSecondary)
  static let accent = Color(curfewHex: CurfewShieldPalette.accent)
}

extension Color {
  /// Local hex initialiser for the Live Activity, named so it cannot clash
  /// with DesignKit's `Color(dsHex:)` in the app target.
  init(curfewHex hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }
}
