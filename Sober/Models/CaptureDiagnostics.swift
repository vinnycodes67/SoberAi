import CoreGraphics
import Foundation

// MARK: - Image statistics

/// Brightness and sharpness of the camera image, measured on the phone from a
/// sparse grid of luma samples. Nothing here leaves the device or is kept
/// beyond these few numbers.
///
/// The thresholds that read these are engineering guesses, not calibrated on
/// people. They can only mark a capture *degraded*; whether a capture counts
/// is still decided by `CaptureQualitySnapshot.isUsable`.
struct CaptureImageStats: Codable, Equatable, Sendable {
  /// Mean brightness, 0 to 1.
  var meanLuma: Double
  /// Fraction of samples at or above 98% brightness.
  var clippedFraction: Double
  /// Fraction of samples at or below 2% brightness.
  var crushedFraction: Double
  /// Mean absolute Laplacian over the centre of the frame, 0 to 1. A blurred
  /// or out-of-focus image has little local contrast and scores near zero.
  var sharpness: Double

  static let darkMeanLuma = 0.18
  static let clippedLimit = 0.06
  static let crushedLimit = 0.25
  static let blurLimit = 0.012

  var isTooDark: Bool { meanLuma < Self.darkMeanLuma || crushedFraction > Self.crushedLimit }
  var isOverexposed: Bool { clippedFraction > Self.clippedLimit }
  var isBlurry: Bool { sharpness < Self.blurLimit }

  /// Samples the central 60% of an 8-bit luma plane on a `grid` x `grid`
  /// lattice. Each sample's Laplacian uses its immediate pixel neighbours, so
  /// fine focus is measured even though only a few thousand pixels are read.
  static func measure(
    luma: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int, grid: Int = 48
  ) -> CaptureImageStats? {
    guard width >= 8, height >= 8, grid >= 2 else { return nil }
    let x0 = Int(Double(width) * 0.2)
    let y0 = Int(Double(height) * 0.2)
    let spanX = max(Int(Double(width) * 0.6) - 2, 1)
    let spanY = max(Int(Double(height) * 0.6) - 2, 1)

    var total = 0.0
    var clipped = 0
    var crushed = 0
    var laplacian = 0.0
    var count = 0
    for gy in 0..<grid {
      let y = min(max(y0 + gy * spanY / (grid - 1), 1), height - 2)
      for gx in 0..<grid {
        let x = min(max(x0 + gx * spanX / (grid - 1), 1), width - 2)
        func at(_ px: Int, _ py: Int) -> Double { Double(luma[py * bytesPerRow + px]) }
        let centre = at(x, y)
        total += centre
        if centre >= 250 { clipped += 1 }
        if centre <= 5 { crushed += 1 }
        laplacian += abs(4 * centre - at(x - 1, y) - at(x + 1, y) - at(x, y - 1) - at(x, y + 1))
        count += 1
      }
    }
    let n = Double(count)
    return CaptureImageStats(
      meanLuma: total / n / 255,
      clippedFraction: Double(clipped) / n,
      crushedFraction: Double(crushed) / n,
      sharpness: laplacian / n / (4 * 255)
    )
  }
}

// MARK: - Verdict

/// One level for how good a capture is, with one sentence the person can act
/// on. `invalid` is exactly `!isUsable`: the capture does not count. `degraded`
/// still counts, but something measurable was marginal, and the session
/// records it so thresholds can be calibrated against real captures later.
enum CaptureVerdict: String, Codable, Equatable, Sendable {
  case valid
  case degraded
  case invalid

  var title: String {
    switch self {
    case .valid: "Capture is clear"
    case .degraded: "Capture is usable but marginal"
    case .invalid: "Capture can't be used"
    }
  }
}

struct CaptureAssessment: Equatable, Sendable {
  let verdict: CaptureVerdict
  /// What to do about it. Nil when the capture is clear.
  let guidance: String?

