import XCTest

/// The public build must have no way to reach an internal route.
///
/// `Scripts/check-public-binary.sh` proves the strings are absent from the
/// Release artifact. This proves the running app agrees: the tab bar offers
/// three destinations, and nothing on a reachable screen leads to Guardian,
/// Circle, Research, or the founder previews.
///
/// Both checks are needed. The binary scan would pass if a route existed but
/// reused copy that already ships; this would pass if a route were unreachable
/// but its copy still shipped.
@MainActor
final class PublicBoundaryUITests: XCTestCase {

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launchApp(_ extraArguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-sober-ui-testing", "-sober-onboarding-complete"] + extraArguments
    app.launch()
    return app
  }

  func testTabBarOffersOnlyPublicDestinations() {
    let app = launchApp()

    XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["History"].exists)
    XCTAssertTrue(app.buttons["Settings"].exists)
    XCTAssertFalse(app.buttons["Circle"].exists, "Guardian is not in public v1")
  }

  /// Internal copy must not appear anywhere a person can navigate to.
  func testNoInternalRouteIsReachable() {
    let app = launchApp()
    XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 10))

    let forbidden = [
      "Founder tools",
      "Research Center",
      "Circle Map",
      "Guardian",
      "Preview concerning result",
    ]

    for destination in ["Home", "History", "Settings"] {
      app.buttons[destination].tap()
      for label in forbidden {
        XCTAssertFalse(
          app.staticTexts[label].exists,
          "\"\(label)\" is reachable from \(destination) in a public build")
      }
    }
  }
}
