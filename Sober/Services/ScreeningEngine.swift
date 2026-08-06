import Foundation

/// A deliberately transparent prototype scorer. It is not a validated medical model.
struct ScreeningEngine: Sendable {
  static let minimumQuality = 0.72
  private let signalThreshold = 0.58

  func evaluate(
    selfReport: SelfReport,
    metrics: ScreeningMetrics,
    personalBaseline: PersonalBaseline? = nil,
    founderScenario: FounderScenario = .live
  ) -> ScreeningOutcome {
    if founderScenario != .live {
      return previewOutcome(for: founderScenario)
    }

    // A baseline that hasn't reached its required session count doesn't
    // back any metric yet — everything falls back to the population range
    // until it does.
    let baseline = personalBaseline?.isReady == true ? personalBaseline : nil

    let reactionRisk = risk(
      metrics.reactionTimeMilliseconds, populationLow: 320, populationHigh: 850,
      personalValues: baseline?.samples.map(\.reactionTimeMilliseconds), sdFloor: 40)
    let missRisk = risk(
      Double(metrics.reactionMisses), populationLow: 0, populationHigh: 3,
      personalValues: baseline?.samples.map { Double($0.reactionMisses) }, sdFloor: 0.5)
    let trackingRisk = metrics.trackingError.map {
      risk(
        $0, populationLow: 0.16, populationHigh: 0.62,
        personalValues: baseline?.samples.compactMap(\.trackingError), sdFloor: 0.05)
    }
    let timingRisk = risk(
      metrics.timeEstimateError, populationLow: 0.08, populationHigh: 0.45,
      personalValues: baseline?.samples.map(\.timeEstimateError), sdFloor: 0.05)
    let gazeRisk = metrics.gazeSmoothness.map {
      risk(
        $0, populationLow: 0.14, populationHigh: 0.58,
        personalValues: baseline?.samples.compactMap(\.gazeSmoothness), sdFloor: 0.05)
    }
    let baselineTrials = baseline?.samples.compactMap(\.pupillometry).flatMap(\.trials)
    let pupilRisk = pupilRisk(metrics.pupillometry, baselineTrials: baselineTrials)

    // A metric that wasn't captured contributes the conservative (highest
    // risk) value here, but never on its own decides the outcome — the
    // guard below refuses to score at all when a task wasn't measured.
    // Pupillometry is the one exception: it's a brand-new capture pathway
    // riding on a freshly trained model with real domain-gap risk, so it
    // contributes here but is deliberately kept out of that guard below —
    // see the comment there.
    let riskScore =
      (reactionRisk * 0.20)
      + (missRisk * 0.12)
      + ((trackingRisk ?? 1) * 0.18)
      + (timingRisk * 0.10)
      + ((gazeRisk ?? 1) * 0.15)
      + ((pupilRisk ?? 1) * 0.25)

    let details = details(
      reactionRisk: reactionRisk,
      trackingRisk: trackingRisk,
      timingRisk: timingRisk,
      gazeRisk: gazeRisk,
      pupilRisk: pupilRisk,
      metrics: metrics
    )

    // Self-report is a hard safety gate. A reported use can never produce
    // NO_SIGNALS_DETECTED, regardless of task performance.
    if selfReport == .yes {
      return ScreeningOutcome(
        state: .signalsDetected,
        qualityScore: metrics.qualityScore,
        riskScore: max(riskScore, signalThreshold),
        details: details
      )
    }

    if selfReport == .unsure {
      return ScreeningOutcome(
        state: .inconclusive,
        qualityScore: metrics.qualityScore,
        riskScore: riskScore,
        details: details
      )
    }

    // Deliberately does not require metrics.pupillometry != nil here.
    // Hard-gating every check to INCONCLUSIVE whenever the pupil capture
    // pathway misses would make the app unusable if the model
    // underperforms in the field — the likely case for a model trained in
    // days on public data. It still runs, still scores, still gets
    // baselined; it just isn't allowed to unilaterally block a result the
    // way these already-proven tasks can.
    guard
      metrics.completedAllTasks,
      metrics.qualityScore >= Self.minimumQuality,
      metrics.trackingError != nil,
      metrics.gazeSmoothness != nil
    else {
      return ScreeningOutcome(
        state: .inconclusive,
        qualityScore: metrics.qualityScore,
        riskScore: riskScore,
        details: details
      )
    }

    return ScreeningOutcome(
      state: riskScore >= signalThreshold ? .signalsDetected : .noSignalsDetected,
      qualityScore: metrics.qualityScore,
      riskScore: riskScore,
      details: details
    )
  }

