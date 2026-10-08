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

enum ScreeningOutcomeReason: Equatable, Sendable {
  case measuredComparison
  case reportedUse
}

struct ScreeningMetrics: Equatable, Sendable {
  /// The session's mean correct latency, which is what scoring and the
  /// baseline use. See `reactionMedianMilliseconds` for why that may change.
  var reactionTimeMilliseconds: Double
  /// Every reaction error in one number, which is what risk scoring weighs.
  ///
  /// Kept as the total because the three kinds below are not interchangeable
  /// and summing them is a deliberate scoring choice, not a storage one.
  var reactionMisses: Int
  /// `false` when the reaction task never ran, such as a self-report-only result.
  var reactionWasMeasured: Bool = true

  // The error breakdown behind `reactionMisses`.
  //
  // A wrong choice, a response before the target appeared, and no response at
  // all are three different behaviours with three different causes, and the
  // reaction task already tells them apart. They were being summed into one
  // `Int` at the point of capture, which threw the distinction away before
  // anything could use it. Stored separately so a baseline can eventually
  // speak about them separately.
  //
  // Optional because sessions recorded before this existed genuinely do not
  // know, and a zero would claim they did.

  /// Median correct latency. Recorded alongside the mean, not instead of it.
  ///
  /// The median is the robust summary of a right-skewed reaction-time
  /// distribution and is what the baseline should eventually compare. Scoring
  /// still uses the mean because switching it would score new sessions against
  /// baselines built from means — and the alternative, retiring every existing
  /// baseline, is what `ReviewRegressionTests` exists to prevent. Recording both
  /// now lets the switch be made later against real data rather than guessed.
  var reactionMedianMilliseconds: Double?
  /// Responded, but chose the wrong target.
  var reactionIncorrectChoices: Int?
  /// Responded before the target appeared.
  var reactionAnticipations: Int?
  /// Did not respond within the trial window.
  var reactionMissedResponses: Int?
  /// Standard deviation of correct latencies, in milliseconds.
  var reactionVariabilityMilliseconds: Double?
  /// How many trials the session actually presented.
  var reactionTrialCount: Int?
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
  let reason: ScreeningOutcomeReason

  /// False when the eye task never ran: the check ran on hardware with no
  /// TrueDepth camera, or it ended at the self-report question. Nothing was
  /// captured, so `qualityScore` grades nothing and must not be shown as a
  /// percentage: 0% reads as a ruined capture and 100% as a perfect one, and
  /// the honest answer is that the question does not apply.
  let measuredCapture: Bool

  init(
    state: ScreeningResultState,
    qualityScore: Double,
    riskScore: Double,
    details: [SignalDetail],
    reason: ScreeningOutcomeReason = .measuredComparison,
    measuredCapture: Bool = true
  ) {
    self.state = state
    self.qualityScore = qualityScore
    self.riskScore = riskScore
    self.details = details
    self.reason = reason
    self.measuredCapture = measuredCapture
  }

  var title: String {
    switch reason {
    case .measuredComparison: state.title
    case .reportedUse: "You reported recent use"
    }
  }

  var message: String {
    switch reason {
    case .measuredComparison: state.message
    case .reportedUse:
      "You reported drinking or using something in the last 4 hours. No tasks were needed. Don’t drive."
    }
  }
}

enum BaselineCompletionReason: Sendable {
  case ready
  case captureQualityTooLow
  case taskUnavailable
  case notSaved
}

struct BaselineCompletionState: Equatable, Sendable {
  let title: String
  let message: String

