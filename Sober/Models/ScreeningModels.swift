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
    case .signalsDetected: "Changes detected"
    case .inconclusive: "No clear read"
    case .noSignalsDetected: "No changes detected"
    }
  }

  var message: String {
    switch self {
    case .signalsDetected:
      "This check found changes outside your usual range. Don’t drive."
    case .inconclusive:
      "We couldn’t get a clear read. If you’ve had anything, don’t drive."
    case .noSignalsDetected:
      "This check did not find changes. It cannot establish sobriety or driving safety."
    }
  }
}

struct ScreeningMetrics: Equatable, Sendable {
  var reactionTimeMilliseconds: Double
  var reactionMisses: Int
  /// `false` when the reaction task never ran, such as a self-report-only result.
  var reactionWasMeasured: Bool = true
  /// `nil` means the task was skipped or the capture failed. An unmeasured
  /// metric is never substituted with a stand-in value.
  var trackingError: Double?
  var timeEstimateError: Double
  /// `false` when the timing task never ran.
  var timingWasMeasured: Bool = true
  var gazeSmoothness: Double?
  /// Internal-research-only signal. Public builds neither bundle its model
  /// nor include this value in a result.
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
  /// Carries capture state explicitly so presentation never has to infer it
  /// from localized display copy.
  let wasMeasured: Bool

  init(
    id: String,
    label: String,
    value: String,
    concern: Bool,
    wasMeasured: Bool = true
  ) {
    self.id = id
    self.label = label
    self.value = value
    self.concern = concern
    self.wasMeasured = wasMeasured
  }
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
  let title: String
  let message: String

  init(reason: BaselineCompletionReason) {
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
  case live = "Run live check"
  case signals = "Preview changes detected"
  case inconclusive = "Preview inconclusive"
  case noSignals = "Preview no changes"

  var id: String { rawValue }
}

enum ScreeningMode: Sendable {
  case check
  case baseline
}

enum SafeRideMessage {
  nonisolated static func body(destinationName: String) -> String {
    "Can you help me get to \(destinationName)? I’m choosing not to drive."
  }
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
  let guardianCheckInOccurrenceID: String?

  init(
    mode: ScreeningMode,
    scenario: FounderScenario,
    guardianCheckInOccurrenceID: String? = nil
  ) {
    self.mode = mode
    self.scenario = scenario
    self.guardianCheckInOccurrenceID = guardianCheckInOccurrenceID
  }
}

struct SafetyPlan: Codable, Equatable, Sendable {
  var isActive: Bool
  var userName: String
  var contactName: String
  var contactPhone: String
  /// The user's own number, collected only so a guardian number equal to it can
  /// be rejected. Never sent anywhere.
  var selfPhone: String
  /// Additional family numbers beyond the primary contact.
  var additionalContactPhones: [String]
  var automaticParentAlerts: Bool
  var parentAlertConsent: Bool
  /// A user-editable nickname such as "Home" or "Campus". This is display-only.
  var homeLabel: String
  /// The actual ride-provider drop-off address. Never substitute the nickname for this value.
  var homeAddress: String
  var preferredRide: String

  init(
    isActive: Bool = true,
    userName: String = "",
    contactName: String = "",
    contactPhone: String = "",
    selfPhone: String = "",
    additionalContactPhones: [String] = [],
    automaticParentAlerts: Bool = false,
    parentAlertConsent: Bool = false,
    homeLabel: String = "",
    homeAddress: String = "",
    preferredRide: String = "Uber"
  ) {
    self.isActive = isActive
    self.userName = userName
    self.contactName = contactName
    self.contactPhone = contactPhone
    self.selfPhone = selfPhone
    self.additionalContactPhones = additionalContactPhones
    self.automaticParentAlerts = automaticParentAlerts
    self.parentAlertConsent = parentAlertConsent
    self.homeLabel = homeLabel
    self.homeAddress = homeAddress
    self.preferredRide = preferredRide
  }

  var trimmedHomeLabel: String {
    homeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var trimmedHomeAddress: String {
    homeAddress.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var destinationDisplayName: String {
    trimmedHomeLabel.isEmpty ? "Saved destination" : trimmedHomeLabel
  }

  var hasRideDestination: Bool { !trimmedHomeAddress.isEmpty }

  var normalizedContactPhone: String { contactPhone.filter(\.isNumber) }

  /// A plan can only be offered as a ride/text intervention once the person
  /// has actually named someone. There is no placeholder contact.
  var hasContact: Bool {
    !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !normalizedContactPhone.isEmpty
  }

  var selfPhoneDigits: String? {
    let digits = selfPhone.filter(\.isNumber)
    return digits.isEmpty ? nil : digits
  }

  /// Every family number, primary first, normalized and non-empty.
  var allContactPhoneDigits: [String] {
    ([contactPhone] + additionalContactPhones)
      .map { $0.filter(\.isNumber) }
      .filter { !$0.isEmpty }
  }

  /// Two contacts sharing a number means one of them would never be reached.
  var hasDuplicateContactPhones: Bool {
    let numbers = allContactPhoneDigits
    return Set(numbers).count != numbers.count
  }

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
    case selfPhone
    case additionalContactPhones
    case automaticParentAlerts
    case parentAlertConsent
    case homeLabel
    case homeAddress
    case preferredRide
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    isActive = try values.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    userName = try values.decodeIfPresent(String.self, forKey: .userName) ?? ""
    contactName = try values.decodeIfPresent(String.self, forKey: .contactName) ?? ""
    contactPhone = try values.decodeIfPresent(String.self, forKey: .contactPhone) ?? ""
    selfPhone = try values.decodeIfPresent(String.self, forKey: .selfPhone) ?? ""
    additionalContactPhones =
      try values.decodeIfPresent([String].self, forKey: .additionalContactPhones) ?? []
    automaticParentAlerts =
      try values.decodeIfPresent(Bool.self, forKey: .automaticParentAlerts) ?? false
    parentAlertConsent = try values.decodeIfPresent(Bool.self, forKey: .parentAlertConsent) ?? false
    let legacyLabel = try values.decodeIfPresent(String.self, forKey: .homeLabel) ?? ""
    if let storedAddress = try values.decodeIfPresent(String.self, forKey: .homeAddress) {
      homeLabel = legacyLabel
      homeAddress = storedAddress
    } else if legacyLabel.rangeOfCharacter(from: .decimalDigits) != nil {
      // The old UI called this field a label but passed it to the ride provider as an address.
      // Preserve address-like legacy input while separating it from the nickname going forward.
      homeLabel = ""
      homeAddress = legacyLabel
    } else {
      // Do not keep the old hard-coded "Home" value. A fresh nickname should be the user's choice.
      homeLabel = legacyLabel.caseInsensitiveCompare("Home") == .orderedSame ? "" : legacyLabel
      homeAddress = ""
    }
    preferredRide = try values.decodeIfPresent(String.self, forKey: .preferredRide) ?? "Uber"
  }
}
