import Foundation

// The one decision function: "should this phone be paused right now?"
//
// Compiled into the internal app and the DeviceActivity monitor extension so
// both reach the same answer from the same inputs. It is pure — no clock, no
// store, no framework — so it is unit-tested in SoberTests instead of only on a
// device at 11 p.m.
//
// Rules it encodes (see Docs/CURFEW_SHREY_BRIEF.md §2):
//   • A check-in lifts the pause. A Sober result is not an input at all.
//   • Unknown or stale home state counts as *not* home. That is safe only
//     because the pause never touches the ride path.
//   • Asking for a ride lifts the pause for the rest of the night.

/// One night's curfew window, keyed by the evening it belongs to.
struct CurfewNight: Equatable, Sendable {
  /// `night-YYYYMMDD` of the evening date, in the schedule's time zone.
  let id: String
  let curfewAt: Date
  /// Curfew plus grace. Apps pause from here, not from `curfewAt`.
  let pauseStartsAt: Date
  /// When the night is over regardless of check-ins.
  let endsAt: Date
  let usesWeekendTime: Bool
}

/// What the main app last learned from the home region monitor.
struct CurfewHomeReading: Codable, Equatable, Sendable {
  var isHome: Bool
  var observedAt: Date

  init(isHome: Bool, observedAt: Date) {
    self.isHome = isHome
    self.observedAt = observedAt
  }
}

/// Tonight's check-ins. Reset when a new night begins.
struct CurfewTonight: Codable, Equatable, Sendable {
  var nightID: String
  var checkIns: [CurfewCheckIn]

  init(nightID: String, checkIns: [CurfewCheckIn] = []) {
    self.nightID = nightID
    self.checkIns = checkIns
  }

  var reportableCheckIns: [CurfewCheckIn] { checkIns.filter(\.isReportable) }
  var askedForRide: Bool { reportableCheckIns.contains { $0.status == .askedForRide } }
  var lastCheckInAt: Date? { reportableCheckIns.map(\.at).max() }
}

enum CurfewPauseDecision: Equatable, Sendable {
  /// No valid schedule. Nothing is ever paused.
  case noSchedule
  /// Outside any curfew window. `next` is nil only if no night can be computed.
  case beforeCurfew(next: CurfewNight?)
  /// Curfew has passed but grace has not. Countdown shows; nothing paused yet.
  case grace(CurfewNight)
  /// Fresh reading says home. Nothing happens.
  case home(CurfewNight)
  /// The teen asked for a ride tonight. Nothing more is asked of them.
  case liftedForRide(CurfewNight)
  /// Checked in recently. Paused again at `nextCheckInAt` if still not home.
  case checkedIn(CurfewNight, nextCheckInAt: Date)
  /// Apps are paused until the teen checks in.
  case checkInDue(CurfewNight, dueSince: Date)

  /// The only state in which the named ManagedSettings store carries a shield.
  var shouldPause: Bool {
    if case .checkInDue = self { return true }
    return false
  }

  var night: CurfewNight? {
    switch self {
    case .noSchedule: nil
    case let .beforeCurfew(next): next
    case let .grace(night), let .home(night), let .liftedForRide(night): night
    case let .checkedIn(night, _), let .checkInDue(night, _): night
    }
  }

  /// True while a curfew window is open, whatever the pause state.
  var isWithinCurfewNight: Bool {
    switch self {
    case .noSchedule, .beforeCurfew: false
    case .grace, .home, .liftedForRide, .checkedIn, .checkInDue: true
    }
  }
}

enum CurfewPauseEvaluator {
  /// A night runs from curfew for this long: 23:00 → 06:00, 00:30 → 07:30.
  static let nightLengthMinutes = 7 * 60
  /// A home reading older than this is treated as unknown, i.e. not home.
  ///
  /// Region monitoring writes a reading only on a boundary crossing, on
  /// `start()`, and on a decisive one-shot fix, so a teen home since 8 p.m. has
  /// an "inside" reading that is hours old at 11 p.m. iOS delivers the exit
  /// event even when the app is not running, which keeps that reading true
  /// until it is contradicted; the window here only bounds how long a phone
  /// that lost location access (permission revoked, powered off) can be
  /// trusted. A wrong guess pauses social apps until the teen opens Sober,
  /// which refreshes the reading and lifts the pause — harmless by design.
  static let homeFreshnessMinutes = 8 * 60

