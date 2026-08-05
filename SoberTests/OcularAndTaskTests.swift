import XCTest

@testable import Sober

final class OcularAndTaskTests: XCTestCase {
  func testUnsupportedCaptureIsNeverUsable() {
    XCTAssertFalse(CaptureQualitySnapshot.unsupported.isUsable)
    XCTAssertEqual(CaptureQualitySnapshot.unsupported.score, 0)
    XCTAssertEqual(CaptureQualitySnapshot.unsupported.primaryGuidance, CaptureQualityIssue.unsupported.guidance)
  }

  func testProtocolContainsAllFourMeasuredPhases() {
    XCTAssertEqual(OcularProtocolSchedule.target(at: 0).phase, .fixation)
    XCTAssertEqual(OcularProtocolSchedule.target(at: 4).phase, .horizontalPursuit)
    XCTAssertEqual(OcularProtocolSchedule.target(at: 12).phase, .verticalPursuit)
    XCTAssertEqual(OcularProtocolSchedule.target(at: 19).phase, .saccades)
  }

  func testAnalyzerAcceptsStableSyntheticCapture() {
    let samples = syntheticSamples(framesPerSecond: 30)
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

    XCTAssertTrue(summary.quality.isUsable)
    XCTAssertGreaterThanOrEqual(summary.qualityScore, 0.72)
    XCTAssertLessThan(summary.features.horizontalPursuitError, 0.05)
    XCTAssertLessThan(summary.features.verticalPursuitError, 0.05)
  }

  func testAnalyzerRejectsInsufficientSamples() {
    let quality = CaptureQualitySnapshot(
      isSupported: true,
      hasCameraPermission: true,
      facePresent: true,
      centered: true,
      distanceAcceptable: true,
      lightingAcceptable: true,
      headStable: true,
      frameRate: 30,
      sampleCount: 3,
      dropoutRatio: 0,
      issues: []
    )
    let summary = OcularSignalAnalyzer().summarize(
      samples: Array(syntheticSamples(framesPerSecond: 1).prefix(3)),
      observedFrameCount: 3,
      liveQuality: quality
    )

    XCTAssertEqual(summary.qualityScore, 0)
    XCTAssertFalse(summary.quality.isUsable)
    XCTAssertTrue(summary.quality.issues.contains(.insufficientSamples))
  }

  func testAnalyzerKeepsMissingBlinkTelemetryAbsent() {
    let samples = syntheticSamples(framesPerSecond: 30).map { sample in
      OcularSample(
        timestamp: sample.timestamp,
        phase: sample.phase,
        targetX: sample.targetX,
        targetY: sample.targetY,
        leftGazeX: sample.leftGazeX,
        leftGazeY: sample.leftGazeY,
        rightGazeX: sample.rightGazeX,
        rightGazeY: sample.rightGazeY,
        headX: sample.headX,
        headY: sample.headY,
        headZ: sample.headZ,
        blinkLeft: nil,
        blinkRight: nil
      )
    }

    let summary = OcularSignalAnalyzer().summarize(
      samples: samples,
      observedFrameCount: samples.count,
      liveQuality: CaptureQualitySnapshot(
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
    )

    XCTAssertNil(summary.features.blinkRatePerMinute)
  }

  func testCaptureQualityCannotBeRescuedByOneGoodFinalFrame() {
    var history = CaptureQualityHistory()
    for _ in 0..<8 {
      history.record(
        facePresent: true,
        centered: false,
        distanceAcceptable: false,
        lightingAcceptable: false,
        headStable: false
      )
    }
    for _ in 0..<2 {
      history.record(
        facePresent: true,
        centered: true,
        distanceAcceptable: true,
        lightingAcceptable: true,
        headStable: true
      )
    }

    let finalFrame = CaptureQualitySnapshot(
      isSupported: true,
      hasCameraPermission: true,
      facePresent: true,
      centered: true,
      distanceAcceptable: true,
      lightingAcceptable: true,
      headStable: true,
      frameRate: 30,
      sampleCount: 300,
      dropoutRatio: 0,
      issues: []
    )
    let aggregate = history.applying(to: finalFrame)

    XCTAssertFalse(aggregate.isUsable)
    XCTAssertFalse(aggregate.centered)
    XCTAssertFalse(aggregate.distanceAcceptable)
    XCTAssertFalse(aggregate.lightingAcceptable)
    XCTAssertFalse(aggregate.headStable)
    XCTAssertTrue(aggregate.issues.contains(.offCenter))
    XCTAssertTrue(aggregate.issues.contains(.distance))
    XCTAssertTrue(aggregate.issues.contains(.lowLight))
    XCTAssertTrue(aggregate.issues.contains(.unstable))
  }

  func testChoiceReactionSummaryIncludesEveryErrorType() {
    let summary = ChoiceReactionSummary(trials: [
      ChoiceReactionTrial(
        expected: .blueCircle,
        selected: .blueCircle,
        latencyMilliseconds: 300,
        wasAnticipation: false,
        wasMiss: false
      ),
      ChoiceReactionTrial(
        expected: .pinkDiamond,
        selected: .pinkCircle,
        latencyMilliseconds: 450,
        wasAnticipation: false,
        wasMiss: false
      ),
      ChoiceReactionTrial(
        expected: .blueDiamond,
        selected: .blueDiamond,
        latencyMilliseconds: nil,
        wasAnticipation: true,
        wasMiss: false
      ),
      ChoiceReactionTrial(
        expected: .pinkCircle,
        selected: nil,
        latencyMilliseconds: nil,
        wasAnticipation: false,
        wasMiss: true
      ),
    ])

    XCTAssertEqual(summary.averageMilliseconds, 300)
    XCTAssertEqual(summary.incorrectChoices, 1)
    XCTAssertEqual(summary.anticipations, 1)
    XCTAssertEqual(summary.misses, 1)
    XCTAssertEqual(summary.totalErrors, 3)
  }

  private func syntheticSamples(framesPerSecond: Int) -> [OcularSample] {
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
}
