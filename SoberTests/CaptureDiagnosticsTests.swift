import CoreGraphics
import XCTest

@testable import Sober

/// Second face, capture verdict, image statistics, tracking telemetry and
/// directional guidance. The simulator has no TrueDepth camera, so these drive
/// the pure pieces directly; that ARKit reports a second face or the luma
/// values claimed here on a real phone still needs a device.
final class CaptureDiagnosticsTests: XCTestCase {

  private func usable(frameRate: Double = 60, dropout: Double = 0.05) -> CaptureQualitySnapshot {
    CaptureQualitySnapshot(
      isSupported: true, hasCameraPermission: true, facePresent: true, centered: true,
      distanceAcceptable: true, lightingAcceptable: true, headStable: true,
      frameRate: frameRate, sampleCount: 120, dropoutRatio: dropout, issues: [])
  }

  // MARK: - Second face

  func testAnotherFaceInViewMakesTheCaptureUnusable() {
    var quality = usable()
    XCTAssertTrue(quality.isUsable)
    quality.otherFacesInView = true
    quality.issues = [.multipleFaces]
    XCTAssertFalse(quality.isUsable)
    XCTAssertEqual(quality.primaryGuidance, CaptureQualityIssue.multipleFaces.guidance)
  }

  /// Sustained, not a one-frame false detection.
  func testASustainedSecondFaceInvalidatesTheWholeCapture() {
    func history(multipleFaceFrames: Int, of total: Int) -> CaptureQualitySnapshot {
      var history = CaptureQualityHistory()
      for frame in 0..<total {
        history.record(
          facePresent: true, centered: true, distanceAcceptable: true,
          lightingAcceptable: true, headStable: true,
          otherFacesInView: frame < multipleFaceFrames)
      }
      return history.applying(to: usable())
    }

    let sustained = history(multipleFaceFrames: 10, of: 100)
    XCTAssertTrue(sustained.otherFacesInView)
    XCTAssertEqual(sustained.issues.first, .multipleFaces)
    XCTAssertFalse(sustained.isUsable)

    let blip = history(multipleFaceFrames: 2, of: 100)
    XCTAssertFalse(blip.otherFacesInView)
    XCTAssertTrue(blip.isUsable)
  }

  /// Sessions saved before the field existed must still load, or every
  /// stored baseline would be lost.
  func testSnapshotsSavedBeforeTheSecondFaceCheckStillDecode() throws {
    let legacy = """
      {"isSupported":true,"hasCameraPermission":true,"facePresent":true,"centered":true,
       "distanceAcceptable":true,"lightingAcceptable":true,"headStable":true,"frameRate":60,
       "sampleCount":120,"dropoutRatio":0.05,"issues":[]}
      """
    let decoded = try JSONDecoder().decode(CaptureQualitySnapshot.self, from: Data(legacy.utf8))
    XCTAssertFalse(decoded.otherFacesInView)
    XCTAssertTrue(decoded.isUsable)

    var flagged = usable()
    flagged.otherFacesInView = true
    let roundTrip = try JSONDecoder().decode(
      CaptureQualitySnapshot.self, from: JSONEncoder().encode(flagged))
    XCTAssertEqual(roundTrip, flagged)
  }

  func testSummariesKeepTheirTelemetryAndOldOnesDecodeWithout() throws {
    let telemetry = CaptureTelemetryRecorder().summary(verdict: .valid)
    let summary = GazeCaptureSummary(
      smoothnessRisk: 0.2, qualityScore: 0.9, sampleCount: 100, quality: usable(),
      telemetry: telemetry)
    let decoded = try JSONDecoder().decode(
      GazeCaptureSummary.self, from: JSONEncoder().encode(summary))
    XCTAssertEqual(decoded.telemetry, telemetry)

    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as! [String: Any]
    legacy.removeValue(forKey: "telemetry")
    let old = try JSONDecoder().decode(
      GazeCaptureSummary.self, from: JSONSerialization.data(withJSONObject: legacy))
    XCTAssertNil(old.telemetry)
  }

  // MARK: - Image statistics

