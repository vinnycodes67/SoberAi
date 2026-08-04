import Foundation
import XCTest

@testable import Sober

/// Regressions for the defects found in the 2026-08-03 safety and privacy review.
final class ReviewRegressionTests: XCTestCase {

  func testReducedMotionScheduleContainsNoContinuousInterpolation() {
    let phases = stride(from: 0.0, through: 11.0, by: 0.5).map {
      OcularProtocolSchedule.target(at: $0, variant: .reducedMotion).phase
    }

    XCTAssertFalse(phases.contains(.horizontalPursuit))
    XCTAssertFalse(phases.contains(.verticalPursuit))
  }

  func testReducedMotionAnalyzerRenormalisesRiskAndKeepsCleanCapturesUsable() {
    let liveQuality = CaptureQualitySnapshot(
      isSupported: true,
      hasCameraPermission: true,
      facePresent: true,
      centered: true,
      distanceAcceptable: true,
      lightingAcceptable: true,
      headStable: true,
      frameRate: 30,
      sampleCount: 240,
      dropoutRatio: 0.01,
      issues: []
    )

    let cleanSamples = Self.syntheticReducedMotionSamples(followsTarget: true)
    let cleanSummary = OcularSignalAnalyzer().summarize(
      samples: cleanSamples,
      observedFrameCount: cleanSamples.count,
      liveQuality: liveQuality,
      variant: .reducedMotion
    )
    XCTAssertTrue(cleanSummary.quality.isUsable)
    XCTAssertLessThan(cleanSummary.smoothnessRisk, 0.5)
    XCTAssertEqual(cleanSummary.protocolVariant, .reducedMotion)

    let poorSamples = Self.syntheticReducedMotionSamples(followsTarget: false)
    let poorSummary = OcularSignalAnalyzer().summarize(
      samples: poorSamples,
      observedFrameCount: poorSamples.count,
      liveQuality: liveQuality,
      variant: .reducedMotion
    )
    XCTAssertGreaterThan(poorSummary.smoothnessRisk, cleanSummary.smoothnessRisk)
    XCTAssertGreaterThan(poorSummary.smoothnessRisk, 0.3)
    XCTAssertTrue(poorSummary.quality.isUsable)
    XCTAssertEqual(poorSummary.protocolVariant, .reducedMotion)
  }

  func testAnticipationDoesNotInventAnExpectedTarget() {
    let anticipation = ChoiceReactionTrial(
      expected: nil,
      selected: .pinkDiamond,
      latencyMilliseconds: nil,
      wasAnticipation: true,
      wasMiss: false
    )

    XCTAssertNil(anticipation.expected)
    XCTAssertFalse(anticipation.isCorrect)
    XCTAssertEqual(ChoiceReactionSummary(trials: [anticipation]).anticipations, 1)
  }

  func testDefaultSafetyPlanRequiresExplicitContactEntry() {
    let plan = SafetyPlan(automaticParentAlerts: true, parentAlertConsent: true)

    XCTAssertTrue(plan.userName.isEmpty)
    XCTAssertTrue(plan.contactName.isEmpty)
    XCTAssertTrue(plan.contactPhone.isEmpty)
    XCTAssertFalse(plan.canAutomaticallyAlertParent)
  }

  func testBaselineProfileEngineNeverPoolsVariants() {
    let participant = PseudonymousParticipantID(rawValue: "participant_test")
    let sessions = Array(repeating: Self.makeBaselineSession(participantID: participant, variant: .full), count: 5)
      + Array(repeating: Self.makeBaselineSession(participantID: participant, variant: .reducedMotion), count: 5)

    let fullProfile = BaselineProfileEngine().summarize(
      participantID: participant,
      sessions: sessions,
      protocolVariant: .full
    )
    let reducedProfile = BaselineProfileEngine().summarize(
      participantID: participant,
      sessions: sessions,
      protocolVariant: .reducedMotion
    )

    XCTAssertEqual(fullProfile.eligibleSessionCount, 5)
    XCTAssertEqual(reducedProfile.eligibleSessionCount, 5)
    XCTAssertEqual(fullProfile.candidateSessionCount, 5)
    XCTAssertEqual(reducedProfile.candidateSessionCount, 5)
  }

