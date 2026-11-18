import CoreGraphics
import XCTest

@testable import Sober

/// Follow-the-dot calibration (HANDOFF 2.6) against a synthetic person whose
/// raw screen gaze is off by a known offset and scale.
final class OcularCalibrationTests: XCTestCase {
  /// A 353 x 330 pt stimulus field on an iPhone 15 Pro display. At 40 cm the
  /// corner dots sit about 2.5 degrees left and right of the centre and 1.7
  /// degrees above and below it.
  private let field = CGRect(x: 20, y: 260, width: 353, height: 330)
  private let display = DisplayGeometry(nativePixelWidth: 1179, nativePixelHeight: 2556, nativeScale: 3)!
  private let bar = OcularCalibrationFitter.maximumResidualDegrees

  // MARK: - Schedule

  func testCalibrationVisitsTheProtocolsCornersThenTheCentre() {
    let points = OcularCalibrationSchedule.points
    let expected = [(0.2, 0.28), (0.8, 0.72), (0.2, 0.72), (0.8, 0.28), (0.5, 0.5)]
    XCTAssertEqual(points.count, 5)
    for (point, expected) in zip(points, expected) {
      XCTAssertEqual(point.x, expected.0)
      XCTAssertEqual(point.y, expected.1)
    }
    // The same insets the protocol's jumps use, in both variants.
    for index in 0..<4 {
      let full = OcularProtocolSchedule.target(at: 17 + Double(index) + 0.5, variant: .full)
      let reduced = OcularProtocolSchedule.target(at: 3 + Double(index) + 0.5, variant: .reducedMotion)
      for jump in [full, reduced] {
        XCTAssertEqual(jump.phase, .saccades)
        XCTAssertEqual(points[index].x, jump.x)
        XCTAssertEqual(points[index].y, jump.y)
      }
    }
    XCTAssertEqual(OcularCalibrationSchedule.totalDuration, 5)
    XCTAssertEqual(OcularCalibrationSchedule.target(at: 2.5).phase, .calibration)
    // The protocol it precedes is still 25 and 11 seconds.
    XCTAssertEqual(OcularProtocolSchedule.totalDuration(for: .full), 25)
    XCTAssertEqual(OcularProtocolSchedule.totalDuration(for: .reducedMotion), 11)
  }

  func testOnlyTheEndOfEachPointIsScored() {
    let schedule = OcularCalibrationSchedule.self
    for index in 0..<5 {
      let start = Double(index)
      XCTAssertEqual(schedule.pointIndex(at: start + 0.5), index)
      XCTAssertFalse(schedule.isScored(at: start + 0.01))
      XCTAssertFalse(schedule.isScored(at: start + 0.39))
      XCTAssertTrue(schedule.isScored(at: start + 0.41))
      XCTAssertTrue(schedule.isScored(at: start + 0.99))
    }
    let outside: [Double] = [-0.1, 5.0, 7.0, .nan, .infinity]
    for time in outside {
      XCTAssertNil(schedule.pointIndex(at: time))
      XCTAssertFalse(schedule.isScored(at: time))
    }
    // The target never leaves the pattern, whatever time it is asked for.
    XCTAssertEqual(schedule.target(at: -3).x, 0.2)
    XCTAssertEqual(schedule.target(at: 99).x, 0.5)
    XCTAssertEqual(schedule.target(at: .nan).x, 0.2)
  }

