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