  private func stats(width: Int = 64, height: Int = 48, _ pixel: (Int, Int) -> UInt8) -> CaptureImageStats {
    var buffer = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height { for x in 0..<width { buffer[y * width + x] = pixel(x, y) } }
    return buffer.withUnsafeBufferPointer {
      CaptureImageStats.measure(luma: $0.baseAddress!, width: width, height: height, bytesPerRow: width)!
    }
  }

  func testAFlatImageIsBlurryAndAFineTextureIsNot() {
    let flat = stats { _, _ in 128 }
    XCTAssertEqual(flat.sharpness, 0, accuracy: 1e-9)
    XCTAssertTrue(flat.isBlurry)
    XCTAssertEqual(flat.meanLuma, 128.0 / 255, accuracy: 1e-6)

    let checker = stats { x, y in (x + y).isMultiple(of: 2) ? 200 : 60 }
    XCTAssertFalse(checker.isBlurry)
    XCTAssertGreaterThan(checker.sharpness, 0.3)
  }

  func testExposureExtremesAreRecognised() {
    let white = stats { _, _ in 255 }
    XCTAssertTrue(white.isOverexposed)
    XCTAssertEqual(white.clippedFraction, 1)

    let black = stats { _, _ in 0 }
    XCTAssertTrue(black.isTooDark)
    XCTAssertEqual(black.crushedFraction, 1)
  }

  func testRowPaddingIsRespected() {
    // 16 bytes of padding per row hold 255; only the image pixels are 100.
    let width = 32, height = 24, bytesPerRow = 48
    var buffer = [UInt8](repeating: 255, count: bytesPerRow * height)
    for y in 0..<height { for x in 0..<width { buffer[y * bytesPerRow + x] = 100 } }
    let result = buffer.withUnsafeBufferPointer {
      CaptureImageStats.measure(luma: $0.baseAddress!, width: width, height: height, bytesPerRow: bytesPerRow)!
    }
    XCTAssertEqual(result.meanLuma, 100.0 / 255, accuracy: 1e-6)
    XCTAssertEqual(result.clippedFraction, 0)
  }

  // MARK: - Verdict

  func testTheVerdictHasThreeLevelsEachWithOneSentence() {
    var broken = usable()
    broken.facePresent = false
    broken.issues = [.noFace]
    let invalid = CaptureAssessment.assess(broken, image: nil)
    XCTAssertEqual(invalid.verdict, .invalid)
    XCTAssertEqual(invalid.guidance, CaptureQualityIssue.noFace.guidance)

    let sharp = CaptureImageStats(meanLuma: 0.5, clippedFraction: 0, crushedFraction: 0, sharpness: 0.05)
    XCTAssertEqual(CaptureAssessment.assess(usable(), image: sharp).verdict, .valid)
    XCTAssertNil(CaptureAssessment.assess(usable(), image: sharp).guidance)

    var soft = sharp
    soft.sharpness = 0.002
    let degraded = CaptureAssessment.assess(usable(), image: soft)
    XCTAssertEqual(degraded.verdict, .degraded)
    XCTAssertNotNil(degraded.guidance)

    XCTAssertEqual(CaptureAssessment.assess(usable(frameRate: 24), image: sharp).verdict, .degraded)
    XCTAssertEqual(CaptureAssessment.assess(usable(dropout: 0.2), image: sharp).verdict, .degraded)
  }

  /// Degraded never decides whether a capture counts; only `isUsable` does.
  func testADegradedCaptureIsStillUsable() {
    let dark = CaptureImageStats(meanLuma: 0.1, clippedFraction: 0, crushedFraction: 0.4, sharpness: 0.05)
    let quality = usable()
    XCTAssertEqual(CaptureAssessment.assess(quality, image: dark).verdict, .degraded)
    XCTAssertTrue(quality.isUsable)
  }

  // MARK: - Telemetry

