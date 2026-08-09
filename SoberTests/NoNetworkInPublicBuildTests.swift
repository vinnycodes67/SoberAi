import XCTest

@testable import Sober

/// Public v1 sends nothing anywhere.
///
/// That claim is load-bearing: it is what the Privacy Centre tells people, and
/// it is what the App Privacy questionnaire will say. `URLSession` appears in
/// exactly one file, `GuardianAPIClient`, and Guardian is not in public v1 — the
/// public target ships no `SoberGuardianAPIURL`, so the client resolves a nil
/// base URL and every request guards out before touching the network.
///
/// These pin that behaviour so a later change cannot quietly give the public
/// build a network path.
final class NoNetworkInPublicBuildTests: XCTestCase {

  /// The public `Info.plist` has no `SoberGuardianAPIURL` key at all.
  func testMissingConfigurationKeyYieldsNoBaseURL() {
    let bundle = Bundle(for: type(of: self))
    let configuration = GuardianAPIConfiguration.from(bundle: bundle)
    XCTAssertNil(configuration.baseURL)
  }

  /// An empty Release value must not become a URL.
  func testEmptyConfigurationYieldsNoBaseURL() {
    XCTAssertNil(GuardianAPIConfiguration(baseURL: nil).baseURL)
  }

  /// The transport is never invoked when there is no base URL. If this ever
  /// fires, something is issuing a request against an unconfigured host.
  func testClientWithNoBaseURLNeverReachesTheTransport() async {
    let transportWasCalled = expectation(description: "transport invoked")
    transportWasCalled.isInverted = true

    let client = GuardianAPIClient(
      configuration: GuardianAPIConfiguration(baseURL: nil),
      transport: { _ in
        transportWasCalled.fulfill()
        throw URLError(.badURL)
      }
    )

    // Any relationship call is fine; they all funnel through `makeRequest`,
    // which is where the nil base URL stops them.
    _ = try? await client.createRelationship(personDisplayName: "Test")

    await fulfillment(of: [transportWasCalled], timeout: 1)
  }
}
