import XCTest

@testable import Sober

/// The reaction task's summary, and the two defects that made it lossy.
///
/// Per-trial data was always captured and persisted. It was collapsed into a
/// mean and a single error total at the point of capture, so nothing
/// downstream could use it.
final class ReactionMetricsTests: XCTestCase {

  /// `isCorrect` is derived from `expected == selected`, so a wrong choice is
  /// built by selecting a different symbol rather than by setting a flag.
  private func trial(
    latency: Double,
    correct: Bool = true,
    miss: Bool = false,
    anticipation: Bool = false
  ) -> ChoiceReactionTrial {
    ChoiceReactionTrial(
      expected: anticipation ? nil : .blueCircle,
      selected: miss ? nil : (correct ? .blueCircle : .pinkDiamond),
      latencyMilliseconds: (miss || anticipation) ? nil : latency,
      wasAnticipation: anticipation,
      wasMiss: miss
    )
  }

  // MARK: - Median

  /// The defect: one lapse used to redefine the session. Four trials near
  /// 300 ms and a single 2,000 ms lapse put the mean above every typical
  /// trial, which is the opposite of summarising them.
  func testOneSlowTrialMovesTheMeanButNotTheMedian() {
    let summary = ChoiceReactionSummary(trials: [
      trial(latency: 300), trial(latency: 310), trial(latency: 290),
      trial(latency: 305), trial(latency: 2_000),
    ])

    XCTAssertEqual(summary.medianMilliseconds, 305, accuracy: 0.001)
    XCTAssertGreaterThan(summary.averageMilliseconds, 600)
  }

  func testMedianOfAnEvenCountAveragesTheMiddleTwo() {
    let summary = ChoiceReactionSummary(trials: [
      trial(latency: 200), trial(latency: 300),
      trial(latency: 400), trial(latency: 500),
    ])

    XCTAssertEqual(summary.medianMilliseconds, 350, accuracy: 0.001)
  }

  func testMedianIgnoresIncorrectTrials() {
    let summary = ChoiceReactionSummary(trials: [
      trial(latency: 300), trial(latency: 320),
      trial(latency: 50, correct: false),
    ])

    XCTAssertEqual(summary.medianMilliseconds, 310, accuracy: 0.001)
  }

  func testASingleTrialIsItsOwnMedian() {
    XCTAssertEqual(
      ChoiceReactionSummary(trials: [trial(latency: 412)]).medianMilliseconds,
      412,
      accuracy: 0.001)
  }

  /// A session with no correct trials cannot report a latency. It falls back
  /// to the same stand-in the mean uses, and `completedAllTasks` rejects it
  /// before it reaches a baseline.
  func testNoCorrectTrialsFallsBackRatherThanDividingByZero() {
    let summary = ChoiceReactionSummary(trials: [
      trial(latency: 0, correct: false, miss: true)
    ])

    XCTAssertEqual(summary.medianMilliseconds, 1_500, accuracy: 0.001)
    XCTAssertEqual(summary.medianMilliseconds, summary.averageMilliseconds, accuracy: 0.001)
  }

  // MARK: - The error breakdown

  /// A wrong choice, a premature response and a non-response are three
  /// behaviours. `totalErrors` is their sum and stays the sum — but the parts
  /// have to survive alongside it.
  func testTheThreeErrorKindsStaySeparableFromTheirTotal() {
    let summary = ChoiceReactionSummary(trials: [
      trial(latency: 300),
      trial(latency: 280, correct: false),
      trial(latency: 40, correct: false, anticipation: true),
      trial(latency: 0, correct: false, miss: true),
      trial(latency: 0, correct: false, miss: true),
    ])

    XCTAssertEqual(summary.incorrectChoices, 1)
    XCTAssertEqual(summary.anticipations, 1)
    XCTAssertEqual(summary.misses, 2)
    XCTAssertEqual(summary.totalErrors, 4)
  }

  func testAPerfectSessionReportsNoErrorsOfAnyKind() {
    let summary = ChoiceReactionSummary(trials: [
      trial(latency: 300), trial(latency: 310), trial(latency: 295),
    ])

    XCTAssertEqual(summary.totalErrors, 0)
    XCTAssertEqual(summary.incorrectChoices, 0)
    XCTAssertEqual(summary.anticipations, 0)
    XCTAssertEqual(summary.misses, 0)
  }

  // MARK: - Persistence

  func testTheBreakdownSurvivesAnEncodeDecodeRound() throws {
    let metrics = ScreeningMetrics(
      reactionTimeMilliseconds: 680,
      reactionMisses: 4,
      reactionMedianMilliseconds: 305,
      reactionIncorrectChoices: 1,
      reactionAnticipations: 1,
      reactionMissedResponses: 2,
      reactionVariabilityMilliseconds: 42.5,
      reactionTrialCount: 5,
      trackingError: 0.2,
      timeEstimateError: 0.1,
      gazeSmoothness: 0.15,
      qualityScore: 0.9,
      completedAllTasks: true
    )

    let data = try JSONEncoder().encode(ResearchScreeningMetrics(metrics))
    let decoded = try JSONDecoder().decode(ResearchScreeningMetrics.self, from: data)

    XCTAssertEqual(decoded.reactionTimeMilliseconds, 680, accuracy: 0.001)
    XCTAssertEqual(decoded.reactionMedianMilliseconds ?? 0, 305, accuracy: 0.001)
    XCTAssertEqual(decoded.reactionIncorrectChoices, 1)
    XCTAssertEqual(decoded.reactionAnticipations, 1)
    XCTAssertEqual(decoded.reactionMissedResponses, 2)
    XCTAssertEqual(decoded.reactionTrialCount, 5)
    XCTAssertEqual(decoded.reactionVariabilityMilliseconds ?? 0, 42.5, accuracy: 0.001)
    XCTAssertEqual(decoded.screeningMetrics.reactionIncorrectChoices, 1)
  }

  /// A session stored before the breakdown existed does not know its error
  /// kinds. It must decode as unknown, not as zero of each — zero is a claim.
  func testASessionWrittenBeforeTheBreakdownDecodesAsUnknownNotZero() throws {
    let json = Data(
      """
      {
        "reactionTimeMilliseconds": 318,
        "reactionMisses": 2,
        "reactionWasMeasured": true,
        "trackingError": 0.18,
        "timeEstimateError": 0.08,
        "timingWasMeasured": true,
        "gazeSmoothness": 0.16,
        "qualityScore": 0.94,
        "completedAllTasks": true
      }
      """.utf8)

    let decoded = try JSONDecoder().decode(ResearchScreeningMetrics.self, from: json)

    XCTAssertEqual(decoded.reactionMisses, 2)
    XCTAssertNil(decoded.reactionMedianMilliseconds)
    XCTAssertNil(decoded.reactionIncorrectChoices)
    XCTAssertNil(decoded.reactionAnticipations)
    XCTAssertNil(decoded.reactionMissedResponses)
    XCTAssertNil(decoded.reactionTrialCount)
    XCTAssertNil(decoded.reactionVariabilityMilliseconds)
  }

  /// Recording the median must not retire existing baselines. Scoring still
  /// uses the mean, and the schema is unchanged, so every session recorded
  /// before this keeps counting — `ReviewRegressionTests` guards the same.
  func testRecordingTheMedianLeavesTheSchemaAndScoringInputAlone() {
    XCTAssertEqual(ResearchSessionEnvelope.currentSchemaVersion, 1)
  }
}
