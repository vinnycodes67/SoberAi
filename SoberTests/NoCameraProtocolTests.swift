import Foundation
import XCTest

@testable import Sober

final class NoCameraProtocolTests: XCTestCase {
  private let screeningEngine = ScreeningEngine()

  func testNoCameraCheckConcludesWithThreeMeasuredTasks() {
    let outcome = screeningEngine.evaluate(
      selfReport: .no,
      metrics: noCameraMetrics(),
      protocolVariant: .noCamera
    )

    XCTAssertNotEqual(outcome.state, .inconclusive)
  }

  func testNoCameraRiskRenormalizesThreeTasksAndExcludesCameraSignals() {
    var metrics = noCameraMetrics(
      reactionTimeMilliseconds: 585,
      reactionMisses: 3,
      trackingError: 0.39,
      timeEstimateError: 0.265
    )
    metrics.gazeSmoothness = 1
    metrics.pupillometry = PupillometrySample(
      trials: [
        PupilLightReflexTrial(
          baselineDiameterMm: 5,
          minDiameterMm: 4.9,
          latencySeconds: 0.6,
          peakConstrictionVelocityMmPerSecond: 0.5,
          amplitudePercent: 0.02,
          recoveryTo75PercentSeconds: nil
        )
      ],
      qualityScore: 1
    )

    let outcome = screeningEngine.evaluate(
      selfReport: .no,
      metrics: metrics,
      protocolVariant: .noCamera
    )
    let expectedRisk = ((0.5 * 0.20) + (1 * 0.12) + (0.5 * 0.18) + (0.5 * 0.10)) / 0.60

    XCTAssertEqual(outcome.riskScore, expectedRisk, accuracy: 0.000_001)

    metrics.gazeSmoothness = 0
    metrics.pupillometry = nil
    let withoutCameraSignals = screeningEngine.evaluate(
      selfReport: .no,
      metrics: metrics,
      protocolVariant: .noCamera
    )
    XCTAssertEqual(outcome.riskScore, withoutCameraSignals.riskScore, accuracy: 0.000_001)
  }

  func testNoCameraGazeDetailExplainsWhyItWasNotMeasured() throws {
    let outcome = screeningEngine.evaluate(
      selfReport: .no,
      metrics: noCameraMetrics(),
      protocolVariant: .noCamera
    )
    let gaze = try XCTUnwrap(outcome.details.first { $0.id == "gaze" })

    XCTAssertEqual(gaze.value, "Not measured")
    XCTAssertTrue(gaze.label.contains("this iPhone has no TrueDepth camera"))
    XCTAssertFalse(gaze.concern)
    XCTAssertFalse(gaze.wasMeasured)
  }

  /// The result screen prints capture quality as a percentage. A camera-free
  /// check captured nothing, so the outcome has to say so rather than let the
  /// screen render a number that grades a recording that never happened.
  func testACameraFreeOutcomeReportsThatNothingWasCaptured() {
    let outcome = ScreeningEngine().evaluate(
      selfReport: .no,
      metrics: noCameraMetrics(),
      personalBaseline: nil,
      protocolVariant: .noCamera
    )

    XCTAssertFalse(outcome.measuredCapture)
  }

  func testACameraCheckStillReportsItsCapture() {
    let outcome = ScreeningEngine().evaluate(
      selfReport: .no,
      metrics: noCameraMetrics(),
      personalBaseline: nil,
      protocolVariant: .full
    )

    XCTAssertTrue(outcome.measuredCapture)
  }

  func testFullProtocolStillRequiresGaze() {
    let outcome = screeningEngine.evaluate(
      selfReport: .no,
      metrics: noCameraMetrics(),
      protocolVariant: .full
    )

    XCTAssertEqual(outcome.state, .inconclusive)
  }

