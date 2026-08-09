import XCTest

@testable import Sober

final class ScreeningEngineTests: XCTestCase {
  private let engine = ScreeningEngine()

  func testReportedUseCanNeverReturnNoSignals() {
    let performances: [ScreeningMetrics] = [
      .demoClear,
      ScreeningMetrics(
        reactionTimeMilliseconds: 210,
        reactionMisses: 0,
        trackingError: 0,
        timeEstimateError: 0,
        gazeSmoothness: 0,
        qualityScore: 1,
        completedAllTasks: true
      ),
      ScreeningMetrics(
        reactionTimeMilliseconds: 1_200,
        reactionMisses: 4,
        trackingError: 1,
        timeEstimateError: 1,
        gazeSmoothness: 1,
        qualityScore: 0.2,
        completedAllTasks: false
      ),
    ]

    for metrics in performances {
      let result = engine.evaluate(selfReport: .yes, metrics: metrics)
      XCTAssertEqual(result.state, .signalsDetected)
      XCTAssertNotEqual(result.state, .noSignalsDetected)
    }
  }

  func testUnsureSelfReportReturnsInconclusive() {
    let result = engine.evaluate(selfReport: .unsure, metrics: .demoClear)
    XCTAssertEqual(result.state, .inconclusive)
  }

  func testSelfReportOnlyResultDoesNotClaimTasksWereMeasured() {
    let metrics = ScreeningMetrics(
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

    let result = engine.evaluate(selfReport: .yes, metrics: metrics)

    XCTAssertEqual(result.state, .signalsDetected)
    XCTAssertTrue(result.details.allSatisfy { !$0.wasMeasured })
    XCTAssertTrue(result.details.allSatisfy { $0.value == "Not measured" })
  }

  func testLowQualityRefusesToGuess() {
    var metrics = ScreeningMetrics.demoClear
    metrics.qualityScore = 0.41

    let result = engine.evaluate(selfReport: .no, metrics: metrics)
    XCTAssertEqual(result.state, .inconclusive)
  }

  func testIncompleteTasksRefuseToGuess() {
    var metrics = ScreeningMetrics.demoClear
    metrics.completedAllTasks = false

    let result = engine.evaluate(selfReport: .no, metrics: metrics)
    XCTAssertEqual(result.state, .inconclusive)
  }

  func testStrongTaskDeviationsReturnSignalsDetected() {
    let metrics = ScreeningMetrics(
      reactionTimeMilliseconds: 910,
      reactionMisses: 3,
      trackingError: 0.72,
      timeEstimateError: 0.58,
      gazeSmoothness: 0.66,
      qualityScore: 0.91,
      completedAllTasks: true
    )

    let result = engine.evaluate(selfReport: .no, metrics: metrics)
    XCTAssertEqual(result.state, .signalsDetected)
  }

  func testNoSignalsCopyRetainsMandatoryWarning() {
    XCTAssertEqual(
      ScreeningResultState.noSignalsDetected.message,
      "We didn’t detect signals. This does not mean you’re sober or safe to drive."
    )
  }

  func testPersonalBaselineFlipsAVerdictPopulationThresholdsWouldClear() {
    // This person's own sober readings are fast and steady across the
    // board. The check-time values below are each individually within
    // the population's "clear" ranges, but each is a large (~4+ SD)
    // deviation from this person's own baseline, and together should tip
    // the combined verdict once that baseline is ready — even though no
    // single metric alone carries enough weight to do it.
    var baseline = PersonalBaseline()
    for _ in 0..<3 {
      baseline.record(
        BaselineSample(
          reactionTimeMilliseconds: 260,
          reactionMisses: 0,
          trackingError: 0.12,
          timeEstimateError: 0.05,
          gazeSmoothness: 0.10
        ))
    }

    let metrics = ScreeningMetrics(
      reactionTimeMilliseconds: 500,
      reactionMisses: 0,
      trackingError: 0.30,
      timeEstimateError: 0.25,
      gazeSmoothness: 0.30,
      qualityScore: 0.9,
      completedAllTasks: true
    )

    let withoutBaseline = engine.evaluate(selfReport: .no, metrics: metrics)
    XCTAssertEqual(withoutBaseline.state, .noSignalsDetected)

    let withBaseline = engine.evaluate(
      selfReport: .no, metrics: metrics, personalBaseline: baseline)
    XCTAssertEqual(withBaseline.state, .signalsDetected)
  }

  func testBaselineBelowRequiredSessionsFallsBackToPopulationThresholds() {
    var baseline = PersonalBaseline()
    baseline.record(
      BaselineSample(
        reactionTimeMilliseconds: 260, reactionMisses: 0, trackingError: 0.12,
        timeEstimateError: 0.05, gazeSmoothness: 0.10))

    let result = engine.evaluate(
      selfReport: .no, metrics: .demoClear, personalBaseline: baseline)
    XCTAssertEqual(result.state, .noSignalsDetected)
  }

  func testMissingPerMetricBaselineFallsBackForThatMetricOnly() {
    // Three ready sessions overall, but gaze was skipped every time, so
    // gaze alone should still fall back to the population range.
    var baseline = PersonalBaseline()
    for _ in 0..<3 {
      baseline.record(
        BaselineSample(
          reactionTimeMilliseconds: 300, reactionMisses: 0, trackingError: 0.15,
          timeEstimateError: 0.06, gazeSmoothness: nil))
    }

    let result = engine.evaluate(
      selfReport: .no, metrics: .demoClear, personalBaseline: baseline)
    XCTAssertEqual(result.state, .noSignalsDetected)
  }

  func testEllipseFitRecoversKnownDiameter() {
    var points: [(x: Double, y: Double)] = []
    let radius = 20.0
    let center = 50.0
    for x in stride(from: center - radius, through: center + radius, by: 1.0) {
      for y in stride(from: center - radius, through: center + radius, by: 1.0) {
        if (x - center) * (x - center) + (y - center) * (y - center) <= radius * radius {
          points.append((x, y))
        }
      }
    }

    let result = EllipseFit.fit(points: points)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.averageDiameter ?? 0, radius * 2, accuracy: 0.5)
  }

