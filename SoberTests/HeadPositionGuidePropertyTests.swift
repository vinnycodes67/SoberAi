import XCTest

@testable import Sober

/// Randomized checks on head-position guidance.
///
/// `HeadPositionGuideTests` pins hand-picked frames. These feed thousands of
/// seeded random trajectories through the guide and check the rules that
/// have to hold for every one of them: guidance settles where the head
/// actually is, does not flicker, never points the wrong way on distance, and
/// survives garbage input. The seed is fixed, so a failure reproduces exactly;
/// every message carries the case index and the input that broke it.
final class HeadPositionGuidePropertyTests: XCTestCase {

  private let trajectories = 2_000
  private let holdFrames = 30
  private let t = HeadPositionGuide.Thresholds()

  // MARK: - Properties

  /// From a fresh guide, holding any finite position settles on exactly the
  /// state that position classifies to. A fresh guide starts at
  /// `.faceNotDetected`, which applies the tighter enter bands everywhere, so
  /// the answer from a cold start never depends on history.
  func testFromAColdStartAHeldPositionSettlesOnItsClassification() {
    var rng = SplitMix64(seed: 0x5EED_0001)
    var failures = 0
    for index in 0..<trajectories {
      let target = randomTarget(&rng)
      var guide = HeadPositionGuide()
      let state = hold(&guide, target, frames: holdFrames)
      let expected = classify(target, current: .faceNotDetected)
      if state != expected {
        failures += 1
        if failures <= 5 {
          XCTFail("case \(index): \(target) settled on \(state), expected \(expected)")
        }
      }
    }
  }

  /// After any history, a held position settles on a state the classifier
  /// would keep: the published state is a fixed point for that position. Where
  /// the position sits outside every hysteresis band there is only one such
  /// state, so there the answer is exact regardless of where the head was.
  func testAfterAnyHistoryAHeldPositionSettlesOnAFixedPoint() {
    var rng = SplitMix64(seed: 0x5EED_0002)
    var failures = 0
    var historyFree = 0
    for index in 0..<trajectories {
      var guide = HeadPositionGuide()
      feed(&guide, randomTrajectory(&rng))
      let target = randomTarget(&rng)
      let state = hold(&guide, target, frames: holdFrames)

      var problem: String?
      let kept = classify(target, current: state)
      if state != kept {
        problem = "settled on \(state), but that position classifies to \(kept) from there"
      } else if !inAnyHysteresisBand(target) {
        historyFree += 1
        let unique = classify(target, current: .faceNotDetected)
        if state != unique { problem = "settled on \(state), expected \(unique)" }
      }
      if let problem {
        failures += 1
        if failures <= 5 { XCTFail("case \(index): \(target) \(problem)") }
      }
    }
    // Guards against a generator that never leaves the bands.
    XCTAssertGreaterThan(historyFree, trajectories / 4)
  }

  /// A head held still with sensor noise much smaller than any hysteresis gap
  /// must not make the instruction change back and forth. The smoothed value
  /// stays inside a window narrower than every gap, so each dimension can
  /// cross a boundary at most once. Distance and centering are separate
  /// dimensions: when only one of them is near a boundary the instruction
  /// changes at most once; when both are, at most twice.
  func testSmallNoiseOnAStillHeadChangesTheInstructionAtMostOnce() {
    var rng = SplitMix64(seed: 0x5EED_0003)
    let noise = 0.004
    var failures = 0
    var sawAChange = false
    for index in 0..<trajectories {
      let base = randomTarget(&rng)
      var guide = HeadPositionGuide()
      for _ in 0..<holdFrames { step(&guide, jittered(base, noise, &rng)) }

      var changes = 0
      var last = guide.current
      for _ in 0..<200 {
        let state = step(&guide, jittered(base, noise, &rng))
        if !state.isSameKind(as: last) { changes += 1 }
        last = state
      }
      if changes > 0 { sawAChange = true }

      let distanceNear = [t.nearExit, t.nearEnter, t.farEnter, t.farExit]
        .contains { abs(base.distance - $0) <= noise }
      let centeringNear =
        [t.horizontalExit, t.horizontalEnter].contains { abs(abs(base.x) - $0) <= noise }
        || [t.verticalExit, t.verticalEnter].contains { abs(abs(base.y) - $0) <= noise }
      let allowed = (distanceNear && centeringNear) ? 2 : 1
      if changes > allowed {
        failures += 1
        if failures <= 5 {
          XCTFail("case \(index): \(base) with ±\(noise) noise changed \(changes) times")
        }
      }
    }
    // The generator aims at boundaries, so some cases should cross one.
    XCTAssertTrue(sawAChange)
  }

