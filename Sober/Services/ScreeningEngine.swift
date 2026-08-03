import Foundation

/// A deliberately transparent prototype scorer. It is not a validated medical model.
struct ScreeningEngine: Sendable {
  private let minimumQuality = 0.72
  private let signalThreshold = 0.58

  func evaluate(
    selfReport: SelfReport,
    metrics: ScreeningMetrics,
    founderScenario: FounderScenario = .live
  ) -> ScreeningOutcome {
    if founderScenario != .live {
      return previewOutcome(for: founderScenario)
    }

    let reactionRisk = normalized(metrics.reactionTimeMilliseconds, low: 320, high: 850)
    let missRisk = min(Double(metrics.reactionMisses) / 3.0, 1)
    let trackingRisk = normalized(metrics.trackingError, low: 0.16, high: 0.62)
    let timingRisk = normalized(metrics.timeEstimateError, low: 0.08, high: 0.45)
    let gazeRisk = normalized(metrics.gazeSmoothness, low: 0.14, high: 0.58)

    let riskScore =
      (reactionRisk * 0.27)
      + (missRisk * 0.18)
      + (trackingRisk * 0.25)
      + (timingRisk * 0.15)
      + (gazeRisk * 0.15)

    let details = details(
      reactionRisk: reactionRisk,
      trackingRisk: trackingRisk,
      timingRisk: timingRisk,
      gazeRisk: gazeRisk,
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

    guard metrics.completedAllTasks, metrics.qualityScore >= minimumQuality else {
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

  private func details(
    reactionRisk: Double,
    trackingRisk: Double,
    timingRisk: Double,
    gazeRisk: Double,
    metrics: ScreeningMetrics
  ) -> [SignalDetail] {
    [
      SignalDetail(
        id: "reaction",
        label: "Reaction",
        value: "\(Int(metrics.reactionTimeMilliseconds.rounded())) ms",
        concern: reactionRisk >= 0.55 || metrics.reactionMisses > 0
      ),
      SignalDetail(
        id: "tracking",
        label: "Motor tracking",
        value: "\(Int((1 - metrics.trackingError) * 100))% steady",
        concern: trackingRisk >= 0.55
      ),
      SignalDetail(
        id: "timing",
        label: "Time estimate",
        value: "\(Int(metrics.timeEstimateError * 100))% off",
        concern: timingRisk >= 0.55
      ),
      SignalDetail(
        id: "gaze",
        label: "Guided gaze",
        value: "\(Int((1 - metrics.gazeSmoothness) * 100))% smooth",
        concern: gazeRisk >= 0.55
      ),
    ]
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
        ]
      )
    }
  }
}
