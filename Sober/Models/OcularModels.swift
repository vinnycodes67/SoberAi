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
  case multipleFaces

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
    case .multipleFaces: "Only you should be in view. Make sure no one else is in the camera."
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
  /// Another face was tracked alongside the person's. The check follows the
  /// nearest face, but with two in view it can switch to the wrong one, so
  /// the capture does not count.
  var otherFacesInView = false

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
      && !otherFacesInView
  }

  var primaryGuidance: String {
    issues.first?.guidance ?? "Capture quality is ready."
  }
}

extension CaptureQualitySnapshot {
  private enum CodingKeys: String, CodingKey {
    case isSupported, hasCameraPermission, facePresent, centered, distanceAcceptable
    case lightingAcceptable, headStable, frameRate, sampleCount, dropoutRatio, issues
    case otherFacesInView
  }

  /// Written out so sessions saved before `otherFacesInView` existed still
  /// decode. Synthesized decoding ignores property defaults and would throw.
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      isSupported: try values.decode(Bool.self, forKey: .isSupported),
      hasCameraPermission: try values.decode(Bool.self, forKey: .hasCameraPermission),
      facePresent: try values.decode(Bool.self, forKey: .facePresent),
      centered: try values.decode(Bool.self, forKey: .centered),
      distanceAcceptable: try values.decode(Bool.self, forKey: .distanceAcceptable),
      lightingAcceptable: try values.decode(Bool.self, forKey: .lightingAcceptable),
      headStable: try values.decode(Bool.self, forKey: .headStable),
      frameRate: try values.decode(Double.self, forKey: .frameRate),
      sampleCount: try values.decode(Int.self, forKey: .sampleCount),
      dropoutRatio: try values.decode(Double.self, forKey: .dropoutRatio),
      issues: try values.decode([CaptureQualityIssue].self, forKey: .issues),
      otherFacesInView: try values.decodeIfPresent(Bool.self, forKey: .otherFacesInView) ?? false
    )
  }
}

enum OcularProtocolVariant: String, Codable, CaseIterable, Sendable {
  case full
  case reducedMotion
  /// No eye task at all: the device has no TrueDepth camera, so the check runs
  /// reaction, tracking and timing only. Its sessions form a baseline of their
  /// own and are never mixed into a camera baseline -- a check is only ever
  /// compared against sessions that measured the same things.
  ///
  /// Chosen for unsupported hardware only, never for a denied camera: someone
  /// who can grant access should get the full check.
  case noCamera

  var displayName: String {
    switch self {
    case .full: "Full protocol"
    case .reducedMotion: "Reduced motion"
    case .noCamera: "Without eye task"
    }
  }

  /// The variant the next check on this iPhone will run. Baseline readiness and
  /// the check itself both ask this, because each variant has its own baseline:
  /// "ready" has to mean the next check compares against this person's
  /// sessions, not that some other variant happens to have five.
  static func forNextCheck(supportsFaceTracking: Bool, reduceMotion: Bool) -> Self {
    guard supportsFaceTracking else { return .noCamera }
    return reduceMotion ? .reducedMotion : .full
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

  // MARK: Screen gaze (`ScreenGazeGeometry`)

  /// Where the gaze rays met the screen, in portrait screen points (origin at
  /// the display's top-left, x right, y down). Unlike the eye-in-head fields
  /// above, these do not move when the head turns and the eyes stay on the
  /// dot. All nil when the frame had no camera pose or the display was not
  /// known. Off-screen points are kept; `screenGazeValidity` says where the
  /// combined point landed. In memory only, like every other field here.
  var screenGazeX: Double? = nil
  var screenGazeY: Double? = nil
  var leftScreenGazeX: Double? = nil
  var leftScreenGazeY: Double? = nil
  var rightScreenGazeX: Double? = nil
  var rightScreenGazeY: Double? = nil
  /// Of the combined point. Nil when screen gaze was not computed at all.
  var screenGazeValidity: ScreenGazeValidity? = nil
  /// Mean distance of the two eyes from the screen plane, metres.
  var screenViewingDistanceMetres: Double? = nil

  mutating func setScreenGaze(_ gaze: ScreenGaze) {
    screenGazeX = gaze.combined.x
    screenGazeY = gaze.combined.y
    leftScreenGazeX = gaze.left.x
    leftScreenGazeY = gaze.left.y
    rightScreenGazeX = gaze.right.x
    rightScreenGazeY = gaze.right.y
    screenGazeValidity = gaze.combined.validity
    screenViewingDistanceMetres = gaze.combined.distanceMetres
  }
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
  /// Tracking benchmark for this capture. Nil for captures recorded before it
  /// existed, and for any capture that never opened the camera.
  let telemetry: CaptureTelemetry?
  /// Richer eye measures, recorded but not scored. Nil for captures recorded
  /// before they existed and for any capture that never opened the camera.
  let detailed: OcularDetailedMetrics?

  init(
    smoothnessRisk: Double,
    qualityScore: Double,
    sampleCount: Int,
    capturedDurationMilliseconds: Double = 0,
    quality: CaptureQualitySnapshot = .unsupported,
    features: OcularSignalFeatures = .unavailable,
    protocolVariant: OcularProtocolVariant = .full,
    telemetry: CaptureTelemetry? = nil,
    detailed: OcularDetailedMetrics? = nil
  ) {
    self.smoothnessRisk = smoothnessRisk
    self.qualityScore = qualityScore
    self.sampleCount = sampleCount
    self.capturedDurationMilliseconds = capturedDurationMilliseconds
    self.quality = quality
    self.features = features
    self.protocolVariant = protocolVariant
    self.telemetry = telemetry
    self.detailed = detailed
  }

  func with(telemetry: CaptureTelemetry?) -> GazeCaptureSummary {
    GazeCaptureSummary(
      smoothnessRisk: smoothnessRisk, qualityScore: qualityScore, sampleCount: sampleCount,
      capturedDurationMilliseconds: capturedDurationMilliseconds, quality: quality,
      features: features, protocolVariant: protocolVariant, telemetry: telemetry,
      detailed: detailed)
  }

  private enum CodingKeys: String, CodingKey {
    case smoothnessRisk
    case qualityScore
    case sampleCount
    case capturedDurationMilliseconds
    case quality
    case features
    case protocolVariant
    case telemetry
    case detailed
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
    // Record-only extras fail soft. A record from a later schema, or a
    // damaged one, loses just that field; throwing here would make the whole
    // session unreadable, and with it a baseline session.
    telemetry = (try? values.decodeIfPresent(CaptureTelemetry.self, forKey: .telemetry)) ?? nil
    detailed = (try? values.decodeIfPresent(OcularDetailedMetrics.self, forKey: .detailed)) ?? nil
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
    // No ocular protocol runs without a camera.
    case .noCamera: return 0
    }
  }