  /// Distance guidance must never point the wrong way. Read off the code: a
  /// state that is already too near or too far needs the enter band
  /// [nearEnter, farEnter] to clear, and anything outside it is split at the
  /// midpoint of the exit band. So once settled, `.tooClose` means the held
  /// distance is below `nearEnter` and `.tooFar` means above `farEnter`;
  /// conversely a distance below `nearExit` or above `farExit` must say so.
  func testDistanceGuidanceAlwaysPointsTheRightWay() {
    var rng = SplitMix64(seed: 0x5EED_0004)
    var failures = 0
    var sawClose = false
    var sawFar = false
    for index in 0..<trajectories {
      var guide = HeadPositionGuide()
      feed(&guide, randomTrajectory(&rng))
      let target = randomTarget(&rng)
      let state = hold(&guide, target, frames: holdFrames)
      let d = target.distance

      var problem: String?
      if state == .tooClose, !(d < t.nearEnter) { problem = "said too close" }
      if state == .tooFar, !(d > t.farEnter) { problem = "said too far" }
      if d < t.nearExit, state != .tooClose { problem = "said \(state), not too close" }
      if d > t.farExit, state != .tooFar { problem = "said \(state), not too far" }
      if state == .tooClose { sawClose = true }
      if state == .tooFar { sawFar = true }
      if let problem {
        failures += 1
        if failures <= 5 { XCTFail("case \(index): held |z| \(d) \(problem)") }
      }
    }
    XCTAssertTrue(sawClose && sawFar)
  }

  /// NaN, infinity and missing components arrive from real trackers. The code
  /// treats any of them as no face: it drops the smoothed state and proposes
  /// `.faceNotDetected`, so a run of `framesToSwitch` of them publishes it.
  /// Because the smoothing is dropped, a position held after a no-face state
  /// starts clean: `framesToSwitch` frames of it publish exactly its cold-start
  /// classification, with nothing left over from before. Nothing may crash
  /// and the returned state must always be the published one.
  ///
  /// (Finite frames at different positions do not have to clear no-face in
  /// three frames: the debounce restarts whenever the proposed kind changes.)
  func testNonFiniteInputReadsAsNoFaceAndNeverPoisonsLaterFrames() {
    var rng = SplitMix64(seed: 0x5EED_0005)
    var failures = 0
    for index in 0..<trajectories {
      var guide = HeadPositionGuide()
      var problem: String?
      // True at the start and right after a bad frame: no smoothing state.
      var smoothingIsClear = true
      segments: for segment in 0..<16 {
        if segment > 0, rng.chance(0.5) {
          // A burst of bad frames.
          let length = Int.random(in: 1...5, using: &rng)
          for run in 1...length {
            let input = randomNonFinite(&rng)
            let returned = step(&guide, input)
            if returned != guide.current {
              problem = "\(input) returned \(returned) but published \(guide.current)"
            } else if run >= guide.framesToSwitch, guide.current != .faceNotDetected {
              problem = "\(run) non-finite frames (last \(input)) still say \(guide.current)"
            }
            if problem != nil { break segments }
          }
          smoothingIsClear = true
        } else {
          // A held position.
          let target = randomTarget(&rng)
          let startsClean = smoothingIsClear && guide.current == .faceNotDetected
          smoothingIsClear = false
          let length = Int.random(in: 1...10, using: &rng)
          for run in 1...length {
            let returned = step(&guide, Frame(x: target.x, y: target.y, z: target.z))
            if returned != guide.current {
              problem = "\(target) returned \(returned) but published \(guide.current)"
            } else if startsClean, run == guide.framesToSwitch {
              let expected = classify(target, current: .faceNotDetected)
              if guide.current != expected {
                problem = "\(target) after no face published \(guide.current), expected \(expected)"
              }
            }
            if problem != nil { break segments }
          }
        }
      }
      if let problem {
        failures += 1
        if failures <= 5 { XCTFail("case \(index): \(problem)") }
        continue
      }

      // Smoothing restarts cleanly: a held position afterwards behaves like
      // any other history and settles on a fixed point.
      let target = randomTarget(&rng)
      let state = hold(&guide, target, frames: holdFrames)
      if state != classify(target, current: state) {
        failures += 1
        if failures <= 5 { XCTFail("case \(index): after non-finite input \(target) settled on \(state)") }
      }
    }
  }

