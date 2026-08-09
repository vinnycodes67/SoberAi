import XCTest

@testable import Sober

/// A failed read must never look like deletion.
///
/// This is a halt criterion in the release runbook — "history, baseline, or
/// Safety Plan disappearing" — and without these it would be indistinguishable
/// from a corrupted file. Someone seeing an empty History and a zero baseline
/// would reasonably conclude the app lost their data and start recording five
/// new baseline sessions over data that is still on disk.
@MainActor
final class LocalDataFailureTests: XCTestCase {

  private struct Harness {
    let model: AppModel
    let historyDirectory: URL
    let researchDirectory: URL
  }

  private func makeHarness() -> Harness {
    let suiteName = "LocalDataFailureTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let research = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let history = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    addTeardownBlock {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: research)
      try? FileManager.default.removeItem(at: history)
    }
    let model = AppModel(
      defaults: defaults,
      researchStore: ResearchSessionStore(directoryURL: research),
      checkHistoryStore: CheckHistoryStore(directoryURL: history),
      automaticallyStartsGuardianServices: false,
      allowsInternalTools: false
    )
    return Harness(model: model, historyDirectory: history, researchDirectory: research)
  }

  private func writeGarbage(to directory: URL, named name: String) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? Data("{ not json".utf8).write(to: directory.appendingPathComponent(name))
  }

  func testUnreadableHistoryReportsAFailureRatherThanAnEmptyList() async {
    let harness = makeHarness()
    writeGarbage(to: harness.historyDirectory, named: "check-history-v1.json")

    await harness.model.reloadCheckHistory()

    XCTAssertEqual(harness.model.localDataError, .history)
  }

  /// The entries already on screen stay there. Replacing them with an empty
  /// array on a failed refresh is the behaviour that reads as deletion.
  func testAFailedRefreshDoesNotClearLoadedHistory() async {
    let harness = makeHarness()
    await harness.model.recordCompletedSession(
      mode: .check,
      selfReport: .no,
      metrics: ScreeningMetrics(
        reactionTimeMilliseconds: 420, reactionMisses: 0, trackingError: 0.2,
        timeEstimateError: 0.1, gazeSmoothness: 0.2, qualityScore: 0.9,
        completedAllTasks: true),
      reactionSummary: nil,
      ocularSummary: nil,
      startedAt: Date(),
      outcome: ScreeningOutcome(
        state: .noSignalsDetected, qualityScore: 0.9, riskScore: 0.1, details: [])
    )
    XCTAssertEqual(harness.model.checkHistory.count, 1)

    writeGarbage(to: harness.historyDirectory, named: "check-history-v1.json")
    await harness.model.reloadCheckHistory()

    XCTAssertEqual(harness.model.localDataError, .history)
    XCTAssertEqual(
      harness.model.checkHistory.count, 1,
      "a failed read must not empty the list that is already on screen")
  }

  func testUnreadableSessionsReportAFailure() async {
    let harness = makeHarness()
    writeGarbage(to: harness.researchDirectory, named: "research-sessions-v1.json")

    await harness.model.reloadResearchData()

    XCTAssertEqual(harness.model.localDataError, .sessions)
  }

  /// The dangerous one. Recomputing the measured count from a failed read would
  /// zero a baseline that is still on disk, and the app would then ask for five
  /// more sessions.
  func testAFailedSessionReadDoesNotZeroTheMeasuredBaseline() async {
    let harness = makeHarness()
    harness.model.setMeasuredBaselineSessionsForTesting(5)
    XCTAssertTrue(harness.model.baselineReady)

    writeGarbage(to: harness.researchDirectory, named: "research-sessions-v1.json")
    await harness.model.reloadResearchData()

    XCTAssertEqual(harness.model.baselineSessions, 5)
    XCTAssertTrue(
      harness.model.baselineReady,
      "an unreadable archive must not present as a lost baseline")
  }

  func testRecoveringFromAFailureClearsTheError() async {
    let harness = makeHarness()
    writeGarbage(to: harness.historyDirectory, named: "check-history-v1.json")
    await harness.model.reloadCheckHistory()
    XCTAssertEqual(harness.model.localDataError, .history)

    try? FileManager.default.removeItem(
      at: harness.historyDirectory.appendingPathComponent("check-history-v1.json"))
    await harness.model.reloadCheckHistory()

    XCTAssertNil(harness.model.localDataError)
  }
}
