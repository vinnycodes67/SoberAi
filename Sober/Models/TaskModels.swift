import Foundation

enum ChoiceReactionSymbol: String, Codable, CaseIterable, Sendable {
  case blueCircle
  case blueDiamond
  case pinkCircle
  case pinkDiamond

  var colorName: String {
    switch self {
    case .blueCircle, .blueDiamond: "Blue"
    case .pinkCircle, .pinkDiamond: "Pink"
    }
  }

  var shapeName: String {
    switch self {
    case .blueCircle, .pinkCircle: "circle"
    case .blueDiamond, .pinkDiamond: "diamond"
    }
  }

  var accessibilityLabel: String { "\(colorName) \(shapeName)" }
}

/// Result of the motor tracking task.
///
/// `wasMeasured` is false when the participant used the non-visual alternative,
/// which cannot produce a real coordination measurement. Sober must not invent
/// a favourable score in that case: the check is reported as incomplete so the
/// engine returns `INCONCLUSIVE`.
struct MotorTrackingOutcome: Equatable, Sendable {
  let error: Double
  let wasMeasured: Bool

  init(error: Double, wasMeasured: Bool = true) {
    self.error = error
    self.wasMeasured = wasMeasured
  }

  /// Maximum error and an explicit "not measured" flag, so this can never read
  /// as good performance.
  static let notMeasured = MotorTrackingOutcome(error: 1, wasMeasured: false)
}

struct ChoiceReactionTrial: Codable, Equatable, Sendable {
  /// Nil for an anticipation because no target had appeared yet. Persisting the
  /// previous round's target would make the research record factually wrong.
  let expected: ChoiceReactionSymbol?
  let selected: ChoiceReactionSymbol?
  let latencyMilliseconds: Double?
  let wasAnticipation: Bool
  let wasMiss: Bool

  var isCorrect: Bool {
    guard let expected else { return false }
    return selected == expected && !wasAnticipation && !wasMiss
  }
}

struct ChoiceReactionSummary: Codable, Equatable, Sendable {
  let trials: [ChoiceReactionTrial]

  var correctLatencies: [Double] {
    trials.compactMap { $0.isCorrect ? $0.latencyMilliseconds : nil }
  }

  var averageMilliseconds: Double {
    guard !correctLatencies.isEmpty else { return 1_500 }
    return correctLatencies.reduce(0, +) / Double(correctLatencies.count)
  }

  /// The robust summary of this session. Recorded alongside the mean; scoring
  /// still uses the mean (see `ScreeningMetrics.reactionMedianMilliseconds`).
  ///
  /// Reaction-time distributions are right-skewed: the floor is physiology and
  /// the tail is attention, so a single lapse pulls the mean well above where
  /// most of the trials sat. The median does not move. The baseline engine
  /// already summarises *across* sessions with a median and MAD; using the mean
  /// *within* a session left the non-robust half of the pipeline sitting
  /// closest to the noise.
  ///
  /// An engineering metric, not a clinical one. The 1,500 ms stand-in for an
  /// empty session matches `averageMilliseconds`, and only a session with no
  /// correct trials can reach it — which `completedAllTasks` already rejects.
  var medianMilliseconds: Double {
    guard !correctLatencies.isEmpty else { return 1_500 }
    let sorted = correctLatencies.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
  }

  var variabilityMilliseconds: Double {
    guard correctLatencies.count > 1 else { return 0 }
    let mean = averageMilliseconds
    let variance = correctLatencies
      .map { pow($0 - mean, 2) }
      .reduce(0, +) / Double(correctLatencies.count)
    return sqrt(variance)
  }

  var incorrectChoices: Int { trials.filter { !$0.isCorrect && !$0.wasMiss && !$0.wasAnticipation }.count }
  var anticipations: Int { trials.filter(\.wasAnticipation).count }
  var misses: Int { trials.filter(\.wasMiss).count }
  var totalErrors: Int { incorrectChoices + anticipations + misses }
}