  func testEllipseFitRefusesTooFewPoints() {
    XCTAssertNil(EllipseFit.fit(points: [(0, 0), (1, 1)]))
  }

  /// Regression guard for the pupil-segmentation model actually shipping:
  /// this project runs its tests inside the Sober.app host process (see
  /// TEST_HOST in project.pbxproj), so Bundle.main here is the real app
  /// bundle — if PupilSegmentation.mlmodelc is ever dropped from the
  /// target's Resources build phase, or fails to compile, this fails
  /// instead of silently degrading pupillometry back to "no reading."
  @MainActor
  func testPupilSegmentationModelIsBundledAndLoads() {
    XCTAssertTrue(
      PupilCaptureService().isModelAvailable,
      "PupilSegmentation.mlmodelc should be bundled and loadable — see Training/PupilSegmentation/README.md"
    )
  }

  func testDeriveTrialExtractsExpectedPLRMetrics() {
    // A hand-constructed diameter/time trace with known latency, peak
    // constriction velocity, amplitude, and recovery time, verified against
    // this exact function with a standalone script before trusting these
    // numbers.
    let samples: [(timestamp: TimeInterval, diameterMm: Double)] = [
      (8.0, 5.0), (8.5, 5.0), (9.0, 5.0), (9.5, 5.0),
      (10.0, 5.0), (10.2, 5.0), (10.4, 4.6), (10.6, 4.0), (10.8, 3.4), (11.0, 3.0),
      (11.2, 3.2), (11.4, 3.6), (11.6, 4.0), (11.8, 4.5), (12.0, 4.8),
    ]

    let trial = PupilLightReflexAnalyzer.deriveTrial(samples: samples, flashOnsetTime: 10.0)
    XCTAssertNotNil(trial)
    XCTAssertEqual(trial?.baselineDiameterMm ?? 0, 5.0, accuracy: 0.001)
    XCTAssertEqual(trial?.minDiameterMm ?? 0, 3.0, accuracy: 0.001)
    XCTAssertEqual(trial?.latencySeconds ?? 0, 0.4, accuracy: 0.001)
    XCTAssertEqual(trial?.peakConstrictionVelocityMmPerSecond ?? 0, 3.0, accuracy: 0.001)
    XCTAssertEqual(trial?.amplitudePercent ?? 0, 0.4, accuracy: 0.001)
    XCTAssertEqual(trial?.recoveryTo75PercentSeconds ?? 0, 0.8, accuracy: 0.001)
  }

