import simd
import XCTest

@testable import Sober

/// Screen gaze from synthetic heads, eyes and phones with known ground truth.
///
/// The phone and the person live in ARKit's gravity-aligned world: y up, the
/// person at -z looking toward +z at the phone. The camera's x axis runs down
/// the screen, as `ScreenGazeGeometry.screenDownInCamera` assumes. Which way
/// its z axis faces is not documented for the front camera, so every geometry
/// test runs both ways.
final class ScreenGazeGeometryTests: XCTestCase {
  /// iPhone 15 Pro: 1179 x 2556 pixels at 460 ppi, 3x.
  private let display = DisplayGeometry(nativePixelWidth: 1179, nativePixelHeight: 2556, nativeScale: 3)!
  /// Eye centres relative to the face anchor: the face's own left is +x, and
  /// the eyes sit slightly in front of the anchor, toward the phone.
  private let leftEyeOffset = SIMD3<Float>(0.032, 0.03, 0.025)
  private let rightEyeOffset = SIMD3<Float>(-0.032, 0.03, 0.025)

  // MARK: - Head-free gaze

  func testATurningHeadWithEyesOnTheDotKeepsScreenGazeOnTheDot() throws {
    let dot = (x: 120.0, y: 520.0)
    for cameraZ in CameraZ.allCases {
      for tilt: Float in [0, 30, 55] {
        let phone = Phone(tiltDegrees: tilt, cameraZ: cameraZ)
        let world = phone.world(dot.x, dot.y, on: display)
        var eyeInHeadX: [Float] = []
        for yaw in stride(from: Float(-15), through: 15, by: 5) {
          for pitch: Float in [-10, 0, 10] {
            for shift in [SIMD3<Float>(0, 0, 0), SIMD3<Float>(0.04, -0.03, 0.05)] {
              let face = head(phone: phone, yaw: yaw, pitch: pitch, shift: shift)
              let left = eye(at: leftEyeOffset, lookingAt: world, face: face)
              let right = eye(at: rightEyeOffset, lookingAt: world, face: face)
              let gaze = ScreenGazeGeometry.gaze(
                face: face, leftEye: left, rightEye: right, camera: phone.camera, display: display)
              let context = "\(cameraZ) tilt \(tilt) yaw \(yaw) pitch \(pitch) shift \(shift)"
              for point in [gaze.left, gaze.right, gaze.combined] {
                XCTAssertEqual(point.validity, .onScreen, context)
                XCTAssertEqual(try XCTUnwrap(point.x), dot.x, accuracy: 0.5, context)
                XCTAssertEqual(try XCTUnwrap(point.y), dot.y, accuracy: 0.5, context)
              }
              eyeInHeadX.append(left.columns.2.x)
            }
          }
        }
        // What the scored path reads for the same steady gaze: it swings
        // about 30 degrees with the head.
        let swing = try XCTUnwrap(eyeInHeadX.max()) - XCTUnwrap(eyeInHeadX.min())
        XCTAssertGreaterThan(swing, 0.4, "\(cameraZ) tilt \(tilt)")
      }
    }
  }