  static func evaluate(
    now: Date,
    schedule: CurfewSchedule?,
    home: CurfewHomeReading?,
    tonight: CurfewTonight?,
    homeFreshness: TimeInterval = TimeInterval(homeFreshnessMinutes * 60)
  ) -> CurfewPauseDecision {
    guard let schedule, schedule.isValid else { return .noSchedule }
    guard let night = activeNight(at: now, schedule: schedule) else {
      return .beforeCurfew(next: nextNight(after: now, schedule: schedule))
    }

    let record: CurfewTonight? = (tonight?.nightID == night.id) ? tonight : nil
    if record?.askedForRide == true { return .liftedForRide(night) }

    if let home, home.isHome, isFresh(home, now: now, within: homeFreshness) {
      return .home(night)
    }

    let recheck = TimeInterval(schedule.recheckMinutes * 60)
    if let last = record?.lastCheckInAt, last <= now {
      let next = last.addingTimeInterval(recheck)
      if now < next { return .checkedIn(night, nextCheckInAt: next) }
      if now < night.pauseStartsAt { return .grace(night) }
      return .checkInDue(night, dueSince: max(next, night.pauseStartsAt))
    }

    if now < night.pauseStartsAt { return .grace(night) }
    return .checkInDue(night, dueSince: night.pauseStartsAt)
  }

  /// The night whose window contains `now`, if any.
  static func activeNight(at now: Date, schedule: CurfewSchedule) -> CurfewNight? {
    guard let calendar = calendar(for: schedule) else { return nil }
    let today = calendar.startOfDay(for: now)
    for offset in [0, -1] {
      guard let evening = calendar.date(byAdding: .day, value: offset, to: today),
        let night = night(eveningOf: evening, schedule: schedule, calendar: calendar)
      else { continue }
      if night.curfewAt <= now, now < night.endsAt { return night }
    }
    return nil
  }

  /// The first night whose curfew is still ahead of `now`.
  static func nextNight(after now: Date, schedule: CurfewSchedule) -> CurfewNight? {
    guard let calendar = calendar(for: schedule) else { return nil }
    let today = calendar.startOfDay(for: now)
    for offset in -1...8 {
      guard let evening = calendar.date(byAdding: .day, value: offset, to: today),
        let night = night(eveningOf: evening, schedule: schedule, calendar: calendar)
      else { continue }
      if night.curfewAt > now { return night }
    }
    return nil
  }

  /// The curfew night for the evening of `day` (any instant on that calendar day).
  static func night(eveningOf day: Date, schedule: CurfewSchedule) -> CurfewNight? {
    guard let calendar = calendar(for: schedule) else { return nil }
    return night(eveningOf: day, schedule: schedule, calendar: calendar)
  }

  static func isFresh(_ reading: CurfewHomeReading, now: Date, within freshness: TimeInterval) -> Bool {
    // A timestamp from the future is a clock problem, not evidence of home.
    guard reading.observedAt <= now else { return false }
    return now.timeIntervalSince(reading.observedAt) <= freshness
  }

  static func calendar(for schedule: CurfewSchedule) -> Calendar? {
    guard let zone = schedule.timeZone else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
  }

  private static func night(
    eveningOf day: Date,
    schedule: CurfewSchedule,
    calendar: Calendar
  ) -> CurfewNight? {
    let evening = calendar.startOfDay(for: day)
    let weekday = calendar.component(.weekday, from: evening)
    let usesWeekendTime = CurfewSchedule.weekendEveningWeekdays.contains(weekday)
    let time = schedule.curfewTime(forEveningWeekday: weekday)
    guard let hour = time.hour, let minute = time.minute else { return nil }

    // Before noon means "the small hours of the next morning".
    let anchorDay: Date
    if hour < 12 {
      guard let next = calendar.date(byAdding: .day, value: 1, to: evening) else { return nil }
      anchorDay = next
    } else {
      anchorDay = evening
    }
    guard let curfewAt = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: anchorDay)
    else { return nil }

    let components = calendar.dateComponents([.year, .month, .day], from: evening)
    let id = String(
      format: "night-%04d%02d%02d",
      components.year ?? 0, components.month ?? 0, components.day ?? 0
    )
    return CurfewNight(
      id: id,
      curfewAt: curfewAt,
      pauseStartsAt: curfewAt.addingTimeInterval(TimeInterval(schedule.graceMinutes * 60)),
      endsAt: curfewAt.addingTimeInterval(TimeInterval(nightLengthMinutes * 60)),
      usesWeekendTime: usesWeekendTime
    )
  }
}
