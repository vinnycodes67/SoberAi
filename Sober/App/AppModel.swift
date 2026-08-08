import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
  @Published var hasCompletedOnboarding: Bool
  /// The number of *measured* eligible baseline sessions. This is always the
  /// truth on disk; the founder preview never inflates it.
  @Published var baselineSessions: Int
  /// Only ever true in an `INTERNAL_BUILD`. Writes are clamped by
  /// `allowsInternalTools`, so a public binary cannot enter this state even if a
  /// stale `UserDefaults` value survives an upgrade from an internal build.
  @Published private(set) var isFounderPreview: Bool
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
  @Published private(set) var guardianCheckInPlan: GuardianCheckInPlanSnapshot?
  @Published private(set) var guardianCheckInEvaluation: GuardianCheckInEvaluation = .inactive
  @Published private(set) var guardianHomeAnchor: GuardianHomeAnchor?
  @Published private(set) var guardianLocationSharing: GuardianLocationSharingSnapshot?
  @Published private(set) var guardianLocalLocation: GuardianLiveLocationUpdate?
  @Published private(set) var guardianLocationAuthorization: GuardianLocationAuthorizationState = .notDetermined
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

  /// Compile-time capability gate. Injectable so tests can exercise both the
  /// public and internal behaviours from a single (Debug) test run.
  let allowsInternalTools: Bool
  private let defaults: UserDefaults
  private let researchStore: ResearchSessionStore
  private let guardianStore: any GuardianSessionStoring
  private let guardianAPI: GuardianAPIClient
  private let guardianHomeStore: any GuardianHomeStoring
  private let guardianLocation: any GuardianLocationProviding
  private let guardianCheckInScheduler: any GuardianCheckInScheduling
  private let guardianLiveLocation: any GuardianLiveLocationProviding
  private let baselineEngine = BaselineProfileEngine()
  private var guardianLocationPublishIsInFlight = false
  private var lastGuardianLocationPublishedAt: Date?

  init(
    defaults: UserDefaults = .standard,
    researchStore: ResearchSessionStore = ResearchSessionStore(),
    guardianStore: any GuardianSessionStoring = KeychainGuardianSessionStore(),
    guardianAPI: GuardianAPIClient = GuardianAPIClient(),
    guardianHomeStore: any GuardianHomeStoring = KeychainGuardianHomeStore(),
    guardianLocation: any GuardianLocationProviding = GuardianLocationService(),
    guardianCheckInScheduler: any GuardianCheckInScheduling = SystemGuardianCheckInScheduler(),
    guardianLiveLocation: any GuardianLiveLocationProviding = GuardianLiveLocationService(),
    automaticallyStartsGuardianServices: Bool = BuildChannel.allowsInternalTools,
    allowsInternalTools: Bool = BuildChannel.allowsInternalTools
  ) {
    self.allowsInternalTools = allowsInternalTools
    self.defaults = defaults
    self.researchStore = researchStore
    self.guardianStore = guardianStore
    self.guardianAPI = guardianAPI
    self.guardianHomeStore = guardianHomeStore
    self.guardianLocation = guardianLocation
    self.guardianCheckInScheduler = guardianCheckInScheduler
    self.guardianLiveLocation = guardianLiveLocation
    hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
    // `baselineSessions` is the measured count and nothing else. Inflating it
    // here made a demo state indistinguishable from a real one on disk, and it
    // survived "delete all data".
    baselineSessions = defaults.integer(forKey: Keys.baselines)
    // A public binary ignores a persisted founder flag rather than trusting it,
    // so an internal build that is later replaced by an App Store build cannot
    // leave the user stranded in the demo state.
    isFounderPreview = allowsInternalTools && defaults.bool(forKey: Keys.founderPreview)
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

    do {
      guardianSession = try guardianStore.load()
    } catch {
      guardianSession = nil
      guardianError = "Guardian setup could not be loaded from this iPhone."
    }
    do {
      guardianHomeAnchor = try guardianHomeStore.load()
    } catch {
      guardianHomeAnchor = nil
      guardianError = "Your private Home location could not be loaded from this iPhone."
    }

    if automaticallyStartsGuardianServices {
      guardianLocationAuthorization = guardianLiveLocation.authorizationState
      guardianLiveLocation.onAuthorizationChange = { [weak self] state in
        self?.guardianLocationAuthorization = state
      }
      guardianLiveLocation.onLocation = { [weak self] update in
        guard let self else { return }
        self.guardianLocalLocation = update
        Task { await self.publishGuardianLocation(update) }
      }
      if guardianSession?.role == .person,
        defaults.bool(forKey: Keys.guardianLocationSharingEnabled)
      {
        guardianLiveLocation.resumeIfAuthorized()
      }
    }

    Task {
      await reloadResearchData()
      if automaticallyStartsGuardianServices, guardianSession != nil { await refreshGuardian() }
    }
  }

  /// True once the person has enough *measured* eligible sessions to be
  /// compared against their own steady.
  ///
  /// The founder preview may short-circuit this, but only in an internal build.
  /// In a public build this is a function of measured data alone — the UI must
  /// never claim a personal baseline exists while `ScreeningEngine` is silently
  /// scoring against population norms.
  var baselineReady: Bool {
    if allowsInternalTools, isFounderPreview { return true }
    return measuredEligibleSessions >= 5
  }

  /// The best eligible-session count across protocol variants, falling back to
  /// the persisted count before research data has loaded.
  var measuredEligibleSessions: Int {
    baselineVariantBreakdown.values.map(\.eligibleSessionCount).max() ?? baselineSessions
  }

  func personalBaseline(for protocolVariant: OcularProtocolVariant) -> PersonalBaseline? {
    baselineEngine.personalBaseline(
      participantID: participantID,
      sessions: researchSessions,
      protocolVariant: protocolVariant
    )
  }

  var guardianRelationshipIsActive: Bool {
    guardianRelationship?.state == .active
  }

  var guardianInviteCode: String? { guardianSession?.inviteCode }

  var guardianLocationSharingIsEnabled: Bool {
    guardianLocationSharing?.enabled == true
      && defaults.bool(forKey: Keys.guardianLocationSharingEnabled)
      && !defaults.bool(forKey: Keys.pendingGuardianLocationDisable)
  }

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
      if session.role == .person,
        defaults.bool(forKey: Keys.pendingGuardianLocationDisable)
      {
        let disabled = try await guardianAPI.setLocationSharing(session: session, enabled: false)
        guardianLocationSharing = disabled.locationSharing
        defaults.set(false, forKey: Keys.pendingGuardianLocationDisable)
      }
      let envelope = try await guardianAPI.relationship(for: session)
      guard guardianRelationship == nil
        || envelope.relationship.relationshipId == guardianRelationship?.relationshipId
      else { return }
      guardianRelationship = envelope.relationship
      guardianActiveAlert = envelope.activeAlert
      guardianCheckInPlan = envelope.checkInPlan
      guardianLocationSharing = envelope.locationSharing
      syncGuardianLiveLocationService(for: session)
      refreshGuardianCheckInEvaluation()
      await retryPendingGuardianCheckInCompletion()
      if let alert = envelope.activeAlert {
        applyGuardianAlert(alert)
      } else if session.activeEventID != nil {
        clearStaleGuardianAlert(requiresDirectAction: false)
        return
      }
      guardianError = nil
    } catch GuardianAPIError.relationshipUnavailable {
      guardianLiveLocation.stopSharing()
      defaults.set(false, forKey: Keys.guardianLocationSharingEnabled)
      guardianRelationship = nil
      guardianActiveAlert = nil
      guardianLocationSharing = nil
      guardianLocalLocation = nil
      guardianAlertState = .notRequired
      guardianError = GuardianAPIError.relationshipUnavailable.localizedDescription
    } catch {
      guardianError = error.localizedDescription
    }
  }

  private func clearStaleGuardianAlert(requiresDirectAction: Bool) {
    if var session = guardianSession {
      session.activeEventID = nil
      guardianSession = session
      do {
        try guardianStore.save(session)
      } catch {
        guardianError = "The expired request was cleared, but Sober could not save that change."
        guardianAlertState = requiresDirectAction ? .actNow : .notRequired
        guardianActiveAlert = nil
        return
      }
    }
    guardianActiveAlert = nil
    guardianAlertState = requiresDirectAction ? .actNow : .notRequired
    guardianError = requiresDirectAction
      ? "The Guardian request expired. Contact someone directly if you still need help."
      : nil
  }

  func enableGuardianLocationSharing() async {
    guard let session = guardianSession,
      session.role == .person,
      guardianRelationshipIsActive
    else { return }
    guardianIsWorking = true
    guardianError = nil
    defer { guardianIsWorking = false }
    do {
      let envelope = try await guardianAPI.setLocationSharing(session: session, enabled: true)
      guardianLocationSharing = envelope.locationSharing
      defaults.set(true, forKey: Keys.guardianLocationSharingEnabled)
      defaults.set(false, forKey: Keys.pendingGuardianLocationDisable)
      guardianLiveLocation.startForegroundSharing()
    } catch {
      guardianError = error.localizedDescription
    }
  }

  func requestGuardianBackgroundLocationAccess() {
    guard guardianSession?.role == .person, guardianLocationSharingIsEnabled else { return }
    guardianLiveLocation.requestBackgroundAccess()
  }

  func stopGuardianLocationSharing() async {
    guard let session = guardianSession, session.role == .person else { return }
    guardianLiveLocation.stopSharing()
    defaults.set(false, forKey: Keys.guardianLocationSharingEnabled)
    defaults.set(true, forKey: Keys.pendingGuardianLocationDisable)
    guardianIsWorking = true
    guardianError = nil
    defer { guardianIsWorking = false }
    do {
      let envelope = try await guardianAPI.setLocationSharing(session: session, enabled: false)
      guardianLocationSharing = envelope.locationSharing
      guardianLocalLocation = nil
      defaults.set(false, forKey: Keys.pendingGuardianLocationDisable)
    } catch {
      guardianError = "Sharing stopped on this iPhone. Sober will remove the last map location when it reconnects."
    }
  }

  private func publishGuardianLocation(_ update: GuardianLiveLocationUpdate) async {
    guard let session = guardianSession,
      session.role == .person,
      guardianLocationSharingIsEnabled,
      update.coordinate.horizontalAccuracy >= 0,
      update.coordinate.horizontalAccuracy <= 1_000,
      !guardianLocationPublishIsInFlight
    else { return }
    if let lastGuardianLocationPublishedAt,
      update.capturedAt.timeIntervalSince(lastGuardianLocationPublishedAt) < 10
    { return }

    guardianLocationPublishIsInFlight = true
    defer { guardianLocationPublishIsInFlight = false }
    do {
      let envelope = try await guardianAPI.publishLocation(
        session: session,
        coordinate: update.coordinate,
        capturedAt: update.capturedAt
      )
      guardianLocationSharing = envelope.locationSharing
      lastGuardianLocationPublishedAt = update.capturedAt
      guardianError = nil
    } catch {
      // A later Core Location update retries naturally; never invent freshness.
    }
  }

  private func syncGuardianLiveLocationService(for session: GuardianSession) {
    guard session.role == .person else { return }
    let pendingDisable = defaults.bool(forKey: Keys.pendingGuardianLocationDisable)
    if guardianLocationSharing?.enabled == true && !pendingDisable {
      defaults.set(true, forKey: Keys.guardianLocationSharingEnabled)
      guardianLiveLocation.resumeIfAuthorized()
    } else {
      defaults.set(false, forKey: Keys.guardianLocationSharingEnabled)
      guardianLiveLocation.stopSharing()
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
    } catch GuardianAPIError.alertUnavailable {
      // The relay deliberately returns the same 404 for a missing alert and
      // an unavailable relationship. Probe the signed relationship endpoint
      // before clearing local state so a revoked relationship is not mistaken
      // for an expired alert.
      do {
        let envelope = try await guardianAPI.relationship(for: session)
        guardianRelationship = envelope.relationship
        guardianCheckInPlan = envelope.checkInPlan
        guardianLocationSharing = envelope.locationSharing
        clearStaleGuardianAlert(requiresDirectAction: true)
      } catch GuardianAPIError.relationshipUnavailable {
        guardianRelationship = nil
        guardianActiveAlert = nil
        guardianAlertState = .actNow
        guardianError = GuardianAPIError.relationshipUnavailable.localizedDescription
      } catch {
        guardianAlertState = .actNow
        guardianError = error.localizedDescription
      }
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

  var guardianHomeIsConfigured: Bool { guardianHomeAnchor != nil }

  func proposeGuardianCheckIn(
    at time: Date,
    condition: GuardianCheckInCondition,
    graceMinutes: Int = 15
  ) async {
    guard let session = guardianSession, session.role == .guardian,
      guardianRelationshipIsActive
    else { return }
    let components = Calendar.current.dateComponents([.hour, .minute], from: time)
    let localTime = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    guardianIsWorking = true
    guardianError = nil
    defer { guardianIsWorking = false }
    do {
      let envelope = try await guardianAPI.proposeCheckInPlan(
        session: session,
        localTime: localTime,
        timeZoneIdentifier: TimeZone.current.identifier,
        condition: condition,
        graceMinutes: graceMinutes
      )
      guardianCheckInPlan = envelope.checkInPlan
      refreshGuardianCheckInEvaluation()
    } catch {
      guardianError = error.localizedDescription
    }
  }

  func acceptGuardianCheckInPlan() async {
    guard let session = guardianSession, session.role == .person,
      let plan = guardianCheckInPlan,
      plan.state == .pendingPersonConsent
    else { return }
    guardianIsWorking = true
    guardianError = nil
    defer { guardianIsWorking = false }
    do {
      if plan.condition == .awayFromHome, guardianHomeAnchor == nil {
        try await captureGuardianHome()
      }
      let envelope = try await guardianAPI.decideCheckInPlan(
        session: session,
        version: plan.version,
        decision: "accept"
      )
      guardianCheckInPlan = envelope.checkInPlan
      let notificationsEnabled = try await guardianCheckInScheduler.schedule(plan: envelope.checkInPlan)
      if !notificationsEnabled {
        guardianError = "Check-in accepted. Enable Sober notifications in Settings for the reminder."
      }
      refreshGuardianCheckInEvaluation()
    } catch {
      guardianError = error.localizedDescription
    }
  }

  func declineGuardianCheckInPlan() async {
    guard let session = guardianSession, session.role == .person,
      let plan = guardianCheckInPlan,
      plan.state == .pendingPersonConsent || plan.state == .active
    else { return }
    guardianIsWorking = true
    guardianError = nil
    defer { guardianIsWorking = false }
    do {
      let envelope = try await guardianAPI.decideCheckInPlan(
        session: session,
        version: plan.version,
        decision: "decline"
      )
      guardianCheckInPlan = envelope.checkInPlan
      await guardianCheckInScheduler.cancel()
      refreshGuardianCheckInEvaluation()
    } catch {
      guardianError = error.localizedDescription
    }
  }

  func updateGuardianHome() async {
    guardianIsWorking = true
    guardianError = nil
    defer { guardianIsWorking = false }
    do {
      try await captureGuardianHome()
      refreshGuardianCheckInEvaluation()
    } catch {
      guardianError = error.localizedDescription
    }
  }

  func evaluateGuardianCheckInLocation() async {
    guard let anchor = guardianHomeAnchor else {
      refreshGuardianCheckInEvaluation()
      return
    }
    guardianIsWorking = true
    guardianError = nil
    defer { guardianIsWorking = false }
    do {
      let coordinate = try await guardianLocation.currentCoordinate()
      let distance = anchor.distance(to: coordinate)
      guardianCheckInEvaluation = GuardianCheckInDueEvaluator.evaluate(
        plan: guardianCheckInPlan,
        homeIsConfigured: true,
        distanceFromHomeMeters: distance,
        locationAccuracyMeters: coordinate.horizontalAccuracy
      )
    } catch {
      guardianError = error.localizedDescription
    }
  }

  func refreshGuardianCheckInEvaluation(now: Date = Date()) {
    guardianCheckInEvaluation = GuardianCheckInDueEvaluator.evaluate(
      plan: guardianCheckInPlan,
      now: now,
      homeIsConfigured: guardianHomeAnchor != nil
    )
  }

  func completeGuardianCheckIn(occurrenceID: String, at date: Date = Date()) async {
    guard let session = guardianSession, session.role == .person else { return }
    defaults.set(occurrenceID, forKey: Keys.pendingGuardianCheckInCompletionID)
    defaults.set(date, forKey: Keys.pendingGuardianCheckInCompletionDate)
    do {
      let envelope = try await guardianAPI.completeCheckIn(
        session: session,
        occurrenceID: occurrenceID,
        completedAt: date
      )
      guardianCheckInPlan = envelope.checkInPlan
      refreshGuardianCheckInEvaluation(now: date)
      clearPendingGuardianCheckInCompletion()
      guardianError = nil
    } catch {
      guardianError = "The check finished, but its completion hasn’t synced yet. Keep Sober open and try Refresh."
    }
  }

  private func retryPendingGuardianCheckInCompletion() async {
    guard let occurrenceID = defaults.string(forKey: Keys.pendingGuardianCheckInCompletionID),
      let completedAt = defaults.object(forKey: Keys.pendingGuardianCheckInCompletionDate) as? Date,
      let session = guardianSession,
      session.role == .person,
      guardianCheckInPlan?.state == .active
    else { return }
    do {
      let envelope = try await guardianAPI.completeCheckIn(
        session: session,
        occurrenceID: occurrenceID,
        completedAt: completedAt
      )
      guardianCheckInPlan = envelope.checkInPlan
      refreshGuardianCheckInEvaluation()
      clearPendingGuardianCheckInCompletion()
    } catch {
      // Keep the exact idempotent occurrence for the next foreground refresh.
    }
  }

  private func clearPendingGuardianCheckInCompletion() {
    defaults.removeObject(forKey: Keys.pendingGuardianCheckInCompletionID)
    defaults.removeObject(forKey: Keys.pendingGuardianCheckInCompletionDate)
  }

  private func captureGuardianHome() async throws {
    let coordinate = try await guardianLocation.currentCoordinate()
    guard coordinate.horizontalAccuracy >= 0, coordinate.horizontalAccuracy <= 100 else {
      throw GuardianLocationError.preciseLocationRequired
    }
    let anchor = GuardianHomeAnchor(
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
      savedAt: Date()
    )
    try guardianHomeStore.save(anchor)
    guardianHomeAnchor = anchor
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
      guardianCheckInPlan = nil
      guardianCheckInEvaluation = .inactive
      guardianLocationSharing = nil
      guardianLocalLocation = nil
      guardianAlertState = .notRequired
      guardianLiveLocation.stopSharing()
      defaults.set(false, forKey: Keys.guardianLocationSharingEnabled)
      defaults.set(false, forKey: Keys.pendingGuardianLocationDisable)
      await guardianCheckInScheduler.cancel()
      try? guardianHomeStore.delete()
      guardianHomeAnchor = nil
      guardianError = nil
    } catch GuardianAPIError.relationshipUnavailable {
      try? guardianStore.delete()
      guardianSession = nil
      guardianRelationship = nil
      guardianActiveAlert = nil
      guardianCheckInPlan = nil
      guardianCheckInEvaluation = .inactive
      guardianLocationSharing = nil
      guardianLocalLocation = nil
      guardianAlertState = .notRequired
      guardianLiveLocation.stopSharing()
      defaults.set(false, forKey: Keys.guardianLocationSharingEnabled)
      defaults.set(false, forKey: Keys.pendingGuardianLocationDisable)
      await guardianCheckInScheduler.cancel()
      try? guardianHomeStore.delete()
      guardianHomeAnchor = nil
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

  /// - Parameter founderPreview: honoured only in an `INTERNAL_BUILD`. A public
  ///   build always completes onboarding into the real-baseline path.
  func completeOnboarding(founderPreview: Bool) {
    isFounderPreview = allowsInternalTools && founderPreview
    hasCompletedOnboarding = true
    defaults.set("prototype-v2", forKey: Keys.consentVersion)
    defaults.set(Date(), forKey: Keys.consentDate)
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
      // Recompute unconditionally. Skipping this in the founder preview froze
      // the stored count, so real sessions recorded afterwards never counted.
      baselineSessions = max(
        baselineVariantBreakdown.values.map(\.eligibleSessionCount).max() ?? 0,
        baselineProfile?.eligibleSessionCount ?? 0
      )
      persist()
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
      baselineSessions = 0
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
    clearPendingGuardianCheckInCompletion()
    try? guardianStore.delete()
    try? guardianHomeStore.delete()
    guardianSession = nil
    guardianRelationship = nil
    guardianActiveAlert = nil
    guardianCheckInPlan = nil
    guardianCheckInEvaluation = .inactive
    guardianHomeAnchor = nil
    guardianLocationSharing = nil
    guardianLocalLocation = nil
    guardianAlertState = .notRequired
    guardianError = nil
    guardianLiveLocation.stopSharing()
    defaults.removeObject(forKey: Keys.guardianLocationSharingEnabled)
    defaults.removeObject(forKey: Keys.pendingGuardianLocationDisable)
    Task { await guardianCheckInScheduler.cancel() }
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
    static let pendingGuardianCheckInCompletionID = "sober.guardian.check-in.pending-id"
    static let pendingGuardianCheckInCompletionDate = "sober.guardian.check-in.pending-date"
    static let guardianLocationSharingEnabled = "sober.guardian.location-sharing.enabled"
    static let pendingGuardianLocationDisable = "sober.guardian.location-sharing.pending-disable"
  }
}
