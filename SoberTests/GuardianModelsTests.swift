import XCTest

@testable import Sober

final class GuardianModelsTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    calendar.date(
      from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  // MARK: - DrivingSchedule window lookup

  func testWindowOpensAtScheduledStartOnActiveDay() {
    // 2026-08-07 is a Friday.
    let schedule = DrivingSchedule(activeDays: [.friday], startHour: 22, startMinute: 0)
    let justBefore = date(2026, 8, 7, 21, 59)
    let justAfter = date(2026, 8, 7, 22, 0)

    XCTAssertNil(schedule.window(containing: justBefore, calendar: calendar))
    XCTAssertNotNil(schedule.window(containing: justAfter, calendar: calendar))
  }

  func testWindowSpansPastMidnightUntilSixAM() {
    let schedule = DrivingSchedule(activeDays: [.friday], startHour: 22, startMinute: 0)
    let earlyMorning = date(2026, 8, 8, 5, 59)  // Saturday 5:59 AM, still Friday's window
    let afterCutoff = date(2026, 8, 8, 6, 0)

    let window = schedule.window(containing: earlyMorning, calendar: calendar)
    XCTAssertNotNil(window)
    XCTAssertNil(schedule.window(containing: afterCutoff, calendar: calendar))
  }

  func testWindowIsNilOnInactiveDay() {
    let schedule = DrivingSchedule(activeDays: [.friday, .saturday], startHour: 22, startMinute: 0)
    // 2026-08-05 is a Wednesday.
    let wednesdayNight = date(2026, 8, 5, 23, 0)
    XCTAssertNil(schedule.window(containing: wednesdayNight, calendar: calendar))
  }

  func testEarlyMorningAndEveningResolveToDistinctWindowIDs() {
    let schedule = DrivingSchedule(activeDays: [.friday, .saturday], startHour: 22, startMinute: 0)
    let fridayNight = schedule.window(
      containing: date(2026, 8, 7, 23, 0), calendar: calendar)
    let saturdayEarlyMorning = schedule.window(
      containing: date(2026, 8, 8, 2, 0), calendar: calendar)
    let saturdayNight = schedule.window(
      containing: date(2026, 8, 8, 23, 0), calendar: calendar)

    XCTAssertEqual(fridayNight?.id, saturdayEarlyMorning?.id)
    XCTAssertNotEqual(fridayNight?.id, saturdayNight?.id)
  }

  // MARK: - Retry / retest state machine

  func testFreshWindowIsUnsatisfiedAndCannotRetest() {
    let state = GuardianCheckWindowState(windowID: Date())
    XCTAssertFalse(state.isSatisfied)
    XCTAssertFalse(state.canRetest())
  }

  func testFirstValidResultSatisfiesWindowButOffersOneRetestAfterCooldown() {
    var state = GuardianCheckWindowState(windowID: Date())
    let firstResultAt = date(2026, 8, 7, 22, 30)
    state.recordValidResult(at: firstResultAt)

    XCTAssertTrue(state.isSatisfied)
    XCTAssertFalse(
      state.canRetest(at: firstResultAt.addingTimeInterval(5 * 60)),
      "retest must wait for the 15-minute cooldown")
    XCTAssertTrue(state.canRetest(at: firstResultAt.addingTimeInterval(15 * 60)))
  }

  func testSecondValidResultIsFinalWithNoFurtherRetest() {
    var state = GuardianCheckWindowState(windowID: Date())
    let first = date(2026, 8, 7, 22, 0)
    state.recordValidResult(at: first)
    state.recordValidResult(at: first.addingTimeInterval(GuardianCheckWindowState.retestCooldown))

    XCTAssertEqual(state.validResultCount, GuardianCheckWindowState.maximumValidResults)
    XCTAssertFalse(state.canRetest(at: first.addingTimeInterval(60 * 60)))
    XCTAssertNil(state.retestAvailableAt)
  }

  func testInconclusiveNeverTouchesWindowState() {
    // INCONCLUSIVE results never call recordValidResult at all, so the
    // window stays unsatisfied and retries stay unlimited — this is
    // enforced by the caller (GuardianCoordinator.recordScreeningResult
    // only calls recordValidResult when isValid is true), so this test
    // documents the invariant at the state-machine level: an untouched
    // state never reports itself satisfied no matter how much time passes.
    let state = GuardianCheckWindowState(windowID: Date())
    XCTAssertFalse(state.isSatisfied)
    XCTAssertEqual(state.validResultCount, 0)
  }

  // MARK: - Sync payload never carries biometric data

  func testSyncEventPayloadContainsOnlyTheBehavioralFact() throws {
    let event = GuardianSyncEvent(windowID: Date(), outcome: .missed, occurredAt: Date())
    let data = try JSONEncoder().encode(event)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    XCTAssertEqual(
      Set(json?.keys.map { $0 } ?? []), ["windowID", "outcome", "occurredAt"],
      "the payload that leaves the phone must never grow a score or metric field")
  }

  func testSyncEventOutcomeIsNeverAnythingOtherThanCompletedOrMissed() {
    XCTAssertEqual(GuardianCheckOutcome.completed.rawValue, "completed")
    XCTAssertEqual(GuardianCheckOutcome.missed.rawValue, "missed")
    XCTAssertEqual(GuardianCheckOutcome.allCases.count, 2)
  }
}
