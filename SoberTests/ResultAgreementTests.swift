import XCTest

@testable import Sober

/// The headline and the rows under it have to tell the same story.
///
/// The composite could stay under the threshold while half the measured rows
/// were orange, so "No changes detected" sat above two "Outside usual range"
/// rows. These pin the rule that closes that gap, and that it only ever moves
/// a result towards caution.
final class ResultAgreementTests: XCTestCase {

  private let engine = ScreeningEngine()

  private func metrics(
    reactionMs: Double = 300,
    misses: Int = 0,
    tracking: Double? = 0.16,
    timing: Double = 0.08,
    gaze: Double? = 0.14,
    quality: Double = 0.94
  ) -> ScreeningMetrics {
    ScreeningMetrics(
      reactionTimeMilliseconds: reactionMs,
      reactionMisses: misses,
      trackingError: tracking,
      timeEstimateError: timing,
      gazeSmoothness: gaze,
      qualityScore: quality,
      completedAllTasks: true
    )
  }

  private func movedCount(_ outcome: ScreeningOutcome) -> Int {
    outcome.details.filter { $0.wasMeasured && $0.concern }.count
  }

  /// The case from the demo recording: reaction errors and a far-off time
  /// estimate, averaged against two ordinary measures.
  func testHalfTheMeasuresOutOfRangeSaysChangesWereDetected() {
    let outcome = engine.evaluate(
      selfReport: .no, metrics: metrics(misses: 3, timing: 0.40))

    XCTAssertLessThan(
      outcome.riskScore, 0.58,
      "precondition: the composite alone would have said no changes")
    XCTAssertEqual(movedCount(outcome), 2)
    XCTAssertEqual(outcome.details.filter(\.wasMeasured).count, 4)
    XCTAssertEqual(outcome.state, .signalsDetected)
  }

  /// Without the eye task there are three measures, so two moved is most.
  func testTwoOfThreeWithoutTheEyeTaskSaysChangesWereDetected() {
    let outcome = engine.evaluate(
      selfReport: .no,
      metrics: metrics(misses: 3, timing: 0.40, gaze: nil, quality: 0),
      protocolVariant: .noCamera)

    XCTAssertEqual(outcome.details.filter(\.wasMeasured).count, 3)
    XCTAssertEqual(movedCount(outcome), 2)
    XCTAssertEqual(outcome.state, .signalsDetected)
  }

  /// A single moved measure is not enough on its own. The result screen
  /// explains that beside the rows instead of hiding the orange one.
  func testOneMeasureOutOfRangeCanStillBeQuiet() {
    let outcome = engine.evaluate(selfReport: .no, metrics: metrics(misses: 1))

    XCTAssertEqual(movedCount(outcome), 1)
    XCTAssertEqual(outcome.state, .noSignalsDetected)
  }

  func testNothingOutOfRangeStaysQuiet() {
    let outcome = engine.evaluate(selfReport: .no, metrics: .demoClear)

    XCTAssertEqual(movedCount(outcome), 0)
    XCTAssertEqual(outcome.state, .noSignalsDetected)
  }

  /// Errors flag the reaction row by themselves, so the value has to show
  /// them. An orange "294 ms" alone reads as a normal time marked wrong.
  func testReactionValueShowsTheErrorsThatFlagIt() {
    func reactionValue(misses: Int) -> String? {
      engine.evaluate(selfReport: .no, metrics: metrics(reactionMs: 294, misses: misses))
        .details.first { $0.id == "reaction" }?.value
    }

    XCTAssertEqual(reactionValue(misses: 0), "294 ms")
    XCTAssertEqual(reactionValue(misses: 1), "294 ms · 1 error")
    XCTAssertEqual(reactionValue(misses: 3), "294 ms · 3 errors")
  }
}
