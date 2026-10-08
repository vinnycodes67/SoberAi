@preconcurrency import ARKit
import AVFoundation
import Combine
import Foundation
import os
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
  private var multipleFaceCount = 0

  /// More than this fraction of frames with another face in view and the
  /// capture does not count. A little slack absorbs a one-frame false
  /// detection; anything sustained could mean tracking followed someone else.
  static let maximumMultipleFaceFraction = 0.05

  mutating func record(
    facePresent: Bool,
    centered: Bool,
    distanceAcceptable: Bool,
    lightingAcceptable: Bool,
    headStable: Bool,
    otherFacesInView: Bool = false
  ) {
    observationCount += 1
    facePresentCount += facePresent ? 1 : 0
    centeredCount += centered ? 1 : 0
    distanceAcceptableCount += distanceAcceptable ? 1 : 0
    lightingAcceptableCount += lightingAcceptable ? 1 : 0
    headStableCount += headStable ? 1 : 0
    multipleFaceCount += otherFacesInView ? 1 : 0
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
    if Double(multipleFaceCount) / Double(observationCount) > Self.maximumMultipleFaceFraction {
      result.otherFacesInView = true
      result.issues.removeAll { $0 == .multipleFaces }
      result.issues.insert(.multipleFaces, at: 0)
    }
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
  /// Smoothed, debounced head position for guidance. Never used to judge
  /// whether a capture is valid -- `quality` still does that.
  @Published private(set) var headPosition: HeadPosition = .faceNotDetected
  /// VALID / DEGRADED / INVALID with one actionable sentence.
  @Published private(set) var assessment = CaptureAssessment(verdict: .invalid, guidance: nil)

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
  private var positionGuide = HeadPositionGuide()
  /// Set when ARKit reports the session failed or was interrupted during this
  /// capture. The samples on either side of the gap are not one continuous
  /// recording, so the capture is not scored, however good it looks after.
  private var captureWasInterrupted = false
  private var telemetry = CaptureTelemetryRecorder()
  private var latestImage: CaptureImageStats?
  /// Face centre on the mirrored preview, for directional guidance.
  private var screenOffset: CGPoint?
  /// Image statistics are sampled on every Nth camera frame. Read from ARKit's
  /// delegate queue, so it lives behind a lock rather than on the main actor.
  private nonisolated let imageSampleCounter = OSAllocatedUnfairLock(initialState: 0)
  private nonisolated static let imageSampleInterval = 6

  init(permissionStore: any PermissionStore = SystemPermissionStore()) {
    self.permissionStore = permissionStore
    super.init()
    session.delegate = self
    if !isSupported {
      quality = .unsupported
      status = .unsupported
    }
  }

  var isSupported: Bool { Self.deviceSupportsFaceTracking }

  /// Hardware capability only: true on any iPhone with a TrueDepth camera,
  /// whether or not camera access has been granted.
  static var deviceSupportsFaceTracking: Bool { ARFaceTrackingConfiguration.isSupported }

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
    if captureWasInterrupted {
      // Same treatment as a face lost at the end: `isUsable` does not read
      // `issues`, so the capture is invalidated through `facePresent`.
      finalQuality.facePresent = false
      finalQuality.issues = mergeIssues(finalQuality.issues, [.interrupted])
    }
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
    assessment = CaptureAssessment.assess(summary.quality, image: telemetry.averageImage)
    return summary.with(telemetry: telemetry.summary(verdict: assessment.verdict))
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
    positionGuide.reset()
    headPosition = .faceNotDetected
    captureWasInterrupted = false
    telemetry = CaptureTelemetryRecorder()
    latestImage = nil
    screenOffset = nil
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
    // One face is the default, and ARKit silently picks it. Tracking more is
    // the only way to notice a second person in frame.
    configuration.maximumNumberOfTrackedFaces =
      min(ARFaceTrackingConfiguration.supportedNumberOfTrackedFaces, 3)
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
    trackedFaceCount: Int,
    screenOffset: CGPoint?,
    timestamp: TimeInterval,
    ambientIntensity: CGFloat?
  ) {
    guard wantsSessionRunning else { return }
    let otherFacesInView = trackedFaceCount > 1
    telemetry.recordFace(
      tracked: face.isTracked, faceCount: trackedFaceCount,
      timestamp: timestamp, now: ProcessInfo.processInfo.systemUptime)
    self.screenOffset = screenOffset
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

    // `headPosition` in this scope is the local SIMD3; the guide is published
    // on the property of the same name.
    self.headPosition = face.isTracked
      ? positionGuide.update(
        x: Double(headPosition.x), y: Double(headPosition.y), z: Double(headPosition.z))
      : positionGuide.update(x: nil, y: nil, z: nil)

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
      headStable: headStable,
      otherFacesInView: otherFacesInView
    )

    var issues: [CaptureQualityIssue] = []
    if otherFacesInView { issues.append(.multipleFaces) }
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
      issues: issues,
      otherFacesInView: otherFacesInView
    )
    invalidateLiveCaptureIfInterrupted()
    assessment = CaptureAssessment.assess(quality, image: latestImage)
    status = quality.isUsable ? .tracking : .limited(liveGuidance)
  }

  /// What to tell the person while the capture is not yet usable.
  ///
  /// Position comes from the debounced guide rather than the raw per-frame
  /// issues, which flip whenever a head rests on a threshold. Once the guide
  /// is satisfied, raw position issues are ignored for copy and the next real
  /// problem -- light, stillness, frame rate -- is shown instead.
  private var liveGuidance: String {
    if quality.issues.first == .interrupted { return CaptureQualityIssue.interrupted.guidance }
    if quality.otherFacesInView { return CaptureQualityIssue.multipleFaces.guidance }
    if case .offCenter(let horizontal, let vertical) = headPosition,
      DirectionalGuidance.isEnabled, let screenOffset,
      let directional = DirectionalGuidance.text(
        screenOffset: screenOffset, horizontal: horizontal != nil, vertical: vertical != nil)
    {
      return directional
    }
    if headPosition != .centered { return headPosition.guidance }
    let positional: [CaptureQualityIssue] = [.noFace, .offCenter, .distance]
    return quality.issues.first { !positional.contains($0) }?.guidance
      ?? HeadPosition.centered.guidance
  }

  // MARK: - Session failure and interruption

  /// ARKit stopped delivering frames while the app stayed in the foreground
  /// -- another process took the camera, or the hardware became unavailable.
  /// Backgrounding is handled separately by `ScreeningFlowView` through
  /// `scenePhase`.
  func handleSessionInterrupted() {
    guard wantsSessionRunning else { return }
    captureWasInterrupted = true
    invalidateLiveCaptureIfInterrupted()
    status = .limited("Camera interrupted. Hold on while it reconnects.")
  }

  /// The camera is back. Restart from a clean tracking state so the frames
  /// that resume are not stitched onto the ones before the gap; the capture
  /// itself stays marked interrupted and will not be scored.
  func handleSessionInterruptionEnded() {
    guard wantsSessionRunning, isSupported,
      permissionStore.cameraAuthorization == .authorized
    else { return }
    recentHeadPositions.removeAll(keepingCapacity: true)
    positionGuide.reset()
    headPosition = .faceNotDetected
    startAuthorizedSession()
  }

  /// ARKit gave up. Permission revoked mid-session is reported as such so the
  /// existing Settings path applies; anything else is a camera failure the
  /// person cannot fix by moving, so the capture ends rather than waiting.
  func handleSessionFailure(_ error: any Error) {
    // A failure reported after the capture ended must not rewrite the status
    // behind the result screen.
    guard wantsSessionRunning else { return }
    captureWasInterrupted = true
    if let arError = error as? ARError, arError.code == .cameraUnauthorized {
      markPermissionDenied()
      return
    }
    wantsSessionRunning = false
    session.pause()
    quality.issues = mergeIssues(quality.issues, [.interrupted])
    invalidateLiveCaptureIfInterrupted()
    status = .limited("The camera stopped. End the task and try again.")
  }

  /// An interrupted eye-task capture is rejected at the end however it looks
  /// after the gap, so the live quality has to say so as well. Left usable,
  /// the task carried on, the recovery screen never appeared, and the person
  /// waited out a run that could not count with no way to end it.
  ///
  /// Calibration is exempt: its frames are never scored, and the eye task
  /// starts a fresh capture.
  private func invalidateLiveCaptureIfInterrupted() {
    guard captureWasInterrupted, protocolStartedAt != nil else { return }
    quality.facePresent = false
    quality.issues = [.interrupted] + quality.issues.filter { $0 != .interrupted }
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
    // Measured here, on ARKit's queue, so the frame itself is never retained
    // or sent anywhere: only four numbers cross to the main actor.
    let sampleNow = imageSampleCounter.withLock { count -> Bool in
      count += 1
      return count % Self.imageSampleInterval == 0
    }
    let image = sampleNow ? Self.imageStats(of: frame.capturedImage) : nil
    Task { @MainActor [weak self] in
      guard let self, self.wantsSessionRunning else { return }
      self.observedFrameCount += 1
      self.telemetry.recordFrame()
      if let image {
        self.latestImage = image
        self.telemetry.recordImage(image)
      }
    }
  }

  private nonisolated static func imageStats(of pixelBuffer: CVPixelBuffer) -> CaptureImageStats? {
    guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 1 else { return nil }
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
    return CaptureImageStats.measure(
      luma: base.assumingMemoryBound(to: UInt8.self),
      width: CVPixelBufferGetWidthOfPlane(pixelBuffer, 0),
      height: CVPixelBufferGetHeightOfPlane(pixelBuffer, 0),
      bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
    )
  }

  nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
    guard anchors.contains(where: { $0 is ARFaceAnchor }) else { return }
    let frame = session.currentFrame
    // Every face in the frame, not just the ones in this update, so a second
    // person is counted even on frames where only the first one moved.
    let faces = (frame?.anchors ?? anchors).compactMap { $0 as? ARFaceAnchor }
    let tracked = faces.filter(\.isTracked)
    // Follow the nearest face: the person holding the phone.
    guard let face = tracked.min(by: { abs($0.transform.columns.3.z) < abs($1.transform.columns.3.z) })
      ?? faces.first
    else { return }
    let timestamp = frame?.timestamp ?? ProcessInfo.processInfo.systemUptime
    let ambientIntensity = frame?.lightEstimate?.ambientIntensity
    let screenOffset = frame.map { frame -> CGPoint in
      let centre = face.transform.columns.3
      let projected = frame.camera.projectPoint(
        simd_float3(centre.x, centre.y, centre.z), orientation: .portrait,
        viewportSize: CGSize(width: 1, height: 1))
      return DirectionalGuidance.mirroredOffset(fromProjected: projected)
    }

    Task { @MainActor [weak self] in
      self?.ingest(
        face: face, trackedFaceCount: tracked.count, screenOffset: screenOffset,
        timestamp: timestamp, ambientIntensity: ambientIntensity)
    }
  }

  nonisolated func session(_ session: ARSession, didFailWithError error: any Error) {
    Task { @MainActor [weak self] in self?.handleSessionFailure(error) }
  }

  nonisolated func sessionWasInterrupted(_ session: ARSession) {
    Task { @MainActor [weak self] in self?.handleSessionInterrupted() }
  }

  nonisolated func sessionInterruptionEnded(_ session: ARSession) {
    Task { @MainActor [weak self] in self?.handleSessionInterruptionEnded() }
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
