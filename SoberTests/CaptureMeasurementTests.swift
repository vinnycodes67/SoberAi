import XCTest

@testable import Sober

final class CaptureMeasurementTests: XCTestCase {
  private func measurement(
    horizontal: Double = 0, vertical: Double = 0, distance: Double = 0.4,
    light: Double? = 900, movement: Double = 0.002, frameRate: Double = 60,
    facePresent: Bool = true, otherFaces: Bool = false
  ) -> CaptureMeasurement {
    CaptureMeasurement(
      facePresent: facePresent, otherFacesInView: otherFaces,
      horizontalMetres: horizontal, verticalMetres: vertical, distanceMetres: distance,
      ambientLight: light, movementMetresPerFrame: movement, frameRate: frameRate, sampleCount: 120)
  }

  func testAGoodFrameReportsNothing() {
    XCTAssertEqual(measurement().failingChecks, [])
  }

  func testEachFailingCheckNamesTheValueAndTheLimit() {
    XCTAssertEqual(
      measurement(vertical: -0.214).failingChecks,
      ["Face 21 cm off centre up or down (limit 18 cm)."])
    XCTAssertEqual(
      measurement(horizontal: 0.15).failingChecks,
      ["Face 15 cm off centre side to side (limit 13 cm)."])
    XCTAssertEqual(
      measurement(distance: 0.82).failingChecks, ["Face 82 cm from the phone (needs 25–75 cm)."])
    XCTAssertEqual(measurement(light: 120).failingChecks, ["Light 120 (needs 180)."])
    XCTAssertEqual(measurement(light: nil).failingChecks, ["Light unknown (needs 180)."])
    XCTAssertEqual(
      measurement(movement: 0.031).failingChecks, ["Head moving 31 mm per frame (limit 25 mm)."])
    XCTAssertEqual(
      measurement(frameRate: 14).failingChecks, ["Camera at 14 frames a second (needs 20)."])
  }

  func testNoFaceOverridesEverythingElse() {
    XCTAssertEqual(measurement(light: 10, facePresent: false).failingChecks, ["No face detected."])
  }

  func testAnotherFaceComesFirst() {
    XCTAssertEqual(
      measurement(horizontal: 0.2, otherFaces: true).failingChecks.first,
      "Another face is in view.")
  }
}
