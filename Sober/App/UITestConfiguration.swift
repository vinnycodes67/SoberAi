import Foundation

/// Deterministic launch state for UI tests.
///
/// A UI test that drives the real app's stored state is not deterministic: it
/// inherits whatever the last run left behind, and it writes into the same
/// `UserDefaults` and Application Support directories a person's data lives in.
/// Under `-sober-ui-testing` the app builds itself a throwaway defaults suite
/// and a throwaway data directory, then seeds exactly what the test asked for.
///
/// Compiled out of Release entirely. `isActive` is `false` there whatever the
/// arguments say, so a launch argument cannot be used to reset a real install.
enum UITestConfiguration {

  /// Creates the isolated app model used by the co-founder UI suites. Returning
  /// `nil` for a normal Debug launch keeps the production persistence path
  /// untouched. The baseline adapter is the same Phase 2 store used by the app,
  /// pointed at a throwaway archive rather than bypassed with a synthetic count.
  @MainActor
  static func makeModel() -> AppModel? {
    guard isActive, let directory = makeDataDirectory() else { return nil }

    let defaults = makeDefaults()
    seedHistory(in: directory)
    seedBaseline(in: directory, participantID: participantID)

    let soberDirectory = directory.appendingPathComponent("Sober", isDirectory: true)
    let researchArchive = ResearchSessionStore(
      directoryURL: soberDirectory.appendingPathComponent("Research", isDirectory: true)
    )
    let baselineStore = LocalBaselineStore(defaults: defaults, archive: researchArchive)

    return AppModel(
      defaults: defaults,
      baselineStore: baselineStore,
      checkHistoryStore: CheckHistoryStore(
        directoryURL: soberDirectory.appendingPathComponent("History", isDirectory: true)
      ),
      automaticallyStartsGuardianServices: false,
      allowsInternalTools: false
    )
  }

  static var isActive: Bool {
    #if DEBUG
    return ProcessInfo.processInfo.arguments.contains("-sober-ui-testing")
    #else
    return false
    #endif
  }

  /// Fixtures a test can ask for by name, rather than by poking at storage.
  enum HistoryFixture: String {
    case none
    case mixed
  }

  static var onboardingComplete: Bool { flag("-sober-onboarding-complete") }

  /// How many eligible sober sessions to seed.
  ///
  /// This writes real session records rather than setting a count, because a
  /// count alone cannot produce a ready baseline: `reloadResearchData` recomputes
  /// from the stored sessions on every launch and would immediately overwrite it
  /// with zero. That is the integrity property working — a baseline is measured
  /// sessions or it does not exist — and a fixture must satisfy it the same way
  /// a person does.
  static var baselineSessions: Int {
    Int(value(for: "-sober-baseline-sessions") ?? "") ?? 0
  }

  static var historyFixture: HistoryFixture {
    HistoryFixture(rawValue: value(for: "-sober-history-fixture") ?? "") ?? .none
  }

  /// A fixed participant so seeded sessions belong to the model that reads
  /// them. `BaselineProfileEngine` filters by participant, so a generated ID
  /// would leave every seeded session invisible.
  static let participantID = PseudonymousParticipantID(rawValue: "uitest-participant")

  /// An isolated defaults suite per launch, so one test cannot see another's
  /// state and none of them can see the real one.
  static func makeDefaults() -> UserDefaults {
    guard isActive, let defaults = UserDefaults(suiteName: "sober.uitest.\(UUID().uuidString)")
    else {
      return .standard
    }
    defaults.set(onboardingComplete, forKey: "sober.onboarding.complete")
    defaults.set(participantID.rawValue, forKey: "sober.research.participant-id")
    return defaults
  }