  static func target(at elapsed: TimeInterval, variant: OcularProtocolVariant = .full) -> OcularTarget {
    let duration = totalDuration(for: variant)
    let time = min(max(elapsed, 0), duration)

    switch variant {
    case .noCamera:
      // Unreachable: the ocular task never starts without a camera. Neutral
      // rather than a crash if that ever changes.
      return OcularTarget(phase: .fixation, x: 0.5, y: 0.5)
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

/// Follow-the-dot calibration, run as its own step immediately before the
/// protocol above, which it does not change. The dot visits each point for
/// `pointDuration`; only the last `scoredDuration` of each is used, after the
/// eyes have arrived. Its samples are fitted and discarded before the
/// protocol's buffer starts (`OcularCalibrationFitter`).
///
/// The durations are engineering choices, not measured on people.
enum OcularCalibrationSchedule {
  /// The four corners the protocol's jumps use, read from the protocol itself
  /// so the two cannot drift apart, then the centre: the eyes end where the
  /// protocol's fixation begins.
  static let points: [(x: Double, y: Double)] = {
    let jumpsStart = OcularProtocolSchedule.totalDuration - OcularProtocolSchedule.saccadeDuration
    let corners = (0..<4).map { index -> (x: Double, y: Double) in
      let target = OcularProtocolSchedule.target(at: jumpsStart + Double(index) + 0.5)
      return (target.x, target.y)
    }
    return corners + [(x: 0.5, y: 0.5)]
  }()

  static let pointDuration = 1.0
  static let scoredDuration = 0.6
  /// With full motion the dot glides to each point for this long, well inside
  /// the unscored part. With Reduced Motion it does not glide at all.
  static let glideDuration = 0.25

  static var totalDuration: TimeInterval { Double(points.count) * pointDuration }

  /// Which point is showing. Nil before the start and from the end on.
  static func pointIndex(at elapsed: TimeInterval) -> Int? {
    guard elapsed.isFinite, elapsed >= 0, elapsed < totalDuration else { return nil }
    return min(Int(elapsed / pointDuration), points.count - 1)
  }

  /// True in the last `scoredDuration` of a point.
  static func isScored(at elapsed: TimeInterval) -> Bool {
    guard let index = pointIndex(at: elapsed) else { return false }
    return elapsed - Double(index) * pointDuration >= pointDuration - scoredDuration
  }

  /// The point the person is asked to look at, which is where the dot rests.
  static func target(at elapsed: TimeInterval) -> OcularTarget {
    let clamped = elapsed.isFinite ? min(max(elapsed, 0), totalDuration) : 0
    let point = points[min(Int(clamped / pointDuration), points.count - 1)]
    return OcularTarget(phase: .calibration, x: point.x, y: point.y)
  }

  /// Where to draw the dot. It starts from the centre, where the idle signal
  /// sits before the task begins.
  static func dotPosition(at elapsed: TimeInterval, reduceMotion: Bool) -> (x: Double, y: Double) {
    let clamped = elapsed.isFinite ? min(max(elapsed, 0), totalDuration) : 0
    let index = min(Int(clamped / pointDuration), points.count - 1)
    let destination = points[index]
    let sincePointStart = clamped - Double(index) * pointDuration
    guard !reduceMotion, sincePointStart < glideDuration else { return destination }
    let origin = index > 0 ? points[index - 1] : (x: 0.5, y: 0.5)
    let progress = sincePointStart / glideDuration
    let eased = progress * progress * (3 - 2 * progress)
    return (origin.x + (destination.x - origin.x) * eased, origin.y + (destination.y - origin.y) * eased)
  }
}
