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

enum BaselineCompletionReason: Sendable {
  case ready
  case captureQualityTooLow
  case taskUnavailable
}

struct BaselineCompletionState: Equatable, Sendable {
  let reason: BaselineCompletionReason
  let title: String
  let message: String

  init(reason: BaselineCompletionReason) {
    self.reason = reason
    switch reason {
    case .ready:
      self.title = "Baseline recorded"
      self.message = ""
    case .captureQualityTooLow:
      self.title = "Capture quality was too low"
      self.message = "The camera view was too weak or unstable. Retry in better light with your face centered."
    case .taskUnavailable:
      self.title = "This task isn’t available to you"
      self.message = "The visual tasks need sight and a steady drag. You can skip them and still reach the safer next step."
    }
  }
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
  var isActive: Bool
  var userName: String
  var contactName: String
  var contactPhone: String
  var automaticParentAlerts: Bool
  var parentAlertConsent: Bool
  var homeLabel: String
  var preferredRide: String

  init(
    isActive: Bool = true,
    userName: String = "",
    contactName: String = "",
    contactPhone: String = "",
    automaticParentAlerts: Bool = false,
    parentAlertConsent: Bool = false,
    homeLabel: String = "Home",
    preferredRide: String = "Uber"
  ) {
    self.isActive = isActive
    self.userName = userName
    self.contactName = contactName
    self.contactPhone = contactPhone
    self.automaticParentAlerts = automaticParentAlerts
    self.parentAlertConsent = parentAlertConsent
    self.homeLabel = homeLabel
    self.preferredRide = preferredRide
  }

  var normalizedContactPhone: String { contactPhone.filter(\.isNumber) }

  var canAutomaticallyAlertParent: Bool {
    isActive
      && automaticParentAlerts
      && parentAlertConsent
      && !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && normalizedContactPhone.count >= 10
      && normalizedContactPhone.count <= 15
  }

  private enum CodingKeys: String, CodingKey {
    case isActive
    case userName
    case contactName
    case contactPhone
    case automaticParentAlerts
    case parentAlertConsent
    case homeLabel
    case preferredRide
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    isActive = try values.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    userName = try values.decodeIfPresent(String.self, forKey: .userName) ?? ""
    contactName = try values.decodeIfPresent(String.self, forKey: .contactName) ?? ""
    contactPhone = try values.decodeIfPresent(String.self, forKey: .contactPhone) ?? ""
    automaticParentAlerts =
      try values.decodeIfPresent(Bool.self, forKey: .automaticParentAlerts) ?? false
    parentAlertConsent = try values.decodeIfPresent(Bool.self, forKey: .parentAlertConsent) ?? false
    homeLabel = try values.decodeIfPresent(String.self, forKey: .homeLabel) ?? "Home"
    preferredRide = try values.decodeIfPresent(String.self, forKey: .preferredRide) ?? "Uber"
  }
}