  /// A throwaway Application Support root for the session and history stores.
  static func makeDataDirectory() -> URL? {
    guard isActive else { return nil }
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("sober-uitest-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  /// Writes the requested history fixture into `directory`.
  ///
  /// Dates are relative to launch so a fixture never ages out of the retention
  /// window and starts failing months after it was written.
  static func seedHistory(in directory: URL, now: Date = Date()) {
    guard isActive, historyFixture == .mixed else { return }

    let entries: [CheckHistoryEntry] = [
      .init(
        id: UUID(), startedAt: now.addingTimeInterval(-3_600), kind: .check,
        outcome: .signalsDetected, qualityScore: 0.91, completedAllTasks: true),
      .init(
        id: UUID(), startedAt: now.addingTimeInterval(-86_400), kind: .check,
        outcome: .inconclusive, qualityScore: 0.55, completedAllTasks: true),
      .init(
        id: UUID(), startedAt: now.addingTimeInterval(-172_800), kind: .check,
        outcome: .noSignalsDetected, qualityScore: 0.88, completedAllTasks: true),
      .init(
        id: UUID(), startedAt: now.addingTimeInterval(-259_200), kind: .baseline,
        outcome: nil, qualityScore: 0.93, completedAllTasks: true),
    ]

    let historyDirectory = directory
      .appendingPathComponent("Sober", isDirectory: true)
      .appendingPathComponent("History", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: historyDirectory, withIntermediateDirectories: true)

    struct Document: Encodable {
      let schemaVersion: Int
      let entries: [CheckHistoryEntry]
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(Document(schemaVersion: 1, entries: entries)) else {
      return
    }
    try? data.write(
      to: historyDirectory.appendingPathComponent("check-history-v1.json"), options: .atomic)
  }

  /// Writes `baselineSessions` eligible sober sessions into `directory`.
  ///
  /// Each has to clear the same bar `BaselineProfileEngine` applies to a real
  /// session — completed, all tasks done, quality above the floor, finite
  /// measurements, matching protocol variant — or it is counted as excluded and
  /// the baseline stays unready.
  @MainActor
  static func seedBaseline(
    in directory: URL,
    participantID: PseudonymousParticipantID,
    now: Date = Date()
  ) {
    guard isActive, baselineSessions > 0 else { return }

    let metadata = ResearchSessionMetadata(
      device: .current(),
      app: .current(),
      protocolMetadata: ResearchProtocolMetadata(name: "sober-uitest", version: "1")
    )
    let context = ResearchSessionContext(
      sessionKind: .soberBaseline,
      soberAtStartAttested: true,
      reportedAlcoholUse: false,
      reportedCannabisUse: nil,
      reportedOtherSubstanceUse: nil,
      sleepHours: nil,
      caffeineWithinSixHours: nil,
      medicationMayAffectPerformance: nil,
      illnessOrInjuryMayAffectPerformance: nil,
      strenuousExerciseWithinTwoHours: nil,
      visionCorrection: .none,
      ambientLighting: .moderate
    )

    let sessions = (0..<baselineSessions).map { index -> ResearchSessionEnvelope in
      let startedAt = now.addingTimeInterval(-Double(index + 1) * 86_400)
      // Small deterministic spread. Identical sessions would give every measure
      // a zero deviation, which is not what a real baseline looks like.
      let jitter = Double(index) * 4
      return ResearchSessionEnvelope(
        participantID: participantID,
        startedAt: startedAt,
        completedAt: startedAt.addingTimeInterval(120),
        metadata: metadata,
        context: context,
        metrics: ResearchScreeningMetrics(
          reactionTimeMilliseconds: 430 + jitter,
          reactionMisses: 0,
          trackingError: 0.18 + Double(index) * 0.005,
          timeEstimateError: 0.12 + Double(index) * 0.004,
          gazeSmoothness: 0.16 + Double(index) * 0.003,
          qualityScore: 0.92,
          completedAllTasks: true
        ),
        protocolVariant: .full
      )
    }

    let researchDirectory = directory
      .appendingPathComponent("Sober", isDirectory: true)
      .appendingPathComponent("Research", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: researchDirectory, withIntermediateDirectories: true)

    struct Document: Encodable {
      let schemaVersion: Int
      let sessions: [ResearchSessionEnvelope]
    }
    // `ResearchSessionStore` reads with a default `JSONDecoder`, so dates are
    // numbers rather than ISO8601 strings. A mismatch here does not fail
    // loudly: the store throws, the model swallows it into `researchDataError`,
    // and the baseline silently stays unready.
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(Document(schemaVersion: 1, sessions: sessions)) else {
      return
    }
    try? data.write(
      to: researchDirectory.appendingPathComponent("research-sessions-v1.json"), options: .atomic)
  }

  private static func flag(_ name: String) -> Bool {
    isActive && ProcessInfo.processInfo.arguments.contains(name)
  }

  private static func value(for name: String) -> String? {
    guard isActive else { return nil }
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
      return nil
    }
    return arguments[index + 1]
  }
}
