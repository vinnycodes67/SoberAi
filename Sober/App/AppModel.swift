import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
  @Published var hasCompletedOnboarding: Bool
  @Published var baselineSessions: Int
  /// The person's own rolling sober-check baseline, used to z-score live
  /// checks in `ScreeningEngine`. Independent of `baselineSessions`, which
  /// tracks progress toward the separate research baseline.
  @Published var baseline: PersonalBaseline {
    didSet {
      if let data = try? JSONEncoder().encode(baseline) {
        defaults.set(data, forKey: Keys.baseline)
      }
    }
  }
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
  @Published var safetyPlan: SafetyPlan {
    didSet {
      if let data = try? JSONEncoder().encode(safetyPlan) {
        defaults.set(data, forKey: Keys.safetyPlan)
      }
    }
  }

  @Published private(set) var participantID: PseudonymousParticipantID

  private let defaults: UserDefaults
  private let researchStore: ResearchSessionStore
  private let baselineEngine = BaselineProfileEngine()

  init(
    defaults: UserDefaults = .standard,
    researchStore: ResearchSessionStore = ResearchSessionStore()
  ) {
    self.defaults = defaults
    self.researchStore = researchStore
    hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
    let storedBaselineSessions = defaults.integer(forKey: Keys.baselines)
    let storedFounderPreview = defaults.bool(forKey: Keys.founderPreview)
    baselineSessions = storedFounderPreview ? max(storedBaselineSessions, 5) : storedBaselineSessions
    isFounderPreview = storedFounderPreview
    researchConsent = defaults.bool(forKey: Keys.researchConsent)

    if let data = defaults.data(forKey: Keys.baseline),
      let storedBaseline = try? JSONDecoder().decode(PersonalBaseline.self, from: data)
    {
      baseline = storedBaseline
    } else {
      baseline = PersonalBaseline()
    }

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

    Task { await reloadResearchData() }
  }

  var baselineReady: Bool {
    isFounderPreview || (baselineVariantBreakdown.values.map(\.eligibleSessionCount).max() ?? baselineSessions) >= 5
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

  /// Records one sober session into the person's live-scoring baseline. This
  /// is independent of the research-baseline counter above.
  func recordBaseline(_ sample: BaselineSample) {
    baseline.record(sample)
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
    baseline = PersonalBaseline()
    isFounderPreview = false
    researchConsent = false
    researchPreferences = ResearchPreferences()
    safetyPlan = SafetyPlan()
    defaults.removeObject(forKey: Keys.onboarding)
    defaults.removeObject(forKey: Keys.baselines)
    defaults.removeObject(forKey: Keys.baseline)
    defaults.removeObject(forKey: Keys.founderPreview)
    defaults.removeObject(forKey: Keys.safetyPlan)
    defaults.removeObject(forKey: Keys.consentVersion)
    defaults.removeObject(forKey: Keys.consentDate)
    defaults.removeObject(forKey: Keys.researchConsent)
    defaults.removeObject(forKey: Keys.researchPreferences)
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
    static let baseline = "sober.baseline.data"
    static let founderPreview = "sober.founder.preview"
    static let safetyPlan = "sober.safety.plan"
    static let consentVersion = "sober.consent.version"
    static let consentDate = "sober.consent.date"
    static let participantID = "sober.research.participant-id"
    static let researchConsent = "sober.research.consent"
    static let researchPreferences = "sober.research.preferences"
  }
}