  func testTheDotGlidesUnlessReducedMotionIsOn() {
    let schedule = OcularCalibrationSchedule.self
    let points = schedule.points

    // Full motion: from the centre to the first point, then point to point.
    let first = schedule.dotPosition(at: 0, reduceMotion: false)
    XCTAssertEqual(first.x, 0.5)
    XCTAssertEqual(first.y, 0.5)
    let leaving = schedule.dotPosition(at: 1.0, reduceMotion: false)
    XCTAssertEqual(leaving.x, points[0].x, accuracy: 1e-12)
    let halfway = schedule.dotPosition(at: 1.0 + schedule.glideDuration / 2, reduceMotion: false)
    XCTAssertEqual(halfway.x, (points[0].x + points[1].x) / 2, accuracy: 1e-12)
    XCTAssertEqual(halfway.y, (points[0].y + points[1].y) / 2, accuracy: 1e-12)

    // Reduced Motion: no position between two points is ever drawn.
    for time in stride(from: 0.0, to: schedule.totalDuration, by: 0.01) {
      let dot = schedule.dotPosition(at: time, reduceMotion: true)
      let target = schedule.target(at: time)
      XCTAssertEqual(dot.x, target.x, "at \(time)")
      XCTAssertEqual(dot.y, target.y, "at \(time)")
    }

    // Either way the dot is at rest on its point for the whole scored part.
    for time in stride(from: 0.0, to: schedule.totalDuration, by: 0.01) where schedule.isScored(at: time) {
      let dot = schedule.dotPosition(at: time, reduceMotion: false)
      let target = schedule.target(at: time)
      XCTAssertEqual(dot.x, target.x, "at \(time)")
      XCTAssertEqual(dot.y, target.y, "at \(time)")
    }
    XCTAssertLessThan(schedule.glideDuration, schedule.pointDuration - schedule.scoredDuration)
  }

  // MARK: - Fit

  func testAFollowerIsFittedThroughTheirOffsetAndScale() throws {
    let person = CalibrationPerson()
    let calibration = fit(person)

    XCTAssertTrue(calibration.metrics.passed)
    XCTAssertEqual(calibration.metrics.pointsScheduled, 5)
    XCTAssertEqual(calibration.metrics.pointsUsed, 5)
    XCTAssertEqual(try XCTUnwrap(calibration.metrics.residualRMSDegrees), 0, accuracy: 1e-6)
    XCTAssertEqual(try XCTUnwrap(calibration.metrics.viewingDistanceMetres), 0.4, accuracy: 1e-12)
    XCTAssertEqual(calibration.metrics.rejectedSampleFraction, 0)
    XCTAssertEqual(calibration.field, field)

    // The map undoes the person's error anywhere on the field, not only at
    // the five points.
    let map = try XCTUnwrap(calibration.map)
    let places: [(Double, Double)] = [(0.14, 0.5), (0.86, 0.5), (0.5, 0.18), (0.33, 0.61)]
    for (x, y) in places {
      let truthX = Double(field.minX) + x * Double(field.width)
      let truthY = Double(field.minY) + y * Double(field.height)
      let raw = person.raw(truthX, truthY)
      let mapped = map.apply(x: raw.x, y: raw.y)
      XCTAssertEqual(mapped.x, truthX, accuracy: 1e-6)
      XCTAssertEqual(mapped.y, truthY, accuracy: 1e-6)
    }

    // The eye-in-head points give pursuit gain the same scale the saccade
    // phase would have.
    XCTAssertEqual(calibration.eyeInHeadPoints.count, 5)
    XCTAssertEqual(
      try XCTUnwrap(OcularDetailedAnalyzer.slope(calibration.eyeInHeadPoints, horizontal: true)),
      person.eyeScaleX, accuracy: 1e-9)
    XCTAssertEqual(
      try XCTUnwrap(OcularDetailedAnalyzer.slope(calibration.eyeInHeadPoints, horizontal: false)),
      person.eyeScaleY, accuracy: 1e-9)
  }

  func testTheResidualIsTheGazeNoiseInDegrees() throws {
    var person = CalibrationPerson()
    person.rawScaleX = 1
    person.rawScaleY = 1
    person.rawOffsetX = 0
    person.rawOffsetY = 0

    // 6 pt per axis is 8.5 pt radially: about 1.4 mm, 0.2 degrees at 40 cm.
    person.noisePoints = 6
    let steady = fit(person).metrics
    let expected = atan2(6 * 2.0.squareRoot() / display.pointsPerMillimetre / 1_000, 0.4) * 180 / .pi
    XCTAssertEqual(try XCTUnwrap(steady.residualRMSDegrees) / expected, 1, accuracy: 0.15)
    XCTAssertTrue(steady.passed)
    XCTAssertEqual(steady.pointsUsed, 5)

    // Further away the same noise on the screen is a smaller angle.
    person.distance = 0.6
    XCTAssertEqual(
      try XCTUnwrap(fit(person).metrics.residualRMSDegrees) / (expected * 0.4 / 0.6), 1, accuracy: 0.15)

    // Too noisy to trust: over the bar, and no single point is to blame.
    person.distance = 0.4
    person.noisePoints = 40
    let noisy = fit(person).metrics
    XCTAssertGreaterThan(try XCTUnwrap(noisy.residualRMSDegrees), bar)
    XCTAssertFalse(noisy.passed)
    XCTAssertEqual(noisy.pointsUsed, 5)
  }