  func testEyesMovingUnderAStillHeadFollowTheOldEyeInHeadReading() throws {
    for cameraZ in CameraZ.allCases {
      let phone = Phone(tiltDegrees: 20, cameraZ: cameraZ)
      let face = head(phone: phone, yaw: 0, pitch: 0)
      var oldX: [Double] = [], newX: [Double] = [], oldY: [Double] = [], newY: [Double] = []
      for h in stride(from: -8.0, through: 8.0, by: 2) {
        for v in stride(from: -8.0, through: 8.0, by: 2) {
          let (hr, vr) = (h * .pi / 180, v * .pi / 180)
          let forward = SIMD3<Float>(Float(sin(hr) * cos(vr)), Float(sin(vr)), Float(cos(hr) * cos(vr)))
          let gaze = ScreenGazeGeometry.gaze(
            face: face, leftEye: eye(at: leftEyeOffset, forward: forward),
            rightEye: eye(at: rightEyeOffset, forward: forward), camera: phone.camera, display: display)
          oldX.append(Double(forward.x))
          oldY.append(Double(forward.y))
          newX.append(try XCTUnwrap(gaze.combined.x))
          newY.append(try XCTUnwrap(gaze.combined.y))
        }
      }
      // A straight line in the old reading, as the old analysis assumed, at
      // the eyes' distance from the screen (40 cm less 2.5 cm) per radian.
      // Looking toward the face's own left (+x) or up (+y) moves gaze toward
      // the person's left and up the screen, so both slopes are negative.
      let pointsPerRadian = 0.375 * 1_000 * display.pointsPerMillimetre
      for (old, new, axis) in [(oldX, newX, "x"), (oldY, newY, "y")] {
        XCTAssertGreaterThan(abs(try XCTUnwrap(OcularDetailedAnalyzer.pearson(old, new))), 0.999, "\(cameraZ) \(axis)")
        XCTAssertEqual(slope(old, new) / -pointsPerRadian, 1, accuracy: 0.03, "\(cameraZ) \(axis)")
      }
    }
  }

  // MARK: - Validity and edge cases

  func testTheOffScreenMarginIsFifteenMillimetres() {
    let mm = display.pointsPerMillimetre
    for cameraZ in CameraZ.allCases {
      let phone = Phone(tiltDegrees: 25, cameraZ: cameraZ)
      let face = head(phone: phone, yaw: 0, pitch: 0)
      func landing(_ x: Double, _ y: Double) -> ScreenGazePoint {
        let world = phone.world(x, y, on: display)
        return ScreenGazeGeometry.gaze(
          face: face, leftEye: eye(at: leftEyeOffset, lookingAt: world, face: face),
          rightEye: eye(at: rightEyeOffset, lookingAt: world, face: face), camera: phone.camera,
          display: display
        ).combined
      }
      XCTAssertEqual(landing(display.widthPoints / 2, -10 * mm).validity, .onScreen, "\(cameraZ)")
      XCTAssertEqual(landing(-10 * mm, 400).validity, .onScreen, "\(cameraZ)")
      XCTAssertEqual(landing(display.widthPoints + 10 * mm, display.heightPoints).validity, .onScreen)

      // Above the phone: a miss, but its point is kept.
      for (y, label) in [(-20 * mm, "just above"), (-100 * mm, "far above")] {
        let point = landing(display.widthPoints / 2, y)
        XCTAssertEqual(point.validity, .offScreen, "\(cameraZ) \(label)")
        XCTAssertEqual(point.y ?? .nan, y, accuracy: 0.5, "\(cameraZ) \(label)")
      }
      XCTAssertEqual(landing(display.widthPoints + 20 * mm, 400).validity, .offScreen)
      XCTAssertEqual(landing(200, display.heightPoints + 20 * mm).validity, .offScreen)
    }
  }

  func testRaysThatCannotMeetTheScreenHaveNoPoint() {
    for cameraZ in CameraZ.allCases {
      let phone = Phone(tiltDegrees: 30, cameraZ: cameraZ)
      let face = head(phone: phone, yaw: 5, pitch: -5)
      let faceRotation = simd_float3x3(
        SIMD3(face.columns.0.x, face.columns.0.y, face.columns.0.z),
        SIMD3(face.columns.1.x, face.columns.1.y, face.columns.1.z),
        SIMD3(face.columns.2.x, face.columns.2.y, face.columns.2.z))
      func inFace(_ worldDirection: SIMD3<Float>) -> SIMD3<Float> { faceRotation.transpose * worldDirection }
      let good = eye(at: rightEyeOffset, lookingAt: phone.world(200, 400, on: display), face: face)

      let cases: [(String, simd_float4x4)] = [
        ("parallel to the screen", eye(at: leftEyeOffset, forward: inFace(phone.down))),
        ("pointing away from the screen", eye(at: leftEyeOffset, forward: inFace(phone.towardViewer))),
        ("NaN direction", eye(at: leftEyeOffset, forward: SIMD3(.nan, 0, 1))),
        ("NaN position", eye(at: SIMD3(.nan, 0, 0), forward: SIMD3(0, 0, 1))),
        ("infinite position", eye(at: SIMD3(0, .infinity, 0), forward: SIMD3(0, 0, 1))),
        ("zero direction", eye(at: leftEyeOffset, forward: .zero)),
      ]
      for (label, broken) in cases {
        let gaze = ScreenGazeGeometry.gaze(
          face: face, leftEye: broken, rightEye: good, camera: phone.camera, display: display)
        XCTAssertEqual(gaze.left, ScreenGazePoint.unavailable, "\(cameraZ) \(label)")
        // One eye is not a combined point: it would jump by half the vergence.
        XCTAssertEqual(gaze.combined, ScreenGazePoint.unavailable, "\(cameraZ) \(label)")
        XCTAssertEqual(gaze.right.validity, .onScreen, "\(cameraZ) \(label): the other eye is kept")
        XCTAssertEqual(gaze.right.x ?? .nan, 200, accuracy: 0.5)
      }
    }
  }

