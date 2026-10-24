import Foundation

/// The numbers behind one frame's capture-quality checks, kept so the
/// recovery screen can say which check failed and by how much.
///
/// "Center your face in the oval" alone gave nobody a way to tell a genuinely
/// off-centre face from a wrong limit. Every limit here mirrors the gate in
/// `FaceTrackingService.ingest`; change both together.
struct CaptureMeasurement: Equatable, Sendable {
  static let horizontalLimitMetres = 0.13
  static let verticalLimitMetres = 0.18
  static let distanceRangeMetres = 0.25...0.75
  static let minimumLight = 180.0
  static let maximumMovementMetresPerFrame = 0.025
  static let minimumFrameRate = 20.0

  var facePresent: Bool
  var otherFacesInView: Bool
  /// Camera-relative, portrait axes (`FaceGeometry`).
  var horizontalMetres: Double
  var verticalMetres: Double
  var distanceMetres: Double
  var ambientLight: Double?
  var movementMetresPerFrame: Double
  var frameRate: Double
  var sampleCount: Int

  /// One short line per failing check, in the order a person can fix them.
  var failingChecks: [String] {
    if !facePresent { return ["No face detected."] }
    var lines: [String] = []
    if otherFacesInView { lines.append("Another face is in view.") }
    if !Self.distanceRangeMetres.contains(distanceMetres) {
      lines.append("Face \(cm(distanceMetres)) cm from the phone (needs 25–75 cm).")
    }
    if abs(horizontalMetres) > Self.horizontalLimitMetres {
      lines.append("Face \(cm(abs(horizontalMetres))) cm off centre side to side (limit 13 cm).")
    }
    if abs(verticalMetres) > Self.verticalLimitMetres {
      lines.append("Face \(cm(abs(verticalMetres))) cm off centre up or down (limit 18 cm).")
    }
    if (ambientLight ?? 0) < Self.minimumLight {
      let measured = ambientLight.map { String(Int($0.rounded())) } ?? "unknown"
      lines.append("Light \(measured) (needs \(Int(Self.minimumLight))).")
    }
    if movementMetresPerFrame > Self.maximumMovementMetresPerFrame {
      lines.append("Head moving \(mm(movementMetresPerFrame)) mm per frame (limit 25 mm).")
    }
    if sampleCount >= 20, frameRate < Self.minimumFrameRate {
      lines.append("Camera at \(Int(frameRate.rounded())) frames a second (needs 20).")
    }
    return lines
  }

  private func cm(_ metres: Double) -> Int { Int((metres * 100).rounded()) }
  private func mm(_ metres: Double) -> Int { Int((metres * 1000).rounded()) }
}
