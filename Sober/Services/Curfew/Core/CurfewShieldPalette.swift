import Foundation

// DesignKit colour values as raw hex, for the shield extension which cannot
// link SwiftUI DesignKit. A unit test pins each value to `DSPalette` so the
// block screen cannot drift from the app. No green: checked in is grey/white.
enum CurfewShieldPalette {
  static let background: UInt32 = 0x0B0B0C
  static let textPrimary: UInt32 = 0xF5F4F1
  static let textSecondary: UInt32 = 0xA9A8A4
  static let accent: UInt32 = 0xFF6B1F
  static let onAccent: UInt32 = 0x0B0B0C
}