  func testSomeoneWhoDoesNotFollowTheDotFails() {
    var person = CalibrationPerson()
    person.follows = false

    // Gaze that never moves gives nothing to fit.
    let frozen = fit(person)
    XCTAssertFalse(frozen.metrics.passed)
    XCTAssertNil(frozen.map)
    XCTAssertNil(frozen.metrics.residualRMSDegrees)

    // With ordinary noise there is a fit, and it is nowhere near the bar.
    person.noisePoints = 6
    for seed in 1...20 {
      person.seed = UInt64(seed)
      let staring = fit(person).metrics
      XCTAssertFalse(staring.passed, "seed \(seed)")
      if let residual = staring.residualRMSDegrees {
        XCTAssertGreaterThan(residual, bar, "seed \(seed)")
      }
    }
  }

  func testGlancesAwayAreRejectedBeforeFitting() throws {
    var person = CalibrationPerson()
    // A tenth of a second looking elsewhere, inside two scored windows.
    person.glances = [1.6, 3.5]
    let calibration = fit(person).metrics

    XCTAssertTrue(calibration.passed)
    XCTAssertEqual(calibration.pointsUsed, 5)
    XCTAssertEqual(try XCTUnwrap(calibration.residualRMSDegrees), 0, accuracy: 1e-6)
    // 12 of the 180 scored samples.
    XCTAssertEqual(try XCTUnwrap(calibration.rejectedSampleFraction), 12.0 / 180, accuracy: 1e-9)
  }

  func testOneMissedPointIsDroppedAndTwoFail() throws {
    // At arm's length the fit pulled off by the missed point is itself under
    // the bar, so the point has to be judged against the other four.
    for distance in [0.4, 0.6] {
      var person = CalibrationPerson()
      person.distance = distance
      person.missedPoints = [1]
      let calibration = fit(person)
      XCTAssertTrue(calibration.metrics.passed, "\(distance) m")
      XCTAssertEqual(calibration.metrics.pointsUsed, 4, "\(distance) m")
      XCTAssertEqual(try XCTUnwrap(calibration.metrics.residualRMSDegrees), 0, accuracy: 1e-6, "\(distance) m")
      // The dropped point is not trusted for pursuit gain's scale either.
      XCTAssertEqual(calibration.eyeInHeadPoints.count, 4, "\(distance) m")
      XCTAssertFalse(calibration.eyeInHeadPoints.contains { $0.targetX == 0.8 && $0.targetY == 0.72 })
    }

    var person = CalibrationPerson()
    person.distance = 0.35
    person.missedPoints = [1, 3]
    let two = fit(person).metrics
    XCTAssertFalse(two.passed)
    XCTAssertGreaterThan(try XCTUnwrap(two.residualRMSDegrees), bar)
  }

  func testABlinkThroughAPointLeavesFourAndTwoLeaveTooFew() {
    var person = CalibrationPerson()
    person.blinkPoints = [2]
    let one = fit(person)
    XCTAssertTrue(one.metrics.passed)
    XCTAssertEqual(one.metrics.pointsUsed, 4)
    XCTAssertEqual(one.eyeInHeadPoints.count, 4)

    person.blinkPoints = [0, 2]
    let two = fit(person)
    XCTAssertFalse(two.metrics.passed)
    XCTAssertEqual(two.metrics.pointsUsed, 3)
    XCTAssertNil(two.metrics.residualRMSDegrees)
    XCTAssertNil(two.map)
  }

  func testWithoutScreenGazeOrAFieldThereIsNoScreenFit() {
    var person = CalibrationPerson()
    let samples = person.samples(field: field)
    let missing: [(String, CGRect?, DisplayGeometry?)] = [
      ("no field", nil, display), ("empty field", .zero, display), ("no display", field, nil),
    ]
    for (label, missingField, missingDisplay) in missing {
      let calibration = OcularCalibrationFitter.fit(
        samples: samples, startedAt: person.start, field: missingField, display: missingDisplay)
      XCTAssertFalse(calibration.metrics.passed, label)
      XCTAssertEqual(calibration.metrics.pointsUsed, 0, label)
      XCTAssertNil(calibration.map, label)
    }

    person.hasScreenGaze = false
    let blind = fit(person)
    XCTAssertFalse(blind.metrics.passed)
    XCTAssertEqual(blind.metrics.pointsUsed, 0)
    XCTAssertNil(blind.metrics.viewingDistanceMetres)
  }

