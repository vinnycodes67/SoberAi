import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
  @Published var hasCompletedOnboarding: Bool
  @Published var baselineSessions: Int
  @Published var isFounderPreview: Bool
  @Published var researchConsent: Bool {
    didSet { defaults.set(researchConsent, forKey: Keys.researchConsent) }
  }
  @Published var researchPreferences: ResearchPreferences {
    didSet {
      if let data = try? JSONEncoder().encode(researchPreferences) {
        defaults.set(data, forKey: Keys.researchPreferences)
      }
    }
  }
  @Published private(set) var researchSessions: [ResearchSessionEnvelope] = []
  @Published private(set) var baselineProfile: BaselineProfileSummary?
  @Published private(set) var baselineVariantBreakdown: [OcularProtocolVariant: BaselineProfileSummary] = [:]
  @Published private(set) var researchDataError: String?
  @Published private(set) var lastExportURL: URL?
  @Published private(set) var guardianSession: GuardianSession?
  @Published private(set) var guardianRelationship: GuardianRelationshipSnapshot?
  @Published private(set) var guardianActiveAlert: GuardianAlertSnapshot?
  @Published private(set) var guardianAlertState: GuardianAlertPresentationState = .notRequired
  @Published private(set) var guardianError: String?
  @Published private(set) var guardianIsWorking = false
  @Published var safetyPlan: SafetyPlan {
    didSet {
      if let data = try? JSONEncoder().encode(safetyPlan) {
        defaults.set(data, forKey: Keys.safetyPlan)
      }
    }
  }

  /// App-local identity. Deliberately never passed to `ResearchSessionEnvelope`.
  @Published var userProfile: UserProfile {
    didSet {
      if let data = try? JSONEncoder().encode(userProfile) {
        defaults.set(data, forKey: Keys.userProfile)
      }
    }
  }

  @Published private(set) var participantID: PseudonymousParticipantID

  private let defaults: UserDefaults
  private let researchStore: ResearchSessionStore
  private let guardianStore: any GuardianSessionStoring
  private let guardianAPI: GuardianAPIClient
  private let baselineEngine = BaselineProfileEngine()

  init(
    defaults: UserDefaults = .standard,
    researchStore: ResearchSessionStore = ResearchSessionStore(),
    guardianStore: any GuardianSessionStoring = KeychainGuardianSessionStore(),
    guardianAPI: GuardianAPIClient = GuardianAPIClient()
  ) {
    self.defaults = defaults
    self.researchStore = researchStore
    self.guardianStore = guardianStore
    self.guardianAPI = guardianAPI
    hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
    let storedBaselineSessions = defaults.integer(forKey: Keys.baselines)
    let storedFounderPreview = defaults.bool(forKey: Keys.founderPreview)
    baselineSessions = storedFounderPreview ? max(storedBaselineSessions, 5) : storedBaselineSessions
    isFounderPreview = storedFounderPreview
    researchConsent = defaults.bool(forKey: Keys.researchConsent)

    if let rawParticipantID = defaults.string(forKey: Keys.participantID) {
      participantID = PseudonymousParticipantID(rawValue: rawParticipantID)
    } else {
      let generated = PseudonymousParticipantID.generate()
      participantID = generated
      defaults.set(generated.rawValue, forKey: Keys.participantID)
    }

    if let data = defaults.data(forKey: Keys.researchPreferences),
      let preferences = try? JSONDecoder().decode(ResearchPreferences.self, from: data)
    {
      researchPreferences = preferences
    } else {
      researchPreferences = ResearchPreferences()
    }

    if let data = defaults.data(forKey: Keys.safetyPlan),
      let storedPlan = try? JSONDecoder().decode(SafetyPlan.self, from: data)
    {
      safetyPlan = storedPlan
    } else {
      safetyPlan = SafetyPlan()
    }

    if let data = defaults.data(forKey: Keys.userProfile),
      let storedProfile = try? JSONDecoder().decode(UserProfile.self, from: data)
    {
      userProfile = storedProfile
    } else {
      userProfile = UserProfile()
    }

    guardianSession = try? guardianStore.load()

    Task {
      await reloadResearchData()
      if guardianSession != nil { await refreshGuardian() }
    }
  }

  var baselineReady: Bool {
    isFounderPreview || (baselineVariantBreakdown.values.map(\.eligibleSessionCount).max() ?? baselineSessions) >= 5
  }

  var guardianRelationshipIsActive: Bool {
    guardianRelationship?.state == .active
  }

  var guardianInviteCode: String? { guardianSession?.inviteCode }

  func createGuardianRelationship() async {
    guard guardianSession == nil else { return }
    guardianIsWorking = true
    guardianError = nil
    defer { guardianIsWorking = false }
    do {
      let displayName = userProfile.trimmedName.isEmpty ? "Your person" : userProfile.trimmedName
      let setup = try await guardianAPI.createRelationship(personDisplayName: displayName)
      guardianSession = setup.session
      guardianRelationship = setup.relationship
      try guardianStore.save(setup.session)
    } catch {
      guardianError = error.localizedDescription
    }
  }

  func joinGuardianRelationship(inviteCode: String) async {
    guard guardianSession == nil else { return }
    guardianIsWorking = true
    guardianError = nil
    defer { guardianIsWorking = false }
    do {
      let setup = try await guardianAPI.redeem(inviteCode: inviteCode)
      guardianSession = setup.session
      guardianRelationship = setup.relationship
      try guardianStore.save(setup.session)
      await refreshGuardian()
    } catch GuardianAPIError.relationshipUnavailable {
      guardianRelationship = nil
      guardianActiveAlert = nil
      guardianAlertState = .notRequired
      guardianError = GuardianAPIError.relationshipUnavailable.localizedDescription
    } catch {
      guardianError = error.localizedDescription
    }
  }

  func refreshGuardian() async {
    guard let session = guardianSession else { return }
    do {
      let envelope = try await guardianAPI.relationship(for: session)
      guard guardianRelationship == nil
        || envelope.relationship.relationshipId == guardianRelationship?.relationshipId
      else { return }
      guardianRelationship = envelope.relationship
      guardianActiveAlert = envelope.activeAlert
      if let alert = envelope.activeAlert {
        applyGuardianAlert(alert)
      }
      guardianError = nil
    } catch GuardianAPIError.relationshipUnavailable {
      guardianRelationship = nil
      guardianActiveAlert = nil
      guardianAlertState = .notRequired
      guardianError = GuardianAPIError.relationshipUnavailable.localizedDescription
    } catch {
      guardianError = error.localizedDescription
    }
  }

  func beginConcerningGuardianAlert(eventID: UUID = UUID(), occurredAt: Date = Date()) async {
    guard var session = guardianSession,
      session.role == .person,
      guardianRelationshipIsActive
    else {
      guardianAlertState = .notConfigured
      return
    }
    let stableEventID = session.activeEventID ?? eventID.uuidString.lowercased()
    session.activeEventID = stableEventID
    guardianSession = session
    try? guardianStore.save(session)
    guardianAlertState = .requestingHelp
    do {
      let envelope = try await guardianAPI.submitAlert(
        session: session,
        eventID: stableEventID,
        occurredAt: occurredAt
      )
      guardianActiveAlert = envelope.alert
      applyGuardianAlert(envelope.alert)
      guardianError = nil
    } catch GuardianAPIError.relationshipUnavailable {
      guardianRelationship = nil
      guardianActiveAlert = nil
      guardianAlertState = .actNow
      guardianError = GuardianAPIError.relationshipUnavailable.localizedDescription
    } catch {
      guardianAlertState = .actNow
      guardianError = error.localizedDescription
    }
  }

  func reconcileActiveGuardianAlert() async {
    guard let session = guardianSession,
      let eventID = session.activeEventID,
      session.role == .person
    else { return }
    do {
      let envelope = try await guardianAPI.alert(session: session, eventID: eventID)
      guardianActiveAlert = envelope.alert
      applyGuardianAlert(envelope.alert)
      guardianError = nil
    } catch GuardianAPIError.relationshipUnavailable {
      guardianRelationship = nil
      guardianActiveAlert = nil
      guardianAlertState = .actNow
      guardianError = GuardianAPIError.relationshipUnavailable.localizedDescription
    } catch {
      guardianAlertState = .actNow
      guardianError = error.localizedDescription
    }
  }

  func acknowledgeGuardianAlert() async {
    guard let session = guardianSession,
      session.role == .guardian,
      let eventID = guardianActiveAlert?.canonicalEventId
    else { return }
    guardianIsWorking = true
    defer { guardianIsWorking = false }
    do {
      let envelope = try await guardianAPI.acknowledge(session: session, eventID: eventID)
      guardianActiveAlert = envelope.alert
      applyGuardianAlert(envelope.alert)
      guardianError = nil
    } catch GuardianAPIError.relationshipUnavailable {
      guardianRelationship = nil
      guardianActiveAlert = nil
      guardianError = GuardianAPIError.relationshipUnavailable.localizedDescription
    } catch {
      guardianError = error.localizedDescription
    }
  }

  func revokeGuardianRelationship() async {
    guard let session = guardianSession else { return }
    guardianIsWorking = true
    defer { guardianIsWorking = false }
    do {
      try await guardianAPI.revoke(session: session)
      try guardianStore.delete()
      guardianSession = nil
      guardianRelationship = nil
      guardianActiveAlert = nil
      guardianAlertState = .notRequired
      guardianError = nil
    } catch GuardianAPIError.relationshipUnavailable {
      try? guardianStore.delete()
      guardianSession = nil
      guardianRelationship = nil
      guardianActiveAlert = nil
      guardianAlertState = .notRequired
      guardianError = nil
    } catch {
      guardianError = error.localizedDescription
    }
  }

  func presentGuardianSample(for outcome: ScreeningOutcome) {
    guardianAlertState = outcome.state == .signalsDetected ? .preview : .notRequired
  }

  func clearGuardianAlertPresentation() {
    guardianAlertState = .notRequired
  }

  func prepareGuardianForNewCheck() {
    guard var session = guardianSession, session.role == .person else {
      guardianAlertState = .notRequired
      return
    }
    session.activeEventID = nil
    guardianSession = session
    try? guardianStore.save(session)
    guardianActiveAlert = nil
    guardianAlertState = .notRequired
  }

  private func applyGuardianAlert(_ alert: GuardianAlertSnapshot) {
    switch alert.personActionState {
    case .requestingHelp:
      guardianAlertState = .requestingHelp
    case .guardianConfirmed:
      guardianAlertState = .guardianConfirmed
    case .actNow, .unknown:
      guardianAlertState = .actNow
    }
  }

  func completeOnboarding(founderPreview: Bool) {
    isFounderPreview = founderPreview
    hasCompletedOnboarding = true
    if founderPreview {
      baselineSessions = 5
    }
    defaults.set("prototype-v2", forKey: Keys.consentVersion)
    defaults.set(Date(), forKey: Keys.consentDate)
    persist()
  }

  /// Legacy counter path retained for previews. Live baseline flows use
  /// `recordCompletedSession` so eligibility comes from stored measurements.
  func recordBaseline() {
    baselineSessions = min(baselineSessions + 1, 5)
    persist()
  }

  func recordCompletedSession(
    mode: ScreeningMode,
    selfReport: SelfReport,
    metrics: ScreeningMetrics,
    reactionSummary: ChoiceReactionSummary?,
    ocularSummary: GazeCaptureSummary?,
    startedAt: Date
  ) async {
    guard mode == .baseline || researchConsent else { return }

    let quality = ocularSummary?.quality
    let preferences = researchPreferences
    let context = ResearchSessionContext(
      sessionKind: mode == .baseline ? .soberBaseline : .screeningCheck,
      soberAtStartAttested: mode == .baseline ? true : nil,
      reportedAlcoholUse: selfReport == .unsure ? nil : selfReport == .yes,
      reportedCannabisUse: nil,
      reportedOtherSubstanceUse: nil,
      sleepHours: preferences.sleepHours,
      caffeineWithinSixHours: preferences.caffeineWithinSixHours,
      medicationMayAffectPerformance: preferences.medicationMayAffectPerformance,
      illnessOrInjuryMayAffectPerformance: preferences.illnessOrInjuryMayAffectPerformance,
      strenuousExerciseWithinTwoHours: preferences.strenuousExerciseWithinTwoHours,
      visionCorrection: preferences.visionCorrection,
      ambientLighting: quality.map { $0.lightingAcceptable ? .moderate : .dim } ?? .unknown
    )

    // Duration comes from the samples that were actually retained. A skipped or
    // unsupported ocular task must never be archived as a completed capture.
    let ocularQuality = ocularSummary.map { summary in
      ResearchOcularQuality(
        faceTrackingAvailable: summary.quality.isSupported,
        cameraPermissionGranted: summary.quality.hasCameraPermission,
        sampleCount: summary.quality.sampleCount,
        trackingDurationMilliseconds: summary.capturedDurationMilliseconds,
        trackingCoverage: 1 - summary.quality.dropoutRatio,
        facePresentAtCompletion: summary.quality.facePresent,
        headStableAtCompletion: summary.quality.headStable,
        lightingAcceptableAtCompletion: summary.quality.lightingAcceptable,
        glareDetected: nil,
        meanFrameRate: summary.quality.frameRate,
        signalQualityScore: summary.quality.score
      )
    }

    let envelope = ResearchSessionEnvelope(
      participantID: participantID,
      startedAt: startedAt,
      completedAt: Date(),
      metadata: ResearchSessionMetadata(
        device: .current(),
        app: .current(),
        protocolMetadata: ResearchProtocolMetadata(
          name: "Sober Research Battery",
          version: "0.2"
        )
      ),
      context: context,
      metrics: ResearchScreeningMetrics(metrics),
      choiceReaction: reactionSummary,
      ocularSummary: ocularSummary,
      ocularQuality: ocularQuality,
      breathReference: nil,
      protocolVariant: ocularSummary?.protocolVariant ?? .full
    )

    do {
      try await researchStore.append(envelope)
      await reloadResearchData()
    } catch {
      researchDataError = error.localizedDescription
    }
  }

  func reloadResearchData() async {
    do {
      let sessions = try await researchStore.list()
      researchSessions = sessions
      baselineProfile = baselineEngine.summarize(
        participantID: participantID,
        sessions: sessions,
        protocolVariant: .full
      )
      baselineVariantBreakdown = [
        .full: baselineEngine.summarize(participantID: participantID, sessions: sessions, protocolVariant: .full),
        .reducedMotion: baselineEngine.summarize(participantID: participantID, sessions: sessions, protocolVariant: .reducedMotion)
      ]
      if !isFounderPreview {
        baselineSessions = max(
          baselineVariantBreakdown.values.map(\.eligibleSessionCount).max() ?? 0,
          baselineProfile?.eligibleSessionCount ?? 0
        )
        persist()
      }
      researchDataError = nil
    } catch {
      researchDataError = error.localizedDescription
    }
  }

  func prepareResearchExport() async -> URL? {
    guard researchConsent else { return nil }
    do {
      let data = try await researchStore.exportData()
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sober-research-export-\(participantID.rawValue).json")
      try data.write(to: url, options: .atomic)
      #if os(iOS)
      try? FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: url.path
      )
      #endif
      lastExportURL = url
      researchDataError = nil
      return url
    } catch {
      researchDataError = error.localizedDescription
      return nil
    }
  }

  /// Deletes the local archive *and* any export file already written to the
  /// temporary directory. Leaving the export behind would keep data the user
  /// was told is gone readable on the device.
  func deleteAllResearchData() async {
    do {
      _ = try await researchStore.deleteAll()
      discardPreparedExport()
      rotateParticipantID()
      baselineSessions = isFounderPreview ? 5 : 0
      await reloadResearchData()
    } catch {
      researchDataError = error.localizedDescription
    }
  }

  func discardPreparedExport() {
    guard let lastExportURL else { return }
    try? FileManager.default.removeItem(at: lastExportURL)
    self.lastExportURL = nil
  }

  private func rotateParticipantID() {
    let replacement = PseudonymousParticipantID.generate()
    participantID = replacement
    defaults.set(replacement.rawValue, forKey: Keys.participantID)
  }

  func resetPrototype() {
    hasCompletedOnboarding = false
    baselineSessions = 0
    isFounderPreview = false
    researchConsent = false
    researchPreferences = ResearchPreferences()
    safetyPlan = SafetyPlan()
    userProfile = UserProfile()
    defaults.removeObject(forKey: Keys.userProfile)
    defaults.removeObject(forKey: Keys.onboarding)
    defaults.removeObject(forKey: Keys.baselines)
    defaults.removeObject(forKey: Keys.founderPreview)
    defaults.removeObject(forKey: Keys.safetyPlan)
    defaults.removeObject(forKey: Keys.consentVersion)
    defaults.removeObject(forKey: Keys.consentDate)
    defaults.removeObject(forKey: Keys.researchConsent)
    defaults.removeObject(forKey: Keys.researchPreferences)
    try? guardianStore.delete()
    guardianSession = nil
    guardianRelationship = nil
    guardianActiveAlert = nil
    guardianAlertState = .notRequired
    guardianError = nil
    Task { await deleteAllResearchData() }
  }

  private func persist() {
    defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding)
    defaults.set(baselineSessions, forKey: Keys.baselines)
    defaults.set(isFounderPreview, forKey: Keys.founderPreview)
  }

  private enum Keys {
    static let onboarding = "sober.onboarding.complete"
    static let baselines = "sober.baseline.sessions"
    static let founderPreview = "sober.founder.preview"
    static let safetyPlan = "sober.safety.plan"
    static let consentVersion = "sober.consent.version"
    static let consentDate = "sober.consent.date"
    static let participantID = "sober.research.participant-id"
    static let researchConsent = "sober.research.consent"
    static let researchPreferences = "sober.research.preferences"
    static let userProfile = "sober.user.profile"
  }
}