  func testAnUnusableCameraOrFacePoseGivesNoGaze() {
    let phone = Phone(tiltDegrees: 10, cameraZ: .towardFace)
    let face = head(phone: phone, yaw: 0, pitch: 0)
    let world = phone.world(150, 300, on: display)
    let left = eye(at: leftEyeOffset, lookingAt: world, face: face)
    let right = eye(at: rightEyeOffset, lookingAt: world, face: face)
    var nanCamera = phone.camera
    nanCamera.columns.3.x = .nan
    var nanFace = face
    nanFace.columns.1.y = .infinity
    let cases: [(String, simd_float4x4, simd_float4x4)] = [
      ("NaN camera", nanCamera, face),
      ("singular camera", simd_float4x4(), face),
      ("non-finite face", phone.camera, nanFace),
    ]
    for (label, camera, face) in cases {
      XCTAssertEqual(
        ScreenGazeGeometry.gaze(face: face, leftEye: left, rightEye: right, camera: camera, display: display),
        ScreenGaze.unavailable, label)
    }
  }

  func testAnEyeOnTheScreenPlaneHasNoPoint() {
    var eye = matrix_identity_double4x4
    eye.columns.3 = SIMD4(0.01, 0.02, 0.0005, 1)
    XCTAssertEqual(ScreenGazeGeometry.point(eyeInCamera: eye, display: display), ScreenGazePoint.unavailable)
    eye.columns.3.z = -0.3
    eye.columns.2 = SIMD4(0.05, 0.02, 1, 0)
    XCTAssertEqual(ScreenGazeGeometry.point(eyeInCamera: eye, display: display).validity, .onScreen)
  }

  func testRandomPosesNeverProduceANonFinitePoint() {
    var random = GazeRandom(seed: 0x6A2E_5C12)
    for run in 0..<3_000 {
      let phone = Phone(
        tiltDegrees: random.float(-90, 90), cameraZ: random.float(0, 1) < 0.5 ? .towardFace : .awayFromFace,
        origin: SIMD3(random.float(-1, 1), random.float(-1, 1), random.float(-1, 1)))
      var face = head(
        phone: phone, yaw: random.float(-80, 80), pitch: random.float(-80, 80),
        shift: SIMD3(random.float(-0.5, 0.5), random.float(-0.5, 0.5), random.float(-0.5, 0.5)))
      let leftForward = SIMD3<Float>(random.float(-1, 1), random.float(-1, 1), random.float(-1, 1))
      let rightForward = SIMD3<Float>(random.float(-1, 1), random.float(-1, 1), random.float(-1, 1))
      var left = eye(at: leftEyeOffset, forward: leftForward)
      let right = eye(at: rightEyeOffset, forward: rightForward)
      if random.float(0, 1) < 0.05 { left.columns.2.y = [Float.nan, .infinity, -.infinity][run % 3] }
      if random.float(0, 1) < 0.02 { face.columns.3.z = .nan }
      let gaze = ScreenGazeGeometry.gaze(
        face: face, leftEye: left, rightEye: right, camera: phone.camera, display: display)
      for point in [gaze.left, gaze.right, gaze.combined] {
        XCTAssertEqual(point.x == nil, point.validity == .noIntersection, "run \(run)")
        XCTAssertEqual(point.x == nil, point.y == nil, "run \(run)")
        XCTAssertEqual(point.x == nil, point.distanceMetres == nil, "run \(run)")
        if let x = point.x, let y = point.y, let distance = point.distanceMetres {
          XCTAssertTrue(x.isFinite && y.isFinite && distance.isFinite, "run \(run)")
          XCTAssertGreaterThanOrEqual(distance, 0.01, "run \(run)")
        }
      }
      if gaze.combined.x != nil {
        XCTAssertNotNil(gaze.left.x, "run \(run)")
        XCTAssertNotNil(gaze.right.x, "run \(run)")
      }
    }
  }