  func testEmptyBrokenAndMistimedSamplesDoNotFit() {
    let person = CalibrationPerson()
    let samples = person.samples(field: field)

    let empty = OcularCalibrationFitter.fit(samples: [], startedAt: 0, field: field, display: display)
    XCTAssertFalse(empty.metrics.passed)
    XCTAssertEqual(empty.metrics.pointsUsed, 0)
    XCTAssertTrue(empty.eyeInHeadPoints.isEmpty)

    // Protocol samples are never calibration samples.
    let protocolSamples = samples.map { sample in
      var copy = OcularSample(
        timestamp: sample.timestamp, phase: .fixation, targetX: sample.targetX, targetY: sample.targetY,
        leftGazeX: sample.leftGazeX, leftGazeY: sample.leftGazeY, rightGazeX: sample.rightGazeX,
        rightGazeY: sample.rightGazeY, headX: 0, headY: 0, headZ: 1, blinkLeft: 0.05, blinkRight: 0.05)
      copy.screenGazeX = sample.screenGazeX
      copy.screenGazeY = sample.screenGazeY
      copy.screenViewingDistanceMetres = sample.screenViewingDistanceMetres
      return copy
    }
    XCTAssertEqual(
      OcularCalibrationFitter.fit(samples: protocolSamples, startedAt: person.start, field: field, display: display)
        .metrics.pointsUsed, 0)

    // A start time that puts every sample outside the pattern.
    XCTAssertEqual(
      OcularCalibrationFitter.fit(samples: samples, startedAt: person.start + 60, field: field, display: display)
        .metrics.pointsUsed, 0)

    // Non-finite screen gaze is left out without poisoning the fit.
    let broken = samples.enumerated().map { index, sample in
      var sample = sample
      if index % 7 == 0 { sample.screenGazeX = .nan }
      if index % 11 == 0 { sample.screenViewingDistanceMetres = .infinity }
      return sample
    }
    let calibration = OcularCalibrationFitter.fit(
      samples: broken, startedAt: person.start, field: field, display: display)
    XCTAssertTrue(calibration.metrics.passed)
    XCTAssertEqual(calibration.metrics.residualRMSDegrees ?? .nan, 0, accuracy: 1e-6)
    XCTAssertNoThrow(try JSONEncoder().encode(calibration.metrics))
  }

  // MARK: - Verdict

  func testAFailedCalibrationDegradesTheCaptureWithOneSentence() {
    let usable = CaptureQualitySnapshot(
      isSupported: true, hasCameraPermission: true, facePresent: true, centered: true,
      distanceAcceptable: true, lightingAcceptable: true, headStable: true,
      frameRate: 60, sampleCount: 1_500, dropoutRatio: 0, issues: [])
    var metrics = fit(CalibrationPerson()).metrics
    XCTAssertEqual(CaptureAssessment.assess(usable, image: nil, calibration: metrics).verdict, .valid)
    XCTAssertEqual(CaptureAssessment.assess(usable, image: nil, calibration: nil).verdict, .valid)

    metrics.passed = false
    let degraded = CaptureAssessment.assess(usable, image: nil, calibration: metrics)
    XCTAssertEqual(degraded.verdict, .degraded)
    XCTAssertEqual(degraded.guidance, "Keep your head still and follow the dot with your eyes.")
    // Degraded still counts.
    XCTAssertTrue(usable.isUsable)

    // It never rescues or replaces an unusable capture.
    var unusable = usable
    unusable.lightingAcceptable = false
    unusable.issues = [.lowLight]
    let invalid = CaptureAssessment.assess(unusable, image: nil, calibration: metrics)
    XCTAssertEqual(invalid.verdict, .invalid)
    XCTAssertEqual(invalid.guidance, CaptureQualityIssue.lowLight.guidance)
  }

  // MARK: - Helpers

