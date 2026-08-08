import Foundation

struct BaselineDeletionReceipt: Equatable, Sendable {
  let deletedSessionCount: Int
  let participantID: PseudonymousParticipantID
}

enum BaselineStoreError: Error, Equatable, LocalizedError {
  case deletionPending

  var errorDescription: String? {
    switch self {
    case .deletionPending:
      "Local baseline data is being deleted."
    }
  }
}

/// Owns the durable evidence used to decide whether a personal baseline exists.
/// Cached UI counters are deliberately outside this contract and can never make
/// an empty archive look ready.
@MainActor
protocol BaselineStore: AnyObject {
  var participantID: PseudonymousParticipantID { get }
  var deletionPending: Bool { get }
  var stateRevision: UInt64 { get }

  func list() async throws -> [ResearchSessionEnvelope]
  func append(_ session: ResearchSessionEnvelope) async throws
  func delete(sessionID: ResearchSessionID) async throws -> Bool
  func exportData(exportedAt: Date) async throws -> Data

  /// Persists a deletion barrier synchronously before asynchronous file work
  /// begins. New model instances must treat the archive as empty while set.
  func beginDeletion()
  func deleteAllAndRotateIdentity() async throws -> BaselineDeletionReceipt
}

@MainActor
final class LocalBaselineStore: BaselineStore {
  private enum Keys {
    static let participantID = "sober.research.participant-id"
    static let deletionPending = "sober.baseline.deletion-pending"
    static let legacyCachedCount = "sober.baseline.sessions"
  }

  private let defaults: UserDefaults
  private let archive: ResearchSessionStore
  private let makeParticipantID: () -> PseudonymousParticipantID

  private(set) var participantID: PseudonymousParticipantID
  private(set) var stateRevision: UInt64 = 0

  var deletionPending: Bool {
    defaults.bool(forKey: Keys.deletionPending)
  }

  init(
    defaults: UserDefaults = .standard,
    archive: ResearchSessionStore = ResearchSessionStore(),
    makeParticipantID: @escaping () -> PseudonymousParticipantID = {
      PseudonymousParticipantID.generate()
    }
  ) {
    self.defaults = defaults
    self.archive = archive
    self.makeParticipantID = makeParticipantID

    if let rawValue = defaults.string(forKey: Keys.participantID) {
      participantID = PseudonymousParticipantID(rawValue: rawValue)
    } else {
      let generated = makeParticipantID()
      participantID = generated
      defaults.set(generated.rawValue, forKey: Keys.participantID)
    }

    // This was only a display cache. Keeping it allowed state without records
    // to survive deletion and appear measured after a relaunch.
    defaults.removeObject(forKey: Keys.legacyCachedCount)
  }

  func list() async throws -> [ResearchSessionEnvelope] {
    guard !deletionPending else { return [] }
    return try await archive.list()
  }

  func append(_ session: ResearchSessionEnvelope) async throws {
    guard !deletionPending else { throw BaselineStoreError.deletionPending }
    try await archive.append(session)
    stateRevision &+= 1
  }

  func delete(sessionID: ResearchSessionID) async throws -> Bool {
    guard !deletionPending else { throw BaselineStoreError.deletionPending }
    let deleted = try await archive.delete(sessionID: sessionID)
    if deleted { stateRevision &+= 1 }
    return deleted
  }

  func exportData(exportedAt: Date = Date()) async throws -> Data {
    guard !deletionPending else { throw BaselineStoreError.deletionPending }
    return try await archive.exportData(exportedAt: exportedAt)
  }

  func beginDeletion() {
    guard !deletionPending else { return }
    defaults.set(true, forKey: Keys.deletionPending)
    stateRevision &+= 1
  }

  func deleteAllAndRotateIdentity() async throws -> BaselineDeletionReceipt {
    beginDeletion()

    // The barrier intentionally remains set if deletion fails. That preserves
    // the data for recovery without allowing it to silently restore readiness.
    let deletedCount = try await archive.deleteAll()
    let replacement = makeParticipantID()
    participantID = replacement
    defaults.set(replacement.rawValue, forKey: Keys.participantID)
    defaults.removeObject(forKey: Keys.deletionPending)
    stateRevision &+= 1

    return BaselineDeletionReceipt(
      deletedSessionCount: deletedCount,
      participantID: replacement
    )
  }
}

struct PrivacySnapshot: Equatable, Sendable {
  var researchConsent: Bool
  var researchPreferences: ResearchPreferences
  var safetyPlan: SafetyPlan
  var userProfile: UserProfile
}

/// Owns app-local consent, profile, and safety-plan persistence. Privacy Lock
/// state will join this boundary during the integration pass.
@MainActor
protocol PrivacyStore: AnyObject {
  func load() -> PrivacySnapshot
  func saveResearchConsent(_ isGranted: Bool)
  func saveResearchPreferences(_ preferences: ResearchPreferences)
  func saveSafetyPlan(_ plan: SafetyPlan)
  func saveUserProfile(_ profile: UserProfile)
  func recordConsent(version: String, at date: Date)
  func reset()
}

@MainActor
final class UserDefaultsPrivacyStore: PrivacyStore {
  private enum Keys {
    static let researchConsent = "sober.research.consent"
    static let researchPreferences = "sober.research.preferences"
    static let safetyPlan = "sober.safety.plan"
    static let userProfile = "sober.user.profile"
    static let consentVersion = "sober.consent.version"
    static let consentDate = "sober.consent.date"
  }

  private let defaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> PrivacySnapshot {
    PrivacySnapshot(
      researchConsent: defaults.bool(forKey: Keys.researchConsent),
      researchPreferences: decode(ResearchPreferences.self, forKey: Keys.researchPreferences)
        ?? ResearchPreferences(),
      safetyPlan: decode(SafetyPlan.self, forKey: Keys.safetyPlan) ?? SafetyPlan(),
      userProfile: decode(UserProfile.self, forKey: Keys.userProfile) ?? UserProfile()
    )
  }

  func saveResearchConsent(_ isGranted: Bool) {
    defaults.set(isGranted, forKey: Keys.researchConsent)
  }

  func saveResearchPreferences(_ preferences: ResearchPreferences) {
    encode(preferences, forKey: Keys.researchPreferences)
  }

  func saveSafetyPlan(_ plan: SafetyPlan) {
    encode(plan, forKey: Keys.safetyPlan)
  }

  func saveUserProfile(_ profile: UserProfile) {
    encode(profile, forKey: Keys.userProfile)
  }

  func recordConsent(version: String, at date: Date) {
    defaults.set(version, forKey: Keys.consentVersion)
    defaults.set(date, forKey: Keys.consentDate)
  }

  func reset() {
    for key in [
      Keys.researchConsent,
      Keys.researchPreferences,
      Keys.safetyPlan,
      Keys.userProfile,
      Keys.consentVersion,
      Keys.consentDate,
    ] {
      defaults.removeObject(forKey: key)
    }
  }

  private func decode<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? decoder.decode(type, from: data)
  }

  private func encode<Value: Encodable>(_ value: Value, forKey key: String) {
    guard let data = try? encoder.encode(value) else { return }
    defaults.set(data, forKey: key)
  }
}
