import FamilyControls
import Foundation

// `FamilyActivitySelection` is Codable but its tokens are opaque and bound to
// this device, so the JSON lives only in the App Group store and never goes
// to the server. Compiled into SoberInternal and the monitor extension.
enum CurfewSelectionCodec {
  static func encode(_ selection: FamilyActivitySelection) throws -> Data {
    try JSONEncoder().encode(selection)
  }

  /// Nil for missing or unreadable data. Unreadable data pauses nothing,
  /// which is the harmless direction (rule 6).
  static func decode(_ data: Data?) -> FamilyActivitySelection? {
    guard let data else { return nil }
    return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
  }
}