  func testLegacyResearchSessionDecodesAsFullProtocolVariantAndRemainsEligible() throws {
    let participant = PseudonymousParticipantID(rawValue: "participant_legacy")
    let json = Data(
      """
      {
        "schemaVersion": 1,
        "participantID": "participant_legacy",
        "sessionID": "session_legacy",
        "startedAt": 807235200,
        "completedAt": 807235201,
        "metadata": {
          "device": {"platform":"iOS","deviceModel":"iPhone","systemName":"iOS","systemVersion":"18.0","localeIdentifier":"en_US"},
          "app": {"bundleIdentifier":"com.example.sober","version":"0.2","build":"1"},
          "protocolMetadata": {"name":"Sober Research Battery","version":"0.2"}
        },
        "context": {"sessionKind":"sober_baseline","visionCorrection":"unknown","ambientLighting":"moderate"},
        "metrics": {
          "reactionTimeMilliseconds": 320,
          "reactionMisses": 0,
          "trackingError": 0.18,
          "timeEstimateError": 0.08,
          "gazeSmoothness": 0.16,
          "qualityScore": 0.72,
          "completedAllTasks": true
        }
      }
      """.utf8
    )

    let envelope = try JSONDecoder().decode(ResearchSessionEnvelope.self, from: json)
    XCTAssertEqual(envelope.protocolVariant, .full)

    let profile = BaselineProfileEngine().summarize(
      participantID: participant,
      sessions: [envelope],
      protocolVariant: .full
    )
    XCTAssertEqual(profile.eligibleSessionCount, 1)
  }

  func testAccessibleRouteWithoutMeasurementNeverScoresNoSignals() {
    let metrics = ScreeningMetrics(
      reactionTimeMilliseconds: 318,
      reactionMisses: 0,
      trackingError: MotorTrackingOutcome.notMeasured.error,
      timeEstimateError: 0.08,
      gazeSmoothness: 0.16,
      qualityScore: 0,
      completedAllTasks: false
    )

    let outcome = ScreeningEngine().evaluate(selfReport: .no, metrics: metrics)
    XCTAssertEqual(outcome.state, .inconclusive)
    XCTAssertNotEqual(outcome.state, .noSignalsDetected)
  }

  func testBaselineCompletionMessagingDistinguishesUnavailableTaskFromLowQualityCapture() {
    let unavailable = BaselineCompletionState(reason: .taskUnavailable)
    let lowQuality = BaselineCompletionState(reason: .captureQualityTooLow)

    XCTAssertEqual(unavailable.title, "This task isn’t available to you")
    XCTAssertEqual(lowQuality.title, "Capture quality was too low")
    XCTAssertNotEqual(unavailable.message, lowQuality.message)
  }

  // MARK: - P0: the non-visual motor tracking path must not invent a score

  func testUnmeasuredMotorTrackingIsNeverScoredAsGoodPerformance() {
    XCTAssertFalse(MotorTrackingOutcome.notMeasured.wasMeasured)
    XCTAssertEqual(MotorTrackingOutcome.notMeasured.error, 1)

    // The screening flow maps `wasMeasured` onto `completedAllTasks`. An
    // otherwise flawless check must still refuse to return NO_SIGNALS_DETECTED.
    var metrics = ScreeningMetrics.demoClear
    metrics.trackingError = MotorTrackingOutcome.notMeasured.error
    metrics.completedAllTasks = MotorTrackingOutcome.notMeasured.wasMeasured

    let outcome = ScreeningEngine().evaluate(selfReport: .no, metrics: metrics)
    XCTAssertEqual(outcome.state, .inconclusive)
    XCTAssertNotEqual(outcome.state, .noSignalsDetected)
  }

  func testMeasuredMotorTrackingStillCompletesTheCheck() {
    let measured = MotorTrackingOutcome(error: 0.18)
    XCTAssertTrue(measured.wasMeasured)

    var metrics = ScreeningMetrics.demoClear
    metrics.trackingError = measured.error
    metrics.completedAllTasks = measured.wasMeasured

    XCTAssertEqual(
      ScreeningEngine().evaluate(selfReport: .no, metrics: metrics).state,
      .noSignalsDetected
    )
  }

