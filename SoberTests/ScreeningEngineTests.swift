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

  func testConcerningLiveResultAlertsConfiguredParent() {
    let outcome = engine.evaluate(
      selfReport: .no,
      metrics: .demoClear,
      founderScenario: .signals
    )
    let plan = SafetyPlan(
      userName: "Alex",
      contactName: "Casey",
      contactPhone: "(512) 555-0147",
      automaticParentAlerts: true,
      parentAlertConsent: true
    )

    XCTAssertTrue(
      ParentAlertPolicy.shouldSend(outcome: outcome, safetyPlan: plan, isSample: false)
    )
  }

  func testParentAlertRequiresConsentAndIsNeverSentForSamples() {
    let outcome = engine.evaluate(
      selfReport: .no,
      metrics: .demoClear,
      founderScenario: .signals
    )
    let planWithoutConsent = SafetyPlan(
      automaticParentAlerts: true,
      parentAlertConsent: false
    )
    let configuredPlan = SafetyPlan(
      automaticParentAlerts: true,
      parentAlertConsent: true
    )

    XCTAssertFalse(
      ParentAlertPolicy.shouldSend(
        outcome: outcome,
        safetyPlan: planWithoutConsent,
        isSample: false
      )
    )
    XCTAssertFalse(
      ParentAlertPolicy.shouldSend(
        outcome: outcome,
        safetyPlan: configuredPlan,
        isSample: true
      )
    )
  }

  func testNoSignalsResultNeverAlertsParent() {
    let outcome = engine.evaluate(
      selfReport: .no,
      metrics: .demoClear,
      founderScenario: .noSignals
    )
    let plan = SafetyPlan(
      automaticParentAlerts: true,
      parentAlertConsent: true
    )

    XCTAssertFalse(
      ParentAlertPolicy.shouldSend(outcome: outcome, safetyPlan: plan, isSample: false)
    )
  }

  func testParentAlertPayloadSharesOnlySafetyMessage() {
    let outcome = engine.evaluate(
      selfReport: .no,
      metrics: .demoClear,
      founderScenario: .signals
    )
    let plan = SafetyPlan(
      userName: "Alex",
      contactName: "Casey",
      contactPhone: "(512) 555-0147",
      automaticParentAlerts: true,
      parentAlertConsent: true
    )

    let payload = ParentAlertRequest(outcome: outcome, safetyPlan: plan)

    XCTAssertEqual(payload.parentPhone, "5125550147")
    XCTAssertEqual(payload.result, ScreeningResultState.signalsDetected.rawValue)
    XCTAssertTrue(payload.message.contains("help arrange a safe ride"))
    XCTAssertFalse(payload.message.localizedCaseInsensitiveContains("quality"))
    XCTAssertFalse(payload.message.localizedCaseInsensitiveContains("camera"))
    XCTAssertFalse(payload.message.localizedCaseInsensitiveContains("BAC"))
  }
}