  func testTelemetryCountsDetectionLossesRecoveryAndDelay() {
    var recorder = CaptureTelemetryRecorder()
    var t = 100.0
    func face(_ tracked: Bool, faces: Int = 1) {
      recorder.recordFrame()
      recorder.recordFace(tracked: tracked, faceCount: faces, timestamp: t, now: t + 0.02)
      t += 1.0 / 60
    }
    for _ in 0..<60 { face(true) }
    for _ in 0..<12 { face(false) }  // lost for 0.2 s
    for _ in 0..<28 { face(true, faces: 2) }

    let summary = recorder.summary(verdict: .degraded)
    XCTAssertEqual(summary.framesObserved, 100)
    XCTAssertEqual(summary.framesWithFace, 88)
    XCTAssertEqual(summary.detectionRate, 0.88, accuracy: 1e-9)
    XCTAssertEqual(summary.trackingLosses, 1)
    XCTAssertEqual(summary.medianRecoveryMilliseconds ?? 0, 200, accuracy: 0.5)
    XCTAssertEqual(summary.medianLatencyMilliseconds ?? 0, 20, accuracy: 0.01)
    XCTAssertEqual(summary.multipleFaceFraction, 28.0 / 88, accuracy: 1e-9)
    XCTAssertEqual(summary.verdict, .degraded)
  }

  func testTheBenchmarkReportIsEmptyUntilACaptureExists() {
    XCTAssertNil(CaptureBenchmarkReport([]))

    var a = CaptureTelemetryRecorder()
    a.recordFrame()
    a.recordFace(tracked: true, faceCount: 1, timestamp: 1, now: 1.01)
    var b = CaptureTelemetryRecorder()
    b.recordFrame()
    b.recordFace(tracked: true, faceCount: 2, timestamp: 1, now: 1.03)
    b.recordFrame()
    b.recordFace(tracked: false, faceCount: 0, timestamp: 2, now: 2.03)

    let report = CaptureBenchmarkReport([a.summary(verdict: .valid), b.summary(verdict: .invalid)])
    XCTAssertEqual(report?.captures, 2)
    XCTAssertEqual(report?.medianDetectionRate ?? 0, 0.75, accuracy: 1e-9)
    XCTAssertEqual(report?.capturesWithTrackingLoss, 1)
    XCTAssertEqual(report?.capturesWithAnotherFace, 1)
    XCTAssertEqual(report?.verdicts[.valid], 1)
    XCTAssertEqual(report?.verdicts[.invalid], 1)
  }

  // MARK: - Directional guidance

  /// The preview is a mirror: a face drawn right of centre should move to the
  /// person's left.
  func testDirectionsFollowTheMirroredPreview() {
    XCTAssertEqual(
      DirectionalGuidance.text(screenOffset: CGPoint(x: 0.2, y: 0), horizontal: true, vertical: false),
      "Move left to center your face in the oval.")
    XCTAssertEqual(
      DirectionalGuidance.text(screenOffset: CGPoint(x: -0.2, y: 0.15), horizontal: true, vertical: true),
      "Move up and right to center your face in the oval.")
    XCTAssertNil(
      DirectionalGuidance.text(screenOffset: CGPoint(x: 0.01, y: 0), horizontal: true, vertical: false),
      "inside the dead zone there is no honest direction to give")
    XCTAssertEqual(
      DirectionalGuidance.text(screenOffset: CGPoint(x: 0.2, y: 0.2), horizontal: false, vertical: true),
      "Move up to center your face in the oval.",
      "only the axes the guide judged off-centre get a word")
  }

  /// Right of centre in the raw camera image is left of centre on the mirror.
  func testProjectedPointsAreMirroredForDisplay() {
    let offset = DirectionalGuidance.mirroredOffset(fromProjected: CGPoint(x: 0.8, y: 0.6))
    XCTAssertEqual(offset.x, -0.3, accuracy: 1e-9)
    XCTAssertEqual(offset.y, 0.1, accuracy: 1e-9)
  }

  /// Pinned off until a Face ID iPhone confirms the words point the right
  /// way. Turning it on means updating this test with what the device showed.
  func testDirectionalWordsStayOffUntilCheckedOnADevice() {
    XCTAssertFalse(DirectionalGuidance.isEnabled)
  }
}
