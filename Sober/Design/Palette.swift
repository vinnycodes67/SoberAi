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

  static let lightPrimary = Color(hue: 0.5500, saturation: 0.650, brightness: 0.550)
  static let lightSecondary = Color(hue: 0.5500, saturation: 0.100, brightness: 0.900)
  static let lightAccent = Color(hue: 0.9670, saturation: 0.550, brightness: 0.600)
  static let lightCardBackground = Color(hue: 0.5500, saturation: 0.040, brightness: 0.970)
  static let lightSurface = Color(hue: 0.5500, saturation: 0.020, brightness: 0.990)
  static let lightTextPrimary = Color(white: 0.1)
  static let lightTextSecondary = Color(white: 0.45)

  static let item0 = Color(hue: 0.4590, saturation: 0.700, brightness: 0.510)
  static let item1 = Color(hue: 0.5197, saturation: 0.400, brightness: 0.500)
  static let item2 = Color(hue: 0.5803, saturation: 0.550, brightness: 0.640)
  static let item3 = Color(hue: 0.6410, saturation: 0.700, brightness: 0.550)

  static let warning = Color(hue: 0.1111, saturation: 0.75, brightness: 0.90)
  static let error = Color(hue: 0.0000, saturation: 0.70, brightness: 0.85)

  static let backgroundGradient = LinearGradient(
    colors: [surface, Color(hue: 0.56, saturation: 0.20, brightness: 0.11), surface],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )
}