  func testDeriveTrialReturnsNilRecoveryWhenItNeverRecovers() {
    let samples: [(timestamp: TimeInterval, diameterMm: Double)] = [
      (0, 5), (0.5, 5), (1, 5), (1.5, 5),
      (2, 5), (2.2, 4.6), (2.4, 4.0), (2.6, 3.4), (2.8, 3.0), (3.0, 3.0),
    ]
    let trial = PupilLightReflexAnalyzer.deriveTrial(samples: samples, flashOnsetTime: 2.0)
    XCTAssertNotNil(trial)
    XCTAssertNil(trial?.recoveryTo75PercentSeconds)
  }

  func testHealthyPupilReadingScoresLowerRiskThanMissingData() {
    var metrics = ScreeningMetrics.demoClear
    metrics.pupillometry = nil
    let missingResult = engine.evaluate(selfReport: .no, metrics: metrics)

    metrics.pupillometry = PupillometrySample(
      trials: [
        PupilLightReflexTrial(
          baselineDiameterMm: 5, minDiameterMm: 3, latencySeconds: 0.15,
          peakConstrictionVelocityMmPerSecond: 5.5, amplitudePercent: 0.40,
          recoveryTo75PercentSeconds: 1.0)
      ],
      qualityScore: 0.9
    )
    let healthyResult = engine.evaluate(selfReport: .no, metrics: metrics)

    // A present, healthy reading should score strictly less risky than no
    // reading at all — missing data defaults to the conservative (highest
    // risk) contribution, same shape as the tracking/gaze fallback.
    XCTAssertLessThan(healthyResult.riskScore, missingResult.riskScore)
    XCTAssertEqual(missingResult.riskScore - healthyResult.riskScore, 0.25, accuracy: 0.001)

    // A clearly blunted reflex should contribute exactly the same
    // (maximum) risk as no reading at all.
    metrics.pupillometry = PupillometrySample(
      trials: [
        PupilLightReflexTrial(
          baselineDiameterMm: 5, minDiameterMm: 4.75, latencySeconds: 0.6,
          peakConstrictionVelocityMmPerSecond: 0.5, amplitudePercent: 0.05,
          recoveryTo75PercentSeconds: nil)
      ],
      qualityScore: 0.9
    )
    let bluntedResult = engine.evaluate(selfReport: .no, metrics: metrics)
    XCTAssertEqual(bluntedResult.riskScore, missingResult.riskScore, accuracy: 0.001)

    // None of these cross the signal threshold on their own — this test is
    // about the pupil contribution's shape, not a verdict flip.
    XCTAssertEqual(missingResult.state, .noSignalsDetected)
    XCTAssertEqual(healthyResult.state, .noSignalsDetected)
    XCTAssertEqual(bluntedResult.state, .noSignalsDetected)
  }

  func testMissingPupillometryDoesNotForceInconclusive() {
    // Unlike trackingError/gazeSmoothness, a missing pupil reading must
    // never gate the result to INCONCLUSIVE on its own.
    var metrics = ScreeningMetrics.demoClear
    metrics.pupillometry = nil
    let result = engine.evaluate(selfReport: .no, metrics: metrics)
    XCTAssertNotEqual(result.state, .inconclusive)
  }

  func testFounderPreviewScenariosMapExactly() {
    XCTAssertEqual(
      engine.evaluate(selfReport: .no, metrics: .demoClear, founderScenario: .signals).state,
      .signalsDetected
    )
    XCTAssertEqual(
      engine.evaluate(selfReport: .no, metrics: .demoClear, founderScenario: .inconclusive).state,
      .inconclusive
    )
    XCTAssertEqual(
      engine.evaluate(selfReport: .no, metrics: .demoClear, founderScenario: .noSignals).state,
      .noSignalsDetected
    )
  }

}
