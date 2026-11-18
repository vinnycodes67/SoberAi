import XCTest

@testable import Sober

/// Detailed eye measures (HANDOFF 2.5) against synthetic gaze with known
/// ground truth. Trajectories are generated here, in ARKit's units: gaze is
/// an eye-in-head vector component, about one radian per unit, with the
/// screen's x axis deliberately mirrored so nothing depends on its sign.
final class OcularDetailedMetricsTests: XCTestCase {
  // MARK: - Pursuit

  func testPerfectPursuitHasUnitGainAndNoLag() throws {
    let metrics = try detailed(EyeModel())
    for pursuit in [metrics.horizontalPursuit, metrics.verticalPursuit] {
      let pursuit = try XCTUnwrap(pursuit)
      XCTAssertEqual(try XCTUnwrap(pursuit.gain), 1, accuracy: 0.05)
      XCTAssertEqual(try XCTUnwrap(pursuit.lagMilliseconds), 0, accuracy: 15)
      XCTAssertEqual(pursuit.catchUpSaccadeCount, 0)
      XCTAssertGreaterThan(pursuit.coverage, 0.9)
    }
  }

  func testLaggedPursuitRecoversTheLag() throws {
    for lag in [0.1, 0.2] {
      var model = EyeModel()
      model.pursuitLag = lag
      let metrics = try detailed(model)
      for pursuit in [metrics.horizontalPursuit, metrics.verticalPursuit] {
        let pursuit = try XCTUnwrap(pursuit)
        XCTAssertEqual(try XCTUnwrap(pursuit.lagMilliseconds), lag * 1_000, accuracy: 20)
        XCTAssertEqual(try XCTUnwrap(pursuit.gain), 1, accuracy: 0.1)
      }
    }
  }

  func testLowGainPursuitIsMeasuredWithItsCatchUpSaccades() throws {
    var model = EyeModel()
    model.pursuitGain = 0.6
    let metrics = try detailed(model)
    let horizontal = try XCTUnwrap(metrics.horizontalPursuit)
    XCTAssertEqual(try XCTUnwrap(horizontal.gain), 0.6, accuracy: 0.1)
    XCTAssertGreaterThanOrEqual(horizontal.catchUpSaccadeCount, 4)
    let vertical = try XCTUnwrap(metrics.verticalPursuit)
    XCTAssertEqual(try XCTUnwrap(vertical.gain), 0.6, accuracy: 0.1)
  }

  func testPursuitGainNeedsTheSaccadeScale() throws {
    // Saccade phase cut off: lag is still measurable, gain has no scale.
    let samples = EyeModel().samples().filter { $0.timestamp < 17 }
    let metrics = try XCTUnwrap(analyze(samples))
    XCTAssertNil(metrics.saccades)
    XCTAssertNil(metrics.horizontalPursuit?.gain)
    XCTAssertNotNil(metrics.horizontalPursuit?.lagMilliseconds)
  }

  // MARK: - Saccades