  static func assess(_ quality: CaptureQualitySnapshot, image: CaptureImageStats?) -> CaptureAssessment {
    guard quality.isUsable else {
      return CaptureAssessment(verdict: .invalid, guidance: quality.primaryGuidance)
    }
    if let image {
      if image.isTooDark {
        return CaptureAssessment(verdict: .degraded, guidance: "Brighter, even light will make this clearer.")
      }
      if image.isOverexposed {
        return CaptureAssessment(verdict: .degraded, guidance: "Turn away from bright light behind or beside you.")
      }
      if image.isBlurry {
        return CaptureAssessment(verdict: .degraded, guidance: "The image is soft. Hold the phone steady and wipe the camera.")
      }
    }
    if quality.frameRate < 30 {
      return CaptureAssessment(verdict: .degraded, guidance: "The camera is running slowly. Hold still.")
    }
    if quality.dropoutRatio > 0.15 {
      return CaptureAssessment(verdict: .degraded, guidance: "Your face dropped out briefly. Keep it inside the guide.")
    }
    return CaptureAssessment(verdict: .valid, guidance: nil)
  }
}

// MARK: - Benchmark telemetry

/// What one capture measured about the tracking itself: how often a face was
/// found, how often it was lost and how fast it came back, how far behind the
/// camera the processing ran. Kept with the session on the phone, so vision
/// performance can be stated from real captures instead of guessed.
struct CaptureTelemetry: Codable, Equatable, Sendable {
  var framesObserved: Int
  var framesWithFace: Int
  var trackingLosses: Int
  var medianRecoveryMilliseconds: Double?
  var maxRecoveryMilliseconds: Double?
  var medianLatencyMilliseconds: Double?
  var p95LatencyMilliseconds: Double?
  /// Fraction of face frames in which more than one face was tracked.
  var multipleFaceFraction: Double
  var image: CaptureImageStats?
  var verdict: CaptureVerdict?

  var detectionRate: Double {
    framesObserved > 0 ? Double(framesWithFace) / Double(framesObserved) : 0
  }
}

/// Accumulates `CaptureTelemetry` during one capture. Bounded: it keeps
/// counts, the latest few hundred latencies and recoveries, and a running
/// image average.
struct CaptureTelemetryRecorder: Sendable {
  private(set) var framesObserved = 0
  private(set) var framesWithFace = 0
  private(set) var trackingLosses = 0
  private var multipleFaceFrames = 0
  private var lostAt: TimeInterval?
  private var wasTracked = false
  private var recoveries: [Double] = []
  private var latencies: [Double] = []
  private var imageSum: CaptureImageStats?
  private var imageCount = 0

  private static let keep = 600

  mutating func recordFrame() {
    framesObserved += 1
  }

  /// One face update. `timestamp` is the camera frame's capture time and
  /// `now` when it was processed, both on the system uptime clock.
  mutating func recordFace(tracked: Bool, faceCount: Int, timestamp: TimeInterval, now: TimeInterval) {
    if tracked {
      framesWithFace += 1
      if faceCount > 1 { multipleFaceFrames += 1 }
      if let lostAt {
        append(&recoveries, (timestamp - lostAt) * 1000)
        self.lostAt = nil
      }
      let latency = (now - timestamp) * 1000
      if latency.isFinite, latency >= 0 { append(&latencies, latency) }
    } else if wasTracked {
      trackingLosses += 1
      lostAt = timestamp
    }
    wasTracked = tracked
  }

  mutating func recordImage(_ stats: CaptureImageStats) {
    imageCount += 1
    guard var sum = imageSum else {
      imageSum = stats
      return
    }
    sum.meanLuma += stats.meanLuma
    sum.clippedFraction += stats.clippedFraction
    sum.crushedFraction += stats.crushedFraction
    sum.sharpness += stats.sharpness
    imageSum = sum
  }

  var averageImage: CaptureImageStats? {
    guard let sum = imageSum, imageCount > 0 else { return nil }
    let n = Double(imageCount)
    return CaptureImageStats(
      meanLuma: sum.meanLuma / n, clippedFraction: sum.clippedFraction / n,
      crushedFraction: sum.crushedFraction / n, sharpness: sum.sharpness / n)
  }

  func summary(verdict: CaptureVerdict?) -> CaptureTelemetry {
    CaptureTelemetry(
      framesObserved: framesObserved,
      framesWithFace: framesWithFace,
      trackingLosses: trackingLosses,
      medianRecoveryMilliseconds: Self.percentile(recoveries, 0.5),
      maxRecoveryMilliseconds: recoveries.max(),
      medianLatencyMilliseconds: Self.percentile(latencies, 0.5),
      p95LatencyMilliseconds: Self.percentile(latencies, 0.95),
      multipleFaceFraction: framesWithFace > 0 ? Double(multipleFaceFrames) / Double(framesWithFace) : 0,
      image: averageImage,
      verdict: verdict
    )
  }

