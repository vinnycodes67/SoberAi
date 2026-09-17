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

    init(phase: Phase, curfewAt: Date, nextCheckInAt: Date? = nil) {
      self.phase = phase
      self.curfewAt = curfewAt
      self.nextCheckInAt = nextCheckInAt
    }
  }

  /// `CurfewNight.id`
  var nightID: String
  var guardianName: String?

  init(nightID: String, guardianName: String? = nil) {
    self.nightID = nightID
    self.guardianName = guardianName
  }
}

#if DEBUG
extension CurfewCountdownAttributes {
  /// Fixtures for the widget's `#Preview` blocks. Tonight's curfew is 40
  /// minutes out so the countdown has something to show.
  static var preview: CurfewCountdownAttributes {
    CurfewCountdownAttributes(nightID: "night-preview", guardianName: "Jordan")
  }

  static var previewCurfewAt: Date { Date().addingTimeInterval(40 * 60) }

  static func previewState(_ phase: Phase) -> ContentState {
    switch phase {
    case .beforeCurfew, .grace, .checkInDue, .ride:
      ContentState(phase: phase, curfewAt: previewCurfewAt)
    case .checkedIn:
      ContentState(
        phase: phase,
        curfewAt: previewCurfewAt,
        nextCheckInAt: previewCurfewAt.addingTimeInterval(60 * 60)
      )
    }
  }
}
#endif