  func testSaccadeLatencyOvershootAndCorrections() throws {
    for latency in [0.15, 0.3] {
      var model = EyeModel()
      model.saccadeLatency = latency
      model.overshoot = 1.25
      let saccades = try XCTUnwrap(try detailed(model).saccades)
      XCTAssertEqual(saccades.jumpCount, 8)
      XCTAssertEqual(saccades.analysedJumpCount, 8)
      XCTAssertEqual(saccades.respondedFraction, 1)
      XCTAssertEqual(try XCTUnwrap(saccades.medianLatencyMilliseconds), latency * 1_000, accuracy: 25)
      XCTAssertEqual(try XCTUnwrap(saccades.medianPrimaryGain), 1.25, accuracy: 0.06)
      XCTAssertEqual(try XCTUnwrap(saccades.medianLandingError), 0.25, accuracy: 0.06)
      XCTAssertGreaterThanOrEqual(saccades.correctiveSaccadeCount, 7)
      for jump in saccades.jumps {
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(jump.latencyMilliseconds), 0)
      }
    }
  }

  func testAccurateSaccadesNeedNoCorrection() throws {
    let saccades = try XCTUnwrap(try detailed(EyeModel()).saccades)
    XCTAssertEqual(try XCTUnwrap(saccades.medianPrimaryGain), 1, accuracy: 0.05)
    XCTAssertEqual(try XCTUnwrap(saccades.medianLandingError), 0, accuracy: 0.05)
    XCTAssertEqual(saccades.correctiveSaccadeCount, 0)
  }

  func testEyesThatNeverMoveDoNotRespond() throws {
    var model = EyeModel()
    model.frozenSaccades = true
    let saccades = try XCTUnwrap(try detailed(model).saccades)
    XCTAssertEqual(saccades.respondedFraction, 0)
    XCTAssertNil(saccades.medianLatencyMilliseconds)
    XCTAssertNil(saccades.medianPrimaryGain)
  }

  // MARK: - Fixation

  func testFixationDispersionMatchesKnownNoise() throws {
    var model = EyeModel()
    model.fixationNoiseDegrees = 0.1
    let fixation = try XCTUnwrap(try detailed(model).fixation)
    // Isotropic noise of sigma per axis: RMS radius sigma*sqrt(2), and a 68%
    // BCEA of 2*pi*k*sigma^2.
    XCTAssertEqual(try XCTUnwrap(fixation.dispersionRMSDegrees), 0.1 * 2.0.squareRoot(), accuracy: 0.02)
    let expectedBCEA = 2 * Double.pi * OcularDetailedAnalyzer.bceaK * 0.01
    XCTAssertEqual(try XCTUnwrap(fixation.bceaSquareDegrees), expectedBCEA, accuracy: expectedBCEA * 0.25)
    XCTAssertEqual(fixation.intrusiveSaccadeCount, 0)
    XCTAssertGreaterThan(try XCTUnwrap(fixation.longestStableMilliseconds), 2_800)
  }

  func testIntrusiveSaccadesBreakFixation() throws {
    var model = EyeModel()
    // Two square-wave jerks of about 1.1 degrees: out and back is two saccades each.
    model.fixationJerks = [1.0, 2.0]
    let fixation = try XCTUnwrap(try detailed(model).fixation)
    XCTAssertEqual(fixation.intrusiveSaccadeCount, 4)
    XCTAssertEqual(try XCTUnwrap(fixation.longestStableMilliseconds), 1_000, accuracy: 60)
  }

  // MARK: - Validity

  func testClosedEyesAreLabelledAndExcluded() throws {
    var model = EyeModel()
    model.fixationNoiseDegrees = 0.1
    model.blinks = [1.0, 2.0]
    let samples = model.samples()
    let labels = OcularDetailedAnalyzer.labels(for: samples)
    for (sample, label) in zip(samples, labels) where model.isBlinking(sample.timestamp) {
      XCTAssertEqual(label, .eyesClosed)
    }
    let metrics = try XCTUnwrap(analyze(samples))
    XCTAssertGreaterThan(metrics.validity.eyesClosed, 0)
    XCTAssertGreaterThan(metrics.validity.lowConfidence, 0, "lid transitions either side")
    XCTAssertEqual(metrics.blinkCount, 2)
    // The drooped gaze while closed never reaches fixation stability.
    let fixation = try XCTUnwrap(metrics.fixation)
    XCTAssertEqual(try XCTUnwrap(fixation.dispersionRMSDegrees), 0.1 * 2.0.squareRoot(), accuracy: 0.03)
    XCTAssertEqual(fixation.intrusiveSaccadeCount, 0)
    XCTAssertLessThan(fixation.coverage, 0.95)
  }

  func testMissingBlinkTelemetryIsNotTreatedAsClosed() throws {
    var model = EyeModel()
    model.blinkTelemetry = false
    let metrics = try detailed(model)
    XCTAssertEqual(metrics.validity.eyesClosed, 0)
    XCTAssertEqual(metrics.validity.valid, 1, accuracy: 0.001)
    XCTAssertEqual(metrics.validity.eyeStateUnknown, 1)
    XCTAssertNil(metrics.blinkCount)
    XCTAssertNil(metrics.blinkRatePerMinute)
    XCTAssertNotNil(metrics.fixation)
    XCTAssertNotNil(metrics.saccades?.medianLatencyMilliseconds)
  }

  func testHeadMovementAndBadVectorsAreLabelled() throws {
    var model = EyeModel()
    model.headTurns = [1.5]
    var samples = model.samples()
    let broken = samples.firstIndex { $0.timestamp > 2.5 }!
    samples[broken] = samples[broken].replacingGaze(.nan)
    let labels = OcularDetailedAnalyzer.labels(for: samples)
    XCTAssertEqual(labels[broken], .missing)
    XCTAssertTrue(zip(samples, labels).contains { abs($0.timestamp - 1.55) < 0.03 && $1 == .headMoved })
    let metrics = try XCTUnwrap(analyze(samples))
    XCTAssertGreaterThan(metrics.validity.headMoved, 0)
    XCTAssertGreaterThan(metrics.validity.missing, 0)
    let total = metrics.validity.valid + metrics.validity.lowConfidence + metrics.validity.eyesClosed
      + metrics.validity.headMoved + metrics.validity.missing
    XCTAssertEqual(total, 1, accuracy: 1e-9)
  }

  func testBinocularConsistencyIgnoresConstantVergence() throws {
    let binocular = try XCTUnwrap(try detailed(EyeModel()).binocular)
    XCTAssertEqual(try XCTUnwrap(binocular.leftRightCorrelation), 1, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(binocular.disagreementRMSDegrees), 0, accuracy: 0.001)
  }

  // MARK: - Timing and coverage

  func testIrregularTimestampsKeepTheMeasures() throws {
    var model = EyeModel()
    model.jitter = 0.5
    model.overshoot = 1.25
    let metrics = try detailed(model)
    let horizontal = try XCTUnwrap(metrics.horizontalPursuit)
    XCTAssertEqual(try XCTUnwrap(horizontal.gain), 1, accuracy: 0.1)
    XCTAssertEqual(try XCTUnwrap(horizontal.lagMilliseconds), 0, accuracy: 25)
    let saccades = try XCTUnwrap(metrics.saccades)
    XCTAssertEqual(try XCTUnwrap(saccades.medianLatencyMilliseconds), 200, accuracy: 30)
    XCTAssertEqual(try XCTUnwrap(saccades.medianPrimaryGain), 1.25, accuracy: 0.1)
  }

  func testThirtyHertzStillMeasures() throws {
    var model = EyeModel()
    model.rate = 30
    let metrics = try detailed(model)
    XCTAssertEqual(try XCTUnwrap(metrics.horizontalPursuit?.gain), 1, accuracy: 0.1)
    XCTAssertEqual(try XCTUnwrap(metrics.saccades?.medianLatencyMilliseconds), 200, accuracy: 40)
  }

  func testShortAndEmptyPhasesAreNilNotZero() throws {
    let fixationOnly = EyeModel().samples().filter { $0.timestamp < 3 }
    let metrics = try XCTUnwrap(analyze(fixationOnly))
    XCTAssertNotNil(metrics.fixation)
    XCTAssertNil(metrics.horizontalPursuit)
    XCTAssertNil(metrics.verticalPursuit)
    XCTAssertNil(metrics.saccades)
    XCTAssertEqual(metrics.coverage.saccades, 0)

    let brief = EyeModel().samples().filter { $0.timestamp < 0.5 }
    let briefMetrics = try XCTUnwrap(analyze(brief))
    XCTAssertNil(briefMetrics.fixation, "a sixth of the phase is not a fixation measure")
    XCTAssertLessThan(try XCTUnwrap(briefMetrics.coverage.fixation), OcularDetailedAnalyzer.minimumPhaseCoverage)
    XCTAssertNil(briefMetrics.gazeTransitionsPerMinute)

    XCTAssertNil(analyze([]))
    let summary = OcularSignalAnalyzer().summarize(
      samples: [], observedFrameCount: 0, liveQuality: usableQuality(count: 0))
    XCTAssertNil(summary.detailed)
  }

  func testDropoutLowersCoverage() throws {
    // Every other half-second missing from the pursuit phases.
    let samples = EyeModel().samples().filter {
      !($0.timestamp > 3 && $0.timestamp < 17 && Int($0.timestamp * 2) % 2 == 0)
    }
    let metrics = try XCTUnwrap(analyze(samples))
    XCTAssertEqual(try XCTUnwrap(metrics.coverage.horizontalPursuit), 0.5, accuracy: 0.05)
    XCTAssertNotNil(metrics.horizontalPursuit)
    XCTAssertEqual(try XCTUnwrap(metrics.coverage.fixation), 1, accuracy: 0.02)
  }

  func testReducedMotionHasNoPursuitMeasures() throws {
    var model = EyeModel()
    model.variant = .reducedMotion
    model.overshoot = 1.25
    let metrics = try detailed(model)
    XCTAssertNil(metrics.horizontalPursuit)
    XCTAssertNil(metrics.verticalPursuit)
    XCTAssertNil(metrics.coverage.horizontalPursuit)
    XCTAssertNil(metrics.coverage.verticalPursuit)
    let saccades = try XCTUnwrap(metrics.saccades)
    XCTAssertEqual(saccades.analysedJumpCount, 8)
    XCTAssertEqual(try XCTUnwrap(saccades.medianLatencyMilliseconds), 200, accuracy: 25)
    XCTAssertNotNil(metrics.fixation)
  }

  func testNoCameraVariantRecordsNothing() {
    XCTAssertNil(OcularDetailedAnalyzer().analyze(
      samples: EyeModel().samples(), variant: .noCamera, blinkCount: nil, blinkRatePerMinute: nil))
  }

  // MARK: - Recording, not scoring

  func testUnusableCaptureStillRecordsDetailedMeasures() throws {
    let samples = EyeModel().samples()
    var quality = usableQuality(count: samples.count)
    quality.lightingAcceptable = false
    let summary = OcularSignalAnalyzer().summarize(
      samples: samples, observedFrameCount: samples.count, liveQuality: quality)
    XCTAssertFalse(summary.quality.isUsable)
    XCTAssertEqual(summary.smoothnessRisk, 1)
    XCTAssertEqual(summary.qualityScore, 0)
    XCTAssertNotNil(summary.detailed?.fixation)
    XCTAssertNotNil(summary.detailed?.saccades?.medianLatencyMilliseconds)
  }

  func testScoredPathIgnoresDetailedMeasures() {
    let samples = EyeModel().samples()
    let summary = OcularSignalAnalyzer().summarize(
      samples: samples, observedFrameCount: samples.count, liveQuality: usableQuality(count: samples.count))
    XCTAssertTrue(summary.quality.isUsable)
    // The same weights as before, recomputed from the features alone.
    let f = summary.features
    let total = 0.22 + 0.25 + 0.18 + 0.2 + 0.15
    let expected = (f.fixationJitter * 0.22 + f.horizontalPursuitError * 0.25 + f.verticalPursuitError * 0.18
      + f.saccadeError * 0.2 + f.headCompensation * 0.15) / total
    XCTAssertEqual(summary.smoothnessRisk, min(max(expected, 0), 1), accuracy: 1e-12)
    XCTAssertEqual(summary.detailed?.blinkRatePerMinute, f.blinkRatePerMinute)
  }

  func testTelemetryDoesNotDropDetailedMeasures() throws {
    let samples = EyeModel().samples()
    let summary = OcularSignalAnalyzer().summarize(
      samples: samples, observedFrameCount: samples.count, liveQuality: usableQuality(count: samples.count))
    let detailed = try XCTUnwrap(summary.detailed)
    let withTelemetry = summary.with(telemetry: CaptureTelemetryRecorder().summary(verdict: .valid))
    XCTAssertEqual(withTelemetry.detailed, detailed)
  }

  func testDetailedMeasuresPersistAndOldSummariesDecodeWithout() throws {
    let samples = EyeModel().samples()
    let summary = OcularSignalAnalyzer().summarize(
      samples: samples, observedFrameCount: samples.count, liveQuality: usableQuality(count: samples.count))
    let data = try JSONEncoder().encode(summary)
    XCTAssertEqual(try JSONDecoder().decode(GazeCaptureSummary.self, from: data), summary)

    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertNotNil(legacy["detailed"])
    legacy.removeValue(forKey: "detailed")
    legacy.removeValue(forKey: "telemetry")
    let old = try JSONDecoder().decode(
      GazeCaptureSummary.self, from: JSONSerialization.data(withJSONObject: legacy))
    XCTAssertNil(old.detailed)
    XCTAssertEqual(old.smoothnessRisk, summary.smoothnessRisk)

    // A summary written before this field existed, verbatim.
    let verbatim = Data(
      """
      {"smoothnessRisk":0.2,"qualityScore":0.9,"sampleCount":240,"capturedDurationMilliseconds":25000,
       "quality":{"isSupported":true,"hasCameraPermission":true,"facePresent":true,"centered":true,
       "distanceAcceptable":true,"lightingAcceptable":true,"headStable":true,"frameRate":30,
       "sampleCount":240,"dropoutRatio":0.02,"issues":[]},
       "features":{"fixationJitter":0.1,"horizontalPursuitError":0.1,"verticalPursuitError":0.1,
       "saccadeError":0.1,"leftRightAsymmetry":0.1,"blinkRatePerMinute":14,"headCompensation":0.1},
       "protocolVariant":"full"}
      """.utf8)
    XCTAssertNil(try JSONDecoder().decode(GazeCaptureSummary.self, from: verbatim).detailed)
  }

  func testResearchExportCarriesDetailedMeasures() throws {
    let samples = EyeModel().samples()
    let summary = OcularSignalAnalyzer().summarize(
      samples: samples, observedFrameCount: samples.count, liveQuality: usableQuality(count: samples.count))
    XCTAssertEqual(try researchExportRoundTrip(summary)?.detailed, summary.detailed)
  }

  // MARK: - Screen gaze (recorded only)

  /// A 353 x 330 pt stimulus field at (20, 120) on an iPhone 15 Pro display.
  private static let field = (x: 20.0, y: 120.0, width: 353.0, height: 330.0)
  private static let display = DisplayGeometry(nativePixelWidth: 1179, nativePixelHeight: 2556, nativeScale: 3)

  func testScreenGazeIsRecordedWithoutChangingAnyExistingMeasure() throws {
    let model = EyeModel()
    let plain = model.samples()
    let before = summarize(plain)
    let after = summarize(try screenGaze(on: plain, model: model))

    XCTAssertNil(before.detailed?.screenGaze, "no sample carried screen gaze")
    let screen = try XCTUnwrap(after.detailed?.screenGaze)
    XCTAssertEqual(screen.sampleCount, plain.count)
    XCTAssertEqual(screen.onScreenFraction, 1)
    XCTAssertEqual(screen.offScreenFraction + screen.noIntersectionFraction, 0)
    XCTAssertEqual(try XCTUnwrap(screen.medianViewingDistanceMetres), 0.4, accuracy: 1e-12)
    XCTAssertGreaterThan(try XCTUnwrap(screen.horizontalScreenCorrelation), 0.99)
    XCTAssertGreaterThan(try XCTUnwrap(screen.verticalScreenCorrelation), 0.99)

    // Everything else, scored or recorded, is exactly what it was.
    XCTAssertEqual(after.smoothnessRisk, before.smoothnessRisk)
    XCTAssertEqual(after.qualityScore, before.qualityScore)
    XCTAssertEqual(after.features, before.features)
    XCTAssertEqual(after.quality, before.quality)
    var unchanged = try XCTUnwrap(after.detailed)
    unchanged.screenGaze = nil
    XCTAssertEqual(unchanged, before.detailed)
  }

  func testHeadFreeGazeStillFollowsWhenTheHeadHelps() throws {
    // Side to side, the head follows 60% of the dot half a second late and
    // the eyes make up the rest, so on the screen gaze stays on the dot.
    let scale = 0.25
    let display = try XCTUnwrap(Self.display)
    var samples: [OcularSample] = []
    var t = 0.0
    while t < OcularProtocolSchedule.totalDuration {
      let target = OcularProtocolSchedule.target(at: t)
      let headShare = target.phase == .horizontalPursuit
        ? 0.6 * (OcularProtocolSchedule.target(at: t - 0.5).x - 0.5) : 0
      let gx = -scale * (target.x - 0.5 - headShare)
      let gy = scale * (target.y - 0.5)
      let yaw = headShare * scale
      var sample = OcularSample(
        timestamp: t, phase: target.phase, targetX: target.x, targetY: target.y,
        leftGazeX: gx + 0.01, leftGazeY: gy, rightGazeX: gx - 0.01, rightGazeY: gy,
        headX: sin(yaw), headY: 0, headZ: cos(yaw), blinkLeft: 0.05, blinkRight: 0.05)
      sample.setScreenGaze(gaze(atFieldX: target.x, fieldY: target.y, display: display))
      samples.append(sample)
      t += 1.0 / 60
    }

    let summary = summarize(samples)
    let screen = try XCTUnwrap(summary.detailed?.screenGaze)
    XCTAssertGreaterThan(try XCTUnwrap(screen.horizontalScreenCorrelation), 0.99)
    XCTAssertLessThan(try XCTUnwrap(screen.horizontalEyeInHeadCorrelation), 0.9)
    // Up and down the head held still, and the two agree.
    XCTAssertEqual(try XCTUnwrap(screen.verticalEyeInHeadCorrelation), 1, accuracy: 0.01)
    XCTAssertGreaterThan(try XCTUnwrap(screen.verticalScreenCorrelation), 0.99)
    // The scored path reads the head's share as following error.
    XCTAssertGreaterThan(summary.features.horizontalPursuitError, 0.1)
  }

  func testScreenGazeFractionsLeaveOutClosedEyes() throws {
    var model = EyeModel()
    model.blinks = [5, 12, 20]
    let tagged = try screenGaze(on: model.samples(), model: model).enumerated().map { index, sample in
      var sample = sample
      switch index % 10 {
      case 0:
        sample.setScreenGaze(.unavailable)
      case 1, 2:
        let above = ScreenGazePoint(x: 200, y: -300, validity: .offScreen, distanceMetres: 0.4)
        sample.setScreenGaze(ScreenGaze(left: above, right: above, combined: above))
      default:
        break
      }
      return sample
    }
    let closed = OcularDetailedAnalyzer.labels(for: tagged).filter { $0 == .eyesClosed }.count
    XCTAssertGreaterThan(closed, 0)

    let screen = try XCTUnwrap(analyze(tagged)?.screenGaze)
    XCTAssertEqual(screen.sampleCount, tagged.count - closed)
    XCTAssertEqual(screen.noIntersectionFraction, 0.1, accuracy: 0.02)
    XCTAssertEqual(screen.offScreenFraction, 0.2, accuracy: 0.02)
    XCTAssertEqual(screen.onScreenFraction, 0.7, accuracy: 0.02)
    XCTAssertEqual(screen.onScreenFraction + screen.offScreenFraction + screen.noIntersectionFraction, 1, accuracy: 1e-12)

    // Reduced Motion has no pursuit to follow.
    var reduced = EyeModel()
    reduced.variant = .reducedMotion
    let still = try XCTUnwrap(analyze(try screenGaze(on: reduced.samples(), model: reduced), variant: .reducedMotion)?.screenGaze)
    XCTAssertNil(still.horizontalScreenCorrelation)
    XCTAssertNil(still.verticalEyeInHeadCorrelation)
    XCTAssertEqual(still.onScreenFraction, 1)
  }

  func testScreenGazePersistsAndOlderRecordsDecodeWithout() throws {
    let model = EyeModel()
    let summary = summarize(try screenGaze(on: model.samples(), model: model))
    let detailed = try XCTUnwrap(summary.detailed)
    XCTAssertNotNil(detailed.screenGaze)
    let data = try JSONEncoder().encode(detailed)
    XCTAssertEqual(try JSONDecoder().decode(OcularDetailedMetrics.self, from: data), detailed)

    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    legacy.removeValue(forKey: "screenGaze")
    let old = try JSONDecoder().decode(
      OcularDetailedMetrics.self, from: JSONSerialization.data(withJSONObject: legacy))
    var expected = detailed
    expected.screenGaze = nil
    XCTAssertEqual(old, expected)

    XCTAssertEqual(try researchExportRoundTrip(summary)?.detailed?.screenGaze, detailed.screenGaze)
  }

  /// The same samples with head-free screen gaze where the model put the
  /// eyes, on `field`, 40 cm from the screen.
  private func screenGaze(on samples: [OcularSample], model: EyeModel) throws -> [OcularSample] {
    let display = try XCTUnwrap(Self.display)
    return samples.map { sample in
      var sample = sample
      let x = (sample.leftGazeX + sample.rightGazeX) / 2 / model.scaleX + 0.5
      let y = (sample.leftGazeY + sample.rightGazeY) / 2 / model.scaleY + 0.5
      sample.setScreenGaze(gaze(atFieldX: x, fieldY: y, display: display))
      return sample
    }
  }

  private func gaze(atFieldX x: Double, fieldY y: Double, display: DisplayGeometry) -> ScreenGaze {
    let px = Self.field.x + x * Self.field.width
    let py = Self.field.y + y * Self.field.height
    let point = ScreenGazePoint(
      x: px, y: py, validity: ScreenGazeGeometry.classify(x: px, y: py, display: display), distanceMetres: 0.4)
    return ScreenGaze(left: point, right: point, combined: point)
  }

  private func summarize(
    _ samples: [OcularSample], calibration: OcularCalibration? = nil
  ) -> GazeCaptureSummary {
    OcularSignalAnalyzer().summarize(
      samples: samples, observedFrameCount: samples.count, liveQuality: usableQuality(count: samples.count),
      calibration: calibration)
  }

  /// Through the research JSON export and back.
  private func researchExportRoundTrip(_ summary: GazeCaptureSummary) throws -> GazeCaptureSummary? {
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let envelope = ResearchSessionEnvelope(
      participantID: .init(rawValue: "participant_test"),
      startedAt: startedAt,
      completedAt: startedAt.addingTimeInterval(45),
      metadata: ResearchSessionMetadata(
        device: ResearchDeviceMetadata(
          platform: "iOS", deviceModel: "iPhone", systemName: "iOS", systemVersion: "17.0",
          localeIdentifier: "en_US"),
        app: ResearchAppMetadata(bundleIdentifier: "com.soberprototype.tests", version: "0.2.0", build: "2"),
        protocolMetadata: ResearchProtocolMetadata(name: "Sober Research Battery", version: "0.2")),
      context: ResearchSessionContext(
        sessionKind: .soberBaseline, soberAtStartAttested: true, reportedAlcoholUse: false,
        reportedCannabisUse: false, sleepHours: 8, visionCorrection: .none, ambientLighting: .moderate),
      metrics: ResearchScreeningMetrics(
        reactionTimeMilliseconds: 300, reactionMisses: 0, trackingError: 0.18, timeEstimateError: 0.08,
        gazeSmoothness: summary.smoothnessRisk, qualityScore: summary.qualityScore, completedAllTasks: true),
      ocularSummary: summary
    )
    let payload = ResearchSessionExportPayload(exportedAt: Date(timeIntervalSince1970: 120), sessions: [envelope])
    let decoded = try JSONDecoder().decode(ResearchSessionExportPayload.self, from: JSONEncoder().encode(payload))
    return decoded.sessions.first?.ocularSummary
  }

  // MARK: - Calibration scale (HANDOFF 2.6)

  func testPursuitGainTakesItsScaleFromAPassedCalibration() throws {
    let model = EyeModel()
    // The jump phase cut off: no scale from it, so no gain without calibration.
    let cut = model.samples().filter { $0.timestamp < 17 }
    XCTAssertNil(analyze(cut)?.horizontalPursuit?.gain)

    let calibrated = try XCTUnwrap(analyze(cut, calibration: calibration(model)))
    for pursuit in [calibrated.horizontalPursuit, calibrated.verticalPursuit] {
      let pursuit = try XCTUnwrap(pursuit)
      XCTAssertEqual(try XCTUnwrap(pursuit.gain), 1, accuracy: 0.05)
      XCTAssertEqual(pursuit.gainScaleSource, .calibration)
    }
    XCTAssertEqual(calibrated.calibration, calibration(model).metrics)

    // Calibration comes first when the jump phase could supply a scale too:
    // one that says the eyes travel twice as far per screen unit halves gain.
    let doubled = try XCTUnwrap(analyze(model.samples(), calibration: calibration(model, scale: 2)))
    XCTAssertEqual(try XCTUnwrap(doubled.horizontalPursuit?.gain), 0.5, accuracy: 0.05)
    XCTAssertEqual(doubled.horizontalPursuit?.gainScaleSource, .calibration)
    XCTAssertEqual(doubled.verticalPursuit?.gainScaleSource, .calibration)
  }

  func testAFailedCalibrationFallsBackToTheJumpPhase() throws {
    let model = EyeModel()
    let failed = calibration(model, scale: 2, passed: false)
    let metrics = try XCTUnwrap(analyze(model.samples(), calibration: failed))
    XCTAssertEqual(try XCTUnwrap(metrics.horizontalPursuit?.gain), 1, accuracy: 0.05)
    XCTAssertEqual(metrics.horizontalPursuit?.gainScaleSource, .saccadePhase)
    // Its quality is recorded all the same.
    XCTAssertEqual(metrics.calibration?.passed, false)

    // With neither scale there is no gain, and so no source.
    let cut = model.samples().filter { $0.timestamp < 17 }
    let neither = try XCTUnwrap(analyze(cut, calibration: failed))
    XCTAssertNil(neither.horizontalPursuit?.gain)
    XCTAssertNil(neither.horizontalPursuit?.gainScaleSource)
    XCTAssertNotNil(neither.horizontalPursuit?.lagMilliseconds)
  }

  func testCalibrationNeverReachesTheScore() {
    let model = EyeModel()
    let samples = model.samples()
    let without = summarize(samples)
    XCTAssertTrue(without.quality.isUsable)
    for calibration in [calibration(model), calibration(model, scale: 2), calibration(model, passed: false)] {
      let with = summarize(samples, calibration: calibration)
      XCTAssertEqual(with.smoothnessRisk, without.smoothnessRisk)
      XCTAssertEqual(with.qualityScore, without.qualityScore)
      XCTAssertEqual(with.features, without.features)
      XCTAssertEqual(with.quality, without.quality)
    }
  }

  func testCalibrationQualityPersistsAndVersionOneRecordsDecode() throws {
    XCTAssertEqual(OcularDetailedMetrics.currentVersion, 2)
    let model = EyeModel()
    let summary = summarize(model.samples(), calibration: calibration(model))
    let detailed = try XCTUnwrap(summary.detailed)
    XCTAssertEqual(detailed.version, 2)
    XCTAssertNotNil(detailed.calibration)
    let data = try JSONEncoder().encode(detailed)
    XCTAssertEqual(try JSONDecoder().decode(OcularDetailedMetrics.self, from: data), detailed)
    XCTAssertEqual(try researchExportRoundTrip(summary)?.detailed, detailed)

    // A version 1 record: no calibration, no scale source.
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    legacy["version"] = 1
    legacy.removeValue(forKey: "calibration")
    for key in ["horizontalPursuit", "verticalPursuit"] {
      var pursuit = try XCTUnwrap(legacy[key] as? [String: Any])
      XCTAssertNotNil(pursuit.removeValue(forKey: "gainScaleSource"))
      legacy[key] = pursuit
    }
    let old = try JSONDecoder().decode(
      OcularDetailedMetrics.self, from: JSONSerialization.data(withJSONObject: legacy))
    XCTAssertEqual(old.version, 1)
    XCTAssertNil(old.calibration)
    XCTAssertNil(old.horizontalPursuit?.gainScaleSource)
    XCTAssertEqual(old.horizontalPursuit?.gain, detailed.horizontalPursuit?.gain)
    XCTAssertEqual(old.saccades, detailed.saccades)
  }

  /// A calibration whose eye-in-head points sit where the model's eyes would
  /// settle, times `scale`.
  private func calibration(_ model: EyeModel, scale: Double = 1, passed: Bool = true) -> OcularCalibration {
    OcularCalibration(
      metrics: OcularCalibrationMetrics(
        pointsScheduled: 5, pointsUsed: 5, residualRMSDegrees: passed ? 0.3 : 1.8,
        viewingDistanceMetres: 0.4, rejectedSampleFraction: 0, passed: passed),
      map: nil,
      eyeInHeadPoints: OcularCalibrationSchedule.points.map {
        OcularDetailedAnalyzer.CalibrationPoint(
          targetX: $0.x, targetY: $0.y,
          x: scale * model.scaleX * ($0.x - 0.5), y: scale * model.scaleY * ($0.y - 0.5))
      },
      field: nil)
  }

  // MARK: - Randomized invariants

  func testRandomTrajectoriesKeepInvariants() throws {
    var generator = SeededGenerator(seed: 0x5EED_E7E5)
    let encoder = JSONEncoder()  // Throws on NaN or infinity.
    for run in 0..<1_000 {
      var model = EyeModel.random(using: &generator)
      model.seed = UInt64(run)
      let samples = model.randomlyDamaged(model.samples(), using: &generator)
      let blinks = OcularSignalAnalyzer.countBlinkEvents(samples)
      guard let metrics = OcularDetailedAnalyzer().analyze(
        samples: samples, variant: model.variant, blinkCount: blinks, blinkRatePerMinute: nil)
      else {
        XCTAssertTrue(samples.allSatisfy { $0.phase == .calibration } || samples.isEmpty, "run \(run)")
        continue
      }
      XCTAssertNoThrow(try encoder.encode(metrics), "run \(run) produced a non-finite value")
      try assertInvariants(metrics, variant: model.variant, run: run)
    }
  }

  private func assertInvariants(_ m: OcularDetailedMetrics, variant: OcularProtocolVariant, run: Int) throws {
    let v = m.validity
    for fraction in [v.valid, v.lowConfidence, v.eyesClosed, v.headMoved, v.missing, v.eyeStateUnknown] {
      XCTAssertTrue((0...1).contains(fraction), "run \(run)")
    }
    XCTAssertEqual(v.valid + v.lowConfidence + v.eyesClosed + v.headMoved + v.missing, 1, accuracy: 1e-9, "run \(run)")

    let minimum = OcularDetailedAnalyzer.minimumPhaseCoverage
    func check(_ coverage: Double?, present: Bool) {
      if let coverage {
        XCTAssertTrue((0...1).contains(coverage), "run \(run)")
        if coverage < minimum { XCTAssertFalse(present, "run \(run): measured below minimum coverage") }
      } else {
        XCTAssertFalse(present, "run \(run): measured a phase the variant does not run")
      }
    }
    check(m.coverage.fixation, present: m.fixation != nil)
    check(m.coverage.horizontalPursuit, present: m.horizontalPursuit != nil)
    check(m.coverage.verticalPursuit, present: m.verticalPursuit != nil)
    check(m.coverage.saccades, present: m.saccades != nil)
    if variant == .reducedMotion {
      XCTAssertNil(m.coverage.horizontalPursuit)
      XCTAssertNil(m.coverage.verticalPursuit)
    }

    if let f = m.fixation {
      XCTAssertGreaterThanOrEqual(f.coverage, minimum)
      XCTAssertGreaterThanOrEqual(f.intrusiveSaccadeCount, 0)
      for value in [f.dispersionRMSDegrees, f.bceaSquareDegrees, f.longestStableMilliseconds].compactMap({ $0 }) {
        XCTAssertGreaterThanOrEqual(value, 0, "run \(run)")
      }
    }
    for pursuit in [m.horizontalPursuit, m.verticalPursuit].compactMap({ $0 }) {
      XCTAssertGreaterThanOrEqual(pursuit.coverage, minimum)
      XCTAssertGreaterThanOrEqual(pursuit.catchUpSaccadeCount, 0)
      if let lag = pursuit.lagMilliseconds {
        XCTAssertTrue((-200...500).contains(lag), "run \(run): lag \(lag)")
      }
    }
    if let s = m.saccades {
      XCTAssertGreaterThanOrEqual(s.coverage, minimum)
      XCTAssertLessThanOrEqual(s.analysedJumpCount, s.jumpCount)
      XCTAssertEqual(s.jumps.count, s.analysedJumpCount)
      if let fraction = s.respondedFraction { XCTAssertTrue((0...1).contains(fraction), "run \(run)") }
      if let latency = s.medianLatencyMilliseconds {
        XCTAssertTrue((0...OcularDetailedAnalyzer.responseWindowSeconds * 1_000).contains(latency), "run \(run)")
      }
      if let error = s.medianLandingError { XCTAssertGreaterThanOrEqual(error, 0) }
      for jump in s.jumps {
        if let latency = jump.latencyMilliseconds { XCTAssertGreaterThanOrEqual(latency, 0, "run \(run)") }
        XCTAssertEqual(jump.responded, jump.latencyMilliseconds != nil, "run \(run)")
        XCTAssertGreaterThanOrEqual(jump.correctiveSaccadeCount, 0)
      }
    }
    if let correlation = m.binocular?.leftRightCorrelation {
      XCTAssertTrue((-1...1).contains(correlation), "run \(run)")
    }
    if let rms = m.binocular?.disagreementRMSDegrees { XCTAssertGreaterThanOrEqual(rms, 0) }
    if let count = m.gazeTransitionCount { XCTAssertGreaterThanOrEqual(count, 0) }
    if let rate = m.gazeTransitionsPerMinute { XCTAssertGreaterThanOrEqual(rate, 0) }
  }

  // MARK: - Helpers

  private func analyze(
    _ samples: [OcularSample], variant: OcularProtocolVariant = .full, calibration: OcularCalibration? = nil
  ) -> OcularDetailedMetrics? {
    OcularDetailedAnalyzer().analyze(
      samples: samples, variant: variant,
      blinkCount: OcularSignalAnalyzer.countBlinkEvents(samples), blinkRatePerMinute: nil,
      calibration: calibration)
  }

  private func detailed(_ model: EyeModel) throws -> OcularDetailedMetrics {
    let samples = model.samples()
    let summary = OcularSignalAnalyzer().summarize(
      samples: samples, observedFrameCount: samples.count,
      liveQuality: usableQuality(count: samples.count), variant: model.variant)
    return try XCTUnwrap(summary.detailed)
  }

  private func usableQuality(count: Int) -> CaptureQualitySnapshot {
    CaptureQualitySnapshot(
      isSupported: true, hasCameraPermission: true, facePresent: true, centered: true,
      distanceAcceptable: true, lightingAcceptable: true, headStable: true,
      frameRate: 60, sampleCount: count, dropoutRatio: 0, issues: [])
  }
}