  init(reason: BaselineCompletionReason) {
    switch reason {
    case .ready:
      self.title = "Baseline recorded"
      self.message = ""
    case .notSaved:
      self.title = "This session wasn’t saved"
      self.message =
        "Something went wrong writing it to this iPhone, so it has not been added to your steady. Nothing else was lost — record another when you can."

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
  static let requiredSessions = BaselineThresholds.scoringWindow

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

/// A person the user can call or message from a result.
///
/// Kept on this iPhone with the rest of the Safety Plan. Nothing here is sent
/// anywhere; the only thing that ever leaves the device is a call or message
/// the user starts with a tap.
struct GuardianContact: Codable, Equatable, Identifiable, Sendable {
  /// Digit counts a dialable number can have, country code included.
  static let phoneDigitRange = 10...15

  var id: UUID
  var name: String
  var phone: String
  var canCall: Bool
  var canText: Bool

  init(
    id: UUID = UUID(),
    name: String = "",
    phone: String = "",
    canCall: Bool = true,
    canText: Bool = true
  ) {
    self.id = id
    self.name = name
    self.phone = phone
    self.canCall = canCall
    self.canText = canText
  }

  var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  var phoneDigits: String { phone.filter(\.isNumber) }

  /// Contacts migrated from the old extra-numbers list have no name; the
  /// number is the only honest label for them.
  var displayName: String {
    if !trimmedName.isEmpty { return trimmedName }
    let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedPhone.isEmpty ? "Contact" : trimmedPhone
  }

  var hasValidPhone: Bool { Self.phoneDigitRange.contains(phoneDigits.count) }

  /// Something the result screen can actually offer: a number and at least
  /// one way the user has allowed us to use it.
  var isReachable: Bool { !phoneDigits.isEmpty && (canCall || canText) }

  var callURL: URL? {
    guard canCall, !phoneDigits.isEmpty else { return nil }
    return URL(string: "tel:\(phoneDigits)")
  }

  func messageURL(body: String) -> URL? {
    guard canText, !phoneDigits.isEmpty else { return nil }
    let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
    return URL(string: "sms:\(phoneDigits)?body=\(encoded)")
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, phone, canCall, canText
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
    phone = try values.decodeIfPresent(String.self, forKey: .phone) ?? ""
    canCall = try values.decodeIfPresent(Bool.self, forKey: .canCall) ?? true
    canText = try values.decodeIfPresent(Bool.self, forKey: .canText) ?? true
  }
}

/// Why a contact can't be saved as entered.
enum GuardianContactIssue: String, CaseIterable, Sendable {
  case phoneMissing
  case phoneMalformed
  case phoneMatchesUser
  case duplicatePhone

  var message: String {
    switch self {
    case .phoneMissing:
      return "Add a phone number for this contact."
    case .phoneMalformed:
      return "Check that phone number. Calls and messages can't reach it as written."
    case .phoneMatchesUser:
      return "That's your own number. Add someone else."
    case .duplicatePhone:
      return "Another contact already has this number."
    }
  }
}

struct SafetyPlan: Codable, Equatable, Sendable {
  /// Enough for a household and a friend or two. Past this the "More contacts"
  /// list on a result stops being something you can scan at 2am.
  static let maximumContacts = 5

  var isActive: Bool
  var userName: String
  /// The people the user can call or message, primary first.
  ///
  /// The primary is the first element rather than a flag on each contact, so
  /// "exactly one primary" is structural: there is no state with two, and none
  /// with zero while the list is non-empty. Only the mutators below change the
  /// list, so the cap holds too.
  private(set) var contacts: [GuardianContact]
  /// The user's own number, collected only so a guardian number equal to it can
  /// be rejected. Never sent anywhere.
  var selfPhone: String
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
    contacts: [GuardianContact] = [],
    selfPhone: String = "",
    automaticParentAlerts: Bool = false,
    parentAlertConsent: Bool = false,
    homeLabel: String = "",
    homeAddress: String = "",
    preferredRide: String = "Uber"
  ) {
    self.isActive = isActive
    self.userName = userName
    self.contacts = Array(contacts.prefix(Self.maximumContacts))
    self.selfPhone = selfPhone
    self.automaticParentAlerts = automaticParentAlerts
    self.parentAlertConsent = parentAlertConsent
    self.homeLabel = homeLabel
    self.homeAddress = homeAddress
    self.preferredRide = preferredRide
  }

  // MARK: Contacts

  var primaryContact: GuardianContact? { contacts.first }

  var canAddContact: Bool { contacts.count < Self.maximumContacts }

  /// Appends a contact, or does nothing at the cap. The first contact added
  /// becomes the primary.
  @discardableResult
  mutating func addContact(_ contact: GuardianContact) -> Bool {
    guard canAddContact, !contacts.contains(where: { $0.id == contact.id }) else { return false }
    contacts.append(contact)
    return true
  }

  /// Replaces the contact with the same id, keeping its position.
  mutating func updateContact(_ contact: GuardianContact) {
    guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
    contacts[index] = contact
  }

  /// Removing the primary promotes the next contact, so a non-empty list always
  /// has someone the result screen leads with.
  mutating func removeContact(id: GuardianContact.ID) {
    contacts.removeAll { $0.id == id }
  }

  mutating func makePrimary(id: GuardianContact.ID) {
    guard let index = contacts.firstIndex(where: { $0.id == id }), index != 0 else { return }
    contacts.insert(contacts.remove(at: index), at: 0)
  }

  /// What stops `contact` being saved into this plan as entered. `contact` may
  /// be a new draft or an edit of one already in the list; it is never
  /// compared with its own stored copy.
  func issues(for contact: GuardianContact) -> [GuardianContactIssue] {
    let digits = contact.phoneDigits
    guard !digits.isEmpty else { return [.phoneMissing] }
    var issues: [GuardianContactIssue] = []
    if !contact.hasValidPhone {
      issues.append(.phoneMalformed)
    }
    // Same rule as G0-7 in the guardian contract: a guardian who is you is
    // not a guardian.
    if let selfDigits = selfPhoneDigits, selfDigits == digits {
      issues.append(.phoneMatchesUser)
    }
    if contacts.contains(where: { $0.id != contact.id && $0.phoneDigits == digits }) {
      issues.append(.duplicatePhone)
    }
    return issues
  }

  /// A plan can only be offered as a ride/text intervention once the person
  /// has actually named someone. There is no placeholder contact.
  var hasContact: Bool { !reachableContacts.isEmpty }

  /// Contacts the result screen can offer, primary first.
  var reachableContacts: [GuardianContact] { contacts.filter(\.isReachable) }

  /// The contact who gets the result screen's main call/message action.
  ///
  /// Normally the primary. If the primary has no usable number or both
  /// actions turned off, the next reachable contact steps up rather than the
  /// screen offering nobody.
  var leadContact: GuardianContact? { reachableContacts.first }

  /// Everyone reachable after the lead, for the "More contacts" list.
  var otherReachableContacts: [GuardianContact] { Array(reachableContacts.dropFirst()) }

  var selfPhoneDigits: String? {
    let digits = selfPhone.filter(\.isNumber)
    return digits.isEmpty ? nil : digits
  }

  /// Every contact number, primary first, normalized and non-empty.
  var allContactPhoneDigits: [String] {
    contacts.map(\.phoneDigits).filter { !$0.isEmpty }
  }

  /// Two contacts sharing a number means one of them would never be reached.
  var hasDuplicateContactPhones: Bool {
    let numbers = allContactPhoneDigits
    return Set(numbers).count != numbers.count
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

  /// True only when `rideURL` actually hands the destination to the provider.
  ///
  /// Uber's universal link takes a formatted address; Lyft's takes coordinates
  /// we do not have, and the public build has no network to geocode with. So
  /// the Lyft link opens the app without a destination — and any screen that
  /// promises "Lyft to Home" is claiming something that does not happen.
  var rideCarriesDestination: Bool { preferredRide != "Lyft" && hasRideDestination }

  /// The ride deep link for this plan.
  ///
  /// Shared rather than rebuilt per screen. The result screen and Curfew's
  /// check-in have to open the same ride the same way, and two copies of a URL
  /// builder is exactly how one of them quietly stops carrying the destination.
  var rideURL: URL? {
    if preferredRide == "Lyft" {
      return URL(string: "https://www.lyft.com/rider")
    }

    // Built with URLComponents so the address is percent-encoded exactly once.
    //
    // The previous version encoded it by hand and interpolated it into a
    // string. Uber's parameter name contains square brackets, which are illegal
    // in a query, so `URL(string:)` re-encoded the whole thing — and the already
    // encoded spaces became `%2520`. Uber then received the literal text
    // "123%20Main%20Street" as the destination and could not resolve it, which
    // silently removed the destination from the one action this app exists to
    // offer.
    var components = URLComponents()
    components.scheme = "https"
    components.host = "m.uber.com"
    components.path = "/ul/"
    var items = [
      URLQueryItem(name: "action", value: "setPickup"),
      URLQueryItem(name: "pickup", value: "my_location"),
    ]
    if !trimmedHomeAddress.isEmpty {
      items.append(URLQueryItem(name: "dropoff[formatted_address]", value: trimmedHomeAddress))
    }
    components.queryItems = items
    return components.url
  }

  var canAutomaticallyAlertParent: Bool {
    isActive
      && automaticParentAlerts
      && parentAlertConsent
      && !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !(primaryContact?.trimmedName.isEmpty ?? true)
      && (primaryContact?.hasValidPhone ?? false)
  }

  private enum CodingKeys: String, CodingKey {
    case isActive
    case userName
    case contacts
    case selfPhone
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
    if let stored = try values.decodeIfPresent([GuardianContact].self, forKey: .contacts) {
      contacts = Array(stored.prefix(Self.maximumContacts))
    } else {
      contacts = try Self.legacyContacts(from: decoder)
    }
    selfPhone = try values.decodeIfPresent(String.self, forKey: .selfPhone) ?? ""
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

  /// Only the current shape is written. A plan saved by this version is read
  /// back through `contacts`; the legacy keys exist only to be migrated.
  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(isActive, forKey: .isActive)
    try values.encode(userName, forKey: .userName)
    try values.encode(contacts, forKey: .contacts)
    try values.encode(selfPhone, forKey: .selfPhone)
    try values.encode(automaticParentAlerts, forKey: .automaticParentAlerts)
    try values.encode(parentAlertConsent, forKey: .parentAlertConsent)
    try values.encode(homeLabel, forKey: .homeLabel)
    try values.encode(homeAddress, forKey: .homeAddress)
    try values.encode(preferredRide, forKey: .preferredRide)
  }

  private enum LegacyContactKeys: String, CodingKey {
    case contactName
    case contactPhone
    case additionalContactPhones
  }

  /// Plans saved before several contacts existed held one named contact plus
  /// a list of bare extra numbers.
  ///
  /// The named contact comes first, so it stays the primary. Each extra number
  /// becomes a nameless contact that displays as its number. Blank numbers,
  /// and repeats of a number already kept, are dropped: they reached nobody
  /// new, and keeping them would greet the user with a duplicate warning about
  /// something they never typed twice on purpose.
  private static func legacyContacts(from decoder: Decoder) throws -> [GuardianContact] {
    let legacy = try decoder.container(keyedBy: LegacyContactKeys.self)
    let name = try legacy.decodeIfPresent(String.self, forKey: .contactName) ?? ""
    let phone = try legacy.decodeIfPresent(String.self, forKey: .contactPhone) ?? ""
    let extras = try legacy.decodeIfPresent([String].self, forKey: .additionalContactPhones) ?? []

    var contacts: [GuardianContact] = []
    var seenDigits = Set<String>()
    let primary = GuardianContact(name: name, phone: phone)
    // A name with no number is still the person the user chose; keep it so
    // the editor shows who is missing a number instead of silently losing them.
    if !primary.trimmedName.isEmpty || !primary.phoneDigits.isEmpty {
      contacts.append(primary)
      if !primary.phoneDigits.isEmpty { seenDigits.insert(primary.phoneDigits) }
    }
    for extra in extras {
      let contact = GuardianContact(phone: extra.trimmingCharacters(in: .whitespacesAndNewlines))
      guard !contact.phoneDigits.isEmpty, seenDigits.insert(contact.phoneDigits).inserted else {
        continue
      }
      contacts.append(contact)
    }
    return Array(contacts.prefix(maximumContacts))
  }
}
