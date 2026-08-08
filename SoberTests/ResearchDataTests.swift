import XCTest

@testable import Sober

final class ResearchDataTests: XCTestCase {
  func testResearchSessionJSONRoundTripPreservesVersionedEnvelope() throws {
    let session = makeSession(
      index: 1,
      reactionTimeMilliseconds: 420,
      choiceReaction: ChoiceReactionSummary(
        trials: [
          ChoiceReactionTrial(
            expected: .blueCircle,
            selected: .blueCircle,
            latencyMilliseconds: 420,
            wasAnticipation: false,
            wasMiss: false
          )
        ]
      ),
      ocularSummary: GazeCaptureSummary(
        smoothnessRisk: 0.16,
        qualityScore: 0.9,
        sampleCount: 240,
        quality: CaptureQualitySnapshot(
          isSupported: true,
          hasCameraPermission: true,
          facePresent: true,
          centered: true,
          distanceAcceptable: true,
          lightingAcceptable: true,
          headStable: true,
          frameRate: 30,
          sampleCount: 240,
          dropoutRatio: 0.02,
          issues: []
        ),
        features: OcularSignalFeatures(
          fixationJitter: 0.12,
          horizontalPursuitError: 0.16,
          verticalPursuitError: 0.14,
          saccadeError: 0.18,
          leftRightAsymmetry: 0.04,
          blinkRatePerMinute: 14,
          headCompensation: 0.08
        )
      ),
      ocularQuality: ResearchOcularQuality(
        faceTrackingAvailable: true,
        cameraPermissionGranted: true,
        sampleCount: 240,
        trackingDurationMilliseconds: 8_000,
        trackingCoverage: 0.96,
        bothEyesVisibleFraction: 0.92,
        headStabilityScore: 0.88,
        illuminationScore: 0.84,
        glareDetected: false,
        meanFrameRate: 30,
        signalQualityScore: 0.9
      ),
      breathReference: BreathReferenceMetadata(
        reading: 0.04,
        unit: .bacPercent,
        measuredAt: Date(timeIntervalSince1970: 1_700_000_120),
        manufacturer: "Research Device Company",
        model: "Reference 1",
        pseudonymousDeviceID: "device_hash_001",
        calibrationDueAt: Date(timeIntervalSince1970: 1_800_000_000)
      )
    )

    let data = try JSONEncoder().encode(session)
    let decoded = try JSONDecoder().decode(ResearchSessionEnvelope.self, from: data)

    XCTAssertEqual(decoded, session)
    XCTAssertEqual(decoded.schemaVersion, ResearchSessionEnvelope.currentSchemaVersion)
    XCTAssertEqual(decoded.metrics.screeningMetrics.reactionTimeMilliseconds, 420)
    XCTAssertEqual(decoded.choiceReaction?.trials.count, 1)
    XCTAssertEqual(decoded.ocularSummary?.sampleCount, 240)
  }

  func testResearchMetricsRoundTripPreservesUnmeasuredTasks() throws {
    let stored = ResearchScreeningMetrics(
      ScreeningMetrics(
        reactionTimeMilliseconds: 0,
        reactionMisses: 0,
        reactionWasMeasured: false,
        trackingError: nil,
        timeEstimateError: 0,
        timingWasMeasured: false,
        gazeSmoothness: nil,
        qualityScore: 0,
        completedAllTasks: false
      )
    )

    let data = try JSONEncoder().encode(stored)
    let decoded = try JSONDecoder().decode(ResearchScreeningMetrics.self, from: data)
    let metrics = decoded.screeningMetrics

    XCTAssertFalse(metrics.reactionWasMeasured)
    XCTAssertNil(metrics.trackingError)
    XCTAssertFalse(metrics.timingWasMeasured)
    XCTAssertNil(metrics.gazeSmoothness)
  }

