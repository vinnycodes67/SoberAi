import Foundation

enum OcularPhase: String, Codable, CaseIterable, Sendable {
  case calibration
  case fixation
  case horizontalPursuit
  case verticalPursuit
  case saccades

  var title: String {
    switch self {
    case .calibration: "Camera setup"
    case .fixation: "Hold center"
    case .horizontalPursuit: "Follow side to side"
    case .verticalPursuit: "Follow up and down"
    case .saccades: "Jump between targets"
    }
  }
}

enum CaptureQualityIssue: String, Codable, Equatable, Sendable {
  case unsupported
  case permissionDenied
  case noFace
  case offCenter
  case distance
  case lowLight
  case unstable
  case lowFrameRate
  case interrupted
  case insufficientSamples

  var guidance: String {
    switch self {
    case .unsupported: "Live face tracking is not supported on this device."
    case .permissionDenied: "Allow camera access in Settings to run a live check."
    case .noFace: "Keep your full face inside the guide."
    case .offCenter: "Center your face in the oval."
    case .distance: "Move the phone about an arm’s length away."
    case .lowLight: "Move into brighter, even light."
    case .unstable: "Hold the phone and your head still."
    case .lowFrameRate: "Capture is dropping frames. Hold still and retry."
    case .interrupted: "Face tracking was interrupted."
    case .insufficientSamples: "Not enough usable camera samples were recorded."
    }
  }
}

struct CaptureQualitySnapshot: Codable, Equatable, Sendable {
  var isSupported: Bool
  var hasCameraPermission: Bool
  var facePresent: Bool
  var centered: Bool
  var distanceAcceptable: Bool
  var lightingAcceptable: Bool
  var headStable: Bool
  var frameRate: Double
  var sampleCount: Int
  var dropoutRatio: Double
  var issues: [CaptureQualityIssue]

  static let idle = CaptureQualitySnapshot(
    isSupported: true,
    hasCameraPermission: false,
    facePresent: false,
    centered: false,
    distanceAcceptable: false,
    lightingAcceptable: false,
    headStable: false,
    frameRate: 0,
    sampleCount: 0,
    dropoutRatio: 1,
    issues: [.noFace, .insufficientSamples]
  )

  static let unsupported = CaptureQualitySnapshot(
    isSupported: false,
    hasCameraPermission: false,
    facePresent: false,
    centered: false,
    distanceAcceptable: false,
    lightingAcceptable: false,
    headStable: false,
    frameRate: 0,
    sampleCount: 0,
    dropoutRatio: 1,
    issues: [.unsupported]
  )

  var score: Double {
    guard isSupported, hasCameraPermission, facePresent else { return 0 }
    let frameQuality = min(max(frameRate / 45, 0), 1)
    let checks = [centered, distanceAcceptable, lightingAcceptable, headStable]
    let checkQuality = Double(checks.filter { $0 }.count) / Double(checks.count)
    let dropoutQuality = max(1 - dropoutRatio, 0)
    return min(max((checkQuality * 0.54) + (frameQuality * 0.28) + (dropoutQuality * 0.18), 0), 1)
  }

  var isUsable: Bool {
    isSupported
      && hasCameraPermission
      && facePresent
      && centered
      && distanceAcceptable
      && lightingAcceptable
      && headStable
      && frameRate >= 20
      && dropoutRatio <= 0.3
      && sampleCount >= 20
  }

  var primaryGuidance: String {
    issues.first?.guidance ?? "Capture quality is ready."
  }
}

enum OcularProtocolVariant: String, Codable, CaseIterable, Sendable {
  case full
  case reducedMotion

  var displayName: String {
    switch self {
    case .full: "Full protocol"
    case .reducedMotion: "Reduced motion"
    }
  }
}

struct OcularTarget: Equatable, Sendable {
  let phase: OcularPhase
  let x: Double
  let y: Double
}

struct OcularSample: Equatable, Sendable {
  let timestamp: TimeInterval
  let phase: OcularPhase
  let targetX: Double
  let targetY: Double
  let leftGazeX: Double
  let leftGazeY: Double
  let rightGazeX: Double
  let rightGazeY: Double
  let headX: Double
  let headY: Double
  let headZ: Double
  /// Nil means ARKit did not provide the corresponding blendshape. Missing
  /// telemetry must not be converted into an "eyes open" observation.
  let blinkLeft: Double?
  let blinkRight: Double?
}

struct OcularSignalFeatures: Codable, Equatable, Sendable {
  var fixationJitter: Double
  var horizontalPursuitError: Double
  var verticalPursuitError: Double
  var saccadeError: Double
  var leftRightAsymmetry: Double
  /// Nil means the capture contained no usable blink telemetry.
  var blinkRatePerMinute: Double?
  var headCompensation: Double

