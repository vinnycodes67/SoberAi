import AVFoundation
import XCTest

@testable import Sober

@MainActor
final class PersistenceFoundationTests: XCTestCase {
  private struct LegacyArchive: Encodable {
    let schemaVersion = 1
    let sessions: [ResearchSessionEnvelope]
  }

  func testVersionOneArchiveMigratesToVersionTwoWithoutChangingRecords() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let expected = makeSession(index: 1)
    let legacyURL = directory.appendingPathComponent(ResearchSessionStore.legacyFileName)
    try JSONEncoder().encode(LegacyArchive(sessions: [expected])).write(to: legacyURL)

    let store = ResearchSessionStore(directoryURL: directory)
    let loaded = try await store.list()

    XCTAssertEqual(loaded, [expected])
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))

    let currentURL = directory.appendingPathComponent(ResearchSessionStore.currentFileName)
    XCTAssertTrue(FileManager.default.fileExists(atPath: currentURL.path))
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: currentURL)) as? [String: Any]
    )
    XCTAssertEqual(object["schemaVersion"] as? Int, ResearchSessionStore.currentStoreSchemaVersion)
    XCTAssertEqual((object["records"] as? [[String: Any]])?.count, 1)
  }

  func testMalformedArchiveIsQuarantinedByteForByteInsteadOfErased() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let malformed = Data("{not-valid-json".utf8)
    let sourceURL = directory.appendingPathComponent(ResearchSessionStore.currentFileName)
    try malformed.write(to: sourceURL)
    let store = ResearchSessionStore(directoryURL: directory, quarantineID: { "test-id" })

    do {
      _ = try await store.list()
      XCTFail("Expected the malformed archive to be quarantined")
    } catch let error as ResearchSessionStoreError {
      XCTAssertEqual(
        error,
        .archiveQuarantined(fileName: "research-sessions-v2-test-id.json")
      )
    }

    XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
    let quarantined = await store.quarantinedArchiveURLs()
    XCTAssertEqual(quarantined.count, 1)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(quarantined.first)), malformed)
    let recordsAfterQuarantine = try await store.list()
    XCTAssertEqual(recordsAfterQuarantine, [])
  }

  func testUnsupportedArchiveVersionIsQuarantined() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let sourceURL = directory.appendingPathComponent(ResearchSessionStore.currentFileName)
    try Data("{\"schemaVersion\":99,\"records\":[]}".utf8).write(to: sourceURL)
    let store = ResearchSessionStore(directoryURL: directory, quarantineID: { "future" })

    await XCTAssertThrowsErrorAsync(try await store.list()) { error in
      XCTAssertEqual(
        error as? ResearchSessionStoreError,
        .archiveQuarantined(fileName: "research-sessions-v2-future.json")
      )
    }
    let quarantined = await store.quarantinedArchiveURLs()
    XCTAssertEqual(quarantined.count, 1)
  }

  func testDuplicateRecordIdentifiersQuarantineTheWholeArchive() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let duplicated = makeSession(index: 1)
    let sourceURL = directory.appendingPathComponent(ResearchSessionStore.legacyFileName)
    try JSONEncoder().encode(LegacyArchive(sessions: [duplicated, duplicated])).write(to: sourceURL)
    let store = ResearchSessionStore(directoryURL: directory, quarantineID: { "duplicate" })

    await XCTAssertThrowsErrorAsync(try await store.list()) { error in
      XCTAssertEqual(
        error as? ResearchSessionStoreError,
        .archiveQuarantined(fileName: "research-sessions-v1-duplicate.json")
      )
    }
    let quarantined = await store.quarantinedArchiveURLs()
    XCTAssertEqual(quarantined.count, 1)
  }

  func testUnsupportedRecordSchemaQuarantinesTheWholeArchive() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let unsupported = makeSession(index: 1, schemaVersion: 99)
    let sourceURL = directory.appendingPathComponent(ResearchSessionStore.legacyFileName)
    try JSONEncoder().encode(LegacyArchive(sessions: [unsupported])).write(to: sourceURL)
    let store = ResearchSessionStore(directoryURL: directory, quarantineID: { "record-schema" })

    await XCTAssertThrowsErrorAsync(try await store.list()) { error in
      XCTAssertEqual(
        error as? ResearchSessionStoreError,
        .archiveQuarantined(fileName: "research-sessions-v1-record-schema.json")
      )
    }
    let quarantined = await store.quarantinedArchiveURLs()
    XCTAssertEqual(quarantined.count, 1)
  }

  func testDeleteAllRemovesActiveLegacyAndQuarantinedCopiesWithoutDecoding() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let quarantineDirectory = directory.appendingPathComponent(
      ResearchSessionStore.quarantineDirectoryName,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: quarantineDirectory, withIntermediateDirectories: true)
    try Data("corrupt-current".utf8).write(
      to: directory.appendingPathComponent(ResearchSessionStore.currentFileName)
    )
    try Data("corrupt-legacy".utf8).write(
      to: directory.appendingPathComponent(ResearchSessionStore.legacyFileName)
    )
    try Data("preserved-corrupt-copy".utf8).write(
      to: quarantineDirectory.appendingPathComponent("archive.json")
    )

    let store = ResearchSessionStore(directoryURL: directory)
    _ = try await store.deleteAll()

    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
  }

  func testDeletionBarrierSurvivesRelaunchAndBlocksReadAppendAndExport() async throws {
    let harness = makeHarness()
    defer { harness.cleanup() }
    let archive = ResearchSessionStore(directoryURL: harness.directory)
    let originalID = PseudonymousParticipantID(rawValue: "participant-original")
    harness.defaults.set(originalID.rawValue, forKey: "sober.research.participant-id")
    harness.defaults.set(5, forKey: "sober.baseline.sessions")

    let store = LocalBaselineStore(defaults: harness.defaults, archive: archive)
    try await store.append(makeSession(index: 1, participantID: originalID))
    store.beginDeletion()

    XCTAssertTrue(store.deletionPending)
    let recordsWhileDeleting = try await store.list()
    XCTAssertEqual(recordsWhileDeleting, [])
    XCTAssertNil(harness.defaults.object(forKey: "sober.baseline.sessions"))
    await XCTAssertThrowsErrorAsync(try await store.append(makeSession(index: 2))) { error in
      XCTAssertEqual(error as? BaselineStoreError, .deletionPending)
    }
    await XCTAssertThrowsErrorAsync(try await store.exportData(exportedAt: Date())) { error in
      XCTAssertEqual(error as? BaselineStoreError, .deletionPending)
    }

    let relaunched = LocalBaselineStore(
      defaults: harness.defaults,
      archive: archive,
      makeParticipantID: { PseudonymousParticipantID(rawValue: "participant-new") }
    )
    XCTAssertTrue(relaunched.deletionPending)
    let relaunchedRecords = try await relaunched.list()
    XCTAssertEqual(relaunchedRecords, [])

    let receipt = try await relaunched.deleteAllAndRotateIdentity()
    XCTAssertEqual(receipt.deletedSessionCount, 1)
    XCTAssertEqual(receipt.participantID.rawValue, "participant-new")
    XCTAssertFalse(relaunched.deletionPending)
    let recordsAfterDeletion = try await relaunched.list()
    XCTAssertEqual(recordsAfterDeletion, [])
  }

  func testQuarantinedArchiveCannotLeaveStaleBaselineReadinessInMemory() async throws {
    let harness = makeHarness()
    defer { harness.cleanup() }
    let archive = ResearchSessionStore(
      directoryURL: harness.directory,
      quarantineID: { "stale-readiness" }
    )
    let baselineStore = LocalBaselineStore(defaults: harness.defaults, archive: archive)
    for index in 0..<5 {
      try await baselineStore.append(
        makeSession(index: index, participantID: baselineStore.participantID)
      )
    }
    let model = AppModel(
      defaults: harness.defaults,
      baselineStore: baselineStore,
      automaticallyStartsGuardianServices: false
    )
    await model.reloadResearchData()
    XCTAssertTrue(model.baselineReady)

    let currentURL = harness.directory.appendingPathComponent(ResearchSessionStore.currentFileName)
    try Data("corrupt-after-load".utf8).write(to: currentURL, options: .atomic)
    await model.reloadResearchData()

    XCTAssertFalse(model.baselineReady)
    XCTAssertEqual(model.baselineSessions, 0)
    XCTAssertTrue(model.researchSessions.isEmpty)
    XCTAssertNotNil(model.researchDataError)
    let quarantined = await archive.quarantinedArchiveURLs()
    XCTAssertEqual(quarantined.count, 1)
  }

  func testPrivacyStoreOwnsAndTruthfullyResetsSensitiveDefaults() throws {
    let harness = makeHarness()
    defer { harness.cleanup() }
    let store = UserDefaultsPrivacyStore(defaults: harness.defaults)
    let preferences = ResearchPreferences(sleepHours: 4)
    let plan = SafetyPlan(userName: "Alex", contactName: "Sam", contactPhone: "3125550100")
    let profile = UserProfile(displayName: "Alex", ageYears: 19)

    store.saveResearchConsent(true)
    store.saveResearchPreferences(preferences)
    store.saveSafetyPlan(plan)
    store.saveUserProfile(profile)
    store.recordConsent(version: "test-v1", at: Date(timeIntervalSince1970: 100))

    XCTAssertEqual(
      store.load(),
      PrivacySnapshot(
        researchConsent: true,
        researchPreferences: preferences,
        safetyPlan: plan,
        userProfile: profile
      )
    )

    store.reset()

    XCTAssertEqual(
      store.load(),
      PrivacySnapshot(
        researchConsent: false,
        researchPreferences: ResearchPreferences(),
        safetyPlan: SafetyPlan(),
        userProfile: UserProfile()
      )
    )
    XCTAssertNil(harness.defaults.object(forKey: "sober.consent.version"))
    XCTAssertNil(harness.defaults.object(forKey: "sober.consent.date"))
  }

  func testSystemPermissionMappingIsExhaustiveAndConservative() {
    XCTAssertEqual(SystemPermissionStore.map(.notDetermined), .notDetermined)
    XCTAssertEqual(SystemPermissionStore.map(.restricted), .restricted)
    XCTAssertEqual(SystemPermissionStore.map(.denied), .denied)
    XCTAssertEqual(SystemPermissionStore.map(.authorized), .authorized)
  }

  private func makeSession(
    index: Int,
    participantID: PseudonymousParticipantID = .init(rawValue: "participant-test"),
    schemaVersion: Int = ResearchSessionEnvelope.currentSchemaVersion
  ) -> ResearchSessionEnvelope {
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
    return ResearchSessionEnvelope(
      schemaVersion: schemaVersion,
      participantID: participantID,
      sessionID: ResearchSessionID(rawValue: "session-\(index)"),
      startedAt: startedAt,
      completedAt: startedAt.addingTimeInterval(45),
      metadata: ResearchSessionMetadata(
        device: ResearchDeviceMetadata(
          platform: "iOS",
          deviceModel: "iPhone",
          systemName: "iOS",
          systemVersion: "26.0",
          localeIdentifier: "en_US"
        ),
        app: ResearchAppMetadata(
          bundleIdentifier: "com.soberprototype.tests",
          version: "0.2.0",
          build: "2"
        ),
        protocolMetadata: ResearchProtocolMetadata(name: "Sober Battery", version: "0.2")
      ),
      context: ResearchSessionContext(
        sessionKind: .soberBaseline,
        soberAtStartAttested: true,
        reportedAlcoholUse: false,
        sleepHours: 8,
        visionCorrection: .none,
        ambientLighting: .moderate
      ),
      metrics: ResearchScreeningMetrics(
        reactionTimeMilliseconds: 320,
        reactionMisses: 0,
        trackingError: 0.18,
        timeEstimateError: 0.08,
        gazeSmoothness: 0.16,
        qualityScore: 0.9,
        completedAllTasks: true
      )
    )
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("SoberPersistenceFoundationTests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }

  private func makeHarness() -> PersistenceHarness {
    let suiteName = "PersistenceFoundationTests.\(UUID().uuidString)"
    return PersistenceHarness(
      defaults: UserDefaults(suiteName: suiteName)!,
      suiteName: suiteName,
      directory: temporaryDirectory()
    )
  }
}

@MainActor
private struct PersistenceHarness {
  let defaults: UserDefaults
  let suiteName: String
  let directory: URL

  func cleanup() {
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: directory)
  }
}

@MainActor
private func XCTAssertThrowsErrorAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  _ handler: (Error) -> Void,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("Expected expression to throw", file: file, line: line)
  } catch {
    handler(error)
  }
}