  private func fit(_ person: CalibrationPerson) -> OcularCalibration {
    OcularCalibrationFitter.fit(
      samples: person.samples(field: field), startedAt: person.start, field: field, display: display)
  }
}

/// The hand-over from calibration to the protocol inside the tracking
/// service. The simulator has no TrueDepth camera, so samples are fed in.
@MainActor
final class EyeCalibrationHandoverTests: XCTestCase {
  private let field = CGRect(x: 20, y: 260, width: 353, height: 330)
  private let display = DisplayGeometry(nativePixelWidth: 1179, nativePixelHeight: 2556, nativeScale: 3)!

  func testCalibrationSamplesAreGoneBeforeTheProtocolBufferStarts() throws {
    let service = FaceTrackingService()
    service.startEyeCalibration(field: field, display: display)
    var person = CalibrationPerson()
    person.start = try XCTUnwrap(service.eyeCalibrationStartedAt)
    let calibrationSamples = person.samples(field: field)
    for sample in calibrationSamples { service.appendSample(sample) }
    XCTAssertEqual(service.sampleCount, calibrationSamples.count)

    let calibration = try XCTUnwrap(service.finishEyeCalibration())
    XCTAssertTrue(calibration.metrics.passed)
    XCTAssertEqual(service.sampleCount, 0, "fitted, then discarded")
    XCTAssertNil(service.eyeCalibrationStartedAt)
    XCTAssertEqual(service.eyeCalibration, calibration)

    service.startOcularProtocol()
    XCTAssertEqual(service.eyeCalibration, calibration, "kept for the capture it precedes")
    let protocolSamples = person.protocolSamples()
    for sample in protocolSamples { service.appendSample(sample) }
    let summary = service.stopOcularProtocol()

    XCTAssertEqual(summary.sampleCount, protocolSamples.count)
    let detailed = try XCTUnwrap(summary.detailed)
    XCTAssertEqual(detailed.validity.sampleCount, protocolSamples.count)
    XCTAssertEqual(detailed.calibration, calibration.metrics)
    XCTAssertEqual(detailed.horizontalPursuit?.gainScaleSource, .calibration)
    XCTAssertEqual(try XCTUnwrap(detailed.horizontalPursuit?.gain), 1, accuracy: 0.05)
    XCTAssertNil(service.eyeCalibration, "gone once the capture ends")
  }

  func testAbandoningOrRestartingDropsTheCalibration() throws {
    let service = FaceTrackingService()

    try calibrate(service)
    service.pause()
    XCTAssertNil(service.eyeCalibration)

    try calibrate(service)
    service.startCalibration()
    XCTAssertNil(service.eyeCalibration, "camera setup starts clean")

    try calibrate(service)
    service.startEyeCalibration(field: field, display: display)
    XCTAssertNil(service.eyeCalibration, "a new calibration replaces the old one")
    service.pause()

    // Nothing running, nothing to finish; a protocol with no calibration
    // records none.
    XCTAssertNil(service.finishEyeCalibration())
    service.startOcularProtocol()
    for sample in CalibrationPerson().protocolSamples() { service.appendSample(sample) }
    let detailed = try XCTUnwrap(service.stopOcularProtocol().detailed)
    XCTAssertNil(detailed.calibration)
    XCTAssertEqual(detailed.horizontalPursuit?.gainScaleSource, .saccadePhase)
    XCTAssertEqual(try XCTUnwrap(detailed.horizontalPursuit?.gain), 1, accuracy: 0.05)
  }

  private func calibrate(_ service: FaceTrackingService) throws {
    service.startEyeCalibration(field: field, display: display)
    var person = CalibrationPerson()
    person.start = try XCTUnwrap(service.eyeCalibrationStartedAt)
    for sample in person.samples(field: field) { service.appendSample(sample) }
    XCTAssertNotNil(service.finishEyeCalibration())
    XCTAssertNotNil(service.eyeCalibration)
  }
}

// MARK: - Synthetic person

