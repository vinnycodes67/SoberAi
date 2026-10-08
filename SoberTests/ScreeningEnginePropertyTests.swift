import XCTest

@testable import Sober

/// Randomized checks on the product's safety rules for a screening result.
///
/// The example tests pin particular numbers. These run thousands of seeded
/// random metric sets through `ScreeningEngine.evaluate` on every protocol
/// variant and check what must hold for all of them: a reported use is never
/// overruled, a poor capture never reads as clear, "No changes detected" never
/// sits above a mostly orange table, and a worse performance never reads as a
/// better one. The seed is fixed, so a failure reproduces exactly; every
/// message carries the case index and the metrics that broke it.
final class ScreeningEnginePropertyTests: XCTestCase {

  private let engine = ScreeningEngine()
  private let casesPerProperty = 5_000
  private let signalThreshold = 0.58

  // MARK: - Self-report

  /// Self-report is a hard gate. Someone who says they used something is
  /// told changes were detected whatever the tasks showed, and "unsure" never
  /// gets a measured verdict either way.
  func testSelfReportGatesTheOutcome() {
    var rng = SplitMix64(seed: 0xC0DE_0001)
    var failures = 0
    for index in 0..<casesPerProperty {
      let variant = OcularProtocolVariant.allCases.randomElement(using: &rng)!
      let metrics = randomMetrics(&rng, variant: variant)
      let baseline = rng.chance(0.3) ? randomReadyBaseline(&rng) : nil

      let yes = engine.evaluate(
        selfReport: .yes, metrics: metrics, personalBaseline: baseline, protocolVariant: variant)
      let unsure = engine.evaluate(
        selfReport: .unsure, metrics: metrics, personalBaseline: baseline, protocolVariant: variant)

      var problems: [String] = []
      if yes.state != .signalsDetected { problems.append("yes gave \(yes.state)") }
      if yes.reason != .reportedUse { problems.append("yes gave reason \(yes.reason)") }
      if !(yes.riskScore >= signalThreshold) { problems.append("yes gave risk \(yes.riskScore)") }
      if unsure.state != .inconclusive { problems.append("unsure gave \(unsure.state)") }
      if !problems.isEmpty {
        failures += 1
        if failures <= 5 { XCTFail("case \(index) \(variant) \(metrics): \(problems)") }
      }
    }
  }

  // MARK: - Headline agrees with the rows

  /// "No changes detected" is only allowed when the composite is under the
  /// signal threshold and fewer than half of the measured rows are orange.
  /// Anything else puts a reassuring headline above a table that disagrees.
  func testNoChangesDetectedNeverSitsAboveAMostlyFlaggedTable() {
    var rng = SplitMix64(seed: 0xC0DE_0002)
    var failures = 0
    var quiet = 0
    for index in 0..<casesPerProperty {
      let variant = OcularProtocolVariant.allCases.randomElement(using: &rng)!
      let metrics = randomMetrics(&rng, variant: variant)
      let baseline = rng.chance(0.3) ? randomReadyBaseline(&rng) : nil
      let outcome = engine.evaluate(
        selfReport: .no, metrics: metrics, personalBaseline: baseline, protocolVariant: variant)
      guard outcome.state == .noSignalsDetected else { continue }
      quiet += 1

      let measured = outcome.details.filter(\.wasMeasured)
      let flagged = measured.filter(\.concern).count
      if !(flagged * 2 < measured.count) || !(outcome.riskScore < signalThreshold) {
        failures += 1
        if failures <= 5 {
          XCTFail(
            "case \(index) \(variant) \(metrics): no changes with \(flagged)/\(measured.count)"
              + " flagged, risk \(outcome.riskScore)")
        }
      }
    }
    // Otherwise the property holds vacuously.
    XCTAssertGreaterThan(quiet, casesPerProperty / 10)
  }

  // MARK: - Capture quality

  /// An unfinished check, or a camera capture below the quality floor, can
  /// only ever be inconclusive or cautious. It must never read as clear.
  func testAnIncompleteOrPoorCaptureIsNeverClear() {
    var rng = SplitMix64(seed: 0xC0DE_0003)
    var failures = 0
    for index in 0..<casesPerProperty {
      let variant = OcularProtocolVariant.allCases.randomElement(using: &rng)!
      var metrics = randomMetrics(&rng, variant: variant)
      // Start from something that would otherwise often be clear.
      metrics.completedAllTasks = true
      if variant == .noCamera || rng.chance(0.5) {
        metrics.completedAllTasks = false
      } else {
        metrics.qualityScore = Double.random(
          in: 0..<ScreeningEngine.minimumQuality, using: &rng)
      }
      let baseline = rng.chance(0.3) ? randomReadyBaseline(&rng) : nil

      for report in SelfReport.allCases {
        let outcome = engine.evaluate(
          selfReport: report, metrics: metrics, personalBaseline: baseline,
          protocolVariant: variant)
        if outcome.state == .noSignalsDetected {
          failures += 1
          if failures <= 5 { XCTFail("case \(index) \(variant) \(report) \(metrics): clear") }
        }
      }
    }
  }