  /// `reset()` must forget everything: a reset guide is indistinguishable
  /// from a new one, frame for frame, so a retake never inherits the previous
  /// attempt's smoothing or pending switch.
  func testResetIsIndistinguishableFromANewGuide() {
    var rng = SplitMix64(seed: 0x5EED_0006)
    var failures = 0
    for index in 0..<trajectories {
      var used = HeadPositionGuide()
      feed(&used, randomTrajectory(&rng))
      used.reset()
      var fresh = HeadPositionGuide()

      if used.current != .faceNotDetected {
        failures += 1
        if failures <= 5 { XCTFail("case \(index): reset left \(used.current)") }
        continue
      }
      for (frame, input) in randomTrajectory(&rng).enumerated() {
        let a = step(&used, input)
        let b = step(&fresh, input)
        if a != b {
          failures += 1
          if failures <= 5 { XCTFail("case \(index) frame \(frame): reset \(a), new \(b)") }
          break
        }
      }
    }
  }

  // MARK: - Model

  /// A position as it is held, with the sign of z kept so |z| is exercised.
  private struct Target: CustomStringConvertible {
    var x: Double
    var y: Double
    var z: Double
    var distance: Double { abs(z) }
    var description: String { "(x: \(x), y: \(y), z: \(z))" }
  }

  private struct Frame: CustomStringConvertible {
    var x: Double?
    var y: Double?
    var z: Double?
    var isFinite: Bool {
      guard let x, let y, let z else { return false }
      return x.isFinite && y.isFinite && z.isFinite
    }
    var description: String {
      "(\(x.map { "\($0)" } ?? "nil"), \(y.map { "\($0)" } ?? "nil"), \(z.map { "\($0)" } ?? "nil"))"
    }
  }

  /// The rule written out from the type's documented thresholds: distance
  /// first, enter bands unless the current state already considers that
  /// dimension fine, and the near/far split at the middle of the exit band.
  private func classify(_ p: Target, current: HeadPosition) -> HeadPosition {
    let distanceAlreadyFine: Bool
    switch current {
    case .tooClose, .tooFar, .faceNotDetected: distanceAlreadyFine = false
    case .centered, .offCenter: distanceAlreadyFine = true
    }
    let near = distanceAlreadyFine ? t.nearExit : t.nearEnter
    let far = distanceAlreadyFine ? t.farExit : t.farEnter
    if p.distance < near || p.distance > far {
      return p.distance < (t.nearExit + t.farExit) / 2 ? .tooClose : .tooFar
    }
    let centered = current == .centered
    let hLimit = centered ? t.horizontalExit : t.horizontalEnter
    let vLimit = centered ? t.verticalExit : t.verticalEnter
    let h: HeadPosition.AxisSide? = abs(p.x) > hLimit ? (p.x < 0 ? .negative : .positive) : nil
    let v: HeadPosition.AxisSide? = abs(p.y) > vLimit ? (p.y < 0 ? .negative : .positive) : nil
    if h == nil, v == nil { return .centered }
    return .offCenter(horizontal: h, vertical: v)
  }

  /// Strictly between an enter and an exit threshold, where the right answer
  /// legitimately depends on the previous state.
  private func inAnyHysteresisBand(_ p: Target) -> Bool {
    let d = p.distance
    let distanceBand = (t.nearExit...t.nearEnter).contains(d) || (t.farEnter...t.farExit).contains(d)
    // Centering only matters while the distance is fine in both readings.
    guard !distanceBand, d >= t.nearEnter, d <= t.farEnter else { return distanceBand }
    return (t.horizontalEnter...t.horizontalExit).contains(abs(p.x))
      || (t.verticalEnter...t.verticalExit).contains(abs(p.y))
  }

