@preconcurrency import ARKit
import Combine
import Foundation
import simd

enum FaceTrackingStatus: Equatable {
  case idle
  case unsupported
  case tracking
  case limited(String)

  var label: String {
    switch self {
    case .idle: "Camera ready"
    case .unsupported: "Guided demo trace"
    case .tracking: "Face tracking steady"
    case .limited(let reason): reason
    }
  }
}

struct GazeCaptureSummary: Sendable {
  let smoothnessRisk: Double
  let qualityScore: Double
  let sampleCount: Int
}

private struct GazeSample: Sendable {
  let timestamp: TimeInterval
  let gazeX: Float
  let gazeY: Float
  let headX: Float
  let headY: Float
  let headZ: Float
}

/// Minimal Phase-1 ARKit harness for the MVP. It retains only a bounded,
/// in-memory ring of numeric samples and never writes camera frames to disk.
@MainActor
final class FaceTrackingService: NSObject, ObservableObject {
  @Published private(set) var status: FaceTrackingStatus = .idle
  @Published private(set) var sampleCount = 0

  private let session = ARSession()
  private var samples: [GazeSample] = []
  private let maximumSamples = 900
  private var trackingStartedAt: TimeInterval?

  override init() {
    super.init()
    session.delegate = self
  }

  var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

  func start() {
    samples.removeAll(keepingCapacity: true)
    sampleCount = 0
    trackingStartedAt = nil

    guard isSupported else {
      status = .unsupported
      return
    }

    let configuration = ARFaceTrackingConfiguration()
    configuration.isLightEstimationEnabled = true
    session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    status = .tracking
  }

  func stop() -> GazeCaptureSummary {
    session.pause()

    guard isSupported, samples.count > 8 else {
      status = isSupported ? .limited("Not enough camera samples") : .unsupported
      return GazeCaptureSummary(
        smoothnessRisk: isSupported ? 0.52 : 0.18,
        qualityScore: isSupported ? 0.42 : 0.93,
        sampleCount: samples.count
      )
    }

    let duration = max((samples.last?.timestamp ?? 0) - (samples.first?.timestamp ?? 0), 0.1)
    let frameRate = Double(samples.count - 1) / duration

    var gazeDelta = 0.0
    var headDelta = 0.0
    for index in 1..<samples.count {
      let current = samples[index]
      let previous = samples[index - 1]
      gazeDelta += hypot(
        Double(current.gazeX - previous.gazeX),
        Double(current.gazeY - previous.gazeY)
      )
      headDelta += sqrt(
        pow(Double(current.headX - previous.headX), 2)
          + pow(Double(current.headY - previous.headY), 2)
          + pow(Double(current.headZ - previous.headZ), 2)
      )
    }

    let averageGazeDelta = gazeDelta / Double(samples.count - 1)
    let averageHeadDelta = headDelta / Double(samples.count - 1)

    // Regress a conservative portion of head-pose leakage out of gaze
    // residuals. This is a prototype feature, not a validated HGN measure.
    let compensatedJitter = max(averageGazeDelta - (averageHeadDelta * 0.35), 0)
    let smoothnessRisk = min(max(compensatedJitter / 0.045, 0), 1)

    let frameQuality = min(frameRate / 45.0, 1)
    let stabilityQuality = max(1 - (averageHeadDelta / 0.035), 0)
    let quality = min(max((frameQuality * 0.72) + (stabilityQuality * 0.28), 0), 1)

    status = quality >= 0.72 ? .tracking : .limited("Hold the phone and your head steadier")
    return GazeCaptureSummary(
      smoothnessRisk: smoothnessRisk,
      qualityScore: quality,
      sampleCount: samples.count
    )
  }

  private func ingest(_ sample: GazeSample) {
    if trackingStartedAt == nil {
      trackingStartedAt = sample.timestamp
    }
    samples.append(sample)
    if samples.count > maximumSamples {
      samples.removeFirst(samples.count - maximumSamples)
    }
    sampleCount = samples.count
  }
}

extension FaceTrackingService: ARSessionDelegate {
  nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
    guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }

    // Eye transforms are face-local. Averaging their forward vectors gives
    // a head-relative gaze proxy and cancels gross head rotation.
    let leftForward = face.leftEyeTransform.columns.2
    let rightForward = face.rightEyeTransform.columns.2
    let head = face.transform
    let timestamp = session.currentFrame?.timestamp ?? ProcessInfo.processInfo.systemUptime

    let sample = GazeSample(
      timestamp: timestamp,
      gazeX: (leftForward.x + rightForward.x) / 2,
      gazeY: (leftForward.y + rightForward.y) / 2,
      headX: head.columns.2.x,
      headY: head.columns.2.y,
      headZ: head.columns.2.z
    )

    Task { @MainActor [weak self] in
      self?.ingest(sample)
    }
  }

  nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
    let nextStatus: FaceTrackingStatus
    switch camera.trackingState {
    case .normal:
      nextStatus = .tracking
    case .notAvailable:
      nextStatus = .limited("Face tracking unavailable")
    case .limited(let reason):
      switch reason {
      case .excessiveMotion: nextStatus = .limited("Hold the phone steadier")
      case .insufficientFeatures: nextStatus = .limited("Move into more even light")
      case .initializing: nextStatus = .limited("Finding your face…")
      case .relocalizing: nextStatus = .limited("Re-centering…")
      @unknown default: nextStatus = .limited("Tracking quality is limited")
      }
    }

    Task { @MainActor [weak self] in
      self?.status = nextStatus
    }
  }
}
