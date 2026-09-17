import XCTest

@testable import Sober

/// The ride link is the product's one real intervention, and it is now built in
/// one place so the result screen and Curfew's check-in cannot drift apart.
final class SafetyPlanRideURLTests: XCTestCase {

  private func plan(ride: String, address: String) -> SafetyPlan {
    SafetyPlan(
      userName: "Alex",
      contactName: "Jordan",
      contactPhone: "3125550100",
      homeLabel: "Home",
      homeAddress: address,
      preferredRide: ride
    )
  }

  func testUberCarriesTheDestination() throws {
    let url = try XCTUnwrap(plan(ride: "Uber", address: "123 Main Street, Chicago, IL").rideURL)
    let text = url.absoluteString
    XCTAssertTrue(text.hasPrefix("https://m.uber.com/ul/"))
    XCTAssertTrue(text.contains("pickup=my_location"))
    XCTAssertTrue(
      text.contains("123%20Main%20Street"),
      "the saved address must survive percent-encoding: \(text)")
    // `%2520` is an encoded `%` — the signature of encoding the address twice,
    // which hands Uber the literal text "%20" instead of a space.
    XCTAssertFalse(text.contains("%2520"), "address was double-encoded: \(text)")
  }

  /// Without an address there is still a ride, just no prefilled destination.
  /// Returning nil here would remove the way home from the result screen.
  func testUberWithoutAnAddressStillProducesARide() throws {
    let url = try XCTUnwrap(plan(ride: "Uber", address: "   ").rideURL)
    XCTAssertTrue(url.absoluteString.hasPrefix("https://m.uber.com/ul/"))
    XCTAssertFalse(url.absoluteString.contains("dropoff"))
  }

  func testLyftUsesItsOwnEntryPoint() throws {
    let url = try XCTUnwrap(plan(ride: "Lyft", address: "123 Main Street, Chicago, IL").rideURL)
    XCTAssertEqual(url.absoluteString, "https://www.lyft.com/rider")
  }

  /// Addresses people actually type. Any of these returning nil would strand
  /// someone on the result screen with a dead button.
  func testAwkwardAddressesStillBuildAURL() {
    let addresses = [
      "1600 Amphitheatre Pkwy #2, Mountain View, CA",
      "Flat 3/2, 10 O'Brien St",
      "Calle Añejo 5, Ciudad de México",
      "123 Main St & 4th Ave",
    ]
    for address in addresses {
      XCTAssertNotNil(plan(ride: "Uber", address: address).rideURL, "failed for: \(address)")
    }
  }
}

/// Curfew's check-in and the result screen must open the identical ride.
///
/// Asserted against the source text rather than the symbol: `Features/Curfew`
/// is excluded from the public target, so `CurfewRideLink` is not linked into
/// this test bundle. Same approach as `testCurfewSourcesNeverReferenceScreeningOutcomes`.
final class CurfewRideLinkParityTests: XCTestCase {
  func testCurfewRideLinkDelegatesRatherThanRebuildingTheURL() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let source = try String(
      contentsOf: root.appendingPathComponent("Sober/Features/Curfew/CurfewRideLink.swift"),
      encoding: .utf8
    )

    XCTAssertTrue(
      source.contains("safetyPlan.rideURL"),
      "Curfew must open the same ride as the result screen")
    for rebuilt in ["m.uber.com", "addingPercentEncoding", "lyft.com"] {
      XCTAssertFalse(
        source.contains(rebuilt),
        "Curfew is rebuilding the ride URL again (\(rebuilt)); it silently lost the destination last time")
    }
  }
}
