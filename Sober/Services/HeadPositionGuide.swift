import Foundation

/// Where the person's head is relative to the capture window, as guidance.
///
/// This drives what the person is *told*. It deliberately does not decide
/// whether a capture is usable -- `CaptureQualitySnapshot` still does that
/// from the raw per-frame thresholds, so adding smoothing here cannot loosen
/// or tighten what counts as valid data.
enum HeadPosition: Equatable, Sendable {
  case faceNotDetected
  case tooClose
  case tooFar
  /// Outside the centered band. Which way is recorded by ARKit axis, not by
  /// the person's left or right: the mapping from a world axis to "your left"
  /// depends on the session's world alignment and has not been confirmed on a
  /// device. A backwards instruction is worse than a neutral one, so the copy
  /// stays neutral until it has been.
  case offCenter(horizontal: AxisSide?, vertical: AxisSide?)
  case centered

  enum AxisSide: Equatable, Sendable {
    case negative
    case positive
  }

  /// Same case, ignoring which side an off-center head is on.
  func isSameKind(as other: HeadPosition) -> Bool {
    switch (self, other) {
    case (.offCenter, .offCenter): true
    default: self == other
    }
  }

  var guidance: String {
    switch self {
    case .faceNotDetected: "Keep your full face inside the guide."
    // Distance comes from |z|, so which way to move is not in doubt.
    case .tooClose: "Hold the phone a little farther away."
    case .tooFar: "Bring the phone a little closer."
    case .offCenter: "Center your face in the oval."
    case .centered: "Hold that position."
    }
  }
}

/// Turns noisy per-frame head positions into guidance that does not flicker.
///
/// Three layers, each fixing a different kind of noise:
///
/// - **Smoothing.** An exponential moving average on position, so a single
///   jittery frame cannot move the estimate across a threshold by itself.
/// - **Hysteresis.** Leaving the centered band uses the same thresholds the
///   quality gate uses; coming back requires getting clearly inside a tighter
///   band. A head resting on the boundary therefore stays in one state instead
///   of alternating CENTERED, LEFT, CENTERED, LEFT.
/// - **Debounce.** A new state has to hold for several consecutive frames
///   before it replaces the published one.
///
/// Pure value type with no ARKit dependency, so it is unit-tested directly.
/// Inputs are metres in ARKit world space; only |z| is used for distance.
struct HeadPositionGuide: Sendable {
  struct Thresholds: Sendable {
    /// Leaving the centered band. Identical to the quality gate in
    /// `FaceTrackingService.ingest`, so guidance and validity agree on where
    /// "off center" begins.
    var horizontalExit = 0.13
    var verticalExit = 0.18
    var nearExit = 0.25
    var farExit = 0.75
    /// Coming back. Tighter, so a boundary position cannot oscillate.
    var horizontalEnter = 0.10
    var verticalEnter = 0.14
    var nearEnter = 0.28
    var farEnter = 0.70
  }

  var thresholds = Thresholds()
  /// Weight of the newest frame. Low enough to absorb single-frame jitter,
  /// high enough that real movement shows up within a few frames at 60 fps.
  var smoothing = 0.35
  /// Consecutive frames a new state must hold before it is published.
  var framesToSwitch = 3

  private(set) var current: HeadPosition = .faceNotDetected

  private var smoothedX: Double?
  private var smoothedY: Double?
  private var smoothedDistance: Double?
  private var pending: HeadPosition?
  private var pendingCount = 0

  /// Feed one frame. `nil` position means no face this frame.
  @discardableResult
  mutating func update(x: Double?, y: Double?, z: Double?) -> HeadPosition {
    guard let x, let y, let z, x.isFinite, y.isFinite, z.isFinite else {
      smoothedX = nil
      smoothedY = nil
      smoothedDistance = nil
      return propose(.faceNotDetected)
    }

    let distance = abs(z)
    smoothedX = blend(smoothedX, x)
    smoothedY = blend(smoothedY, y)
    smoothedDistance = blend(smoothedDistance, distance)

    return propose(classify(
      x: smoothedX ?? x, y: smoothedY ?? y, distance: smoothedDistance ?? distance))
  }

  mutating func reset() {
    self = HeadPositionGuide(
      thresholds: thresholds, smoothing: smoothing, framesToSwitch: framesToSwitch)
  }

  private func blend(_ previous: Double?, _ next: Double) -> Double {
    guard let previous else { return next }
    return previous + smoothing * (next - previous)
  }

  /// Distance first: off-center guidance is meaningless while the face is too
  /// near or too far to frame. Each band applies its exit threshold when the
  /// guide currently considers that dimension fine, and its tighter enter
  /// threshold when it currently does not.
  private func classify(x: Double, y: Double, distance: Double) -> HeadPosition {
    let t = thresholds

    let distanceIsFine: Bool
    switch current {
    case .tooClose, .tooFar, .faceNotDetected:
      distanceIsFine = (t.nearEnter...t.farEnter).contains(distance)
    default:
      distanceIsFine = (t.nearExit...t.farExit).contains(distance)
    }
    if !distanceIsFine {
      return distance < (t.nearExit + t.farExit) / 2 ? .tooClose : .tooFar
    }

    let wasCentered = current == .centered
    let horizontalLimit = wasCentered ? t.horizontalExit : t.horizontalEnter
    let verticalLimit = wasCentered ? t.verticalExit : t.verticalEnter

    let horizontal: HeadPosition.AxisSide? =
      abs(x) > horizontalLimit ? (x < 0 ? .negative : .positive) : nil
    let vertical: HeadPosition.AxisSide? =
      abs(y) > verticalLimit ? (y < 0 ? .negative : .positive) : nil

    if horizontal == nil, vertical == nil { return .centered }
    return .offCenter(horizontal: horizontal, vertical: vertical)
  }

  /// Debounces by kind of state, not by its direction. Off-center by x, then
  /// by x and y, is the same instruction; counting those as different reset
  /// the counter on every alternation, and a head wobbling near one limit kept
  /// "Hold that position" on screen while the capture gate said off-center.
  private mutating func propose(_ candidate: HeadPosition) -> HeadPosition {
    guard !candidate.isSameKind(as: current) else {
      current = candidate
      pending = nil
      pendingCount = 0
      return current
    }
    if let pending, candidate.isSameKind(as: pending) {
      self.pending = candidate
      pendingCount += 1
    } else {
      pending = candidate
      pendingCount = 1
    }
    if pendingCount >= framesToSwitch {
      current = candidate
      pending = nil
      pendingCount = 0
    }
    return current
  }
}