// MARK: - Synthetic eye

/// A synthetic person doing the protocol. Eye position is in screen units
/// (where the target is drawn), mapped to gaze with a per-axis scale.
private struct EyeModel {
  var variant: OcularProtocolVariant = .full
  var rate = 60.0
  /// Each interval is 1/rate times a factor in 1 +/- jitter.
  var jitter = 0.0
  /// Gaze units per screen unit: about 14 degrees across the screen, with x
  /// mirrored.
  var scaleX = -0.25
  var scaleY = 0.25
  var vergence = 0.01
  var fixationNoiseDegrees = 0.0
  var fixationJerks: [Double] = []
  var pursuitLag = 0.0
  var pursuitGain = 1.0
  var saccadeLatency = 0.2
  var saccadeDuration = 0.04
  var overshoot = 1.0
  var frozenSaccades = false
  var blinks: [Double] = []
  var blinkTelemetry = true
  var headTurns: [Double] = []
  var noiseDegrees = 0.0
  var seed: UInt64 = 1

  static let blinkLength = 0.15
  static let headTurnLength = 0.1

  var phaseStart: (fixation: Double, horizontal: Double, vertical: Double, saccades: Double) {
    let s = OcularProtocolSchedule.self
    let saccades = variant == .full ? s.fixationDuration + s.horizontalDuration + s.verticalDuration : s.fixationDuration
    return (0, s.fixationDuration, s.fixationDuration + s.horizontalDuration, saccades)
  }