  func testLegacyResearchMetricsDefaultExistingTasksToMeasured() throws {
    let data = Data(
      """
      {
        "reactionTimeMilliseconds": 420,
        "reactionMisses": 0,
        "trackingError": 0.18,
        "timeEstimateError": 0.08,
        "gazeSmoothness": 0.16,
        "qualityScore": 0.9,
        "completedAllTasks": true
      }
      """.utf8
    )

    let metrics = try JSONDecoder().decode(ResearchScreeningMetrics.self, from: data)

    XCTAssertTrue(metrics.reactionWasMeasured)
    XCTAssertTrue(metrics.timingWasMeasured)
    XCTAssertEqual(metrics.screeningMetrics.trackingError, 0.18)
    XCTAssertEqual(metrics.screeningMetrics.gazeSmoothness, 0.16)
  }

  func testStoreAppendListExportAndDelete() async throws {
    let directoryURL = temporaryDirectory(named: #function)
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let store = ResearchSessionStore(directoryURL: directoryURL)
    let later = makeSession(index: 2, reactionTimeMilliseconds: 440)
    let earlier = makeSession(index: 1, reactionTimeMilliseconds: 410)

    try await store.append(later)
    try await store.append(earlier)

    let sessions = try await store.list()
    XCTAssertEqual(sessions.map(\.sessionID), [earlier.sessionID, later.sessionID])

    let exportDate = Date(timeIntervalSince1970: 1_900_000_000)
    let payload = try await store.exportPayload(exportedAt: exportDate)
    XCTAssertEqual(payload.exportedAt, exportDate)
    XCTAssertEqual(payload.sessions, sessions)
    let exportData = try await store.exportData(exportedAt: exportDate)
    XCTAssertEqual(
      try JSONDecoder().decode(ResearchSessionExportPayload.self, from: exportData),
      payload
    )

    let deletedExistingSession = try await store.delete(sessionID: earlier.sessionID)
    let deletedMissingSession = try await store.delete(sessionID: earlier.sessionID)
    let remainingSessions = try await store.list()
    XCTAssertTrue(deletedExistingSession)
    XCTAssertFalse(deletedMissingSession)
    XCTAssertEqual(remainingSessions, [later])
  }

  func testBaselineExcludesIncompleteAndPoorQualitySessions() {
    let participantID = PseudonymousParticipantID(rawValue: "participant_baseline")
    let eligible = (1...5).map {
      makeSession(
        index: $0,
        participantID: participantID,
        reactionTimeMilliseconds: Double(300 + $0),
        qualityScore: 0.9
      )
    }
    let poorQuality = makeSession(
      index: 6,
      participantID: participantID,
      reactionTimeMilliseconds: 4_000,
      qualityScore: 0.719
    )
    let incomplete = makeSession(
      index: 7,
      participantID: participantID,
      reactionTimeMilliseconds: 5_000,
      qualityScore: 0.99,
      completed: false
    )

    let summary = BaselineProfileEngine().summarize(
      participantID: participantID,
      sessions: eligible + [poorQuality, incomplete]
    )

    XCTAssertEqual(summary.candidateSessionCount, 7)
    XCTAssertEqual(summary.eligibleSessionCount, 5)
    XCTAssertEqual(summary.excludedSessionCount, 2)
    XCTAssertTrue(summary.isReady)
    XCTAssertEqual(summary.metrics?.reactionTimeMilliseconds.median, 303)
  }

  func testStoreDeleteAllRemovesEverySession() async throws {
    let directoryURL = temporaryDirectory(named: #function)
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let store = ResearchSessionStore(directoryURL: directoryURL)
    try await store.append(makeSession(index: 1, reactionTimeMilliseconds: 410))
    try await store.append(makeSession(index: 2, reactionTimeMilliseconds: 440))

    let deletedCount = try await store.deleteAll()
    let sessions = try await store.list()
    let deletedFromEmptyStore = try await store.deleteAll()

    XCTAssertEqual(deletedCount, 2)
    XCTAssertTrue(sessions.isEmpty)
    XCTAssertEqual(deletedFromEmptyStore, 0)
  }

  func testBaselineUsesRobustMedianAndRawMAD() throws {
    let participantID = PseudonymousParticipantID(rawValue: "participant_robust")
    let reactionTimes: [Double] = [100, 110, 120, 130, 1_000]
    let sessions = reactionTimes.enumerated().map { offset, reactionTime in
      makeSession(
        index: offset,
        participantID: participantID,
        reactionTimeMilliseconds: reactionTime
      )
    }

    let summary = BaselineProfileEngine().summarize(
      participantID: participantID,
      sessions: sessions
    )
    let reaction = try XCTUnwrap(summary.metrics?.reactionTimeMilliseconds)

    XCTAssertEqual(reaction.median, 120)
    XCTAssertEqual(reaction.medianAbsoluteDeviation, 10)
  }

  func testBaselineRequiresFiveEligibleSessions() {
    let participantID = PseudonymousParticipantID(rawValue: "participant_readiness")
    let fourSessions = (0..<4).map {
      makeSession(
        index: $0,
        participantID: participantID,
        reactionTimeMilliseconds: Double(300 + $0)
      )
    }

    let engine = BaselineProfileEngine()
    XCTAssertFalse(
      engine.summarize(participantID: participantID, sessions: fourSessions).isReady
    )
    XCTAssertTrue(
      engine.summarize(
        participantID: participantID,
        sessions: fourSessions + [
          makeSession(
            index: 4,
            participantID: participantID,
            reactionTimeMilliseconds: 304
          )
        ]
      ).isReady
    )
  }

  func testScoringBaselineUsesTheLatestThreeOnlyAfterFiveEligibleSessions() throws {
    let participantID = PseudonymousParticipantID(rawValue: "participant_scoring")
    let sessions = (1...5).map {
      makeSession(
        index: $0,
        participantID: participantID,
        reactionTimeMilliseconds: Double(300 + $0)
      )
    }
    let engine = BaselineProfileEngine()

    XCTAssertNil(
      engine.personalBaseline(participantID: participantID, sessions: Array(sessions.prefix(4)))
    )

    let baseline = try XCTUnwrap(
      engine.personalBaseline(participantID: participantID, sessions: sessions)
    )
    XCTAssertTrue(baseline.isReady)
    XCTAssertEqual(baseline.samples.map(\.reactionTimeMilliseconds), [303, 304, 305])
  }

  private func makeSession(
    index: Int,
    participantID: PseudonymousParticipantID = .init(rawValue: "participant_test"),
    reactionTimeMilliseconds: Double,
    qualityScore: Double = 0.9,
    completed: Bool = true,
    choiceReaction: ChoiceReactionSummary? = nil,
    ocularSummary: GazeCaptureSummary? = nil,
    ocularQuality: ResearchOcularQuality? = nil,
    breathReference: BreathReferenceMetadata? = nil
  ) -> ResearchSessionEnvelope {
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(index * 60))
    return ResearchSessionEnvelope(
      participantID: participantID,
      sessionID: ResearchSessionID(rawValue: "session_\(index)"),
      startedAt: startedAt,
      completedAt: completed ? startedAt.addingTimeInterval(45) : nil,
      metadata: ResearchSessionMetadata(
        device: ResearchDeviceMetadata(
          platform: "iOS",
          deviceModel: "iPhone",
          systemName: "iOS",
          systemVersion: "17.0",
          localeIdentifier: "en_US"
        ),
        app: ResearchAppMetadata(
          bundleIdentifier: "com.soberprototype.tests",
          version: "0.2.0",
          build: "2"
        ),
        protocolMetadata: ResearchProtocolMetadata(
          name: "Sober Research Battery",
          version: "0.2"
        )
      ),
      context: ResearchSessionContext(
        sessionKind: .soberBaseline,
        soberAtStartAttested: true,
        reportedAlcoholUse: false,
        reportedCannabisUse: false,
        sleepHours: 8,
        visionCorrection: .none,
        ambientLighting: .moderate
      ),
      metrics: ResearchScreeningMetrics(
        reactionTimeMilliseconds: reactionTimeMilliseconds,
        reactionMisses: 0,
        trackingError: 0.18,
        timeEstimateError: 0.08,
        gazeSmoothness: 0.16,
        qualityScore: qualityScore,
        completedAllTasks: completed
      ),
      choiceReaction: choiceReaction,
      ocularSummary: ocularSummary,
      ocularQuality: ocularQuality,
      breathReference: breathReference
    )
  }

  private func temporaryDirectory(named testName: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("SoberResearchDataTests", isDirectory: true)
      .appendingPathComponent(testName, isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }
}
