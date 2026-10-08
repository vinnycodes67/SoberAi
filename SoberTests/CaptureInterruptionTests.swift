import ARKit
import XCTest

@testable import Sober

/// ARKit losing the camera while the app stays in the foreground.
///
/// Backgrounding is handled by `ScreeningFlowView` through `scenePhase`. These
/// cover the case that previously had no handler at all: the session itself
/// reporting an interruption or a failure mid-capture. The simulator has no
/// TrueDepth camera, so these drive the handlers directly; whether ARKit fires
/// them in a given real-world situation still needs a device.
@MainActor
final class CaptureInterruptionTests: XCTestCase {

  func testAnInterruptedCaptureIsNotScored() {
    let service = FaceTrackingService()
    service.startOcularProtocol()

    service.handleSessionInterrupted()
    let summary = service.stopOcularProtocol()

    XCTAssertTrue(summary.quality.issues.contains(.interrupted))
    XCTAssertFalse(summary.quality.isUsable)
  }

  /// The camera coming back does not make the gap disappear. The frames after
  /// it are not one continuous recording with the frames before.
  func testRecoveringFromAnInterruptionStillLeavesTheCaptureUnscored() {
    let service = FaceTrackingService()
    service.startOcularProtocol()

    service.handleSessionInterrupted()
    service.handleSessionInterruptionEnded()
    let summary = service.stopOcularProtocol()

    XCTAssertTrue(summary.quality.issues.contains(.interrupted))
    XCTAssertFalse(summary.quality.isUsable)
  }

  func testAnUninterruptedCaptureIsNotFlaggedAsInterrupted() {
    let service = FaceTrackingService()
    service.startOcularProtocol()

    let summary = service.stopOcularProtocol()

    XCTAssertFalse(summary.quality.issues.contains(.interrupted))
  }

  /// Each capture starts clean. An interruption in one attempt must not
  /// condemn the next.
  func testTheInterruptionFlagDoesNotLeakIntoTheNextCapture() {
    let service = FaceTrackingService()
    service.startOcularProtocol()
    service.handleSessionInterrupted()
    _ = service.stopOcularProtocol()

    service.startOcularProtocol()
    let second = service.stopOcularProtocol()

    XCTAssertFalse(second.quality.issues.contains(.interrupted))
  }

  /// An interruption reported when no capture is running is noise, not a
  /// failed capture.
  func testAnInterruptionOutsideACaptureIsIgnored() {
    let service = FaceTrackingService()

    service.handleSessionInterrupted()
    service.startOcularProtocol()
    let summary = service.stopOcularProtocol()

    XCTAssertFalse(summary.quality.issues.contains(.interrupted))
  }

  func testACameraFailureEndsTheCaptureAndSaysSo() {
    let service = FaceTrackingService()
    service.startOcularProtocol()

    service.handleSessionFailure(ARError(.sensorFailed))

    XCTAssertTrue(service.quality.issues.contains(.interrupted))
    if case .limited = service.status {} else {
      XCTFail("a failed camera must show a limited status, got \(service.status)")
    }
    XCTAssertFalse(service.stopOcularProtocol().quality.isUsable)
  }

  /// Permission revoked mid-session goes down the existing denied path, which
  /// already offers the route to Settings.
  func testRevokedPermissionIsReportedAsPermissionDenied() {
    let service = FaceTrackingService()
    service.startOcularProtocol()

    service.handleSessionFailure(ARError(.cameraUnauthorized))

    XCTAssertEqual(service.status, .permissionDenied)
    XCTAssertTrue(service.quality.issues.contains(.permissionDenied))
  }

  // MARK: - The analyzer keeps the reason

  /// With 20+ samples the analyzer recomputes live estimates. It used to strip
  /// `.interrupted` along with them, so a capture rejected for an interruption
  /// came back unusable with no issue saying why.
  func testTheAnalyzerKeepsAnInterruptionReportedBeforeSummarising() {
    let samples = (0..<40).map { index in
      OcularSample(
        timestamp: Double(index) / 30,
        phase: .fixation,
        targetX: 0.5, targetY: 0.5,
        leftGazeX: 0, leftGazeY: 0, rightGazeX: 0, rightGazeY: 0,
        headX: 0, headY: 0, headZ: -1,
        blinkLeft: 0, blinkRight: 0)
    }
    let live = CaptureQualitySnapshot(
      isSupported: true, hasCameraPermission: true,
      facePresent: false, centered: true, distanceAcceptable: true,
      lightingAcceptable: true, headStable: true,
      frameRate: 30, sampleCount: 40, dropoutRatio: 0,
      issues: [.interrupted])

    let summary = OcularSignalAnalyzer().summarize(
      samples: samples, observedFrameCount: 40, liveQuality: live)

    XCTAssertTrue(summary.quality.issues.contains(.interrupted))
    XCTAssertFalse(summary.quality.isUsable)
  }
}
