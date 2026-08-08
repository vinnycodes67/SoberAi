import SwiftUI

// Generated from a 198° seed hue with the ios-taste palette tool.
// Sober intentionally stays in dark mode: night-time use should not flash a
// bright interface until the guided eye step explicitly calls for it.
enum Palette {
  static let primary = Color(hue: 0.5500, saturation: 0.700, brightness: 0.610)
  static let secondary = Color(hue: 0.5500, saturation: 0.220, brightness: 0.510)
  static let accent = Color(hue: 0.9670, saturation: 0.700, brightness: 0.810)
  static let cardBackground = Color(hue: 0.5500, saturation: 0.120, brightness: 0.140)
  static let surface = Color(hue: 0.5500, saturation: 0.050, brightness: 0.080)
  static let textPrimary = Color.white
  static let textSecondary = Color(white: 0.65)

  static let item0 = Color(hue: 0.4590, saturation: 0.700, brightness: 0.510)
  static let item2 = Color(hue: 0.5803, saturation: 0.550, brightness: 0.640)
  static let item3 = Color(hue: 0.6410, saturation: 0.700, brightness: 0.550)

  static let warning = Color(hue: 0.1111, saturation: 0.75, brightness: 0.90)

  static let backgroundGradient = LinearGradient(
    colors: [surface, Color(hue: 0.56, saturation: 0.20, brightness: 0.11), surface],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )
}
