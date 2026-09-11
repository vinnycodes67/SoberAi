import XCTest

@testable import Sober

/// `CurfewPauseEvaluator.evaluate` is the one function that decides whether the
/// teen's phone is paused. It is compiled into the app and the monitor
/// extension and has no clock of its own, so every rule from
/// `Docs/CURFEW_SHREY_BRIEF.md` §2 is pinned here against a fixed calendar:
/// America/Los_Angeles, the week of Tuesday 8 September 2026.
final class CurfewEvaluatorTests: XCTestCase {

  // MARK: - Fixtures

  static let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = losAngeles
    return calendar
  }

  /// Weeknight 23:00, weekend 00:30, hourly re-checks, ten minutes of grace.
  let schedule = CurfewSchedule.standard(timeZone: CurfewEvaluatorTests.losAngeles)

  /// A wall-clock instant in Los Angeles.
  func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    let components = DateComponents(
      timeZone: Self.losAngeles, year: year, month: month, day: day, hour: hour, minute: minute
    )
    return Self.calendar.date(from: components)!
  }

  // September 2026: Mon 7, Tue 8, Wed 9, Thu 10, Fri 11, Sat 12, Sun 13.
  func tue(_ hour: Int, _ minute: Int) -> Date { date(2026, 9, 8, hour, minute) }
  func wed(_ hour: Int, _ minute: Int) -> Date { date(2026, 9, 9, hour, minute) }
  func fri(_ hour: Int, _ minute: Int) -> Date { date(2026, 9, 11, hour, minute) }
  func sat(_ hour: Int, _ minute: Int) -> Date { date(2026, 9, 12, hour, minute) }
  func sun(_ hour: Int, _ minute: Int) -> Date { date(2026, 9, 13, hour, minute) }

  func evaluate(
    now: Date,
    schedule: CurfewSchedule?? = nil,
    home: CurfewHomeReading? = nil,
    tonight: CurfewTonight? = nil
  ) -> CurfewPauseDecision {
    CurfewPauseEvaluator.evaluate(
      now: now,
      schedule: schedule ?? self.schedule,
      home: home,
      tonight: tonight
    )
  }

  func tuesdayNight() -> CurfewNight {
    CurfewPauseEvaluator.night(eveningOf: tue(12, 0), schedule: schedule)!
  }

  func checkIn(at: Date, status: CurfewStatus = .checkedIn) -> CurfewCheckIn {
    CurfewCheckIn(at: at, status: status)
  }

  func wallClock(_ date: Date) -> (hour: Int, minute: Int) {
    let components = Self.calendar.dateComponents([.hour, .minute], from: date)
    return (components.hour!, components.minute!)
  }

  // MARK: - Weeknight window

  func testTuesdayBeforeCurfewIsBeforeCurfewWithTonightAsNext() {
    guard case let .beforeCurfew(next) = evaluate(now: tue(22, 59)) else {
      return XCTFail("Expected beforeCurfew")
    }
    XCTAssertEqual(next?.curfewAt, tue(23, 0))
    XCTAssertEqual(next?.id, "night-20260908")
    XCTAssertEqual(next?.usesWeekendTime, false)
  }

  func testTuesdayInsideGraceIsGraceNotPaused() {
    let decision = evaluate(now: tue(23, 5))
    guard case let .grace(night) = decision else {
      return XCTFail("Expected grace, got \(decision)")
    }
    XCTAssertEqual(night.curfewAt, tue(23, 0))
    XCTAssertEqual(night.pauseStartsAt, tue(23, 10))
    XCTAssertFalse(decision.shouldPause)
  }

  func testTuesdayAfterGraceIsCheckInDueSincePauseStart() {
    let decision = evaluate(now: tue(23, 15))
    guard case let .checkInDue(night, dueSince) = decision else {
      return XCTFail("Expected checkInDue, got \(decision)")
    }
    XCTAssertEqual(night.id, "night-20260908")
    XCTAssertEqual(dueSince, tue(23, 10))
    XCTAssertTrue(decision.shouldPause)
  }

  func testWednesdayFiveFiftyNineIsStillTuesdayNight() {
    let decision = evaluate(now: wed(5, 59))
    XCTAssertTrue(decision.isWithinCurfewNight)
    XCTAssertEqual(decision.night?.id, "night-20260908")
    XCTAssertEqual(decision.night?.endsAt, wed(6, 0))
    guard case .checkInDue = decision else {
      return XCTFail("Expected checkInDue, got \(decision)")
    }
  }

  func testWednesdaySixIsBeforeWednesdayNight() {
    let decision = evaluate(now: wed(6, 0))
    XCTAssertFalse(decision.isWithinCurfewNight)
    guard case let .beforeCurfew(next) = decision else {
      return XCTFail("Expected beforeCurfew, got \(decision)")
    }
    XCTAssertEqual(next?.id, "night-20260909")
    XCTAssertEqual(next?.curfewAt, wed(23, 0))
  }

  // MARK: - Weekend window

  func testFridayEveningUsesHalfPastMidnightSaturday() {
    let night = CurfewPauseEvaluator.night(eveningOf: fri(18, 0), schedule: schedule)
    XCTAssertEqual(night?.curfewAt, sat(0, 30))
    XCTAssertEqual(night?.usesWeekendTime, true)
    XCTAssertEqual(night?.id, "night-20260911")
  }

  func testSaturdayJustBeforeWeekendCurfewIsBeforeCurfewForFridayNight() {
    guard case let .beforeCurfew(next) = evaluate(now: sat(0, 29)) else {
      return XCTFail("Expected beforeCurfew")
    }
    XCTAssertEqual(next?.curfewAt, sat(0, 30))
    XCTAssertEqual(next?.usesWeekendTime, true)
    XCTAssertEqual(next?.id, "night-20260911")
  }

  func testSaturdayAfterWeekendGraceIsCheckInDue() {
    guard case let .checkInDue(night, dueSince) = evaluate(now: sat(0, 45)) else {
      return XCTFail("Expected checkInDue")
    }
    XCTAssertEqual(night.id, "night-20260911")
    XCTAssertEqual(dueSince, sat(0, 40))
  }

  func testSaturdayNightIsWeekendToo() {
    let night = CurfewPauseEvaluator.night(eveningOf: sat(12, 0), schedule: schedule)
    XCTAssertEqual(night?.usesWeekendTime, true)
    XCTAssertEqual(night?.curfewAt, sun(0, 30))
    XCTAssertEqual(night?.id, "night-20260912")
  }

  func testSundayEveningIsWeeknight() {
    let night = CurfewPauseEvaluator.night(eveningOf: sun(12, 0), schedule: schedule)
    XCTAssertEqual(night?.usesWeekendTime, false)
    XCTAssertEqual(night?.curfewAt, sun(23, 0))
    XCTAssertEqual(night?.id, "night-20260913")
  }

  func testNightIDIsKeyedByEveningDateEvenAfterMidnight() {
    let decision = evaluate(now: sat(1, 0))
    XCTAssertEqual(decision.night?.id, "night-20260911")
  }

  // MARK: - Home reading

  func testFreshHomeReadingIsHome() {
    let now = tue(23, 15)
    let home = CurfewHomeReading(isHome: true, observedAt: now.addingTimeInterval(-10 * 60))
    guard case let .home(night) = evaluate(now: now, home: home) else {
      return XCTFail("Expected home")
    }
    XCTAssertEqual(night.id, "night-20260908")
  }

  func testStaleHomeReadingCountsAsNotHome() {
    let now = tue(23, 15)
    let limit = TimeInterval(CurfewPauseEvaluator.homeFreshnessMinutes * 60)
    let home = CurfewHomeReading(isHome: true, observedAt: now.addingTimeInterval(-(limit + 60)))
    guard case .checkInDue = evaluate(now: now, home: home) else {
      return XCTFail("A reading older than the freshness window must not count as home")
    }
  }

  func testHomeReadingExactlyAtFreshnessLimitStillCounts() {
    let now = tue(23, 15)
    let limit = TimeInterval(CurfewPauseEvaluator.homeFreshnessMinutes * 60)
    let home = CurfewHomeReading(isHome: true, observedAt: now.addingTimeInterval(-limit))
    guard case .home = evaluate(now: now, home: home) else {
      return XCTFail("Expected home at the freshness boundary")
    }
  }

  func testHomeReadingFromTheFutureIsNotHome() {
    let now = tue(23, 15)
    let home = CurfewHomeReading(isHome: true, observedAt: now.addingTimeInterval(60))
    guard case .checkInDue = evaluate(now: now, home: home) else {
      return XCTFail("A future timestamp is a clock problem, not evidence of home")
    }
  }

  func testNotHomeReadingIsCheckInDue() {
    let now = tue(23, 15)
    let home = CurfewHomeReading(isHome: false, observedAt: now)
    guard case .checkInDue = evaluate(now: now, home: home) else {
      return XCTFail("Expected checkInDue")
    }
  }

  // MARK: - Check-ins

  func testRecentCheckInLiftsUntilRecheck() {
    let last = tue(23, 30)
    let now = tue(23, 50)
    let tonight = CurfewTonight(nightID: "night-20260908", checkIns: [checkIn(at: last)])
    guard case let .checkedIn(night, nextCheckInAt) = evaluate(now: now, tonight: tonight) else {
      return XCTFail("Expected checkedIn")
    }
    XCTAssertEqual(night.id, "night-20260908")
    XCTAssertEqual(nextCheckInAt, last.addingTimeInterval(60 * 60))
    XCTAssertEqual(nextCheckInAt, wed(0, 30))
  }

  func testCheckInOlderThanRecheckIsDueAgainSinceRecheck() {
    let last = tue(23, 30)
    let now = wed(0, 31)
    let tonight = CurfewTonight(nightID: "night-20260908", checkIns: [checkIn(at: last)])
    let decision = evaluate(now: now, tonight: tonight)
    guard case let .checkInDue(_, dueSince) = decision else {
      return XCTFail("Expected checkInDue, got \(decision)")
    }
    XCTAssertEqual(dueSince, last.addingTimeInterval(60 * 60))
    XCTAssertTrue(decision.shouldPause)
  }

  func testCheckInFromAnotherNightIsIgnored() {
    let now = tue(23, 50)
    let yesterday = CurfewTonight(
      nightID: "night-20260907",
      checkIns: [checkIn(at: now.addingTimeInterval(-20 * 60))]
    )
    guard case .checkInDue = evaluate(now: now, tonight: yesterday) else {
      return XCTFail("A check-in recorded under a different night id must not lift tonight")
    }
  }

  func testAskingForRideLiftsForTheNightDespiteStaleHomeAndOldCheckIns() {
    let now = wed(4, 0)
    let stale = CurfewHomeReading(isHome: true, observedAt: tue(20, 0))
    let tonight = CurfewTonight(
      nightID: "night-20260908",
      checkIns: [
        checkIn(at: tue(23, 20)),
        checkIn(at: tue(23, 40), status: .askedForRide),
      ]
    )
    let decision = evaluate(now: now, home: stale, tonight: tonight)
    guard case let .liftedForRide(night) = decision else {
      return XCTFail("Expected liftedForRide, got \(decision)")
    }
    XCTAssertEqual(night.id, "night-20260908")
    XCTAssertFalse(decision.shouldPause)
  }

  func testHomeWinsOverCheckedIn() {
    let now = tue(23, 50)
    let home = CurfewHomeReading(isHome: true, observedAt: now)
    let tonight = CurfewTonight(nightID: "night-20260908", checkIns: [checkIn(at: tue(23, 30))])
    guard case .home = evaluate(now: now, home: home, tonight: tonight) else {
      return XCTFail("A fresh home reading outranks a check-in")
    }
  }

  func testCheckInDuringGraceIsCheckedIn() {
    let now = tue(23, 5)
    let tonight = CurfewTonight(nightID: "night-20260908", checkIns: [checkIn(at: tue(23, 2))])
    guard case let .checkedIn(_, nextCheckInAt) = evaluate(now: now, tonight: tonight) else {
      return XCTFail("Expected checkedIn")
    }
    XCTAssertEqual(nextCheckInAt, wed(0, 2))
  }

  func testNonReportableCheckInsAreIgnoredByTonight() {
    let tonight = CurfewTonight(
      nightID: "night-20260908",
      checkIns: [
        checkIn(at: tue(23, 20), status: .home),
        checkIn(at: tue(23, 25), status: .noCheckInYet),
      ]
    )
    XCTAssertTrue(tonight.reportableCheckIns.isEmpty)
    XCTAssertNil(tonight.lastCheckInAt)
    XCTAssertFalse(tonight.askedForRide)

    guard case .checkInDue = evaluate(now: tue(23, 30), tonight: tonight) else {
      return XCTFail("A status the teen can never send must not lift the pause")
    }
  }

  // MARK: - Schedule validity

  func testRecheckBelowMinimumIsNoSchedule() {
    var invalid = schedule
    invalid.recheckMinutes = 5
    XCTAssertFalse(invalid.isValid)
    XCTAssertEqual(evaluate(now: tue(23, 15), schedule: .some(invalid)), .noSchedule)
  }

  func testGraceAboveMaximumIsNoSchedule() {
    var invalid = schedule
    invalid.graceMinutes = 500
    XCTAssertFalse(invalid.isValid)
    XCTAssertEqual(evaluate(now: tue(23, 15), schedule: .some(invalid)), .noSchedule)
  }

  func testUnknownTimeZoneIsNoSchedule() {
    var invalid = schedule
    invalid.timeZoneIdentifier = "Mars/Olympus_Mons"
    XCTAssertFalse(invalid.isValid)
    XCTAssertEqual(evaluate(now: tue(23, 15), schedule: .some(invalid)), .noSchedule)
  }

  func testHourOutOfRangeIsNoSchedule() {
    var invalid = schedule
    invalid.weeknight = CurfewSchedule.time(25, 0)
    XCTAssertFalse(invalid.isValid)
    XCTAssertEqual(evaluate(now: tue(23, 15), schedule: .some(invalid)), .noSchedule)
  }

  func testNilScheduleIsNoSchedule() {
    let decision = evaluate(now: tue(23, 15), schedule: .some(nil))
    XCTAssertEqual(decision, .noSchedule)
    XCTAssertFalse(decision.shouldPause)
  }

  // MARK: - shouldPause

  func testOnlyCheckInDueShouldPause() {
    let night = tuesdayNight()
    let every: [CurfewPauseDecision] = [
      .noSchedule,
      .beforeCurfew(next: night),
      .beforeCurfew(next: nil),
      .grace(night),
      .home(night),
      .liftedForRide(night),
      .checkedIn(night, nextCheckInAt: wed(0, 30)),
      .checkInDue(night, dueSince: tue(23, 10)),
    ]
    for decision in every {
      if case .checkInDue = decision {
        XCTAssertTrue(decision.shouldPause, "\(decision)")
      } else {
        XCTAssertFalse(decision.shouldPause, "\(decision)")
      }
    }
    XCTAssertEqual(every.filter(\.shouldPause).count, 1)
  }

  // MARK: - Daylight saving

  func testFallBackNightKeepsWallClockCurfew() {
    // Sunday 1 November 2026: 02:00 PDT becomes 01:00 PST. Saturday night's
    // weekend curfew at 00:30 sits just before the repeated hour.
    let saturday = date(2026, 10, 31, 12, 0)
    let night = CurfewPauseEvaluator.night(eveningOf: saturday, schedule: schedule)
    XCTAssertNotNil(night)
    guard let night else { return }
    XCTAssertEqual(wallClock(night.curfewAt).hour, 0)
    XCTAssertEqual(wallClock(night.curfewAt).minute, 30)
    XCTAssertLessThanOrEqual(night.curfewAt, night.pauseStartsAt)
    XCTAssertLessThanOrEqual(night.curfewAt, night.endsAt)
    XCTAssertEqual(night.id, "night-20261031")

    // The Sunday-evening weeknight, after the transition.
    let sunday = date(2026, 11, 1, 12, 0)
    let sundayNight = CurfewPauseEvaluator.night(eveningOf: sunday, schedule: schedule)
    XCTAssertEqual(sundayNight.map { wallClock($0.curfewAt).hour }, 23)
    XCTAssertEqual(sundayNight.map { wallClock($0.curfewAt).minute }, 0)
    XCTAssertLessThanOrEqual(sundayNight!.curfewAt, sundayNight!.endsAt)

    // And evaluating inside the repeated hour does not crash or leave the night.
    let inside = date(2026, 11, 1, 1, 30)
    XCTAssertTrue(evaluate(now: inside).isWithinCurfewNight)
  }

  func testSpringForwardNightKeepsWallClockCurfew() {
    // Sunday 8 March 2026: 02:00 PST becomes 03:00 PDT. Saturday night's curfew
    // at 00:30 exists; the skipped hour falls inside the window.
    let saturday = date(2026, 3, 7, 12, 0)
    let night = CurfewPauseEvaluator.night(eveningOf: saturday, schedule: schedule)
    XCTAssertNotNil(night)
    guard let night else { return }
    XCTAssertEqual(wallClock(night.curfewAt).hour, 0)
    XCTAssertEqual(wallClock(night.curfewAt).minute, 30)
    XCTAssertLessThanOrEqual(night.curfewAt, night.endsAt)
    XCTAssertEqual(night.id, "night-20260307")

    let afterSkip = date(2026, 3, 8, 3, 30)
    XCTAssertTrue(evaluate(now: afterSkip).isWithinCurfewNight)
    XCTAssertEqual(evaluate(now: afterSkip).night?.id, "night-20260307")
  }

  func testCurfewInsideSkippedHourStillYieldsAnOrderedNight() {
    // A curfew set to 02:30 on the spring-forward night names a wall-clock
    // time that never happens. It must resolve to something, not crash.
    var odd = schedule
    odd.weekend = CurfewSchedule.time(2, 30)
    let saturday = date(2026, 3, 7, 12, 0)
    let night = CurfewPauseEvaluator.night(eveningOf: saturday, schedule: odd)
    XCTAssertNotNil(night)
    guard let night else { return }
    XCTAssertLessThanOrEqual(night.curfewAt, night.pauseStartsAt)
    XCTAssertLessThanOrEqual(night.curfewAt, night.endsAt)
    XCTAssertEqual(night.id, "night-20260307")
  }
}