  func isBlinking(_ t: Double) -> Bool { blinks.contains { t >= $0 && t < $0 + Self.blinkLength } }

  func samples() -> [OcularSample] {
    var noise = SeededGenerator(seed: seed)
    let duration = OcularProtocolSchedule.totalDuration(for: variant)
    let simulated = pursuitGain == 1 ? nil : simulateLowGainPursuit()
    var result: [OcularSample] = []
    var t = 0.0
    while t < duration {
      let target = OcularProtocolSchedule.target(at: t, variant: variant)
      var (ex, ey) = eye(at: t, target: target, simulated: simulated)
      if target.phase == .fixation {
        let sigma = fixationNoiseDegrees / OcularDetailedAnalyzer.degreesPerGazeUnit
        ex += noise.gaussian() * sigma / abs(scaleX)
        ey += noise.gaussian() * sigma / abs(scaleY)
      }
      var gx = scaleX * (ex - 0.5)
      var gy = scaleY * (ey - 0.5)
      if noiseDegrees > 0 {
        gx += noise.gaussian() * noiseDegrees / OcularDetailedAnalyzer.degreesPerGazeUnit
        gy += noise.gaussian() * noiseDegrees / OcularDetailedAnalyzer.degreesPerGazeUnit
      }
      let closed = isBlinking(t)
      if closed { gy -= 0.2 }  // Lids drag the tracked eye down while closed.
      var head = (x: 0.0, y: 0.0, z: 1.0)
      for turn in headTurns where t >= turn && t < turn + Self.headTurnLength {
        let angle = (t - turn) / Self.headTurnLength * 0.15  // ~86 deg/s
        head = (sin(angle), 0, cos(angle))
      }
      for turn in headTurns where t >= turn + Self.headTurnLength {
        head = (sin(0.15), 0, cos(0.15))
      }
      let lid: Double? = blinkTelemetry ? (closed ? 0.9 : 0.05) : nil
      result.append(OcularSample(
        timestamp: t, phase: target.phase, targetX: target.x, targetY: target.y,
        leftGazeX: gx + vergence, leftGazeY: gy, rightGazeX: gx - vergence, rightGazeY: gy,
        headX: head.x, headY: head.y, headZ: head.z, blinkLeft: lid, blinkRight: lid))
      let factor = jitter > 0 ? 1 + noise.uniform(-jitter, jitter) : 1
      t += factor / rate
    }
    return result
  }

