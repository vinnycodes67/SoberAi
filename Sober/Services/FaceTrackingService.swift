@preconcurrency import ARKit
import AVFoundation
import Combine
import Foundation
import simd

enum FaceTrackingStatus: Equatable {
  case idle
  case unsupported
  case permissionDenied
  case searching
  case tracking
  case limited(String)

  var label: String {
    switch self {
    case .idle: "Camera ready"
    case .unsupported: "Live face tracking unavailable"
    case .permissionDenied: "Camera permission required"
    case .searching: "Finding your face…"
    case .tracking: "Capture quality ready"
    case .limited(let reason): reason
    }
  }
}

/// Aggregates the per-anchor checks that otherwise only describe the final
/// camera frame. A capture must finish in a good state and remain acceptable
/// for at least the same 70% coverage required by the dropout gate.
struct CaptureQualityHistory: Sendable {
  static let minimumAcceptableFraction = 0.7

  private(set) var observationCount = 0
  private var facePresentCount = 0
  private var centeredCount = 0
  private var distanceAcceptableCount = 0
  private var lightingAcceptableCount = 0
  private var headStableCount = 0

  mutating func record(
    facePresent: Bool,
    centered: Bool,
    distanceAcceptable: Bool,
    lightingAcceptable: Bool,
    headStable: Bool
  ) {
    observationCount += 1
    facePresentCount += facePresent ? 1 : 0
    centeredCount += centered ? 1 : 0
    distanceAcceptableCount += distanceAcceptable ? 1 : 0
    lightingAcceptableCount += lightingAcceptable ? 1 : 0
    headStableCount += headStable ? 1 : 0
  }

  func applying(to finalFrame: CaptureQualitySnapshot) -> CaptureQualitySnapshot {
    guard observationCount > 0 else { return finalFrame }

    var result = finalFrame
    result.facePresent = finalFrame.facePresent && isAcceptable(facePresentCount)
    result.centered = finalFrame.centered && isAcceptable(centeredCount)
    result.distanceAcceptable =
      finalFrame.distanceAcceptable && isAcceptable(distanceAcceptableCount)
    result.lightingAcceptable =
      finalFrame.lightingAcceptable && isAcceptable(lightingAcceptableCount)
    result.headStable = finalFrame.headStable && isAcceptable(headStableCount)

    if !result.facePresent { append(.noFace, to: &result.issues) }
    if !result.centered { append(.offCenter, to: &result.issues) }
    if !result.distanceAcceptable { append(.distance, to: &result.issues) }
    if !result.lightingAcceptable { append(.lowLight, to: &result.issues) }
    if !result.headStable { append(.unstable, to: &result.issues) }
    return result
  }

  private func isAcceptable(_ passingCount: Int) -> Bool {
    Double(passingCount) / Double(observationCount) >= Self.minimumAcceptableFraction
  }

  private func append(
    _ issue: CaptureQualityIssue,
    to issues: inout [CaptureQualityIssue]
  ) {
    if !issues.contains(issue) { issues.append(issue) }
  }
}

/// ARKit face and eye capture for the research prototype. The service keeps a
/// bounded in-memory buffer of numeric landmarks. Camera frames are displayed
/// by ARSCNView but are never persisted or uploaded by this code.
@MainActor
final class FaceTrackingService: NSObject, ObservableObject {
  @Published private(set) var status: FaceTrackingStatus = .idle
  @Published private(set) var sampleCount = 0
  @Published private(set) var quality: CaptureQualitySnapshot = .idle

  private(set) var session = ARSession()

  private let permissionStore: any PermissionStore
  private let analyzer = OcularSignalAnalyzer()
  private var samples: [OcularSample] = []
  private let maximumSamples = 1_800
  private var observedFrameCount = 0
  private var protocolStartedAt: TimeInterval?
  private var captureStartedAt: TimeInterval?
  private var recentHeadPositions: [SIMD3<Float>] = []
  private var qualityHistory = CaptureQualityHistory()
  private var wantsSessionRunning = false
  private var lastFaceSeenAt: TimeInterval?
  private var activeProtocolVariant: OcularProtocolVariant = .full

  init(permissionStore: any PermissionStore = SystemPermissionStore()) {
    self.permissionStore = permissionStore
    super.init()
    session.delegate = self
    if !isSupported {
      quality = .unsupported
      status = .unsupported
    }
  }

  var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

  func attach(to newSession: ARSession) {
    guard session !== newSession else { return }
    session.pause()
    session.delegate = nil
    session = newSession
    session.delegate = self
    if wantsSessionRunning {
      runSessionIfAuthorized()
    }
  }

  func startCalibration() {
    beginCapture()
  }

  func startOcularProtocol(variant: OcularProtocolVariant = .full) {
    activeProtocolVariant = variant
    protocolStartedAt = ProcessInfo.processInfo.systemUptime
    beginCapture(preserveProtocolStart: true)
  }

