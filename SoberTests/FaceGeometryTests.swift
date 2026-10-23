import simd
import XCTest

@testable import Sober

final class FaceGeometryTests: XCTestCase {
  /// A portrait phone tilted back by `degrees`, in ARKit's gravity-aligned
  /// world. The camera's own axes follow the sensor's landscape orientation:
  /// its x runs along the phone's long side, its y across, its -z out of the
  /// front camera towards the face.
  private func tiltedCamera(degrees: Float) -> simd_float4x4 {
    let portrait = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1)))
    let tilt = simd_float4x4(simd_quatf(angle: degrees * .pi / 180, axis: SIMD3(1, 0, 0)))
    return simd_mul(tilt, portrait)
  }

  private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    var m = matrix_identity_float4x4
    m.columns.3 = SIMD4(x, y, z, 1)
    return m
  }

  func testFaceStraightAheadOfATiltedPhoneIsCentered() {
    let camera = tiltedCamera(degrees: 35)
    let face = simd_mul(camera, translation(0, 0, -0.40))

    let position = FaceGeometry.portraitPosition(face: face, camera: camera)

    XCTAssertEqual(position.x, 0, accuracy: 0.001)
    XCTAssertEqual(position.y, 0, accuracy: 0.001)
    XCTAssertEqual(abs(position.z), 0.40, accuracy: 0.001)
    // The bug: the world-space reading of the same face is far outside the
    // 0.18 m vertical band, so the capture was rejected as off center.
    XCTAssertGreaterThan(abs(face.columns.3.y), 0.18)
  }

  func testPortraitAxesSwapTheCameraAxes() {
    let camera = tiltedCamera(degrees: 20)
    // 5 cm along the camera's x (the phone's long side) and 10 cm along its
    // y (across the phone).
    let face = simd_mul(camera, translation(0.05, 0.10, -0.45))

    let position = FaceGeometry.portraitPosition(face: face, camera: camera)

    XCTAssertEqual(abs(position.x), 0.10, accuracy: 0.001, "across the screen")
    XCTAssertEqual(abs(position.y), 0.05, accuracy: 0.001, "along the screen")
    XCTAssertEqual(abs(position.z), 0.45, accuracy: 0.001)
  }

  func testCenteredFaceStaysCenteredForAnyTiltThroughTheGuide() {
    for degrees in stride(from: Float(0), through: 60, by: 10) {
      let camera = tiltedCamera(degrees: degrees)
      let face = simd_mul(camera, translation(0.01, -0.02, -0.40))
      let p = FaceGeometry.portraitPosition(face: face, camera: camera)
      var guide = HeadPositionGuide()
      var state = HeadPosition.faceNotDetected
      for _ in 0..<10 { state = guide.update(x: Double(p.x), y: Double(p.y), z: Double(p.z)) }
      XCTAssertEqual(state, .centered, "tilt \(degrees) degrees")
    }
  }
}