  // MARK: - P0: one stable event ID per screening run

  @MainActor
  func testRetriesReuseASingleEventIDForTheWholeRun() async {
    let recorder = EventIDRecorder()
    let coordinator = ParentAlertCoordinator(
      makeService: { eventID, occurredAt in
        Self.recordingService(eventID: eventID, occurredAt: occurredAt, recorder: recorder) {
          Self.response(statusCode: 502)
        }
      }
    )
    let stableEventID = coordinator.eventID

    coordinator.send(outcome: Self.concerningOutcome, safetyPlan: Self.configuredPlan)
    await coordinator.waitForDelivery()
    XCTAssertEqual(coordinator.state, .failed)

    coordinator.send(outcome: Self.concerningOutcome, safetyPlan: Self.configuredPlan)
    await coordinator.waitForDelivery()

    let observed = await recorder.eventIDs
    XCTAssertEqual(observed.count, 2)
    XCTAssertEqual(observed, [stableEventID.uuidString, stableEventID.uuidString])
  }

  @MainActor
  func testASucceededAlertIsNotResentOnRetry() async {
    let recorder = EventIDRecorder()
    let coordinator = ParentAlertCoordinator(
      makeService: { eventID, occurredAt in
        Self.recordingService(eventID: eventID, occurredAt: occurredAt, recorder: recorder) {
          Self.acceptedResponse(eventID: eventID)
        }
      }
    )

    coordinator.send(outcome: Self.concerningOutcome, safetyPlan: Self.configuredPlan)
    await coordinator.waitForDelivery()
    XCTAssertEqual(coordinator.state, .sent)

    coordinator.send(outcome: Self.concerningOutcome, safetyPlan: Self.configuredPlan)
    await coordinator.waitForDelivery()

    let observed = await recorder.eventIDs
    XCTAssertEqual(observed.count, 1, "A delivered alert must not be submitted twice")
  }

  @MainActor
  func testConcurrentSendsProduceOnlyOneSubmission() async {
    let recorder = EventIDRecorder()
    let coordinator = ParentAlertCoordinator(
      makeService: { eventID, occurredAt in
        Self.recordingService(eventID: eventID, occurredAt: occurredAt, recorder: recorder) {
          Self.acceptedResponse(eventID: eventID)
        }
      }
    )

    coordinator.send(outcome: Self.concerningOutcome, safetyPlan: Self.configuredPlan)
    coordinator.send(outcome: Self.concerningOutcome, safetyPlan: Self.configuredPlan)
    coordinator.send(outcome: Self.concerningOutcome, safetyPlan: Self.configuredPlan)
    await coordinator.waitForDelivery()

    let observed = await recorder.eventIDs
    XCTAssertEqual(observed.count, 1)
  }

  @MainActor
  func testConcerningLiveResultStartsSendingImmediately() {
    let coordinator = ParentAlertCoordinator(
      makeService: { eventID, occurredAt in
        Self.recordingService(
          eventID: eventID,
          occurredAt: occurredAt,
          recorder: EventIDRecorder()
        ) {
          Self.acceptedResponse(eventID: eventID)
        }
      }
    )

    coordinator.send(outcome: Self.concerningOutcome, safetyPlan: Self.configuredPlan)
    XCTAssertEqual(coordinator.state, .sending)
  }

  @MainActor
  func testSamplePreviewsNeverContactTheRelay() async {
    let recorder = EventIDRecorder()
    let coordinator = ParentAlertCoordinator(
      makeService: { eventID, occurredAt in
        Self.recordingService(eventID: eventID, occurredAt: occurredAt, recorder: recorder) {
          Self.acceptedResponse(eventID: eventID)
        }
      }
    )

    coordinator.presentSample(for: Self.concerningOutcome)
    XCTAssertEqual(coordinator.state, .preview)

    let observed = await recorder.eventIDs
    XCTAssertTrue(observed.isEmpty)
  }

