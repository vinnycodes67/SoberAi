#if DEBUG
import SwiftUI
import XCTest
@testable import Sober

@MainActor
final class UITestLaunchConfigurationTests: XCTestCase {
  func testFixtureIsInactiveWithoutExplicitFlag() {
    let configuration = UITestLaunchConfiguration(arguments: ["Sober"])

    XCTAssertFalse(configuration.isActive)
    XCTAssertNil(configuration.fixture)
    XCTAssertNil(configuration.directDestination)
    XCTAssertNil(configuration.dynamicTypeSize)
    XCTAssertFalse(configuration.reduceMotion)
  }

  func testUnknownOrMissingFixtureNeverActivatesDestructiveSetup() {
    XCTAssertFalse(
      UITestLaunchConfiguration(
        arguments: ["Sober", "-sober-ui-test-fixture", "unknown"]
      ).isActive
    )
    XCTAssertFalse(
      UITestLaunchConfiguration(
        arguments: ["Sober", "-sober-ui-test-fixture"]
      ).isActive
    )
  }

  func testDirectResultFixturesMapToExpectedFounderScenarios() {
    XCTAssertEqual(configuration(for: "result-signals").directDestination, .result(.signals))
    XCTAssertEqual(
      configuration(for: "result-inconclusive").directDestination,
      .result(.inconclusive)
    )
    XCTAssertEqual(configuration(for: "result-clear").directDestination, .result(.noSignals))
  }

  func testShellAndRecoveryFixturesRouteAsExpected() {
    XCTAssertNil(configuration(for: "home").directDestination)
    XCTAssertNil(configuration(for: "history").directDestination)
    XCTAssertEqual(configuration(for: "privacy").directDestination, .privacy)
    XCTAssertEqual(configuration(for: "how-results-work").directDestination, .howResults)
    XCTAssertEqual(configuration(for: "interrupted").directDestination, .interrupted)
    XCTAssertEqual(configuration(for: "capture-recovery").directDestination, .captureRecovery)
  }

  func testAccessibilityArgumentsAreParsedOnlyWhenRecognized() {
    let configuration = UITestLaunchConfiguration(
      arguments: [
        "Sober",
        "-sober-ui-test-fixture", "home",
        "-sober-ui-test-content-size", "accessibility3",
        "-sober-ui-test-reduce-motion",
      ]
    )

    XCTAssertEqual(configuration.dynamicTypeSize, .accessibility3)
    XCTAssertTrue(configuration.reduceMotion)
  }

  private func configuration(for fixture: String) -> UITestLaunchConfiguration {
    UITestLaunchConfiguration(
      arguments: ["Sober", "-sober-ui-test-fixture", fixture]
    )
  }
}
#endif