  func pause() {
    wantsSessionRunning = false
    session.pause()
    if status == .tracking { status = .idle }
  }

  func stopOcularProtocol() -> GazeCaptureSummary {
    wantsSessionRunning = false
    session.pause()

    var finalQuality = qualityHistory.applying(to: quality)
    if let lastFaceSeenAt,
      ProcessInfo.processInfo.systemUptime - lastFaceSeenAt > 0.75
    {
      finalQuality.facePresent = false
      finalQuality.issues = mergeIssues(finalQuality.issues, [.noFace, .interrupted])
    }

    let summary = analyzer.summarize(
      samples: samples,
      observedFrameCount: observedFrameCount,
      liveQuality: finalQuality,
      variant: activeProtocolVariant
    )
    quality = summary.quality
    status = summary.quality.isUsable
      ? .tracking
      : .limited(summary.quality.primaryGuidance)
    return summary
  }

  /// Builds a summary for an ocular protocol that never produced measurements
  /// (unsupported device, denied permission, or a skipped task).
  ///
  /// The snapshot must not inherit measurement fields from the earlier
  /// calibration capture: a skipped task would otherwise be recorded as a
  /// high-quality eye-tracking capture in the research archive.
  func unusableSummary(issue: CaptureQualityIssue) -> GazeCaptureSummary {
    var snapshot = issue == .unsupported ? .unsupported : quality
    if issue == .permissionDenied {
      snapshot.hasCameraPermission = false
    }
    snapshot.facePresent = false
    snapshot.centered = false
    snapshot.distanceAcceptable = false
    snapshot.lightingAcceptable = false
    snapshot.headStable = false
    snapshot.frameRate = 0
    snapshot.sampleCount = 0
    snapshot.dropoutRatio = 1
    snapshot.issues = mergeIssues(snapshot.issues, [issue, .insufficientSamples])

    return GazeCaptureSummary(
      smoothnessRisk: 1,
      qualityScore: 0,
      sampleCount: 0,
      capturedDurationMilliseconds: 0,
      quality: snapshot,
      features: .unavailable,
      protocolVariant: activeProtocolVariant
    )
  }

  private func beginCapture(preserveProtocolStart: Bool = false) {
    samples.removeAll(keepingCapacity: true)
    sampleCount = 0
    observedFrameCount = 0
    captureStartedAt = nil
    recentHeadPositions.removeAll(keepingCapacity: true)
    qualityHistory = CaptureQualityHistory()
    lastFaceSeenAt = nil
    wantsSessionRunning = true
    if !preserveProtocolStart { protocolStartedAt = nil }

    guard isSupported else {
      quality = .unsupported
      status = .unsupported
      return
    }

    runSessionIfAuthorized()
  }

  private func runSessionIfAuthorized() {
    switch permissionStore.cameraAuthorization {
    case .authorized:
      startAuthorizedSession()
    case .notDetermined:
      status = .searching
      Task { [weak self] in
        guard let self else { return }
        let nextState = await self.permissionStore.requestCameraAuthorization()
        if nextState == .authorized {
          self.startAuthorizedSession()
        } else {
          self.markPermissionDenied()
        }
      }
    case .denied, .restricted:
      markPermissionDenied()
    @unknown default:
      markPermissionDenied()
    }
  }