  private func append(_ values: inout [Double], _ value: Double) {
    values.append(value)
    if values.count > Self.keep { values.removeFirst(values.count - Self.keep) }
  }

  static func percentile(_ values: [Double], _ p: Double) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let rank = p * Double(sorted.count - 1)
    let lower = Int(rank.rounded(.down))
    let upper = min(lower + 1, sorted.count - 1)
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (rank - Double(lower))
  }
}

// MARK: - Directional guidance

/// "Move left" instead of "Center your face", worked out from where the face
/// actually appears on the preview rather than from ARKit's world axes, whose
/// mapping to the person's left depends on world alignment.
///
/// The preview is a mirror: the front camera's image is flipped for display,
/// so a face drawn right of centre belongs to someone who should move to their
/// own left, which in a mirror is also the screen's left.
///
/// Off until one session on a Face ID iPhone confirms the words point the
/// right way (HANDOFF 2.1). A backwards instruction is worse than a neutral
/// one, so with it off the existing neutral copy stays.
enum DirectionalGuidance {
  static let isEnabled = false

  /// Offsets smaller than this, as a fraction of the preview, give no word for
  /// that axis.
  static let deadZone = 0.03

  /// `screenOffset` is the face centre on the preview as displayed, relative
  /// to the centre, in fractions of its width and height: +x right, +y down.
  /// `horizontal` and `vertical` say which axes the guide judged off-centre.
  static func text(screenOffset: CGPoint, horizontal: Bool, vertical: Bool) -> String? {
    var parts: [String] = []
    if vertical, abs(screenOffset.y) >= deadZone {
      parts.append(screenOffset.y > 0 ? "up" : "down")
    }
    if horizontal, abs(screenOffset.x) >= deadZone {
      parts.append(screenOffset.x > 0 ? "left" : "right")
    }
    guard !parts.isEmpty else { return nil }
    return "Move \(parts.joined(separator: " and ")) to center your face in the oval."
  }

  /// Maps a point from `ARCamera.projectPoint(_:orientation: .portrait,
  /// viewportSize: 1x1)`, which is in the unmirrored camera image, to an
  /// offset on the mirrored preview.
  static func mirroredOffset(fromProjected point: CGPoint) -> CGPoint {
    CGPoint(x: (1 - point.x) - 0.5, y: point.y - 0.5)
  }
}

// MARK: - Across sessions

/// The vision benchmark across every stored capture that recorded telemetry.
/// Medians across captures, so one bad session does not set the figure. Only
/// real captures on this phone feed it; there is nothing to show until one
/// has been made.
struct CaptureBenchmarkReport: Equatable, Sendable {
  let captures: Int
  let medianDetectionRate: Double
  let capturesWithTrackingLoss: Int
  let medianRecoveryMilliseconds: Double?
  let medianLatencyMilliseconds: Double?
  let worstP95LatencyMilliseconds: Double?
  let capturesWithAnotherFace: Int
  let verdicts: [CaptureVerdict: Int]

  init?(_ telemetry: [CaptureTelemetry]) {
    guard !telemetry.isEmpty else { return nil }
    captures = telemetry.count
    medianDetectionRate =
      CaptureTelemetryRecorder.percentile(telemetry.map(\.detectionRate), 0.5) ?? 0
    capturesWithTrackingLoss = telemetry.filter { $0.trackingLosses > 0 }.count
    medianRecoveryMilliseconds =
      CaptureTelemetryRecorder.percentile(telemetry.compactMap(\.medianRecoveryMilliseconds), 0.5)
    medianLatencyMilliseconds =
      CaptureTelemetryRecorder.percentile(telemetry.compactMap(\.medianLatencyMilliseconds), 0.5)
    worstP95LatencyMilliseconds = telemetry.compactMap(\.p95LatencyMilliseconds).max()
    capturesWithAnotherFace = telemetry.filter {
      $0.multipleFaceFraction > CaptureQualityHistory.maximumMultipleFaceFraction
    }.count
    verdicts = telemetry.compactMap(\.verdict).reduce(into: [:]) { $0[$1, default: 0] += 1 }
  }
}
