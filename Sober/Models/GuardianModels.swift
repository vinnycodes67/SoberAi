import Foundation

/// Which side of a paired Guardian Mode setup this install represents.
/// `.none` is the default — Guardian Mode is entirely opt-in, mutually
/// visible on both phones once paired, and never covert. There is no
/// employer or law-enforcement variant of this role.
enum GuardianRole: String, Codable, Sendable {
  case none
  case teen
  case parent
}

enum Weekday: Int, CaseIterable, Codable, Sendable, Comparable {
  case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

  static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

  var shortLabel: String {
    switch self {
    case .sunday: "Sun"
    case .monday: "Mon"
    case .tuesday: "Tue"
    case .wednesday: "Wed"
    case .thursday: "Thu"
    case .friday: "Fri"
    case .saturday: "Sat"
    }
  }
}

/// The parent-configured schedule for when a driving check is expected.
/// A window opens at `startHour:startMinute` on any `activeDay` and always
/// closes at 6 AM the following morning, or earlier the moment a valid
/// check is recorded — see `GuardianCheckWindowState`.
struct DrivingSchedule: Codable, Equatable, Sendable {
  var activeDays: Set<Weekday>
  var startHour: Int
  var startMinute: Int

  static let `default` = DrivingSchedule(
    activeDays: [.friday, .saturday],
    startHour: 22,
    startMinute: 0
  )

  /// The window containing `date`, or `nil` if `date` falls outside every
  /// configured window. Checks both "the window that started today" and
  /// "the window that started yesterday evening" so a lookup just after
  /// midnight still resolves to last night's window rather than missing it.
  func window(containing date: Date, calendar: Calendar = .current) -> DrivingWindow? {
    for daysAgo in [0, 1] {
      guard let anchorDay = calendar.date(byAdding: .day, value: -daysAgo, to: date) else {
        continue
      }
      let anchorStartOfDay = calendar.startOfDay(for: anchorDay)
      guard
        let weekday = Weekday(rawValue: calendar.component(.weekday, from: anchorStartOfDay)),
        activeDays.contains(weekday),
        let windowStart = calendar.date(
          bySettingHour: startHour, minute: startMinute, second: 0, of: anchorStartOfDay),
        let nextDay = calendar.date(byAdding: .day, value: 1, to: anchorStartOfDay),
        let windowEnd = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: nextDay)
      else { continue }

      if date >= windowStart, date < windowEnd {
        return DrivingWindow(id: anchorStartOfDay, startedAt: windowStart, endsAt: windowEnd)
      }
    }
    return nil
  }
}

/// One night's configured driving-check window.
struct DrivingWindow: Equatable, Sendable {
  /// Stable per-night identifier — the calendar day the window's start time
  /// falls on. Used to key `GuardianCheckWindowState` and dedupe sync events.
  let id: Date
  let startedAt: Date
  let endsAt: Date
}

/// The only fact that ever leaves the teen's phone. Never a score, a
/// metric, or anything derived from camera or pupil capture — see
/// `GuardianSyncEvent`.
enum GuardianCheckOutcome: String, Codable, CaseIterable, Sendable {
  case completed
  case missed
}

/// The payload synced to the shared CloudKit zone. Deliberately minimal: a
/// window identifier, a completed-or-missed fact, and when it happened. No
/// biometric data, frame, landmark, or risk score is ever included here —
/// this is the same constraint the screening pipeline already enforces for
/// parent alerts, extended to Guardian Mode.
struct GuardianSyncEvent: Codable, Equatable, Sendable {
  var windowID: Date
  var outcome: GuardianCheckOutcome
  var occurredAt: Date
}

/// Local-only per-window state on the teen's phone. Governs retry and
/// retest rules; never leaves the device.
struct GuardianCheckWindowState: Codable, Equatable, Sendable {
  var windowID: Date
  /// Count of non-inconclusive (valid) results recorded in this window.
  /// INCONCLUSIVE never increments this, so retries on it are unlimited.
  var validResultCount: Int = 0
  var lastValidResultAt: Date?
  var missedAlertSent = false

  static let retestCooldown: TimeInterval = 15 * 60
  static let maximumValidResults = 2

  var isSatisfied: Bool { validResultCount >= 1 }

  func canRetest(at date: Date = Date()) -> Bool {
    guard validResultCount >= 1, validResultCount < Self.maximumValidResults else { return false }
    guard let lastValidResultAt else { return true }
    return date.timeIntervalSince(lastValidResultAt) >= Self.retestCooldown
  }

  var retestAvailableAt: Date? {
    guard lastValidResultAt != nil, validResultCount < Self.maximumValidResults else { return nil }
    return lastValidResultAt?.addingTimeInterval(Self.retestCooldown)
  }

  mutating func recordValidResult(at date: Date = Date()) {
    validResultCount += 1
    lastValidResultAt = date
  }
}

/// Display-only information about the paired participant. Never includes
/// anything derived from a screening result.
struct GuardianPairingInfo: Codable, Equatable, Sendable {
  var participantName: String
  var pairedAt: Date
}
