import XCTest

@testable import Sober

final class CheckHistoryStoreTests: XCTestCase {
  private struct Archive: Encodable {
    let schemaVersion: Int
    let entries: [CheckHistoryEntry]
  }

  private func makeDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return directory
  }

  private func makeStore() -> CheckHistoryStore {
    CheckHistoryStore(directoryURL: makeDirectory())
  }

  private func write(_ archive: Archive, to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(archive).write(
      to: directory.appendingPathComponent(CheckHistoryStore.currentFileName)
    )
  }

  private func entry(
    _ daysAgo: Double,
    kind: CheckHistoryEntry.Kind = .check,
    outcome: CheckHistoryEntry.Outcome? = .noSignalsDetected,
    now: Date
  ) -> CheckHistoryEntry {
    CheckHistoryEntry(
      id: UUID(),
      startedAt: now.addingTimeInterval(-daysAgo * 24 * 60 * 60),
      kind: kind,
      outcome: outcome,
      qualityScore: 0.9,
      completedAllTasks: true
    )
  }

  func testEntriesAreReturnedNewestFirst() async throws {
    let now = Date(timeIntervalSince1970: 1_770_000_000)
    let store = makeStore()

    try await store.append(entry(5, now: now), now: now)
    try await store.append(entry(1, now: now), now: now)
    try await store.append(entry(3, now: now), now: now)

    let listed = try await store.list(now: now)
    XCTAssertEqual(listed.count, 3)
    XCTAssertTrue(listed[0].startedAt > listed[1].startedAt)
    XCTAssertTrue(listed[1].startedAt > listed[2].startedAt)
  }

  /// A permanent record of when someone checked themselves is the thing another
  /// person would ask to see, so the window is enforced rather than advisory.
  func testEntriesOlderThanTheRetentionWindowArePruned() async throws {
    let now = Date(timeIntervalSince1970: 1_770_000_000)
    let store = makeStore()

    let old = entry(Double(CheckHistoryStore.retentionDays) + 1, now: now)
    let recent = entry(1, now: now)
    try await store.append(old, now: now)
    try await store.append(recent, now: now)

    let listed = try await store.list(now: now)
    XCTAssertEqual(listed.map(\.id), [recent.id])
  }

  /// Pruning on read as well as write: an app opened but never used again must
  /// not keep showing entries past their window.
  func testRetentionIsAppliedOnReadWithoutAWrite() async throws {
    let writeTime = Date(timeIntervalSince1970: 1_770_000_000)
    let store = makeStore()
    try await store.append(entry(1, now: writeTime), now: writeTime)

    let muchLater = writeTime.addingTimeInterval(
      Double(CheckHistoryStore.retentionDays + 10) * 24 * 60 * 60)

    let listed = try await store.list(now: muchLater)
    XCTAssertTrue(listed.isEmpty)

    // The retention promise applies to the bytes, not only the current view.
    let listedAtTheOriginalTime = try await store.list(now: writeTime)
    XCTAssertTrue(listedAtTheOriginalTime.isEmpty)
  }

  func testEntryCountIsCapped() async throws {
    let now = Date(timeIntervalSince1970: 1_770_000_000)
    let store = makeStore()

    for index in 0..<(CheckHistoryStore.maximumEntries + 25) {
      // Fractions of a day so every entry stays inside the retention window.
      try await store.append(entry(Double(index) * 0.01, now: now), now: now)
    }

    let listed = try await store.list(now: now)
    XCTAssertEqual(listed.count, CheckHistoryStore.maximumEntries)
  }

  func testDeleteAllRemovesEverything() async throws {
    let now = Date(timeIntervalSince1970: 1_770_000_000)
    let store = makeStore()
    try await store.append(entry(1, now: now), now: now)

    let deleted = try await store.deleteAll()

    XCTAssertEqual(deleted, 1)
    let listed = try await store.list(now: now)
    XCTAssertTrue(listed.isEmpty)
  }

  func testBaselineEntriesCarryNoVerdict() async throws {
    let now = Date(timeIntervalSince1970: 1_770_000_000)
    let store = makeStore()
    try await store.append(entry(1, kind: .baseline, outcome: nil, now: now), now: now)

    let listed = try await store.list(now: now)
    XCTAssertEqual(listed.first?.kind, .baseline)
    XCTAssertNil(listed.first?.outcome, "a baseline session has no result to report")
  }

  func testMalformedArchiveIsQuarantinedByteForByte() async throws {
    let directory = makeDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let malformed = Data("{not-valid-json".utf8)
    let sourceURL = directory.appendingPathComponent(CheckHistoryStore.currentFileName)
    try malformed.write(to: sourceURL)
    let store = CheckHistoryStore(directoryURL: directory, quarantineID: { "malformed" })

    do {
      _ = try await store.list()
      XCTFail("Expected malformed History to be quarantined")
    } catch let error as CheckHistoryStoreError {
      XCTAssertEqual(
        error,
        .archiveQuarantined(fileName: "check-history-v1-malformed.json")
      )
    }

    XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
    let quarantined = await store.quarantinedArchiveURLs()
    XCTAssertEqual(quarantined.count, 1)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(quarantined.first)), malformed)
    let recordsAfterQuarantine = try await store.list()
    XCTAssertEqual(recordsAfterQuarantine, [])
  }

  func testUnsupportedStoreVersionIsQuarantined() async throws {
    let directory = makeDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("{\"schemaVersion\":99,\"entries\":[]}".utf8).write(
      to: directory.appendingPathComponent(CheckHistoryStore.currentFileName)
    )
    let store = CheckHistoryStore(directoryURL: directory, quarantineID: { "future" })

    do {
      _ = try await store.list()
      XCTFail("Expected future-version History to be quarantined")
    } catch let error as CheckHistoryStoreError {
      XCTAssertEqual(
        error,
        .archiveQuarantined(fileName: "check-history-v1-future.json")
      )
    }
    let quarantined = await store.quarantinedArchiveURLs()
    XCTAssertEqual(quarantined.count, 1)
  }

  func testUnsupportedEntryVersionIsQuarantined() async throws {
    let directory = makeDirectory()
    let now = Date(timeIntervalSince1970: 1_770_000_000)
    let unsupported = CheckHistoryEntry(
      id: UUID(),
      startedAt: now,
      kind: .check,
      outcome: .inconclusive,
      qualityScore: 0.5,
      completedAllTasks: true,
      schemaVersion: 99
    )
    try write(Archive(schemaVersion: 1, entries: [unsupported]), to: directory)
    let store = CheckHistoryStore(directoryURL: directory, quarantineID: { "record" })

    do {
      _ = try await store.list(now: now)
      XCTFail("Expected unsupported History entry to be quarantined")
    } catch let error as CheckHistoryStoreError {
      XCTAssertEqual(
        error,
        .archiveQuarantined(fileName: "check-history-v1-record.json")
      )
    }
  }

  func testDuplicateIdentifiersQuarantineTheWholeArchive() async throws {
    let directory = makeDirectory()
    let now = Date(timeIntervalSince1970: 1_770_000_000)
    let duplicated = entry(1, now: now)
    try write(Archive(schemaVersion: 1, entries: [duplicated, duplicated]), to: directory)
    let store = CheckHistoryStore(directoryURL: directory, quarantineID: { "duplicate" })

    do {
      _ = try await store.list(now: now)
      XCTFail("Expected duplicate History identifiers to be quarantined")
    } catch let error as CheckHistoryStoreError {
      XCTAssertEqual(
        error,
        .archiveQuarantined(fileName: "check-history-v1-duplicate.json")
      )
    }
  }

  func testDeleteAllRemovesCorruptAndQuarantinedCopiesWithoutDecoding() async throws {
    let directory = makeDirectory()
    let quarantineDirectory = directory.appendingPathComponent(
      CheckHistoryStore.quarantineDirectoryName,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: quarantineDirectory,
      withIntermediateDirectories: true
    )
    try Data("corrupt-active".utf8).write(
      to: directory.appendingPathComponent(CheckHistoryStore.currentFileName)
    )
    try Data("preserved-copy".utf8).write(
      to: quarantineDirectory.appendingPathComponent("archive.json")
    )
    let store = CheckHistoryStore(directoryURL: directory)

    _ = try await store.deleteAll()

    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    let recordsAfterDeletion = try await store.list()
    XCTAssertEqual(recordsAfterDeletion, [])
  }
}

