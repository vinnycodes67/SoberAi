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
      baselineStore: LocalBaselineStore(
        defaults: defaults,
        archive: ResearchSessionStore(directoryURL: research)
      ),
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
  /// The entries already on screen stay there. Replacing them with an empty
  /// array on a failed refresh is the behaviour that reads as deletion.
  ///
  /// Seeded through the store directly rather than `recordCompletedSession`,
  /// which spawns async work whose completion this test does not control --
  /// that made it pass alone and fail in a full run.
  func testAFailedRefreshDoesNotClearLoadedHistory() async throws {
    let harness = makeHarness()
    let store = CheckHistoryStore(directoryURL: harness.historyDirectory)
    try await store.append(
      CheckHistoryEntry(
        id: UUID(),
        startedAt: Date(),
        kind: .check,
        outcome: .noSignalsDetected,
        qualityScore: 0.9,
        completedAllTasks: true
      )
    )

    await harness.model.reloadCheckHistory()
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

  /// The subtle one, where both obvious answers are wrong.
  ///
  /// Zeroing the count on a failed read tells someone they have no sessions and
  /// invites them to record five more over data still on disk. But leaving
  /// `baselineReady` true is worse: the check would run and be scored against
  /// population norms while the UI claimed it was comparing to this person.
  ///
  /// So the count survives and readiness does not.
  func testAFailedSessionReadClearsReadinessAndExplainsWhy() async {
    let harness = makeHarness()
    harness.model.setMeasuredBaselineSessionsForTesting(5)
    XCTAssertTrue(harness.model.baselineReady)

    writeGarbage(to: harness.researchDirectory, named: "research-sessions-v1.json")
    await harness.model.reloadResearchData()

    // Zero is correct here -- the unreadable archive is quarantined, so those
    // sessions leave the active set. What makes it honest rather than a silent
    // loss is that `localDataError` is set alongside it, and every surface
    // showing the count also shows that message.
    XCTAssertEqual(harness.model.baselineSessions, 0)
    XCTAssertFalse(
      harness.model.baselineReady,
      "without the archive there is no range to compare against")
    XCTAssertEqual(
      harness.model.localDataError, .sessions,
      "a zeroed count without an explanation is indistinguishable from deletion")
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