/// Someone doing the calibration. Their eyes reach each dot `latency` after it
/// appears. Raw screen gaze is where they really look, scaled and offset: the
/// error calibration exists to remove.
struct CalibrationPerson {
  var rate = 60.0
  /// When calibration started, on the samples' clock.
  var start = 100.0
  var latency = 0.3
  var rawScaleX = 0.8
  var rawScaleY = 1.15
  var rawOffsetX = 14.0
  var rawOffsetY = -22.0
  /// Gaussian noise on raw screen gaze, points per axis.
  var noisePoints = 0.0
  var distance = 0.4
  /// Eye-in-head gaze units per unit of the field, x mirrored as on ARKit.
  var eyeScaleX = -0.25
  var eyeScaleY = 0.25
  /// False: stares at the centre throughout.
  var follows = true
  /// Points the person stays on the centre for.
  var missedPoints: Set<Int> = []
  /// Points whose whole second is spent with the lids closed.
  var blinkPoints: Set<Int> = []
  /// Times, from the start, of a tenth of a second looking 150 pt away.
  var glances: [Double] = []
  var hasScreenGaze = true
  var seed: UInt64 = 1

  func raw(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
    (x * rawScaleX + rawOffsetX, y * rawScaleY + rawOffsetY)
  }

  func samples(field: CGRect) -> [OcularSample] {
    var random = CalibrationRandom(seed: seed)
    let schedule = OcularCalibrationSchedule.self
    var result: [OcularSample] = []
    for frame in 0..<Int((schedule.totalDuration * rate).rounded()) {
      let elapsed = (Double(frame) + 0.5) / rate
      guard let index = schedule.pointIndex(at: elapsed) else { continue }
      let target = schedule.target(at: elapsed)
      let arrived = elapsed - Double(index) * schedule.pointDuration >= latency
      let looking = arrived ? index : index - 1
      let look = looking >= 0 && follows && !missedPoints.contains(looking)
        ? schedule.points[looking] : (x: 0.5, y: 0.5)
      let lid = blinkPoints.contains(index) ? 0.9 : 0.05
      let gx = eyeScaleX * (look.x - 0.5)
      let gy = eyeScaleY * (look.y - 0.5)
      var sample = OcularSample(
        timestamp: start + elapsed, phase: .calibration, targetX: target.x, targetY: target.y,
        leftGazeX: gx + 0.01, leftGazeY: gy, rightGazeX: gx - 0.01, rightGazeY: gy,
        headX: 0, headY: 0, headZ: 1, blinkLeft: lid, blinkRight: lid)
      if hasScreenGaze {
        var x = Double(field.minX) + look.x * Double(field.width)
        let y = Double(field.minY) + look.y * Double(field.height)
        if glances.contains(where: { elapsed >= $0 && elapsed < $0 + 0.1 }) { x += 150 }
        let gaze = raw(x, y)
        let point = ScreenGazePoint(
          x: gaze.x + random.gaussian() * noisePoints, y: gaze.y + random.gaussian() * noisePoints,
          validity: .onScreen, distanceMetres: distance)
        sample.setScreenGaze(ScreenGaze(left: point, right: point, combined: point))
      }
      result.append(sample)
    }
    return result
  }

  /// The same person on the 25-second protocol: on the dot while it holds
  /// and glides, and 0.2 s behind each jump, as eyes are.
  func protocolSamples() -> [OcularSample] {
    var result: [OcularSample] = []
    for frame in 0..<Int((OcularProtocolSchedule.totalDuration * rate).rounded()) {
      let elapsed = (Double(frame) + 0.5) / rate
      let target = OcularProtocolSchedule.target(at: elapsed)
      let look = target.phase == .saccades ? OcularProtocolSchedule.target(at: elapsed - 0.2) : target
      let gx = eyeScaleX * (look.x - 0.5)
      let gy = eyeScaleY * (look.y - 0.5)
      result.append(OcularSample(
        timestamp: start + 10 + elapsed, phase: target.phase, targetX: target.x, targetY: target.y,
        leftGazeX: gx + 0.01, leftGazeY: gy, rightGazeX: gx - 0.01, rightGazeY: gy,
        headX: 0, headY: 0, headZ: 1, blinkLeft: 0.05, blinkRight: 0.05))
    }
    return result
  }
}

/// Deterministic, so a failing run can be replayed.
private struct CalibrationRandom {
  private var state: UInt64

  init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 1 }

  private mutating func uniform() -> Double {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Double(state >> 11) / Double(1 << 53)
  }

  mutating func gaussian() -> Double {
    let u = max(uniform(), 1e-12)
    return (-2 * log(u)).squareRoot() * cos(2 * .pi * uniform())
  }
}
