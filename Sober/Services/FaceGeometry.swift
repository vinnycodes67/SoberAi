import simd

/// Where the face is relative to the front camera, which is what "centered",
/// "too close" and "hold still" mean to the person holding the phone.
///
/// `ARFaceAnchor.transform` is in ARKit world space, which a face-tracking
/// session aligns with gravity. Reading its translation directly is only
/// right while the phone is held perfectly upright: tilted back 35 degrees,
/// the normal way to hold a phone at arm's length, a face dead centre in the
/// camera 40 cm away reads about 23 cm "high", past the 18 cm limit, so every
/// capture failed as off center on a real iPhone. The simulator has no
/// TrueDepth camera, so tests never saw it.
enum FaceGeometry {
  /// The face centre in the camera's frame, in portrait screen axes and
  /// metres: x across the screen, y along it, z along the camera axis
  /// (negative in front of the camera). ARKit's camera axes follow the
  /// sensor's native landscape orientation, so in portrait the camera's y is
  /// the screen's horizontal and its x the screen's vertical. Signs are not
  /// normalised; callers use magnitudes, and direction comes from the
  /// projected screen offset (`DirectionalGuidance`).
  static func portraitPosition(face: simd_float4x4, camera: simd_float4x4) -> SIMD3<Float> {
    let local = simd_mul(simd_inverse(camera), face).columns.3
    return SIMD3(local.y, local.x, local.z)
  }
}
