import Foundation
import simd

#if canImport(UIKit)
import UIKit
#endif

/// The phone's display in its portrait frame: its size, how many points make a
/// millimetre, and where the front camera sits on it. Read once, on the main
/// actor, when a capture starts.
struct DisplayGeometry: Equatable, Sendable {
  /// Portrait size in points.
  var widthPoints: Double
  var heightPoints: Double
  var pointsPerMillimetre: Double
  /// Front camera centre in portrait screen points: origin at the display's
  /// top-left corner, x to the right, y down.
  var cameraX: Double
  var cameraY: Double
  /// False when `pixelsPerInchByNativeHeight` had no entry for this display
  /// and `fallbackPixelsPerInch` was used, so millimetres are estimates.
  var isKnownModel: Bool

  /// Published pixel density of each Face ID iPhone display, keyed by its
  /// portrait height in pixels (`UIScreen.nativeBounds`), which is unique
  /// across the range.
  static let pixelsPerInchByNativeHeight: [Int: Double] = [
    1792: 326,  // XR, 11
    2340: 476,  // 12 mini, 13 mini
    2436: 458,  // X, XS, 11 Pro
    2688: 458,  // XS Max, 11 Pro Max
    2778: 458,  // 12 Pro Max, 13 Pro Max, 14 Plus
    2532: 460,  // 12, 12 Pro, 13, 13 Pro, 14, 16e
    2556: 460,  // 14 Pro, 15, 15 Pro, 16
    2796: 460,  // 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
    2622: 460,  // 16 Pro, 17, 17 Pro
    2736: 460,  // Air
    2868: 460,  // 16 Pro Max, 17 Pro Max
  ]
  /// For a display not in the table. Almost every Face ID iPhone is 458-460.
  static let fallbackPixelsPerInch = 460.0

  /// ENGINEERING GUESS: the front camera is taken to sit at the top centre of
  /// the display (x right, y down, millimetres from there). On real phones it
  /// is up to about 7 mm right of centre and a few millimetres from the top
  /// edge. That moves every gaze point by the same amount, which
  /// follow-the-dot calibration absorbs; until then it is a fixed offset.
  static let cameraOffsetFromTopCentreMillimetres = SIMD2<Double>(0, 0)
}

extension DisplayGeometry {
  /// From `UIScreen.nativeBounds.size` (pixels, portrait-up) and
  /// `UIScreen.nativeScale` (pixels per point). Nil for an unusable reading.
  init?(nativePixelWidth: Double, nativePixelHeight: Double, nativeScale: Double) {
    guard [nativePixelWidth, nativePixelHeight, nativeScale].allSatisfy({ $0.isFinite && $0 > 0 })
    else { return nil }
    let width = min(nativePixelWidth, nativePixelHeight)
    let height = max(nativePixelWidth, nativePixelHeight)
    let known = Self.pixelsPerInchByNativeHeight[Int(height.rounded())]
    let pointsPerMillimetre = (known ?? Self.fallbackPixelsPerInch) / nativeScale / 25.4
    let widthPoints = width / nativeScale
    let offset = Self.cameraOffsetFromTopCentreMillimetres
    self.init(
      widthPoints: widthPoints,
      heightPoints: height / nativeScale,
      pointsPerMillimetre: pointsPerMillimetre,
      cameraX: widthPoints / 2 + offset.x * pointsPerMillimetre,
      cameraY: offset.y * pointsPerMillimetre,
      isKnownModel: known != nil)
  }

  #if canImport(UIKit)
  /// The display of the app's foreground scene. Main actor only: never read
  /// from ARKit's delegate queue.
  @MainActor static func current() -> DisplayGeometry? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let screen = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
    else { return nil }
    return DisplayGeometry(
      nativePixelWidth: screen.nativeBounds.width, nativePixelHeight: screen.nativeBounds.height,
      nativeScale: screen.nativeScale)
  }
  #endif
}

/// Whether a gaze ray met the screen.
enum ScreenGazeValidity: String, Equatable, Sendable {
  /// On the display, or within `ScreenGazeGeometry.offScreenMarginMillimetres`.
  case onScreen
  /// Met the screen plane off the display. The point is kept: before
  /// calibration a small miss can still be the person looking at the edge.
  case offScreen
  /// No usable intersection: a non-finite or singular transform, a ray
  /// parallel to the screen or pointing away from it, or an eye on its plane.
  case noIntersection
}

/// Where one gaze ray met the screen plane, in portrait screen points.
struct ScreenGazePoint: Equatable, Sendable {
  var x: Double?
  var y: Double?
  var validity: ScreenGazeValidity
  /// The eye's distance from the screen plane, metres.
  var distanceMetres: Double?

  static let unavailable = ScreenGazePoint(x: nil, y: nil, validity: .noIntersection, distanceMetres: nil)
}

struct ScreenGaze: Equatable, Sendable {
  var left: ScreenGazePoint
  var right: ScreenGazePoint
  /// The two eyes' points averaged, which splits their vergence difference.
  /// Needs both: one eye alone would jump by half that difference.
  var combined: ScreenGazePoint

  static let unavailable = ScreenGaze(left: .unavailable, right: .unavailable, combined: .unavailable)
}

