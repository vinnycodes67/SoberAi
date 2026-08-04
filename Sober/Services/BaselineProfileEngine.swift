import Foundation

struct RobustBaselineStatistic: Codable, Equatable, Sendable {
  let median: Double
  /// Raw median absolute deviation (MAD), without the 1.4826 normality scale.
  let medianAbsoluteDeviation: Double
}

struct BaselineMetricsSummary: Codable, Equatable, Sendable {
  let reactionTimeMilliseconds: RobustBaselineStatistic
  let reactionMisses: RobustBaselineStatistic
  let trackingError: RobustBaselineStatistic
  let timeEstimateError: RobustBaselineStatistic
  let gazeSmoothness: RobustBaselineStatistic
  let qualityScore: RobustBaselineStatistic
}

struct BaselineProfileSummary: Codable, Equatable, Sendable {
  let participantID: PseudonymousParticipantID
  let candidateSessionCount: Int
  let eligibleSessionCount: Int
  let excludedSessionCount: Int
  let minimumRequiredSessions: Int
  let minimumQuality: Double
  let metrics: BaselineMetricsSummary?

  var isReady: Bool {
    eligibleSessionCount >= minimumRequiredSessions
  }
}

/// Produces a robust within-person sober baseline. It intentionally ignores
/// screening checks and controlled-research sessions so exposed observations
/// can never drift the participant's reference profile.
struct BaselineProfileEngine: Sendable {
  let minimumQuality: Double
  let minimumRequiredSessions: Int

  init(minimumQuality: Double = 0.72, minimumRequiredSessions: Int = 5) {
    precondition((0...1).contains(minimumQuality))
    precondition(minimumRequiredSessions > 0)
    self.minimumQuality = minimumQuality
    self.minimumRequiredSessions = minimumRequiredSessions
  }

  func summarize(
    participantID: PseudonymousParticipantID,
    sessions: [ResearchSessionEnvelope],
    protocolVariant: OcularProtocolVariant = .full
  ) -> BaselineProfileSummary {
    let candidates = sessions.filter {
      $0.participantID == participantID
        && $0.context.sessionKind == .soberBaseline
        && $0.protocolVariant == protocolVariant
    }
    let eligible = candidates.filter { isEligible($0, protocolVariant: protocolVariant) }

    return BaselineProfileSummary(
      participantID: participantID,
      candidateSessionCount: candidates.count,
      eligibleSessionCount: eligible.count,
      excludedSessionCount: candidates.count - eligible.count,
      minimumRequiredSessions: minimumRequiredSessions,
      minimumQuality: minimumQuality,
      metrics: makeMetricsSummary(from: eligible)
    )
  }

  private func isEligible(_ session: ResearchSessionEnvelope, protocolVariant: OcularProtocolVariant) -> Bool {
    guard session.schemaVersion == ResearchSessionEnvelope.currentSchemaVersion,
      session.completedAt != nil,
      session.metrics.completedAllTasks,
      session.metrics.qualityScore >= minimumQuality
    else {
      return false
    }

    guard session.protocolVariant == protocolVariant else { return false }

    let metrics = session.metrics
    return metrics.reactionTimeMilliseconds.isFinite
      && metrics.trackingError.isFinite
      && metrics.timeEstimateError.isFinite
      && metrics.gazeSmoothness.isFinite
      && metrics.qualityScore.isFinite
  }

  private func makeMetricsSummary(
    from sessions: [ResearchSessionEnvelope]
  ) -> BaselineMetricsSummary? {
    guard !sessions.isEmpty else { return nil }

    return BaselineMetricsSummary(
      reactionTimeMilliseconds: robustStatistic(
        sessions.map(\.metrics.reactionTimeMilliseconds)
      ),
      reactionMisses: robustStatistic(sessions.map { Double($0.metrics.reactionMisses) }),
      trackingError: robustStatistic(sessions.map(\.metrics.trackingError)),
      timeEstimateError: robustStatistic(sessions.map(\.metrics.timeEstimateError)),
      gazeSmoothness: robustStatistic(sessions.map(\.metrics.gazeSmoothness)),
      qualityScore: robustStatistic(sessions.map(\.metrics.qualityScore))
    )
  }

  private func robustStatistic(_ values: [Double]) -> RobustBaselineStatistic {
    let center = median(values)
    let deviations = values.map { abs($0 - center) }
    return RobustBaselineStatistic(
      median: center,
      medianAbsoluteDeviation: median(deviations)
    )
  }

  private func median(_ values: [Double]) -> Double {
    precondition(!values.isEmpty)
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
  }
}