  private func eye(at t: Double, target: OcularTarget, simulated: [(Double, Double)]?) -> (Double, Double) {
    let starts = phaseStart
    switch target.phase {
    case .calibration:
      return (0.5, 0.5)
    case .fixation:
      var x = 0.5
      if fixationJerks.contains(where: { t >= $0 && t < $0 + 0.2 }) { x += 0.08 }
      return (x, 0.5)
    case .horizontalPursuit, .verticalPursuit:
      if let simulated {
        let index = min(max(Int((t - starts.horizontal) * 1_000), 0), simulated.count - 1)
        return simulated[index]
      }
      let lagged = OcularProtocolSchedule.target(at: t - pursuitLag, variant: variant)
      return (lagged.x, lagged.y)
    case .saccades:
      let before = OcularProtocolSchedule.target(at: starts.saccades - 1e-6, variant: variant)
      if frozenSaccades { return (before.x, before.y) }
      func position(_ j: Int) -> (Double, Double) {
        guard j >= 0 else { return (before.x, before.y) }
        let p = OcularProtocolSchedule.target(at: starts.saccades + Double(j) + 0.001, variant: variant)
        return (p.x, p.y)
      }
      let j = Int(floor(t - starts.saccades - saccadeLatency))
      guard j >= 0 else { return position(-1) }
      let from = position(j - 1)
      let to = position(j)
      let over = (from.0 + overshoot * (to.0 - from.0), from.1 + overshoot * (to.1 - from.1))
      let s = t - starts.saccades - Double(j) - saccadeLatency
      func lerp(_ a: (Double, Double), _ b: (Double, Double), _ f: Double) -> (Double, Double) {
        (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f)
      }
      if s < saccadeDuration { return lerp(from, over, s / saccadeDuration) }
      if s < saccadeDuration + 0.1 { return over }
      if s < saccadeDuration + 0.115 { return lerp(over, to, (s - saccadeDuration - 0.1) / 0.015) }
      return to
    }
  }

