import Foundation

// Shared contract between the teen's phone (Shrey) and the guardian side and
// backend (Vinay). Changes to the three types below need both owners.
//
// This file compiles into the public `Sober` target, the internal app, and
// every Curfew extension, so it must stay free of UIKit, SwiftUI, DesignKit,
// and every Screen Time framework.

/// When curfew falls, in the family's time zone.
///
/// `weeknight` and `weekend` carry only `hour` and `minute`. A time before
/// noon belongs to the *following* calendar day: a weekend curfew of 00:30
/// means Friday night's curfew is 00:30 on Saturday.
struct CurfewSchedule: Codable, Equatable, Sendable {
  var weeknight: DateComponents
  var weekend: DateComponents
  var timeZoneIdentifier: String
  /// Minutes between check-ins while away from home after curfew. 60 = hourly.
  var recheckMinutes: Int
  /// Minutes after curfew before apps pause. The countdown still shows curfew.
  var graceMinutes: Int

  init(
    weeknight: DateComponents,
    weekend: DateComponents,
    timeZoneIdentifier: String,
    recheckMinutes: Int,
    graceMinutes: Int
  ) {
    self.weeknight = weeknight
    self.weekend = weekend
    self.timeZoneIdentifier = timeZoneIdentifier
    self.recheckMinutes = recheckMinutes
    self.graceMinutes = graceMinutes
  }

  /// Evenings that use the weekend time. Gregorian weekday numbering:
  /// 1 = Sunday … 6 = Friday, 7 = Saturday. Friday night and Saturday night.
  static let weekendEveningWeekdays: Set<Int> = [6, 7]

  static let minimumRecheckMinutes = 15
  static let maximumGraceMinutes = 120

  /// "Home by 11:00 on weeknights, 12:30 on weekends", hourly re-checks,
  /// ten minutes of grace. The brief's example, used until a guardian sets one.
  static func standard(timeZone: TimeZone = .current) -> CurfewSchedule {
    CurfewSchedule(
      weeknight: time(23, 0),
      weekend: time(0, 30),
      timeZoneIdentifier: timeZone.identifier,
      recheckMinutes: 60,
      graceMinutes: 10
    )
  }

  static func time(_ hour: Int, _ minute: Int) -> DateComponents {
    DateComponents(hour: hour, minute: minute)
  }

  var timeZone: TimeZone? { TimeZone(identifier: timeZoneIdentifier) }

  /// A schedule the evaluator can act on. Anything else is treated as "no
  /// schedule", which pauses nothing.
  var isValid: Bool {
    guard timeZone != nil else { return false }
    guard Self.isValidTime(weeknight), Self.isValidTime(weekend) else { return false }
    guard recheckMinutes >= Self.minimumRecheckMinutes else { return false }
    guard (0...Self.maximumGraceMinutes).contains(graceMinutes) else { return false }
    return true
  }

  /// The curfew time that applies to the evening of `weekday`.
  func curfewTime(forEveningWeekday weekday: Int) -> DateComponents {
    Self.weekendEveningWeekdays.contains(weekday) ? weekend : weeknight
  }

  private static func isValidTime(_ components: DateComponents) -> Bool {
    guard let hour = components.hour, let minute = components.minute else { return false }
    return (0...23).contains(hour) && (0...59).contains(minute)
  }
}

/// The only thing the guardian ever learns about tonight.
///
/// Deliberately has no result, no score, and no "took a check" flag. Adding
/// any of those is a contract change that both owners have agreed not to make.
enum CurfewStatus: String, Codable, Sendable, CaseIterable {
  case home
  case checkedIn
  case askedForRide
  case noCheckInYet

  /// The two statuses a teen's check-in can carry. `home` and `noCheckInYet`
  /// are derived by the guardian side, never sent by the teen.
  static let reportable: Set<CurfewStatus> = [.checkedIn, .askedForRide]

  var isReportable: Bool { Self.reportable.contains(self) }
}

/// One tap of "I'm OK" or "I need a ride", with the location shared at that
/// moment. Identical in shape whether or not the teen ran a Sober check.
struct CurfewCheckIn: Codable, Equatable, Sendable, Identifiable {
  let id: UUID
  let at: Date
  let status: CurfewStatus
  let latitude: Double?
  let longitude: Double?
  let horizontalAccuracyMeters: Double?

  init(
    id: UUID = UUID(),
    at: Date,
    status: CurfewStatus,
    latitude: Double? = nil,
    longitude: Double? = nil,
    horizontalAccuracyMeters: Double? = nil
  ) {
    self.id = id
    self.at = at
    self.status = status
    self.latitude = latitude
    self.longitude = longitude
    self.horizontalAccuracyMeters = horizontalAccuracyMeters
  }

  /// False for a status the teen's phone must never send. The evaluator and
  /// the outbound queue both ignore such records rather than trusting them.
  var isReportable: Bool { status.isReportable }
}