  // MARK: - Monotonicity

  /// Doing worse on any one task must never make the result look better.
  ///
  /// Every measure is scored by `risk()`, which rises with the value for all
  /// of them, so "worse" is higher in each case: a slower reaction, more
  /// errors, more tracking error, more timing error, and a higher gaze value
  /// (it is a jerkiness score; the row shows `1 - value` as "% smooth"). The
  /// state may only move from no changes to changes, the risk may not fall,
  /// and no row may lose its flag.
  func testAWorseMeasureNeverImprovesTheResultAgainstPopulationRanges() {
    checkMonotonicity(seed: 0xC0DE_0004, withBaseline: false)
  }

  /// The same, scored against a ready personal baseline, where each measure
  /// becomes a z-score against the person's own sessions. Still increasing in
  /// the value, so the same rule holds.
  func testAWorseMeasureNeverImprovesTheResultAgainstAPersonalBaseline() {
    checkMonotonicity(seed: 0xC0DE_0005, withBaseline: true)
  }

  private func checkMonotonicity(seed: UInt64, withBaseline: Bool) {
    var rng = SplitMix64(seed: seed)
    var failures = 0
    var flips = 0
    for index in 0..<casesPerProperty {
      let variant = OcularProtocolVariant.allCases.randomElement(using: &rng)!
      let report = SelfReport.allCases.randomElement(using: &rng)!
      let metrics = randomMetrics(&rng, variant: variant)
      let baseline = withBaseline ? randomReadyBaseline(&rng) : nil
      let (worse, change) = worsenOneMeasure(metrics, &rng)

      let before = engine.evaluate(
        selfReport: report, metrics: metrics, personalBaseline: baseline,
        protocolVariant: variant)
      let after = engine.evaluate(
        selfReport: report, metrics: worse, personalBaseline: baseline,
        protocolVariant: variant)

      var problems: [String] = []
      if before.state != after.state {
        if before.state == .noSignalsDetected, after.state == .signalsDetected {
          flips += 1
        } else {
          problems.append("state \(before.state) -> \(after.state)")
        }
      }
      if after.riskScore < before.riskScore {
        problems.append("risk \(before.riskScore) -> \(after.riskScore)")
      }
      for (old, new) in zip(before.details, after.details) where old.concern && !new.concern {
        problems.append("\(old.id) lost its flag")
      }
      if !problems.isEmpty {
        failures += 1
        if failures <= 5 {
          XCTFail(
            "case \(index) \(variant) \(report) \(change) on \(metrics)"
              + " baseline \(String(describing: baseline)): \(problems)")
        }
      }
    }
    // Some worsening should actually tip a result, or the check is idle.
    XCTAssertGreaterThan(flips, 0)
  }

  // MARK: - Build and protocol scope

  /// Pupillometry is an unvalidated internal experiment. The public build,
  /// which this scheme compiles, must never show its row, even when a sample
  /// is present in the metrics.
  func testThePublicBuildNeverShowsAPupilRow() {
    XCTAssertFalse(BuildChannel.allowsInternalTools, "SoberTests should run the public build")
    var rng = SplitMix64(seed: 0xC0DE_0006)
    var failures = 0
    for index in 0..<casesPerProperty {
      let variant = OcularProtocolVariant.allCases.randomElement(using: &rng)!
      var metrics = randomMetrics(&rng, variant: variant)
      metrics.pupillometry = randomPupilSample(&rng)
      let baseline = rng.chance(0.3) ? randomReadyBaseline(&rng) : nil
      for report in SelfReport.allCases {
        let outcome = engine.evaluate(
          selfReport: report, metrics: metrics, personalBaseline: baseline,
          protocolVariant: variant)
        if outcome.details.contains(where: { $0.id == "pupil" }) {
          failures += 1
          if failures <= 5 { XCTFail("case \(index) \(variant) \(report): pupil row shown") }
        }
      }
    }
  }

  /// Without a TrueDepth camera the eye task never runs, so its row can never
  /// claim a measurement, whatever stale value the metrics carry.
  func testNoCameraNeverMeasuresGaze() {
    var rng = SplitMix64(seed: 0xC0DE_0007)
    var failures = 0
    for index in 0..<casesPerProperty {
      var metrics = randomMetrics(&rng, variant: .noCamera)
      if rng.chance(0.5) { metrics.gazeSmoothness = Double.random(in: 0...1, using: &rng) }
      let baseline = rng.chance(0.3) ? randomReadyBaseline(&rng) : nil
      for report in SelfReport.allCases {
        let outcome = engine.evaluate(
          selfReport: report, metrics: metrics, personalBaseline: baseline,
          protocolVariant: .noCamera)
        let gaze = outcome.details.first { $0.id == "gaze" }
        if gaze == nil || gaze?.wasMeasured == true || outcome.measuredCapture {
          failures += 1
          if failures <= 5 {
            XCTFail("case \(index) \(report) \(metrics): gaze \(String(describing: gaze))")
          }
        }
      }
    }
  }