  // MARK: - Generators

  private var thresholdsPerAxis: (x: [Double], y: [Double], d: [Double]) {
    (
      [t.horizontalEnter, t.horizontalExit],
      [t.verticalEnter, t.verticalExit],
      [t.nearExit, t.nearEnter, t.farEnter, t.farExit]
    )
  }

  /// Half uniform over a generous range, half aimed near a threshold, and
  /// never within 1e-4 of one, so the 30-frame hold converges to the same side
  /// of every threshold as the target itself.
  private func randomTarget(_ rng: inout SplitMix64) -> Target {
    let axes = thresholdsPerAxis
    func coordinate(_ thresholds: [Double], range: ClosedRange<Double>, signed: Bool) -> Double {
      while true {
        var value: Double
        if rng.chance(0.5) {
          value = Double.random(in: range, using: &rng)
        } else {
          let anchor = thresholds.randomElement(using: &rng)!
          value = anchor + Double.random(in: -0.03...0.03, using: &rng)
          if signed, rng.chance(0.5) { value = -value }
        }
        if thresholds.allSatisfy({ abs(abs(value) - $0) > 1e-4 }) { return value }
      }
    }
    let x = coordinate(axes.x, range: -0.45...0.45, signed: true)
    let y = coordinate(axes.y, range: -0.45...0.45, signed: true)
    var distance = coordinate(axes.d, range: 0.05...1.2, signed: false)
    distance = max(distance, 0.05)
    return Target(x: x, y: y, z: rng.chance(0.8) ? -distance : distance)
  }

  private func randomNonFinite(_ rng: inout SplitMix64) -> Frame {
    let specials: [Double?] = [nil, .nan, .infinity, -.infinity, .signalingNaN]
    var frame = jittered(randomTarget(&rng), 0, &rng)
    // At least one component is bad; others may be too.
    switch rng.next() % 3 {
    case 0: frame.x = specials.randomElement(using: &rng)!
    case 1: frame.y = specials.randomElement(using: &rng)!
    default: frame.z = specials.randomElement(using: &rng)!
    }
    if rng.chance(0.3) { frame.z = specials.randomElement(using: &rng)! }
    if frame.isFinite { frame.x = .nan }
    return frame
  }

  /// A sequence of holds of random length, with occasional lost-face and
  /// non-finite frames mixed in.
  private func randomTrajectory(_ rng: inout SplitMix64) -> [Frame] {
    var frames: [Frame] = []
    for _ in 0..<Int.random(in: 0...6, using: &rng) {
      let target = randomTarget(&rng)
      let noise = rng.chance(0.5) ? 0 : Double.random(in: 0...0.05, using: &rng)
      for _ in 0..<Int.random(in: 1...25, using: &rng) {
        frames.append(rng.chance(0.05) ? randomNonFinite(&rng) : jittered(target, noise, &rng))
      }
    }
    return frames
  }

  private func jittered(_ p: Target, _ amount: Double, _ rng: inout SplitMix64) -> Frame {
    guard amount > 0 else { return Frame(x: p.x, y: p.y, z: p.z) }
    return Frame(
      x: p.x + Double.random(in: -amount...amount, using: &rng),
      y: p.y + Double.random(in: -amount...amount, using: &rng),
      z: p.z + Double.random(in: -amount...amount, using: &rng))
  }

  private func feed(_ guide: inout HeadPositionGuide, _ frames: [Frame]) {
    for frame in frames { step(&guide, frame) }
  }

  @discardableResult
  private func step(_ guide: inout HeadPositionGuide, _ frame: Frame) -> HeadPosition {
    guide.update(x: frame.x, y: frame.y, z: frame.z)
  }

  private func hold(_ guide: inout HeadPositionGuide, _ p: Target, frames: Int) -> HeadPosition {
    var state = guide.current
    for _ in 0..<frames { state = guide.update(x: p.x, y: p.y, z: p.z) }
    return state
  }
}

/// SplitMix64: tiny, fast, and fully deterministic for a given seed, so every
/// run of these tests sees the same cases.
private struct SplitMix64: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  mutating func chance(_ probability: Double) -> Bool {
    Double.random(in: 0..<1, using: &self) < probability
  }
}