  // MARK: - Display

  func testAKnownDisplayGivesItsPhysicalSize() throws {
    XCTAssertTrue(display.isKnownModel)
    XCTAssertEqual(display.widthPoints, 393, accuracy: 1e-9)
    XCTAssertEqual(display.heightPoints, 852, accuracy: 1e-9)
    // 1179 pixels at 460 ppi is 65.1 mm.
    XCTAssertEqual(display.widthPoints / display.pointsPerMillimetre, 65.10, accuracy: 0.01)
    XCTAssertEqual(display.cameraX, 196.5, accuracy: 1e-9)
    XCTAssertEqual(display.cameraY, 0, accuracy: 1e-9)

    // A downsampled mini keeps its own density: 1080 pixels at 476 ppi.
    let mini = try XCTUnwrap(DisplayGeometry(nativePixelWidth: 1080, nativePixelHeight: 2340, nativeScale: 2.88))
    XCTAssertTrue(mini.isKnownModel)
    XCTAssertEqual(mini.widthPoints / mini.pointsPerMillimetre, 57.63, accuracy: 0.01)

    // Width and height in either order give the portrait display.
    XCTAssertEqual(DisplayGeometry(nativePixelWidth: 2556, nativePixelHeight: 1179, nativeScale: 3), display)
  }

  func testAnUnknownDisplayFallsBackAndSaysSo() throws {
    let unknown = try XCTUnwrap(DisplayGeometry(nativePixelWidth: 1000, nativePixelHeight: 2000, nativeScale: 2))
    XCTAssertFalse(unknown.isKnownModel)
    XCTAssertEqual(unknown.pointsPerMillimetre, DisplayGeometry.fallbackPixelsPerInch / 2 / 25.4, accuracy: 1e-12)
    let unusable: [(Double, Double, Double)] = [
      (0, 2000, 2), (1000, 2000, 0), (.nan, 2000, 2), (1000, .infinity, 2), (-1000, 2000, 2),
    ]
    for reading in unusable {
      XCTAssertNil(DisplayGeometry(nativePixelWidth: reading.0, nativePixelHeight: reading.1, nativeScale: reading.2))
    }
  }

  func testTelemetryRecordsWhetherTheDensityTableKnewTheDisplay() throws {
    var recorder = CaptureTelemetryRecorder()
    XCTAssertNil(recorder.summary(verdict: .valid).displayIsKnownModel)
    recorder.displayIsKnownModel = false
    let telemetry = recorder.summary(verdict: .valid)
    XCTAssertEqual(telemetry.displayIsKnownModel, false)
    let data = try JSONEncoder().encode(telemetry)
    XCTAssertEqual(try JSONDecoder().decode(CaptureTelemetry.self, from: data), telemetry)

    // Telemetry saved before the field existed.
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    legacy.removeValue(forKey: "displayIsKnownModel")
    let old = try JSONDecoder().decode(CaptureTelemetry.self, from: JSONSerialization.data(withJSONObject: legacy))
    XCTAssertNil(old.displayIsKnownModel)
    XCTAssertEqual(old.framesObserved, telemetry.framesObserved)
  }

  // MARK: - Synthetic world

  enum CameraZ: CaseIterable {
    /// Camera +z points out of the screen toward the person.
    case towardFace
    /// Camera +z points out of the back of the phone; the face is at -z.
    case awayFromFace
  }

