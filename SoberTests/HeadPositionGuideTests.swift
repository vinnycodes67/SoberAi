import XCTest

@testable import Sober

/// Guidance that does not flicker, and does not tell anyone to move the wrong
/// way. Positions are metres in ARKit world space.
final class HeadPositionGuideTests: XCTestCase {

  /// A comfortable framing: on axis, about 40 cm away.
  private let centered = (x: 0.0, y: 0.0, z: -0.40)

  private func settle(
    _ guide: inout HeadPositionGuide, x: Double, y: Double, z: Double, frames: Int = 30
  ) -> HeadPosition {
    var state = guide.current
    for _ in 0..<frames { state = guide.update(x: x, y: y, z: z) }
    return state
  }

  // MARK: - States

  func testStartsWithNoFace() {
    XCTAssertEqual(HeadPositionGuide().current, .faceNotDetected)
  }

  func testAComfortableFramingSettlesOnCentered() {
    var guide = HeadPositionGuide()
    XCTAssertEqual(settle(&guide, x: centered.x, y: centered.y, z: centered.z), .centered)
  }

  func testTooCloseAndTooFarAreToldApart() {
    var near = HeadPositionGuide()
    XCTAssertEqual(settle(&near, x: 0, y: 0, z: -0.15), .tooClose)

    var far = HeadPositionGuide()
    XCTAssertEqual(settle(&far, x: 0, y: 0, z: -0.95), .tooFar)
  }

  /// The defect this fixes: both directions used to say "move the phone
  /// away", which is the wrong instruction for someone already too far.
  func testTheTwoDistanceInstructionsPointOppositeWays() {
    XCTAssertTrue(HeadPosition.tooClose.guidance.contains("farther"))
    XCTAssertTrue(HeadPosition.tooFar.guidance.contains("closer"))
  }

  /// Distance is |z|, so its sign carries no meaning.
  func testDistanceDoesNotDependOnTheSignOfZ() {
    var negative = HeadPositionGuide()
    var positive = HeadPositionGuide()
    XCTAssertEqual(
      settle(&negative, x: 0, y: 0, z: -0.95), settle(&positive, x: 0, y: 0, z: 0.95))
  }

  func testOffCenterRecordsTheAxisSide() {
    var guide = HeadPositionGuide()
    XCTAssertEqual(
      settle(&guide, x: 0.20, y: 0, z: -0.40),
      .offCenter(horizontal: .positive, vertical: nil))
  }

  /// Left/right copy waits on a device check of ARKit's axis mapping. Until
  /// then every off-center state gives the same neutral instruction rather
  /// than risk a backwards one.
  func testOffCenterCopyNamesNoDirection() {
    for state in [
      HeadPosition.offCenter(horizontal: .negative, vertical: nil),
      .offCenter(horizontal: .positive, vertical: .negative),
      .offCenter(horizontal: nil, vertical: .positive),
    ] {
      let copy = state.guidance.lowercased()
      for word in ["left", "right", "up", "down", "higher", "lower"] {
        XCTAssertFalse(copy.contains(word), "\(state) says \(word)")
      }
    }
  }

  /// Off-center is meaningless while the face is too near to frame.
  func testDistanceTakesPriorityOverCentering() {
    var guide = HeadPositionGuide()
    XCTAssertEqual(settle(&guide, x: 0.30, y: 0.30, z: -0.10), .tooClose)
  }

  func testLosingTheFaceIsReported() {
    var guide = HeadPositionGuide()
    _ = settle(&guide, x: 0, y: 0, z: -0.40)
    for _ in 0..<5 { guide.update(x: nil, y: nil, z: nil) }
    XCTAssertEqual(guide.current, .faceNotDetected)
  }

  func testNonFiniteInputIsTreatedAsNoFace() {
    var guide = HeadPositionGuide()
    _ = settle(&guide, x: 0, y: 0, z: -0.40)
    for _ in 0..<5 { guide.update(x: .nan, y: 0, z: -0.40) }
    XCTAssertEqual(guide.current, .faceNotDetected)
  }

  // MARK: - Flicker

  /// The behaviour the brief describes as CENTERED, LEFT, CENTERED, LEFT.
  /// A head resting on the 0.13 boundary, jittering a centimetre either side,
  /// must produce one state, not an alternation.
  func testAHeadOnTheBoundaryDoesNotFlicker() {
    var guide = HeadPositionGuide()
    _ = settle(&guide, x: 0, y: 0, z: -0.40)

    var transitions = 0
    var last = guide.current
    for frame in 0..<200 {
      let x = frame.isMultiple(of: 2) ? 0.12 : 0.14
      let state = guide.update(x: x, y: 0, z: -0.40)
      if state != last { transitions += 1 }
      last = state
    }

    XCTAssertLessThanOrEqual(transitions, 1)
  }

  /// Hysteresis: leaving is at 0.13, but coming back needs 0.10. A head that
  /// drifted out and then sits at 0.12 has not come back.
  func testReturningToCenterRequiresTheTighterBand() {
    var guide = HeadPositionGuide()
    _ = settle(&guide, x: 0.20, y: 0, z: -0.40)
    XCTAssertNotEqual(settle(&guide, x: 0.12, y: 0, z: -0.40), .centered)
    XCTAssertEqual(settle(&guide, x: 0.05, y: 0, z: -0.40), .centered)
  }

  /// One wild frame must not move the published state.
  func testASingleOutlierFrameIsAbsorbed() {
    var guide = HeadPositionGuide()
    _ = settle(&guide, x: 0, y: 0, z: -0.40)
    guide.update(x: 0.50, y: 0, z: -0.40)
    XCTAssertEqual(guide.current, .centered)
  }

  /// Real movement still gets through, within a fraction of a second at the
  /// tracking frame rate.
  func testSustainedMovementIsReportedPromptly() {
    var guide = HeadPositionGuide()
    _ = settle(&guide, x: 0, y: 0, z: -0.40)
    var framesUntilOff = 0
    while guide.current == .centered, framesUntilOff < 60 {
      guide.update(x: 0.30, y: 0, z: -0.40)
      framesUntilOff += 1
    }
    XCTAssertNotEqual(guide.current, .centered)
    XCTAssertLessThanOrEqual(framesUntilOff, 15)
  }

  /// Clearly off to one side while the other axis hovers on its limit. The
  /// direction flips every frame, but the instruction does not, so the guide
  /// must still leave "centered". Debouncing on the direction reset the count
  /// each frame and held "Hold that position" while the gate said off-center.
  func testOffCenterIsReportedWhileTheOtherAxisHoversOnItsLimit() {
    var guide = HeadPositionGuide()
    XCTAssertEqual(settle(&guide, x: centered.x, y: centered.y, z: centered.z), .centered)

    // Raw y alternating 0 and 0.4 smooths to roughly 0.16 and 0.24, either
    // side of the 0.18 vertical limit, so the candidate flips every frame.
    var state = guide.current
    for frame in 0..<40 {
      state = guide.update(x: 0.35, y: frame.isMultiple(of: 2) ? 0 : 0.4, z: centered.z)
    }
    XCTAssertTrue(
      state.isSameKind(as: .offCenter(horizontal: .positive, vertical: nil)),
      "expected off-center, got \(state)")
  }

  func testResetForgetsEverything() {
    var guide = HeadPositionGuide()
    _ = settle(&guide, x: 0, y: 0, z: -0.40)
    guide.reset()
    XCTAssertEqual(guide.current, .faceNotDetected)
  }
}