  private func startAuthorizedSession() {
    guard wantsSessionRunning else { return }
    let configuration = ARFaceTrackingConfiguration()
    configuration.isLightEstimationEnabled = true
    session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    quality = CaptureQualitySnapshot(
      isSupported: true,
      hasCameraPermission: true,
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
    status = .searching
  }

  private func markPermissionDenied() {
    wantsSessionRunning = false
    quality = CaptureQualitySnapshot(
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
      issues: [.permissionDenied]
    )
    status = .permissionDenied
  }

  private func ingest(
    face: ARFaceAnchor,
    timestamp: TimeInterval,
    ambientIntensity: CGFloat?
  ) {
    guard wantsSessionRunning else { return }
    if captureStartedAt == nil { captureStartedAt = timestamp }
    lastFaceSeenAt = ProcessInfo.processInfo.systemUptime

    let leftForward = face.leftEyeTransform.columns.2
    let rightForward = face.rightEyeTransform.columns.2
    let head = face.transform
    let headPosition = SIMD3<Float>(head.columns.3.x, head.columns.3.y, head.columns.3.z)
    recentHeadPositions.append(headPosition)
    if recentHeadPositions.count > 30 {
      recentHeadPositions.removeFirst(recentHeadPositions.count - 30)
    }

    let target: OcularTarget
    if let protocolStartedAt {
      target = OcularProtocolSchedule.target(at: timestamp - protocolStartedAt, variant: activeProtocolVariant)
    } else {
      target = OcularTarget(phase: .calibration, x: 0.5, y: 0.5)
    }

    let blinkLeft = face.blendShapes[.eyeBlinkLeft]?.doubleValue
    let blinkRight = face.blendShapes[.eyeBlinkRight]?.doubleValue
    samples.append(OcularSample(
      timestamp: timestamp,
      phase: target.phase,
      targetX: target.x,
      targetY: target.y,
      leftGazeX: Double(leftForward.x),
      leftGazeY: Double(leftForward.y),
      rightGazeX: Double(rightForward.x),
      rightGazeY: Double(rightForward.y),
      headX: Double(head.columns.2.x),
      headY: Double(head.columns.2.y),
      headZ: Double(head.columns.2.z),
      blinkLeft: blinkLeft,
      blinkRight: blinkRight
    ))
    if samples.count > maximumSamples {
      samples.removeFirst(samples.count - maximumSamples)
    }
    sampleCount = samples.count

    let duration = max(timestamp - (captureStartedAt ?? timestamp), 0.1)
    let frameRate = samples.count > 1 ? Double(samples.count - 1) / duration : 0
    let dropoutRatio = observedFrameCount > 0
      ? max(1 - (Double(samples.count) / Double(observedFrameCount)), 0)
      : 1
    let centered = abs(Double(headPosition.x)) <= 0.13 && abs(Double(headPosition.y)) <= 0.18
    let distance = abs(Double(headPosition.z))
    let distanceAcceptable = (0.25...0.75).contains(distance)
    let lightingAcceptable = (ambientIntensity ?? 0) >= 180
    let headStable = recentHeadMovement() <= 0.025

    qualityHistory.record(
      facePresent: face.isTracked,
      centered: centered,
      distanceAcceptable: distanceAcceptable,
      lightingAcceptable: lightingAcceptable,
      headStable: headStable
    )

    var issues: [CaptureQualityIssue] = []
    if !face.isTracked { issues.append(.noFace) }
    if !centered { issues.append(.offCenter) }
    if !distanceAcceptable { issues.append(.distance) }
    if !lightingAcceptable { issues.append(.lowLight) }
    if !headStable { issues.append(.unstable) }
    if samples.count >= 20, frameRate < 20 { issues.append(.lowFrameRate) }
    if samples.count < 20 { issues.append(.insufficientSamples) }

    quality = CaptureQualitySnapshot(
      isSupported: true,
      hasCameraPermission: true,
      facePresent: face.isTracked,
      centered: centered,
      distanceAcceptable: distanceAcceptable,
      lightingAcceptable: lightingAcceptable,
      headStable: headStable,
      frameRate: frameRate,
      sampleCount: samples.count,
      dropoutRatio: dropoutRatio,
      issues: issues
    )
    status = quality.isUsable ? .tracking : .limited(quality.primaryGuidance)
  }

  private func recentHeadMovement() -> Double {
    guard recentHeadPositions.count > 2 else { return 1 }
    var total = 0.0
    for index in 1..<recentHeadPositions.count {
      total += Double(simd_distance(recentHeadPositions[index], recentHeadPositions[index - 1]))
    }
    return total / Double(recentHeadPositions.count - 1)
  }

  private func mergeIssues(
    _ existing: [CaptureQualityIssue],
    _ additions: [CaptureQualityIssue]
  ) -> [CaptureQualityIssue] {
    var result = existing
    for issue in additions where !result.contains(issue) { result.append(issue) }
    return result
  }
}

extension FaceTrackingService: ARSessionDelegate {
  nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
    Task { @MainActor [weak self] in
      guard let self, self.wantsSessionRunning else { return }
      self.observedFrameCount += 1
    }
  }

  nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
    guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
    let timestamp = session.currentFrame?.timestamp ?? ProcessInfo.processInfo.systemUptime
    let ambientIntensity = session.currentFrame?.lightEstimate?.ambientIntensity

    Task { @MainActor [weak self] in
      self?.ingest(face: face, timestamp: timestamp, ambientIntensity: ambientIntensity)
    }
  }

  nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
    let nextStatus: FaceTrackingStatus
    switch camera.trackingState {
    case .normal:
      nextStatus = .searching
    case .notAvailable:
      nextStatus = .limited("Face tracking unavailable")
    case .limited(let reason):
      switch reason {
      case .excessiveMotion: nextStatus = .limited("Hold the phone steadier")
      case .insufficientFeatures: nextStatus = .limited("Move into more even light")
      case .initializing: nextStatus = .searching
      case .relocalizing: nextStatus = .limited("Re-centering…")
      @unknown default: nextStatus = .limited("Tracking quality is limited")
      }
    }

    Task { @MainActor [weak self] in
      guard let self, self.status != .permissionDenied, self.status != .unsupported else { return }
      if !self.quality.isUsable { self.status = nextStatus }
    }
  }
}