  private func normalized(_ value: Double, low: Double, high: Double) -> Double {
    min(max((value - low) / (high - low), 0), 1)
  }

  /// Scores a metric against the person's own baseline when at least two
  /// personal samples exist for it — 0 at or below their mean, ramping to
  /// 1 at three of their own standard deviations above it. `sdFloor`
  /// guards against a near-zero personal spread producing a runaway
  /// z-score; it's a numerical safeguard, not a threshold that decides
  /// anything on its own. Falls back to the fixed population range when
  /// there's no usable personal baseline for this metric yet.
  private func risk(
    _ value: Double,
    populationLow: Double,
    populationHigh: Double,
    personalValues: [Double]?,
    sdFloor: Double
  ) -> Double {
    guard let personalValues, personalValues.count >= 2 else {
      return normalized(value, low: populationLow, high: populationHigh)
    }
    let mean = personalValues.reduce(0, +) / Double(personalValues.count)
    let variance =
      personalValues.reduce(0) { $0 + pow($1 - mean, 2) } / Double(personalValues.count - 1)
    let standardDeviation = max(variance.squareRoot(), sdFloor)
    let z = (value - mean) / standardDeviation
    return min(max(z / 3.0, 0), 1)
  }

  /// Folds a pupillometry session into one composite risk value: each
  /// trial's four PLR sub-metrics (latency, peak constriction velocity,
  /// amplitude, recovery time) are individually scored through the same
  /// `risk()` helper — population fallback ranges when no personal
  /// baseline exists, personal z-score once one does — then averaged, and
  /// trials are averaged together. The population ranges here are rough
  /// literature-informed starting points, not calibrated clinical
  /// constants, same spirit as every other range in this file.
  private func pupilRisk(_ sample: PupillometrySample?, baselineTrials: [PupilLightReflexTrial]?)
    -> Double?
  {
    guard let sample, !sample.trials.isEmpty else { return nil }
    let trialRisks = sample.trials.map { trialRisk($0, baselineTrials: baselineTrials) }
    return trialRisks.reduce(0, +) / Double(trialRisks.count)
  }

  private func trialRisk(_ trial: PupilLightReflexTrial, baselineTrials: [PupilLightReflexTrial]?)
    -> Double
  {
    let latencyRisk = risk(
      trial.latencySeconds, populationLow: 0.18, populationHigh: 0.5,
      personalValues: baselineTrials?.map(\.latencySeconds), sdFloor: 0.03)

    // Velocity and amplitude are "lower is worse," the opposite direction
    // risk()/normalized() assume — negating both the value and the range
    // flips the comparison without duplicating the underlying math.
    let velocityRisk = risk(
      -trial.peakConstrictionVelocityMmPerSecond, populationLow: -5, populationHigh: -1,
      personalValues: baselineTrials?.map { -$0.peakConstrictionVelocityMmPerSecond }, sdFloor: 0.3)
    let amplitudeRisk = risk(
      -trial.amplitudePercent, populationLow: -0.35, populationHigh: -0.10,
      personalValues: baselineTrials?.map { -$0.amplitudePercent }, sdFloor: 0.03)

    // A trial that never recovered to 75% of baseline within the capture
    // window is scored as slower than the worst end of the recovery
    // range — that failure to recover is itself the observation, not a
    // fabricated estimate standing in for one.
    let recoverySeconds = trial.recoveryTo75PercentSeconds ?? 6.0
    let recoveryRisk = risk(
      recoverySeconds, populationLow: 1.5, populationHigh: 4.5,
      personalValues: baselineTrials?.compactMap(\.recoveryTo75PercentSeconds), sdFloor: 0.2)

    return (latencyRisk + velocityRisk + amplitudeRisk + recoveryRisk) / 4
  }