  @MainActor
  func testNonConcerningResultNeverSends() async {
    let recorder = EventIDRecorder()
    let coordinator = ParentAlertCoordinator(
      makeService: { eventID, occurredAt in
        Self.recordingService(eventID: eventID, occurredAt: occurredAt, recorder: recorder) {
          Self.acceptedResponse(eventID: eventID)
        }
      }
    )
    let clearOutcome = ScreeningEngine().evaluate(
      selfReport: .no,
      metrics: .demoClear,
      founderScenario: .noSignals
    )

    coordinator.send(outcome: clearOutcome, safetyPlan: Self.configuredPlan)
    XCTAssertEqual(coordinator.state, .notRequired)

    let observed = await recorder.eventIDs
    XCTAssertTrue(observed.isEmpty)
  }

  // MARK: - P1: a skipped or blocked ocular task is never archived as a capture

  @MainActor
  func testSkippedOcularTaskReportsNoCaptureDespiteGoodCalibration() {
    let service = FaceTrackingService()
    // Reduced Motion skip and permission loss both route through here.
    for issue in [CaptureQualityIssue.interrupted, .permissionDenied, .unsupported] {
      let summary = service.unusableSummary(issue: issue)

      XCTAssertFalse(summary.quality.isUsable, "\(issue) must never look usable")
      XCTAssertEqual(summary.qualityScore, 0)
      XCTAssertEqual(summary.quality.score, 0)
      XCTAssertEqual(summary.sampleCount, 0)
      XCTAssertEqual(summary.quality.sampleCount, 0)
      XCTAssertEqual(summary.capturedDurationMilliseconds, 0)
      XCTAssertEqual(summary.quality.frameRate, 0)
      XCTAssertEqual(summary.quality.dropoutRatio, 1)
      XCTAssertFalse(summary.quality.facePresent)
      XCTAssertTrue(summary.quality.issues.contains(issue))
      XCTAssertTrue(summary.quality.issues.contains(.insufficientSamples))
    }
  }

  func testAnalyzerReportsTheDurationItActuallyMeasured() {
    let samples = Self.syntheticSamples(framesPerSecond: 30)
    let liveQuality = CaptureQualitySnapshot(
      isSupported: true,
      hasCameraPermission: true,
      facePresent: true,
      centered: true,
      distanceAcceptable: true,
      lightingAcceptable: true,
      headStable: true,
      frameRate: 30,
      sampleCount: samples.count,
      dropoutRatio: 0,
      issues: []
    )

    let summary = OcularSignalAnalyzer().summarize(
      samples: samples,
      observedFrameCount: samples.count,
      liveQuality: liveQuality
    )

    XCTAssertEqual(
      summary.capturedDurationMilliseconds,
      OcularProtocolSchedule.totalDuration * 1_000,
      accuracy: 100
    )
  }

  func testGazeSummaryDurationSurvivesJSONRoundTripAndDefaultsForLegacyRecords() throws {
    let summary = GazeCaptureSummary(
      smoothnessRisk: 0.2,
      qualityScore: 0.9,
      sampleCount: 240,
      capturedDurationMilliseconds: 25_000
    )
    let decoded = try JSONDecoder().decode(
      GazeCaptureSummary.self,
      from: try JSONEncoder().encode(summary)
    )
    XCTAssertEqual(decoded.capturedDurationMilliseconds, 25_000)

    // A schema-1 record written before this field existed must still decode.
    let legacy = Data(
      """
      {
        "smoothnessRisk": 0.2,
        "qualityScore": 0.9,
        "sampleCount": 240,
        "quality": {
          "isSupported": true, "hasCameraPermission": true, "facePresent": true,
          "centered": true, "distanceAcceptable": true, "lightingAcceptable": true,
          "headStable": true, "frameRate": 30, "sampleCount": 240,
          "dropoutRatio": 0.02, "issues": []
        },
        "features": {
          "fixationJitter": 0.1, "horizontalPursuitError": 0.1,
          "verticalPursuitError": 0.1, "saccadeError": 0.1,
          "leftRightAsymmetry": 0.1, "blinkRatePerMinute": 14, "headCompensation": 0.1
        }
      }
      """.utf8
    )
    let decodedLegacy = try JSONDecoder().decode(GazeCaptureSummary.self, from: legacy)
    XCTAssertEqual(decodedLegacy.capturedDurationMilliseconds, 0)
  }