/// Gaze as a point on the screen, independent of where the head points.
///
/// `ARFaceAnchor.leftEyeTransform` and `rightEyeTransform` are relative to the
/// face, so their direction alone changes when the head turns even if the eyes
/// stay on the dot. Each eye's ray is taken into the camera's frame (camera⁻¹ ×
/// face × eye) and met with the screen plane, which is the camera's z = 0
/// plane: the front camera sits in the face of the phone. A head that turns
/// while the eyes counter-rotate keeps the same point on the screen.
///
/// Same face data as before (the eye transforms and face transform), plus the
/// camera pose ARKit already supplies with the frame.
enum ScreenGazeGeometry {
  /// Screen "down" (toward the bottom of the phone in portrait) as a direction
  /// in ARKit camera space. ARCamera's documentation puts the camera's x axis
  /// "along the long axis of the device, from the front-facing camera toward
  /// the Home button". **Not yet confirmed on a Face ID iPhone (HANDOFF
  /// 1.11):** if gaze reads higher at the bottom edge than at the top, flip
  /// this to (-1, 0, 0) and record what was seen.
  ///
  /// Screen "right" is not assumed. It follows from this and the side of the
  /// screen the eyes are on, so it is right whichever way ARKit's camera z
  /// axis faces.
  static let screenDownInCamera = SIMD3<Double>(1, 0, 0)

  /// ENGINEERING GUESS: a point this far outside the display still counts as
  /// on screen. Uncalibrated ARKit gaze and the camera-position guess are both
  /// off by millimetres; 15 mm is about 2 degrees at 40 cm.
  static let offScreenMarginMillimetres = 15.0

  /// Numerical guard, not a tuned threshold: an eye this close to the screen
  /// plane cannot be told apart from one on it.
  private static let minimumEyeDistanceMetres = 0.01

  /// `face` is `ARFaceAnchor.transform` and `camera` is `ARCamera.transform`,
  /// both in world space; the eye transforms are relative to the face.
  static func gaze(
    face: simd_float4x4,
    leftEye: simd_float4x4,
    rightEye: simd_float4x4,
    camera: simd_float4x4,
    display: DisplayGeometry
  ) -> ScreenGaze {
    let cameraMatrix = double(camera)
    guard isFinite(cameraMatrix) else { return .unavailable }
    let determinant = simd_determinant(cameraMatrix)
    guard determinant.isFinite, abs(determinant) > 1e-9 else { return .unavailable }
    let cameraFromFace = simd_mul(simd_inverse(cameraMatrix), double(face))
    guard isFinite(cameraFromFace) else { return .unavailable }

    let left = point(eyeInCamera: simd_mul(cameraFromFace, double(leftEye)), display: display)
    let right = point(eyeInCamera: simd_mul(cameraFromFace, double(rightEye)), display: display)
    guard let lx = left.x, let ly = left.y, let rx = right.x, let ry = right.y,
      let ld = left.distanceMetres, let rd = right.distanceMetres
    else { return ScreenGaze(left: left, right: right, combined: .unavailable) }
    let x = (lx + rx) / 2
    let y = (ly + ry) / 2
    let combined = ScreenGazePoint(
      x: x, y: y, validity: classify(x: x, y: y, display: display), distanceMetres: (ld + rd) / 2)
    return ScreenGaze(left: left, right: right, combined: combined)
  }

  /// One eye, its transform already in camera space: origin in column 3,
  /// gaze direction (+z of the eye) in column 2.
  static func point(eyeInCamera eye: simd_double4x4, display: DisplayGeometry) -> ScreenGazePoint {
    let origin = SIMD3(eye.columns.3.x, eye.columns.3.y, eye.columns.3.z)
    let axis = SIMD3(eye.columns.2.x, eye.columns.2.y, eye.columns.2.z)
    let length = simd_length(axis)
    guard isFinite(origin), isFinite(axis), length.isFinite, length > 1e-9,
      abs(origin.z) >= minimumEyeDistanceMetres
    else { return .unavailable }
    let direction = axis / length
    // Within about 0.006 degrees of parallel: the ray would meet the plane
    // kilometres away, and float rounding decides on which side.
    guard abs(direction.z) > 1e-4 else { return .unavailable }
    let along = -origin.z / direction.z
    guard along.isFinite, along > 0 else { return .unavailable }
    let hit = origin + along * direction

    // The eye is in front of the screen, so the side it is on is the side the
    // screen faces. For someone looking at a screen, right = toward-them x down.
    let towardViewer = SIMD3<Double>(0, 0, origin.z > 0 ? 1 : -1)
    let down = screenDownInCamera
    let right = simd_cross(towardViewer, down)
    let pointsPerMetre = 1_000 * display.pointsPerMillimetre
    let x = display.cameraX + simd_dot(hit, right) * pointsPerMetre
    let y = display.cameraY + simd_dot(hit, down) * pointsPerMetre
    guard x.isFinite, y.isFinite else { return .unavailable }
    return ScreenGazePoint(
      x: x, y: y, validity: classify(x: x, y: y, display: display), distanceMetres: abs(origin.z))
  }

  static func classify(x: Double, y: Double, display: DisplayGeometry) -> ScreenGazeValidity {
    let margin = offScreenMarginMillimetres * display.pointsPerMillimetre
    let onScreen = (-margin...(display.widthPoints + margin)).contains(x)
      && (-margin...(display.heightPoints + margin)).contains(y)
    return onScreen ? .onScreen : .offScreen
  }

  // MARK: - Arithmetic

  static func double(_ m: simd_float4x4) -> simd_double4x4 {
    simd_double4x4(columns: (
      SIMD4<Double>(m.columns.0), SIMD4<Double>(m.columns.1),
      SIMD4<Double>(m.columns.2), SIMD4<Double>(m.columns.3)))
  }

  private static func isFinite(_ v: SIMD3<Double>) -> Bool {
    v.x.isFinite && v.y.isFinite && v.z.isFinite
  }

  private static func isFinite(_ m: simd_double4x4) -> Bool {
    [m.columns.0, m.columns.1, m.columns.2, m.columns.3].allSatisfy {
      $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite
    }
  }
}
