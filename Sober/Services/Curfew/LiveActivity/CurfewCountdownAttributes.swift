import ActivityKit
import Foundation

/// Shared between SoberInternal (which starts and updates the activity) and the
/// CurfewLiveActivity widget extension (which renders it). No result, no score.
struct CurfewCountdownAttributes: ActivityAttributes {
  enum Phase: String, Codable, Hashable, Sendable {
    /// "Home by 11:00 · 42 min"
    case beforeCurfew
    /// Curfew passed, grace running.
    case grace
    /// Apps paused; open Sober to check in.
    case checkInDue
    /// Checked in; next check-in at `nextAt`.
    case checkedIn
    /// Asked for a ride; nothing more tonight.
    case ride
  }

  struct ContentState: Codable, Hashable, Sendable {
    var phase: Phase
    var curfewAt: Date
    var nextCheckInAt: Date?
  }

  /// `CurfewNight.id`
  var nightID: String
  var guardianName: String?
}