  /// Smooth pursuit at `pursuitGain` of target speed, with a 25 ms catch-up
  /// saccade whenever the eye falls 0.12 screen units behind. 1 kHz from the
  /// start of horizontal pursuit to the end of vertical.
  private func simulateLowGainPursuit() -> [(Double, Double)] {
    let starts = phaseStart
    let end = starts.vertical + OcularProtocolSchedule.verticalDuration
    let step = 0.001
    var result: [(Double, Double)] = []
    var t = starts.horizontal
    var position = { let p = OcularProtocolSchedule.target(at: t, variant: variant); return (p.x, p.y) }()
    var catchUpLeft = 0.0
    var catchUpVelocity = (0.0, 0.0)
    var phase = OcularPhase.horizontalPursuit
    while t < end {
      let now = OcularProtocolSchedule.target(at: t, variant: variant)
      if now.phase != phase {
        phase = now.phase
        position = (now.x, now.y)  // Each pursuit starts on its target.
        catchUpLeft = 0
      }
      result.append(position)
      let next = OcularProtocolSchedule.target(at: t + step, variant: variant)
      if catchUpLeft > 0 {
        position.0 += catchUpVelocity.0 * step
        position.1 += catchUpVelocity.1 * step
        catchUpLeft -= step
      } else {
        position.0 += pursuitGain * (next.x - now.x)
        position.1 += pursuitGain * (next.y - now.y)
        if hypot(next.x - position.0, next.y - position.1) > 0.12 {
          let landing = OcularProtocolSchedule.target(at: t + 0.025, variant: variant)
          catchUpVelocity = ((landing.x - position.0) / 0.025, (landing.y - position.1) / 0.025)
          catchUpLeft = 0.025
        }
      }
      t += step
    }
    return result
  }