  // MARK: - Generators

  /// Half the cases sit in a typical sober range so clear results are common;
  /// the rest spread wide. Captures are mostly complete and good, but missing
  /// tasks and weak quality appear often enough to exercise every gate.
  private func randomMetrics(
    _ rng: inout SplitMix64, variant: OcularProtocolVariant
  ) -> ScreeningMetrics {
    let typical = rng.chance(0.5)
    func value(_ typicalRange: ClosedRange<Double>, _ wideRange: ClosedRange<Double>) -> Double {
      Double.random(in: typical ? typicalRange : wideRange, using: &rng)
    }
    let reaction = value(250...520, 150...1_500)
    let misses = typical ? (rng.chance(0.8) ? 0 : 1) : Int.random(in: 0...6, using: &rng)
    let tracking: Double? = rng.chance(0.1) ? nil : value(0.08...0.35, 0...1)
    let timing = value(0.02...0.22, 0...0.9)
    let gaze: Double? =
      variant == .noCamera && rng.chance(0.7)
      ? nil : (rng.chance(0.1) ? nil : value(0.06...0.32, 0...1))
    var metrics = ScreeningMetrics(
      reactionTimeMilliseconds: reaction,
      reactionMisses: misses,
      trackingError: tracking,
      timeEstimateError: timing,
      gazeSmoothness: gaze,
      qualityScore: rng.chance(0.85)
        ? Double.random(in: ScreeningEngine.minimumQuality...1, using: &rng)
        : Double.random(in: 0...1, using: &rng),
      completedAllTasks: rng.chance(0.9)
    )
    metrics.reactionWasMeasured = rng.chance(0.95)
    metrics.timingWasMeasured = rng.chance(0.95)
    if rng.chance(0.2) { metrics.pupillometry = randomPupilSample(&rng) }
    return metrics
  }

  /// Raises exactly one measure that the metrics actually carry.
  private func worsenOneMeasure(
    _ metrics: ScreeningMetrics, _ rng: inout SplitMix64
  ) -> (ScreeningMetrics, String) {
    var worse = metrics
    var options = ["reaction", "misses", "timing"]
    if metrics.trackingError != nil { options.append("tracking") }
    if metrics.gazeSmoothness != nil { options.append("gaze") }
    let choice = options.randomElement(using: &rng)!
    switch choice {
    case "reaction":
      worse.reactionTimeMilliseconds += Double.random(in: 1...400, using: &rng)
    case "misses":
      worse.reactionMisses += Int.random(in: 1...3, using: &rng)
    case "timing":
      worse.timeEstimateError += Double.random(in: 0.005...0.3, using: &rng)
    case "tracking":
      worse.trackingError! += Double.random(in: 0.005...0.3, using: &rng)
    default:
      worse.gazeSmoothness! += Double.random(in: 0.005...0.3, using: &rng)
    }
    return (worse, "worse \(choice)")
  }

  /// Three sober sessions, the scoring window, so the baseline is ready.
  /// Tracking and gaze are sometimes skipped to exercise the per-metric
  /// fallback to population ranges.
  private func randomReadyBaseline(_ rng: inout SplitMix64) -> PersonalBaseline {
    var baseline = PersonalBaseline()
    let skipTracking = rng.chance(0.15)
    let skipGaze = rng.chance(0.15)
    for _ in 0..<PersonalBaseline.requiredSessions {
      baseline.record(
        BaselineSample(
          reactionTimeMilliseconds: Double.random(in: 220...480, using: &rng),
          reactionMisses: rng.chance(0.8) ? 0 : 1,
          trackingError: skipTracking ? nil : Double.random(in: 0.06...0.3, using: &rng),
          timeEstimateError: Double.random(in: 0.02...0.2, using: &rng),
          gazeSmoothness: skipGaze ? nil : Double.random(in: 0.05...0.3, using: &rng)
        ))
    }
    precondition(baseline.isReady)
    return baseline
  }

  private func randomPupilSample(_ rng: inout SplitMix64) -> PupillometrySample {
    let trials = (0..<Int.random(in: 1...3, using: &rng)).map { _ in
      PupilLightReflexTrial(
        baselineDiameterMm: Double.random(in: 3...7, using: &rng),
        minDiameterMm: Double.random(in: 2...5, using: &rng),
        latencySeconds: Double.random(in: 0.1...0.7, using: &rng),
        peakConstrictionVelocityMmPerSecond: Double.random(in: 0.5...6, using: &rng),
        amplitudePercent: Double.random(in: 0.02...0.4, using: &rng),
        recoveryTo75PercentSeconds: rng.chance(0.2) ? nil : Double.random(in: 1...6, using: &rng)
      )
    }
    return PupillometrySample(trials: trials, qualityScore: Double.random(in: 0...1, using: &rng))
  }
}

/// SplitMix64: tiny, fast, and fully deterministic for a given seed, so every
/// run of these tests sees the same cases.
private struct SplitMix64: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  mutating func chance(_ probability: Double) -> Bool {
    Double.random(in: 0..<1, using: &self) < probability
  }
}