  /// A portrait phone tilted back by `tiltDegrees`, with the screen's real
  /// axes as the person sees them.
  private struct Phone {
    let right: SIMD3<Float>
    let down: SIMD3<Float>
    let towardViewer: SIMD3<Float>
    let origin: SIMD3<Float>
    let camera: simd_float4x4

    init(tiltDegrees: Float, cameraZ: CameraZ, origin: SIMD3<Float> = SIMD3(0.02, -0.05, 0.03)) {
      let tilt = simd_float3x3(simd_quatf(angle: tiltDegrees * .pi / 180, axis: SIMD3(1, 0, 0)))
      down = tilt * SIMD3(0, -1, 0)
      towardViewer = tilt * SIMD3(0, 0, -1)
      // The person faces +z with y up, so their right is world -x.
      right = simd_cross(towardViewer, down)
      self.origin = origin
      let z = cameraZ == .towardFace ? towardViewer : -towardViewer
      let y = simd_cross(z, down)
      camera = ScreenGazeGeometryTests.transform(simd_float3x3(down, y, z), origin)
    }

    /// The world position of a point on the display.
    func world(_ x: Double, _ y: Double, on display: DisplayGeometry) -> SIMD3<Float> {
      let rightMetres = Float((x - display.cameraX) / display.pointsPerMillimetre / 1_000)
      let downMetres = Float((y - display.cameraY) / display.pointsPerMillimetre / 1_000)
      return origin + right * rightMetres + down * downMetres
    }
  }

  /// A face 40 cm in front of the upper middle of the display, facing it,
  /// then turned by `yaw` and `pitch` and moved by `shift`.
  private func head(phone: Phone, yaw: Float, pitch: Float, shift: SIMD3<Float> = .zero) -> simd_float4x4 {
    let position = phone.world(display.widthPoints / 2, 300, on: display) + phone.towardViewer * 0.4 + shift
    // ARKit's face axes: +z out of the face toward the camera, +y up, +x the
    // face's own left.
    let z = -phone.towardViewer
    let y = -phone.down
    let base = simd_float3x3(simd_cross(y, z), y, z)
    let turn = simd_float3x3(simd_quatf(angle: yaw * .pi / 180, axis: SIMD3(0, 1, 0)))
      * simd_float3x3(simd_quatf(angle: pitch * .pi / 180, axis: SIMD3(1, 0, 0)))
    return Self.transform(base * turn, position)
  }

  /// An eye at `offset` in face space looking at `target` in world space.
  private func eye(at offset: SIMD3<Float>, lookingAt target: SIMD3<Float>, face: simd_float4x4) -> simd_float4x4 {
    let local = simd_mul(simd_inverse(face), SIMD4(target, 1))
    return eye(at: offset, forward: SIMD3(local.x, local.y, local.z) - offset)
  }

  /// An eye at `offset` in face space whose +z points along `forward`.
  private func eye(at offset: SIMD3<Float>, forward: SIMD3<Float>) -> simd_float4x4 {
    let length = simd_length(forward)
    guard length > 0, length.isFinite else {
      return Self.transform(simd_float3x3(SIMD3(1, 0, 0), SIMD3(0, 1, 0), forward), offset)
    }
    let z = forward / length
    let x = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), z))
    return Self.transform(simd_float3x3(x, simd_cross(z, x), z), offset)
  }

  private static func transform(_ r: simd_float3x3, _ t: SIMD3<Float>) -> simd_float4x4 {
    simd_float4x4(SIMD4(r.columns.0, 0), SIMD4(r.columns.1, 0), SIMD4(r.columns.2, 0), SIMD4(t, 1))
  }

  private func slope(_ x: [Double], _ y: [Double]) -> Double {
    let mx = x.reduce(0, +) / Double(x.count)
    let my = y.reduce(0, +) / Double(y.count)
    let covariance = zip(x, y).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
    let variance = x.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
    return covariance / variance
  }
}

/// Deterministic, so a failing run can be replayed.
private struct GazeRandom {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func float(_ low: Float, _ high: Float) -> Float {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return low + (high - low) * Float(state >> 40) / Float(1 << 24)
  }
}