  private func details(
    reactionRisk: Double,
    trackingRisk: Double?,
    timingRisk: Double,
    gazeRisk: Double?,
    pupilRisk: Double?,
    metrics: ScreeningMetrics
  ) -> [SignalDetail] {
    [
      SignalDetail(
        id: "reaction",
        label: "Reaction",
        value: "\(Int(metrics.reactionTimeMilliseconds.rounded())) ms",
        concern: reactionRisk >= 0.55 || metrics.reactionMisses > 0,
        risk: reactionRisk
      ),
      trackingDetail(risk: trackingRisk, error: metrics.trackingError),
      SignalDetail(
        id: "timing",
        label: "Time estimate",
        value: "\(Int(metrics.timeEstimateError * 100))% off",
        concern: timingRisk >= 0.55,
        risk: timingRisk
      ),
      gazeDetail(risk: gazeRisk, smoothness: metrics.gazeSmoothness),
      pupilDetail(risk: pupilRisk, sample: metrics.pupillometry),
    ]
  }

  /// Never prints a percentage for a task that didn't run.
  private func pupilDetail(risk: Double?, sample: PupillometrySample?) -> SignalDetail {
    guard let risk, let sample, !sample.trials.isEmpty else {
      return SignalDetail(id: "pupil", label: "Light reflex", value: "Not measured", concern: true)
    }
    let averageAmplitude =
      sample.trials.map(\.amplitudePercent).reduce(0, +) / Double(sample.trials.count)
    return SignalDetail(
      id: "pupil",
      label: "Light reflex",
      value: "\(Int(averageAmplitude * 100))% reactive",
      concern: risk >= 0.55,
      risk: risk
    )
  }

  /// Never prints a percentage for a task that didn't run.
  private func trackingDetail(risk: Double?, error: Double?) -> SignalDetail {
    guard let risk, let error else {
      return SignalDetail(id: "tracking", label: "Motor tracking", value: "Not measured", concern: true)
    }
    return SignalDetail(
      id: "tracking",
      label: "Motor tracking",
      value: "\(Int((1 - error) * 100))% steady",
      concern: risk >= 0.55,
      risk: risk
    )
  }

  /// Never prints a percentage for a task that didn't run.
  private func gazeDetail(risk: Double?, smoothness: Double?) -> SignalDetail {
    guard let risk, let smoothness else {
      return SignalDetail(id: "gaze", label: "Guided gaze", value: "Not measured", concern: true)
    }
    return SignalDetail(
      id: "gaze",
      label: "Guided gaze",
      value: "\(Int((1 - smoothness) * 100))% smooth",
      concern: risk >= 0.55,
      risk: risk
    )
  }

  private func previewOutcome(for scenario: FounderScenario) -> ScreeningOutcome {
    switch scenario {
    case .live:
      evaluate(selfReport: .no, metrics: .demoClear)
    case .signals:
      ScreeningOutcome(
        state: .signalsDetected,
        qualityScore: 0.91,
        riskScore: 0.76,
        details: [
          SignalDetail(id: "reaction", label: "Reaction", value: "742 ms", concern: true),
          SignalDetail(id: "tracking", label: "Motor tracking", value: "49% steady", concern: true),
          SignalDetail(id: "timing", label: "Time estimate", value: "31% off", concern: false),
          SignalDetail(id: "gaze", label: "Guided gaze", value: "58% smooth", concern: true),
          SignalDetail(id: "pupil", label: "Light reflex", value: "12% reactive", concern: true),
        ]
      )
    case .inconclusive:
      ScreeningOutcome(
        state: .inconclusive,
        qualityScore: 0.48,
        riskScore: 0.37,
        details: [
          SignalDetail(id: "reaction", label: "Reaction", value: "2 missed", concern: true),
          SignalDetail(
            id: "tracking", label: "Motor tracking", value: "Interrupted", concern: true),
          SignalDetail(id: "timing", label: "Time estimate", value: "Completed", concern: false),
          SignalDetail(id: "gaze", label: "Guided gaze", value: "Low light", concern: true),
          SignalDetail(id: "pupil", label: "Light reflex", value: "Not measured", concern: true),
        ]
      )
    case .noSignals:
      ScreeningOutcome(
        state: .noSignalsDetected,
        qualityScore: 0.94,
        riskScore: 0.18,
        details: [
          SignalDetail(id: "reaction", label: "Reaction", value: "318 ms", concern: false),
          SignalDetail(
            id: "tracking", label: "Motor tracking", value: "82% steady", concern: false),
          SignalDetail(id: "timing", label: "Time estimate", value: "8% off", concern: false),
          SignalDetail(id: "gaze", label: "Guided gaze", value: "84% smooth", concern: false),
          SignalDetail(id: "pupil", label: "Light reflex", value: "27% reactive", concern: false),
        ]
      )
    }
  }
}
