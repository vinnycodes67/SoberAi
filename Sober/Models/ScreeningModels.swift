import Foundation

enum SelfReport: String, CaseIterable, Sendable {
  case no
  case yes
  case unsure
}

enum ScreeningResultState: String, Codable, Sendable {
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
  /// `nil` means the task was skipped or the capture failed. An unmeasured
  /// metric is never substituted with a stand-in value.
  var trackingError: Double?
  var timeEstimateError: Double
  var gazeSmoothness: Double?
  /// `nil` when the pupillometry step was skipped or the model/capture
  /// couldn't produce a reading. Unlike trackingError/gazeSmoothness this
  /// does not force an INCONCLUSIVE result — see ScreeningEngine for why.
  var pupillometry: PupillometrySample? = nil
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

/// One flash trial's derived pupillary light reflex readings.
struct PupilLightReflexTrial: Codable, Equatable, Sendable {
  var baselineDiameterMm: Double
  var minDiameterMm: Double
  var latencySeconds: Double
  var peakConstrictionVelocityMmPerSecond: Double
  var amplitudePercent: Double
  /// `nil` if the pupil hadn't recovered to 75% of baseline within the
  /// capture window — never backfilled with an estimate.
  var recoveryTo75PercentSeconds: Double?
}

/// One pupillometry session: up to three light-condition trials plus a
/// capture-quality score for the session as a whole.
struct PupillometrySample: Codable, Equatable, Sendable {
  var trials: [PupilLightReflexTrial]
  var qualityScore: Double
}

struct SignalDetail: Identifiable, Equatable, Sendable {
  let id: String
  let label: String
  let value: String
  let concern: Bool
  /// How far this one measure sits from the person's own baseline, where 0
  /// is at or below their usual and 1 is roughly three of their own standard
  /// deviations above it. `nil` when the task did not run.
  ///
  /// This is per-signal only. The composite `riskScore` is never surfaced as
  /// a figure anywhere in the UI, because a single number describing a
  /// person is the score this product refuses to produce.
  var risk: Double? = nil

  /// The point on that scale where a signal starts being called out.
  static let concernThreshold = 0.55
}

struct ScreeningOutcome: Equatable, Sendable {
  let state: ScreeningResultState
  let qualityScore: Double
  let riskScore: Double
  let details: [SignalDetail]

  /// Per-signal positions, for persisting alongside the session. Signals that
  /// could not be measured are omitted rather than stored as zero, so a
  /// missing reading is never mistaken later for a reading of nothing.
  var signalRisks: [String: Double] {
    details.reduce(into: [:]) { result, detail in
      if let risk = detail.risk { result[detail.id] = risk }
    }
  }
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

/// One completed sober baseline session's per-task readings. Optional
/// fields mean that task was skipped or unmeasured during that session,
/// same as ScreeningMetrics.
struct BaselineSample: Codable, Equatable, Sendable {
  var reactionTimeMilliseconds: Double
  var reactionMisses: Int
  var trackingError: Double?
  var timeEstimateError: Double
  var gazeSmoothness: Double?
  var pupillometry: PupillometrySample? = nil
}

/// A rolling window of the person's own sober sessions. Once it reaches
/// `requiredSessions`, scoring compares a check against this instead of a
/// fixed population range. Recording a new sample past the window rolls
/// the oldest one off, so a stale baseline can be refreshed over time.
struct PersonalBaseline: Codable, Equatable, Sendable {
  static let requiredSessions = 3

  private(set) var samples: [BaselineSample] = []

  var sessionCount: Int { samples.count }
  var isReady: Bool { sessionCount >= Self.requiredSessions }

  mutating func record(_ sample: BaselineSample) {
    samples.append(sample)
    if samples.count > Self.requiredSessions {
      samples.removeFirst(samples.count - Self.requiredSessions)
    }
  }
}

struct ScreeningLaunch: Identifiable, Sendable {
  let id = UUID()
  let mode: ScreeningMode
  let scenario: FounderScenario
}

struct SafetyPlan: Codable, Equatable, Sendable {
  var isActive: Bool
  var contactName: String
  var contactPhone: String
  var homeLabel: String
  var preferredRide: String

  init(
    isActive: Bool = true,
    contactName: String = "",
    contactPhone: String = "",
    homeLabel: String = "Home",
    preferredRide: String = "Uber"
  ) {
    self.isActive = isActive
    self.contactName = contactName
    self.contactPhone = contactPhone
    self.homeLabel = homeLabel
    self.preferredRide = preferredRide
  }

  var normalizedContactPhone: String { contactPhone.filter(\.isNumber) }

  /// A plan can only be offered as a ride/text intervention once the person
  /// has actually named someone. There is no placeholder contact.
  var hasContact: Bool {
    !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !normalizedContactPhone.isEmpty
  }

  private enum CodingKeys: String, CodingKey {
    case isActive
    case contactName
    case contactPhone
    case homeLabel
    case preferredRide
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    isActive = try values.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    contactName = try values.decodeIfPresent(String.self, forKey: .contactName) ?? ""
    contactPhone = try values.decodeIfPresent(String.self, forKey: .contactPhone) ?? ""
    homeLabel = try values.decodeIfPresent(String.self, forKey: .homeLabel) ?? "Home"
    preferredRide = try values.decodeIfPresent(String.self, forKey: .preferredRide) ?? "Uber"
  }
}