  func testNoCameraBaselineIsEligibleWithoutGazeOrCameraQuality() {
    let participantID = PseudonymousParticipantID(rawValue: "participant_no_camera")
    let session = makeSession(
      participantID: participantID,
      metrics: ResearchScreeningMetrics(noCameraMetrics()),
      protocolVariant: .noCamera
    )

    let summary = BaselineProfileEngine().summarize(
      participantID: participantID,
      sessions: [session],
      protocolVariant: .noCamera
    )

    XCTAssertEqual(summary.candidateSessionCount, 1)
    XCTAssertEqual(summary.eligibleSessionCount, 1)
    XCTAssertNil(summary.metrics?.gazeSmoothness)
  }

  /// Defence in depth for the partition boundary. The check flow now stores a
  /// nil gaze figure for a camera-free run, but the baseline a check is scored
  /// against must not depend on every producer remembering to: a stray value in
  /// the field cannot become a gaze statistic in a partition that has no eyes.
  func testACameraFreeBaselineIgnoresAStrayGazeValue() {
    let participantID = PseudonymousParticipantID(rawValue: "participant_stray_gaze")
    var metrics = noCameraMetrics()
    metrics.gazeSmoothness = 0
    let session = makeSession(
      participantID: participantID,
      metrics: ResearchScreeningMetrics(metrics),
      protocolVariant: .noCamera
    )

    let summary = BaselineProfileEngine().summarize(
      participantID: participantID,
      sessions: [session],
      protocolVariant: .noCamera
    )

    XCTAssertEqual(summary.eligibleSessionCount, 1)
    XCTAssertNil(summary.metrics?.gazeSmoothness)
  }

  func testNoCameraBaselineRejectsAnUnmeasuredTask() {
    let participantID = PseudonymousParticipantID(rawValue: "participant_unmeasured")
    var metrics = noCameraMetrics()
    metrics.reactionWasMeasured = false
    let session = makeSession(
      participantID: participantID,
      metrics: ResearchScreeningMetrics(metrics),
      protocolVariant: .noCamera
    )

    let summary = BaselineProfileEngine().summarize(
      participantID: participantID,
      sessions: [session],
      protocolVariant: .noCamera
    )

    XCTAssertEqual(summary.eligibleSessionCount, 0)
  }

  func testNoCameraSessionDoesNotCountTowardFullBaseline() {
    let participantID = PseudonymousParticipantID(rawValue: "participant_partitioned")
    let session = makeSession(
      participantID: participantID,
      metrics: ResearchScreeningMetrics(noCameraMetrics()),
      protocolVariant: .noCamera
    )

    let fullSummary = BaselineProfileEngine().summarize(
      participantID: participantID,
      sessions: [session],
      protocolVariant: .full
    )

    XCTAssertEqual(fullSummary.candidateSessionCount, 0)
    XCTAssertEqual(fullSummary.eligibleSessionCount, 0)
  }

  private func noCameraMetrics(
    reactionTimeMilliseconds: Double = 318,
    reactionMisses: Int = 0,
    trackingError: Double? = 0.18,
    timeEstimateError: Double = 0.08
  ) -> ScreeningMetrics {
    ScreeningMetrics(
      reactionTimeMilliseconds: reactionTimeMilliseconds,
      reactionMisses: reactionMisses,
      trackingError: trackingError,
      timeEstimateError: timeEstimateError,
      gazeSmoothness: nil,
      qualityScore: 0,
      completedAllTasks: true
    )
  }

  private func makeSession(
    participantID: PseudonymousParticipantID,
    metrics: ResearchScreeningMetrics,
    protocolVariant: OcularProtocolVariant
  ) -> ResearchSessionEnvelope {
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    return ResearchSessionEnvelope(
      participantID: participantID,
      sessionID: ResearchSessionID(rawValue: "session_no_camera"),
      startedAt: startedAt,
      completedAt: startedAt.addingTimeInterval(45),
      metadata: ResearchSessionMetadata(
        device: ResearchDeviceMetadata(
          platform: "iOS",
          deviceModel: "iPhone",
          systemName: "iOS",
          systemVersion: "18.0",
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
        reportedCannabisUse: false
      ),
      metrics: metrics,
      protocolVariant: protocolVariant
    )
  }
}
