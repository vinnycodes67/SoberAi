import Foundation

enum SelfReport: String, CaseIterable, Sendable {
  case no
  case yes
  case unsure
}

enum ScreeningResultState: String, Sendable {
  case signalsDetected = "SIGNALS_DETECTED"
  case inconclusive = "INCONCLUSIVE"
  case noSignalsDetected = "NO_SIGNALS_DETECTED"

  var title: String {
    switch self {
    case .signalsDetected: "Signals detected"
    case .inconclusive: "No clear read"
    case .noSignalsDetected: "No signals detected"
    }
  }

  var message: String {
    switch self {
    case .signalsDetected:
      "We saw signs consistent with impairment. Don’t drive."
    case .inconclusive:
      "We couldn’t get a clear read. If you’ve had anything, don’t drive."
    case .noSignalsDetected:
      "We didn’t detect signals. This does not mean you’re sober or safe to drive."
    }
  }
}

struct ScreeningMetrics: Equatable, Sendable {
  var reactionTimeMilliseconds: Double
  var reactionMisses: Int
  var trackingError: Double
  var timeEstimateError: Double
  var gazeSmoothness: Double
  var qualityScore: Double
  var completedAllTasks: Bool

  static let demoClear = ScreeningMetrics(
    reactionTimeMilliseconds: 318,
    reactionMisses: 0,
    trackingError: 0.18,
    timeEstimateError: 0.08,
    gazeSmoothness: 0.16,
    qualityScore: 0.94,
    completedAllTasks: true
  )
}

struct SignalDetail: Identifiable, Equatable, Sendable {
  let id: String
  let label: String
  let value: String
  let concern: Bool
}

struct ScreeningOutcome: Equatable, Sendable {
  let state: ScreeningResultState
  let qualityScore: Double
  let riskScore: Double
  let details: [SignalDetail]
}

enum FounderScenario: String, CaseIterable, Identifiable, Sendable {
  case live = "Run the live prototype"
  case signals = "Preview signals detected"
  case inconclusive = "Preview inconclusive"
  case noSignals = "Preview no signals"

  var id: String { rawValue }
}

enum ScreeningMode: Sendable {
  case check
  case baseline
}

struct ScreeningLaunch: Identifiable, Sendable {
  let id = UUID()
  let mode: ScreeningMode
  let scenario: FounderScenario
}

struct SafetyPlan: Codable, Equatable, Sendable {
  var isActive = true
  var contactName = "Casey"
  var contactPhone = "5125550147"
  var homeLabel = "Home"
  var preferredRide = "Uber"
}
