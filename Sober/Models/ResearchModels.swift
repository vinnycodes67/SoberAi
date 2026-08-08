import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// A random, non-identifying participant key. The display name, phone number,
/// and other direct identifiers do not belong in a research session.
struct PseudonymousParticipantID: RawRepresentable, Codable, Hashable, Sendable {
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  static func generate() -> Self {
    Self(rawValue: "participant_\(UUID().uuidString.lowercased())")
  }

  init(from decoder: Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct ResearchSessionID: RawRepresentable, Codable, Hashable, Sendable {
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  static func generate() -> Self {
    Self(rawValue: "session_\(UUID().uuidString.lowercased())")
  }

  init(from decoder: Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct ResearchDeviceMetadata: Codable, Equatable, Sendable {
  let platform: String
  let deviceModel: String
  let systemName: String
  let systemVersion: String
  let localeIdentifier: String

  @MainActor
  static func current(locale: Locale = .current) -> Self {
    #if canImport(UIKit)
    let device = UIDevice.current
    return Self(
      platform: "iOS",
      deviceModel: device.model,
      systemName: device.systemName,
      systemVersion: device.systemVersion,
      localeIdentifier: locale.identifier
    )
    #else
    return Self(
      platform: "unknown",
      deviceModel: "unknown",
      systemName: ProcessInfo.processInfo.operatingSystemVersionString,
      systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      localeIdentifier: locale.identifier
    )
    #endif
  }
}

struct ResearchAppMetadata: Codable, Equatable, Sendable {
  let bundleIdentifier: String
  let version: String
  let build: String

  static func current(bundle: Bundle = .main) -> Self {
    Self(
      bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
      version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "unknown",
      build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    )
  }
}

struct ResearchProtocolMetadata: Codable, Equatable, Sendable {
  let name: String
  let version: String
  let configurationHash: String?

  init(name: String, version: String, configurationHash: String? = nil) {
    self.name = name
    self.version = version
    self.configurationHash = configurationHash
  }
}

struct ResearchSessionMetadata: Codable, Equatable, Sendable {
  let device: ResearchDeviceMetadata
  let app: ResearchAppMetadata
  let protocolMetadata: ResearchProtocolMetadata

  init(
    device: ResearchDeviceMetadata,
    app: ResearchAppMetadata,
    protocolMetadata: ResearchProtocolMetadata
  ) {
    self.device = device
    self.app = app
    self.protocolMetadata = protocolMetadata
  }
}

enum ResearchSessionKind: String, Codable, CaseIterable, Sendable {
  case soberBaseline = "sober_baseline"
  case screeningCheck = "screening_check"
  case controlledResearch = "controlled_research"
}

enum ResearchVisionCorrection: String, Codable, CaseIterable, Sendable {
  case none
  case glasses
  case contactLenses = "contact_lenses"
  case unknown
}

enum ResearchAmbientLighting: String, Codable, CaseIterable, Sendable {
  case dim
  case moderate
  case bright
  case unknown
}

/// Self-reported variables that can affect task performance independently of
/// alcohol. Optional values mean the question was not answered, not `false`.
struct ResearchSessionContext: Codable, Equatable, Sendable {
  var sessionKind: ResearchSessionKind
  var soberAtStartAttested: Bool?
  var reportedAlcoholUse: Bool?
  var reportedCannabisUse: Bool?
  var reportedOtherSubstanceUse: Bool?
  var sleepHours: Double?
  var caffeineWithinSixHours: Bool?
  var medicationMayAffectPerformance: Bool?
  var illnessOrInjuryMayAffectPerformance: Bool?
  var strenuousExerciseWithinTwoHours: Bool?
  var visionCorrection: ResearchVisionCorrection
  var ambientLighting: ResearchAmbientLighting

  init(
    sessionKind: ResearchSessionKind,
    soberAtStartAttested: Bool? = nil,
    reportedAlcoholUse: Bool? = nil,
    reportedCannabisUse: Bool? = nil,
    reportedOtherSubstanceUse: Bool? = nil,
    sleepHours: Double? = nil,
    caffeineWithinSixHours: Bool? = nil,
    medicationMayAffectPerformance: Bool? = nil,
    illnessOrInjuryMayAffectPerformance: Bool? = nil,
    strenuousExerciseWithinTwoHours: Bool? = nil,
    visionCorrection: ResearchVisionCorrection = .unknown,
    ambientLighting: ResearchAmbientLighting = .unknown
  ) {
    self.sessionKind = sessionKind
    self.soberAtStartAttested = soberAtStartAttested
    self.reportedAlcoholUse = reportedAlcoholUse
    self.reportedCannabisUse = reportedCannabisUse
    self.reportedOtherSubstanceUse = reportedOtherSubstanceUse
    self.sleepHours = sleepHours
    self.caffeineWithinSixHours = caffeineWithinSixHours
    self.medicationMayAffectPerformance = medicationMayAffectPerformance
    self.illnessOrInjuryMayAffectPerformance = illnessOrInjuryMayAffectPerformance
    self.strenuousExerciseWithinTwoHours = strenuousExerciseWithinTwoHours
    self.visionCorrection = visionCorrection
    self.ambientLighting = ambientLighting
  }
}

/// Codable mirror of `ScreeningMetrics`. Keeping this adapter separate means
/// the live scorer does not become a persistence contract.
struct ResearchScreeningMetrics: Codable, Equatable, Sendable {
  let reactionTimeMilliseconds: Double
  let reactionMisses: Int
  let reactionWasMeasured: Bool
  let trackingError: Double?
  let timeEstimateError: Double
  let timingWasMeasured: Bool
  let gazeSmoothness: Double?
  let qualityScore: Double
  let completedAllTasks: Bool

  init(
    reactionTimeMilliseconds: Double,
    reactionMisses: Int,
    reactionWasMeasured: Bool = true,
    trackingError: Double?,
    timeEstimateError: Double,
    timingWasMeasured: Bool = true,
    gazeSmoothness: Double?,
    qualityScore: Double,
    completedAllTasks: Bool
  ) {
    self.reactionTimeMilliseconds = reactionTimeMilliseconds
    self.reactionMisses = reactionMisses
    self.reactionWasMeasured = reactionWasMeasured
    self.trackingError = trackingError
    self.timeEstimateError = timeEstimateError
    self.timingWasMeasured = timingWasMeasured
    self.gazeSmoothness = gazeSmoothness
    self.qualityScore = qualityScore
    self.completedAllTasks = completedAllTasks
  }

  init(_ metrics: ScreeningMetrics) {
    self.init(
      reactionTimeMilliseconds: metrics.reactionTimeMilliseconds,
      reactionMisses: metrics.reactionMisses,
      reactionWasMeasured: metrics.reactionWasMeasured,
      trackingError: metrics.trackingError,
      timeEstimateError: metrics.timeEstimateError,
      timingWasMeasured: metrics.timingWasMeasured,
      gazeSmoothness: metrics.gazeSmoothness,
      qualityScore: metrics.qualityScore,
      completedAllTasks: metrics.completedAllTasks
    )
  }

  private enum CodingKeys: String, CodingKey {
    case reactionTimeMilliseconds
    case reactionMisses
    case reactionWasMeasured
    case trackingError
    case timeEstimateError
    case timingWasMeasured
    case gazeSmoothness
    case qualityScore
    case completedAllTasks
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    reactionTimeMilliseconds = try values.decode(Double.self, forKey: .reactionTimeMilliseconds)
    reactionMisses = try values.decode(Int.self, forKey: .reactionMisses)
    reactionWasMeasured = try values.decodeIfPresent(Bool.self, forKey: .reactionWasMeasured) ?? true
    trackingError = try values.decodeIfPresent(Double.self, forKey: .trackingError)
    timeEstimateError = try values.decode(Double.self, forKey: .timeEstimateError)
    timingWasMeasured = try values.decodeIfPresent(Bool.self, forKey: .timingWasMeasured) ?? true
    gazeSmoothness = try values.decodeIfPresent(Double.self, forKey: .gazeSmoothness)
    qualityScore = try values.decode(Double.self, forKey: .qualityScore)
    completedAllTasks = try values.decode(Bool.self, forKey: .completedAllTasks)
  }

  var screeningMetrics: ScreeningMetrics {
    ScreeningMetrics(
      reactionTimeMilliseconds: reactionTimeMilliseconds,
      reactionMisses: reactionMisses,
      reactionWasMeasured: reactionWasMeasured,
      trackingError: trackingError,
      timeEstimateError: timeEstimateError,
      timingWasMeasured: timingWasMeasured,
      gazeSmoothness: gazeSmoothness,
      qualityScore: qualityScore,
      completedAllTasks: completedAllTasks
    )
  }
}

/// Reserved signal-quality fields for the front-camera calibration and ocular
/// tasks. Nil means the source has not started producing that measurement yet.
struct ResearchOcularQuality: Codable, Equatable, Sendable {
  var faceTrackingAvailable: Bool?
  var cameraPermissionGranted: Bool?
  var sampleCount: Int?
  var trackingDurationMilliseconds: Double?
  var trackingCoverage: Double?
  /// Legacy schema-1 fields. Nil in new records because the current ARKit
  /// capture does not measure per-frame eye visibility, stability, or light.
  var bothEyesVisibleFraction: Double?
  var headStabilityScore: Double?
  var illuminationScore: Double?
  var facePresentAtCompletion: Bool?
  var headStableAtCompletion: Bool?
  var lightingAcceptableAtCompletion: Bool?
  var glareDetected: Bool?
  var meanFrameRate: Double?
  var signalQualityScore: Double?

  init(
    faceTrackingAvailable: Bool? = nil,
    cameraPermissionGranted: Bool? = nil,
    sampleCount: Int? = nil,
    trackingDurationMilliseconds: Double? = nil,
    trackingCoverage: Double? = nil,
    bothEyesVisibleFraction: Double? = nil,
    headStabilityScore: Double? = nil,
    illuminationScore: Double? = nil,
    facePresentAtCompletion: Bool? = nil,
    headStableAtCompletion: Bool? = nil,
    lightingAcceptableAtCompletion: Bool? = nil,
    glareDetected: Bool? = nil,
    meanFrameRate: Double? = nil,
    signalQualityScore: Double? = nil
  ) {
    self.faceTrackingAvailable = faceTrackingAvailable
    self.cameraPermissionGranted = cameraPermissionGranted
    self.sampleCount = sampleCount
    self.trackingDurationMilliseconds = trackingDurationMilliseconds
    self.trackingCoverage = trackingCoverage
    self.bothEyesVisibleFraction = bothEyesVisibleFraction
    self.headStabilityScore = headStabilityScore
    self.illuminationScore = illuminationScore
    self.facePresentAtCompletion = facePresentAtCompletion
    self.headStableAtCompletion = headStableAtCompletion
    self.lightingAcceptableAtCompletion = lightingAcceptableAtCompletion
    self.glareDetected = glareDetected
    self.meanFrameRate = meanFrameRate
    self.signalQualityScore = signalQualityScore
  }
}

enum BreathReferenceUnit: String, Codable, CaseIterable, Sendable {
  case bacPercent = "bac_percent"
  case gramsPer210Liters = "grams_per_210_liters"
  case milligramsPerLiter = "milligrams_per_liter"
  case perMille = "per_mille"
}

struct BreathReferenceMetadata: Codable, Equatable, Sendable {
  let reading: Double
  let unit: BreathReferenceUnit
  let measuredAt: Date
  let manufacturer: String?
  let model: String?
  let pseudonymousDeviceID: String?
  let calibrationDueAt: Date?

  init(
    reading: Double,
    unit: BreathReferenceUnit,
    measuredAt: Date,
    manufacturer: String? = nil,
    model: String? = nil,
    pseudonymousDeviceID: String? = nil,
    calibrationDueAt: Date? = nil
  ) {
    self.reading = reading
    self.unit = unit
    self.measuredAt = measuredAt
    self.manufacturer = manufacturer
    self.model = model
    self.pseudonymousDeviceID = pseudonymousDeviceID
    self.calibrationDueAt = calibrationDueAt
  }
}

struct ResearchSessionEnvelope: Codable, Equatable, Identifiable, Sendable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let participantID: PseudonymousParticipantID
  let sessionID: ResearchSessionID
  let startedAt: Date
  let completedAt: Date?
  let metadata: ResearchSessionMetadata
  let context: ResearchSessionContext
  let metrics: ResearchScreeningMetrics
  let choiceReaction: ChoiceReactionSummary?
  let ocularSummary: GazeCaptureSummary?
  let ocularQuality: ResearchOcularQuality?
  let breathReference: BreathReferenceMetadata?
  let protocolVariant: OcularProtocolVariant

  var id: ResearchSessionID { sessionID }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case participantID
    case sessionID
    case startedAt
    case completedAt
    case metadata
    case context
    case metrics
    case choiceReaction
    case ocularSummary
    case ocularQuality
    case breathReference
    case protocolVariant
  }

  init(
    schemaVersion: Int = Self.currentSchemaVersion,
    participantID: PseudonymousParticipantID,
    sessionID: ResearchSessionID = .generate(),
    startedAt: Date,
    completedAt: Date?,
    metadata: ResearchSessionMetadata,
    context: ResearchSessionContext,
    metrics: ResearchScreeningMetrics,
    choiceReaction: ChoiceReactionSummary? = nil,
    ocularSummary: GazeCaptureSummary? = nil,
    ocularQuality: ResearchOcularQuality? = nil,
    breathReference: BreathReferenceMetadata? = nil,
    protocolVariant: OcularProtocolVariant = .full
  ) {
    self.schemaVersion = schemaVersion
    self.participantID = participantID
    self.sessionID = sessionID
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.metadata = metadata
    self.context = context
    self.metrics = metrics
    self.choiceReaction = choiceReaction
    self.ocularSummary = ocularSummary
    self.ocularQuality = ocularQuality
    self.breathReference = breathReference
    self.protocolVariant = protocolVariant
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
    participantID = try values.decode(PseudonymousParticipantID.self, forKey: .participantID)
    sessionID = try values.decode(ResearchSessionID.self, forKey: .sessionID)
    startedAt = try values.decode(Date.self, forKey: .startedAt)
    completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
    metadata = try values.decode(ResearchSessionMetadata.self, forKey: .metadata)
    context = try values.decode(ResearchSessionContext.self, forKey: .context)
    metrics = try values.decode(ResearchScreeningMetrics.self, forKey: .metrics)
    choiceReaction = try values.decodeIfPresent(ChoiceReactionSummary.self, forKey: .choiceReaction)
    ocularSummary = try values.decodeIfPresent(GazeCaptureSummary.self, forKey: .ocularSummary)
    ocularQuality = try values.decodeIfPresent(ResearchOcularQuality.self, forKey: .ocularQuality)
    breathReference = try values.decodeIfPresent(BreathReferenceMetadata.self, forKey: .breathReference)
    // Records created before measured protocol variants were introduced used
    // the full visual protocol. Preserve that meaning when importing them.
    protocolVariant = try values.decodeIfPresent(OcularProtocolVariant.self, forKey: .protocolVariant) ?? .full
  }
}

struct ResearchSessionExportPayload: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let exportedAt: Date
  let sessions: [ResearchSessionEnvelope]

  init(
    schemaVersion: Int = Self.currentSchemaVersion,
    exportedAt: Date,
    sessions: [ResearchSessionEnvelope]
  ) {
    self.schemaVersion = schemaVersion
    self.exportedAt = exportedAt
    self.sessions = sessions
  }
}