  // MARK: Random

  static func random(using g: inout SeededGenerator) -> EyeModel {
    var model = EyeModel()
    model.variant = g.uniform(0, 1) < 0.3 ? .reducedMotion : .full
    // Mostly below ARKit's 60 Hz to keep 1,000 runs fast; full-rate
    // behaviour is covered by the ground-truth tests.
    model.rate = g.uniform(10, 40)
    model.jitter = g.uniform(0, 1) < 0.5 ? 0 : g.uniform(0, 0.9)
    let scale = g.uniform(0.002, 0.6)
    model.scaleX = g.uniform(0, 1) < 0.5 ? -scale : scale
    model.scaleY = g.uniform(0, 1) < 0.5 ? -scale : scale
    model.vergence = g.uniform(-0.05, 0.05)
    model.noiseDegrees = g.uniform(0, 1) < 0.3 ? 0 : g.uniform(0, 3)
    model.pursuitLag = g.uniform(-0.3, 0.6)
    model.pursuitGain = g.uniform(0, 1) < 0.15 ? g.uniform(0.2, 1.5) : 1
    model.saccadeLatency = g.uniform(0, 0.9)
    model.saccadeDuration = g.uniform(0.01, 0.1)
    model.overshoot = g.uniform(0, 1.8)
    model.frozenSaccades = g.uniform(0, 1) < 0.1
    model.blinkTelemetry = g.uniform(0, 1) > 0.15
    model.blinks = (0..<Int(g.uniform(0, 6))).map { _ in g.uniform(0, 25) }
    model.headTurns = (0..<Int(g.uniform(0, 3))).map { _ in g.uniform(0, 25) }
    model.fixationJerks = (0..<Int(g.uniform(0, 3))).map { _ in g.uniform(0, 3) }
    return model
  }

