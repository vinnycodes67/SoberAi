import XCTest

@testable import Sober

/// The app must not promise a destination the ride provider never receives.
///
/// Uber's universal link carries a formatted address. Lyft's takes coordinates
/// we do not hold, and the public build has no network to geocode with — so the
/// Lyft link opens without a destination. Home and Settings both rendered
/// "Lyft to Home" anyway, which is a claim about something that does not happen.
final class SafetyPlanRidePromiseTests: XCTestCase {

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

  func testUberWithASavedAddressCarriesTheDestination() {
    XCTAssertTrue(plan(ride: "Uber", address: "123 Main Street, Chicago, IL").rideCarriesDestination)
  }

  func testUberWithoutAnAddressDoesNotPromiseOne() {
    XCTAssertFalse(plan(ride: "Uber", address: "   ").rideCarriesDestination)
  }

  /// The bug this file exists for.
  func testLyftNeverPromisesADestination() {
    let lyft = plan(ride: "Lyft", address: "123 Main Street, Chicago, IL")
    XCTAssertFalse(
      lyft.rideCarriesDestination,
      "the Lyft link has no destination parameter, so no screen may claim one")

    let url = try? XCTUnwrap(lyft.rideURL)
    XCTAssertFalse(
      url?.absoluteString.contains("Main") ?? true,
      "if the Lyft URL ever starts carrying the address, flip rideCarriesDestination too")
  }
}