  static let unavailable = OcularSignalFeatures(
    fixationJitter: 1,
    horizontalPursuitError: 1,
    verticalPursuitError: 1,
    saccadeError: 1,
    leftRightAsymmetry: 1,
    blinkRatePerMinute: nil,
    headCompensation: 1
  )
}

struct GazeCaptureSummary: Codable, Equatable, Sendable {
  let smoothnessRisk: Double
  let qualityScore: Double
  let sampleCount: Int
  /// Duration actually spanned by the retained samples. Zero means no ocular
  /// protocol produced measurements, so downstream records must not imply one.
  let capturedDurationMilliseconds: Double
  let quality: CaptureQualitySnapshot
  let features: OcularSignalFeatures
  let protocolVariant: OcularProtocolVariant

  init(
    smoothnessRisk: Double,
    qualityScore: Double,
    sampleCount: Int,
    capturedDurationMilliseconds: Double = 0,
    quality: CaptureQualitySnapshot = .unsupported,
    features: OcularSignalFeatures = .unavailable,
    protocolVariant: OcularProtocolVariant = .full
  ) {
    self.smoothnessRisk = smoothnessRisk
    self.qualityScore = qualityScore
    self.sampleCount = sampleCount
    self.capturedDurationMilliseconds = capturedDurationMilliseconds
    self.quality = quality
    self.features = features
    self.protocolVariant = protocolVariant
  }

  private enum CodingKeys: String, CodingKey {
    case smoothnessRisk
    case qualityScore
    case sampleCount
    case capturedDurationMilliseconds
    case quality
    case features
    case protocolVariant
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    smoothnessRisk = try values.decode(Double.self, forKey: .smoothnessRisk)
    qualityScore = try values.decode(Double.self, forKey: .qualityScore)
    sampleCount = try values.decode(Int.self, forKey: .sampleCount)
    capturedDurationMilliseconds =
      try values.decodeIfPresent(Double.self, forKey: .capturedDurationMilliseconds) ?? 0
    quality = try values.decode(CaptureQualitySnapshot.self, forKey: .quality)
    features = try values.decode(OcularSignalFeatures.self, forKey: .features)
    protocolVariant = try values.decodeIfPresent(OcularProtocolVariant.self, forKey: .protocolVariant) ?? .full
  }
}

enum OcularProtocolSchedule {
  static let fixationDuration = 3.0
  static let horizontalDuration = 8.0
  static let verticalDuration = 6.0
  static let saccadeDuration = 8.0
  static let totalDuration = fixationDuration + horizontalDuration + verticalDuration + saccadeDuration

  static func totalDuration(for variant: OcularProtocolVariant) -> TimeInterval {
    switch variant {
    case .full: return fixationDuration + horizontalDuration + verticalDuration + saccadeDuration
    case .reducedMotion: return fixationDuration + saccadeDuration
    }
  }

  static func target(at elapsed: TimeInterval, variant: OcularProtocolVariant = .full) -> OcularTarget {
    let duration = totalDuration(for: variant)
    let time = min(max(elapsed, 0), duration)

    switch variant {
    case .full:
      if time < fixationDuration {
        return OcularTarget(phase: .fixation, x: 0.5, y: 0.5)
      }

      if time < fixationDuration + horizontalDuration {
        let phaseTime = time - fixationDuration
        let travel = (sin((phaseTime / 4) * .pi * 2 - (.pi / 2)) + 1) / 2
        return OcularTarget(phase: .horizontalPursuit, x: 0.14 + (travel * 0.72), y: 0.5)
      }

      if time < fixationDuration + horizontalDuration + verticalDuration {
        let phaseTime = time - fixationDuration - horizontalDuration
        let travel = (sin((phaseTime / 3) * .pi * 2 - (.pi / 2)) + 1) / 2
        return OcularTarget(phase: .verticalPursuit, x: 0.5, y: 0.18 + (travel * 0.64))
      }

      let positions = [
        (0.2, 0.28), (0.8, 0.72), (0.2, 0.72), (0.8, 0.28),
        (0.5, 0.18), (0.5, 0.82), (0.18, 0.5), (0.82, 0.5),
      ]
      let phaseTime = time - fixationDuration - horizontalDuration - verticalDuration
      let index = min(Int(phaseTime), positions.count - 1)
      return OcularTarget(phase: .saccades, x: positions[index].0, y: positions[index].1)
    case .reducedMotion:
      if time < fixationDuration {
        return OcularTarget(phase: .fixation, x: 0.5, y: 0.5)
      }
      let positions = [
        (0.2, 0.28), (0.8, 0.72), (0.2, 0.72), (0.8, 0.28),
        (0.5, 0.18), (0.5, 0.82), (0.18, 0.5), (0.82, 0.5),
      ]
      let phaseTime = time - fixationDuration
      let index = min(Int(phaseTime), positions.count - 1)
      return OcularTarget(phase: .saccades, x: positions[index].0, y: positions[index].1)
    }
  }
}