  /// Truncation, dropouts, broken vectors, partial blink telemetry,
  /// duplicate and swapped timestamps, and pure garbage.
  func randomlyDamaged(_ samples: [OcularSample], using g: inout SeededGenerator) -> [OcularSample] {
    var result = samples
    if g.uniform(0, 1) < 0.4 {
      let start = Int(g.uniform(0, Double(result.count)))
      let end = Int(g.uniform(Double(start), Double(result.count)))
      result = Array(result[start..<end])
    }
    let dropout = g.uniform(0, 1) < 0.5 ? 0 : g.uniform(0, 0.8)
    if dropout > 0 {
      var kept: [OcularSample] = []
      var dropping = false
      for sample in result {
        if g.uniform(0, 1) < 0.05 { dropping = g.uniform(0, 1) < dropout }
        if !dropping { kept.append(sample) }
      }
      result = kept
    }
    let garbage = g.uniform(0, 1) < 0.1
    for index in result.indices {
      let roll = g.uniform(0, 1)
      if garbage {
        result[index] = result[index].replacingGaze(g.uniform(-1, 1), g.uniform(-1, 1))
      } else if roll < 0.01 {
        result[index] = result[index].replacingGaze([Double.nan, .infinity, 0][Int(g.uniform(0, 2.99))])
      } else if roll < 0.02 {
        result[index] = result[index].replacingBlink(left: nil, right: g.uniform(0, 1))
      } else if roll < 0.025, index > 0 {
        result[index] = result[index].replacingTimestamp(result[index - 1].timestamp)
      } else if roll < 0.028, index > 0 {
        result.swapAt(index, index - 1)
      }
    }
    if g.uniform(0, 1) < 0.05 { result = result.map { $0.replacingPhase(.calibration) } }
    return result
  }
}

private extension OcularSample {
  func replacingGaze(_ value: Double) -> OcularSample { replacingGaze(value, value) }

  func replacingGaze(_ x: Double, _ y: Double) -> OcularSample {
    OcularSample(
      timestamp: timestamp, phase: phase, targetX: targetX, targetY: targetY,
      leftGazeX: x, leftGazeY: y, rightGazeX: x, rightGazeY: y,
      headX: headX, headY: headY, headZ: headZ, blinkLeft: blinkLeft, blinkRight: blinkRight)
  }

  func replacingBlink(left: Double?, right: Double?) -> OcularSample {
    OcularSample(
      timestamp: timestamp, phase: phase, targetX: targetX, targetY: targetY,
      leftGazeX: leftGazeX, leftGazeY: leftGazeY, rightGazeX: rightGazeX, rightGazeY: rightGazeY,
      headX: headX, headY: headY, headZ: headZ, blinkLeft: left, blinkRight: right)
  }

  func replacingTimestamp(_ value: TimeInterval) -> OcularSample {
    OcularSample(
      timestamp: value, phase: phase, targetX: targetX, targetY: targetY,
      leftGazeX: leftGazeX, leftGazeY: leftGazeY, rightGazeX: rightGazeX, rightGazeY: rightGazeY,
      headX: headX, headY: headY, headZ: headZ, blinkLeft: blinkLeft, blinkRight: blinkRight)
  }

  func replacingPhase(_ value: OcularPhase) -> OcularSample {
    OcularSample(
      timestamp: timestamp, phase: value, targetX: targetX, targetY: targetY,
      leftGazeX: leftGazeX, leftGazeY: leftGazeY, rightGazeX: rightGazeX, rightGazeY: rightGazeY,
      headX: headX, headY: headY, headZ: headZ, blinkLeft: blinkLeft, blinkRight: blinkRight)
  }
}

/// SplitMix64: deterministic across runs and platforms.
private struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  mutating func uniform(_ low: Double, _ high: Double) -> Double {
    low + (high - low) * (Double(next() >> 11) / Double(1 << 53))
  }

  mutating func gaussian() -> Double {
    let u = max(uniform(0, 1), 1e-12)
    return sqrt(-2 * log(u)) * cos(2 * .pi * uniform(0, 1))
  }
}