@MainActor
final class CheckHistoryRecordingTests: XCTestCase {
  private func makeModel() -> AppModel {
    let suiteName = "CheckHistoryTests.\(UUID().uuidString)"
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
    return AppModel(
      defaults: defaults,
      baselineStore: LocalBaselineStore(
        defaults: defaults,
        archive: ResearchSessionStore(directoryURL: research)
      ),
      checkHistoryStore: CheckHistoryStore(directoryURL: history),
      automaticallyStartsGuardianServices: false,
      allowsInternalTools: false
    )
  }

  private var completedMetrics: ScreeningMetrics {
    ScreeningMetrics(
      reactionTimeMilliseconds: 420,
      reactionMisses: 0,
      trackingError: 0.2,
      timeEstimateError: 0.1,
      gazeSmoothness: 0.2,
      qualityScore: 0.9,
      completedAllTasks: true
    )
  }

  /// The defect this store exists to fix: research consent gated check
  /// recording, and a public build has no way to grant it, so History could
  /// never contain a single check.
  func testChecksAreRecordedWithoutResearchConsent() async {
    let model = makeModel()
    XCTAssertFalse(model.researchConsent)

    await model.recordCompletedSession(
      mode: .check,
      selfReport: .no,
      metrics: completedMetrics,
      reactionSummary: nil,
      ocularSummary: nil,
      startedAt: Date(),
      outcome: ScreeningOutcome(
        state: .noSignalsDetected, qualityScore: 0.9, riskScore: 0.1, details: [])
    )

    XCTAssertEqual(model.checkHistory.count, 1)
    XCTAssertEqual(model.checkHistory.first?.kind, .check)
    XCTAssertEqual(model.checkHistory.first?.outcome, .noSignalsDetected)
    XCTAssertTrue(
      model.researchSessions.isEmpty,
      "history must not smuggle a check into the research archive")
  }

  func testBaselineSessionsAppearInHistoryWithoutAVerdict() async {
    let model = makeModel()

    await model.recordCompletedSession(
      mode: .baseline,
      selfReport: .no,
      metrics: completedMetrics,
      reactionSummary: nil,
      ocularSummary: nil,
      startedAt: Date()
    )

    XCTAssertEqual(model.checkHistory.first?.kind, .baseline)
    XCTAssertNil(model.checkHistory.first?.outcome)
  }

  /// "Delete all local data" says it deletes everything, so it has to.
  func testDeletingAllDataClearsHistory() async {
    let model = makeModel()
    await model.recordCompletedSession(
      mode: .check,
      selfReport: .no,
      metrics: completedMetrics,
      reactionSummary: nil,
      ocularSummary: nil,
      startedAt: Date(),
      outcome: ScreeningOutcome(
        state: .inconclusive, qualityScore: 0.4, riskScore: 0.2, details: [])
    )
    XCTAssertFalse(model.checkHistory.isEmpty)

    await model.deleteAllResearchData()

    XCTAssertTrue(model.checkHistory.isEmpty)
  }
}
