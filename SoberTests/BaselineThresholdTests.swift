import XCTest

@testable import Sober

/// The baseline numbers must have exactly one definition.
///
/// Readiness lived in `AppModel` as a bare `>= 5` and acceptance in
/// `ScreeningFlowView` as a bare `>= 0.72`, both independent of
/// `BaselineProfileEngine`. Tuning the engine moved scoring while leaving those
/// two insisting on the old number, so the app could call itself ready and then
/// refuse to compare. Device testing is expected to move `minimumQuality`, so
/// this has to stay consolidated.
@MainActor
final class BaselineThresholdTests: XCTestCase {

  func testEngineDefaultsComeFromTheSharedConstants() {
    let engine = BaselineProfileEngine()
    XCTAssertEqual(engine.minimumQuality, BaselineThresholds.minimumQuality)
    XCTAssertEqual(engine.minimumRequiredSessions, BaselineThresholds.requiredSessions)
  }

  func testTheScoringWindowIsTheSharedConstant() {
    XCTAssertEqual(PersonalBaseline.requiredSessions, BaselineThresholds.scoringWindow)
    XCTAssertLessThan(
      BaselineThresholds.scoringWindow, BaselineThresholds.requiredSessions,
      "scoring against more sessions than are required would never be satisfiable")
  }

  /// Readiness must follow the constant, not a copy of today's value.
  func testReadinessFlipsAtTheSharedRequiredCount() {
    let suiteName = "BaselineThresholdTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
    let model = AppModel(
      defaults: defaults,
      automaticallyStartsGuardianServices: false,
      allowsInternalTools: false
    )

    model.setMeasuredBaselineSessionsForTesting(BaselineThresholds.requiredSessions - 1)
    XCTAssertFalse(model.baselineReady, "one short of the requirement is not ready")

    model.setMeasuredBaselineSessionsForTesting(BaselineThresholds.requiredSessions)
    XCTAssertTrue(model.baselineReady, "exactly the requirement is ready")
  }

  /// A source scan, because the failure mode is someone typing the number again
  /// rather than calling the constant. Same approach as the Curfew source rules.
  func testNoLogicFileHardcodesAThreshold() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let scanned = [
      "Sober/App/AppModel.swift",
      "Sober/Services/BaselineProfileEngine.swift",
      "Sober/Services/ScreeningEngine.swift",
      "Sober/Features/Screening/ScreeningFlowView.swift",
    ]

    for path in scanned {
      let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
      for offender in [">= 0.72", ">= 5 ", ">= 5\n", "> 0.72"] {
        XCTAssertFalse(
          source.contains(offender),
          "\(path) hardcodes \"\(offender.trimmingCharacters(in: .whitespacesAndNewlines))\" — use BaselineThresholds")
      }
    }
  }

  /// The screens that show progress toward the requirement. A typed `5` here
  /// is cosmetic until the number moves, and then the meter and the engine
  /// disagree in front of the person.
  func testNoScreenHardcodesAThreshold() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let scanned = [
      "Sober/DesignKit/Screens/DSIntegratedHomeScreen.swift",
      "Sober/DesignKit/DSGallery.swift",
      "Sober/Features/History/HistoryView.swift",
      "Sober/Features/Steady/YourSteadyView.swift",
    ]

    for path in scanned {
      let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
      for offender in ["of 5 ", "total: 5", "?? 5\n", "0.72", "\"Five "] {
        XCTAssertFalse(
          source.contains(offender),
          "\(path) hardcodes \"\(offender.trimmingCharacters(in: .whitespacesAndNewlines))\" — use BaselineThresholds")
      }
    }
  }

  func testRequiredSessionsInWordsFollowsTheConstant() {
    let words = BaselineThresholds.requiredSessionsInWords
    XCTAssertEqual(
      words,
      NumberFormatter.localizedString(
        from: NSNumber(value: BaselineThresholds.requiredSessions), number: .spellOut))
    XCTAssertEqual(
      BaselineThresholds.requiredSessionsInWordsCapitalized.lowercased(), words.lowercased())
    XCTAssertEqual(
      BaselineThresholds.requiredSessionsInWordsCapitalized.first?.isUppercase, true)
  }
}