  @MainActor
  func testSkippedOcularTaskIsExcludedFromTheBaseline() async {
    let suiteName = "ReviewRegressionTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let model = AppModel(
      defaults: defaults,
      researchStore: ResearchSessionStore(directoryURL: directory)
    )
    let skipped = FaceTrackingService().unusableSummary(issue: .interrupted)

    await model.recordCompletedSession(
      mode: .baseline,
      selfReport: .no,
      metrics: ScreeningMetrics(
        reactionTimeMilliseconds: 318,
        reactionMisses: 0,
        trackingError: 0.18,
        timeEstimateError: 0.08,
        gazeSmoothness: skipped.smoothnessRisk,
        qualityScore: skipped.qualityScore,
        completedAllTasks: true
      ),
      reactionSummary: nil,
      ocularSummary: skipped,
      startedAt: Date()
    )

    XCTAssertEqual(model.researchSessions.count, 1)
    XCTAssertEqual(model.baselineProfile?.eligibleSessionCount, 0)
    XCTAssertEqual(model.baselineProfile?.excludedSessionCount, 1)

    // The archived record must not claim a 25-second high-quality capture.
    guard let archived = model.researchSessions.first?.ocularQuality else {
      return XCTFail("Expected an archived ocular quality record")
    }
    XCTAssertEqual(archived.trackingDurationMilliseconds, 0)
    XCTAssertEqual(archived.sampleCount, 0)
    XCTAssertEqual(archived.signalQualityScore, 0)
    XCTAssertNil(archived.bothEyesVisibleFraction)
    XCTAssertNil(archived.headStabilityScore)
    XCTAssertNil(archived.illuminationScore)
    XCTAssertEqual(archived.facePresentAtCompletion, false)
    XCTAssertEqual(archived.headStableAtCompletion, false)
    XCTAssertEqual(archived.lightingAcceptableAtCompletion, false)
  }

  // MARK: - P1: deletion must also remove a prepared export

  @MainActor
  func testDeletingResearchDataAlsoRemovesThePreparedExportFile() async {
    let suiteName = "ReviewRegressionTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let model = AppModel(
      defaults: defaults,
      researchStore: ResearchSessionStore(directoryURL: directory)
    )
    let originalParticipantID = model.participantID
    model.researchConsent = true

    await model.recordCompletedSession(
      mode: .check,
      selfReport: .no,
      metrics: .demoClear,
      reactionSummary: nil,
      ocularSummary: nil,
      startedAt: Date()
    )

    let exportURL = await model.prepareResearchExport()
    let url = try? XCTUnwrap(exportURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url!.path))

    await model.deleteAllResearchData()

    XCTAssertFalse(
      FileManager.default.fileExists(atPath: url!.path),
      "Deleted research data must not survive in the temporary export file"
    )
    XCTAssertNil(model.lastExportURL)
    XCTAssertTrue(model.researchSessions.isEmpty)
    XCTAssertNotEqual(model.participantID, originalParticipantID)
    XCTAssertEqual(
      defaults.string(forKey: "sober.research.participant-id"),
      model.participantID.rawValue
    )
  }

  // MARK: - Fixtures

  private static var concerningOutcome: ScreeningOutcome {
    ScreeningEngine().evaluate(
      selfReport: .no,
      metrics: .demoClear,
      founderScenario: .signals
    )
  }

  private static var configuredPlan: SafetyPlan {
    SafetyPlan(
      userName: "Alex",
      contactName: "Casey",
      contactPhone: "512-555-0147",
      automaticParentAlerts: true,
      parentAlertConsent: true
    )
  }

  private static func recordingService(
    eventID: UUID,
    occurredAt: Date,
    recorder: EventIDRecorder,
    response: @escaping @Sendable () -> (Data, URLResponse)
  ) -> ParentAlertService {
    ParentAlertService(
      configuration: ParentAlertConfiguration(
        endpoint: URL(string: "https://alerts.example.test/v1/alerts")!,
        bearerToken: "test-shared-token-at-least-20-characters"
      ),
      eventID: eventID,
      occurredAt: occurredAt,
      transport: { request in
        await recorder.capture(request)
        return response()
      }
    )
  }

  private static func acceptedResponse(eventID: UUID) -> (Data, URLResponse) {
    let data = try! JSONSerialization.data(withJSONObject: [
      "submissionStatus": "accepted",
      "eventID": eventID.uuidString,
      "reference": "SM123",
    ])
    return (data, response(statusCode: 202).1)
  }

  private static func response(statusCode: Int) -> (Data, URLResponse) {
    (
      Data("{}".utf8),
      HTTPURLResponse(
        url: URL(string: "https://alerts.example.test/v1/alerts")!,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
      )!
    )
  }

  private static func syntheticSamples(framesPerSecond: Int) -> [OcularSample] {
    let step = 1 / Double(framesPerSecond)
    return stride(from: 0.0, through: OcularProtocolSchedule.totalDuration, by: step).map { time in
      let target = OcularProtocolSchedule.target(at: time)
      return OcularSample(
        timestamp: time,
        phase: target.phase,
        targetX: target.x,
        targetY: target.y,
        leftGazeX: target.x * 0.1,
        leftGazeY: target.y * 0.1,
        rightGazeX: target.x * 0.1,
        rightGazeY: target.y * 0.1,
        headX: 0,
        headY: 0,
        headZ: -1,
        blinkLeft: 0,
        blinkRight: 0
      )
    }
  }

  private static func syntheticReducedMotionSamples(followsTarget: Bool) -> [OcularSample] {
    let step = 1 / 30.0
    return stride(from: 0.0, through: OcularProtocolSchedule.totalDuration(for: .reducedMotion), by: step).map { time in
      let target = OcularProtocolSchedule.target(at: time, variant: .reducedMotion)
      let gazeX = followsTarget ? target.x : 0.1
      let gazeY = followsTarget ? target.y : 0.9
      return OcularSample(
        timestamp: time,
        phase: target.phase,
        targetX: target.x,
        targetY: target.y,
        leftGazeX: gazeX,
        leftGazeY: gazeY,
        rightGazeX: gazeX,
        rightGazeY: gazeY,
        headX: 0,
        headY: 0,
        headZ: -1,
        blinkLeft: 0,
        blinkRight: 0
      )
    }
  }

  private static func makeBaselineSession(participantID: PseudonymousParticipantID, variant: OcularProtocolVariant) -> ResearchSessionEnvelope {
    ResearchSessionEnvelope(
      participantID: participantID,
      startedAt: Date(),
      completedAt: Date(),
      metadata: ResearchSessionMetadata(
        device: ResearchDeviceMetadata(
          platform: "iOS",
          deviceModel: "iPhone",
          systemName: "iOS",
          systemVersion: "test",
          localeIdentifier: "en_US"
        ),
        app: .current(),
        protocolMetadata: ResearchProtocolMetadata(name: "Sober Research Battery", version: "0.2")
      ),
      context: ResearchSessionContext(sessionKind: .soberBaseline),
      metrics: ResearchScreeningMetrics(
        reactionTimeMilliseconds: 320,
        reactionMisses: 0,
        trackingError: 0.18,
        timeEstimateError: 0.08,
        gazeSmoothness: 0.16,
        qualityScore: 0.72,
        completedAllTasks: true
      ),
      ocularSummary: GazeCaptureSummary(
        smoothnessRisk: 0.1,
        qualityScore: 0.9,
        sampleCount: 240,
        capturedDurationMilliseconds: 11_000,
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
          dropoutRatio: 0.01,
          issues: []
        ),
        features: OcularSignalFeatures.unavailable,
        protocolVariant: variant
      ),
      protocolVariant: variant
    )
  }
}

private actor EventIDRecorder {
  private(set) var eventIDs: [String] = []

  func capture(_ request: URLRequest) {
    if let header = request.value(forHTTPHeaderField: "Idempotency-Key") {
      eventIDs.append(header)
    }
  }
}
