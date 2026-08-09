import XCTest

/// Smoke coverage for the states a person actually lands on.
///
/// Every case runs off a named fixture and an isolated store, so these assert
/// behaviour rather than whatever the simulator happened to be left in.
final class JourneySmokeUITests: XCTestCase {

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launchApp(_ extraArguments: [String]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-sober-ui-testing"] + extraArguments
    app.launch()
    return app
  }

  // MARK: - Onboarding

  /// The founder demo fabricated a ready baseline and was the primary button on
  /// this screen. It must not exist in a public build at all.
  func testOnboardingOffersOnlyTheRealBaselinePath() {
    let app = launchApp([])

    XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["Explore founder demo"].exists)
  }

  // MARK: - Home

  func testHomeAsksForABaselineBeforeOneExists() {
    let app = launchApp(["-sober-onboarding-complete"])

    XCTAssertTrue(
      app.buttons["Record a baseline session"].waitForExistence(timeout: 10),
      "with no measured sessions Home must ask for a baseline, not offer a check")
    XCTAssertFalse(app.buttons["Start Sober check"].exists)
  }

  func testHomeOffersACheckOnceTheBaselineIsMeasured() {
    let app = launchApp([
      "-sober-onboarding-complete", "-sober-baseline-sessions", "5",
    ])

    XCTAssertTrue(app.buttons["Start Sober check"].waitForExistence(timeout: 10))
  }

  // MARK: - History

  func testHistoryEmptyStateExplainsItself() {
    let app = launchApp([
      "-sober-onboarding-complete", "-sober-initial-tab", "history",
    ])

    XCTAssertTrue(app.staticTexts["Nothing recorded yet"].waitForExistence(timeout: 10))
  }

  func testHistoryListsResultsWithoutAggregatingThem() {
    let app = launchApp([
      "-sober-onboarding-complete", "-sober-initial-tab", "history",
      "-sober-history-fixture", "mixed",
    ])

    XCTAssertTrue(app.staticTexts["Signals detected"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Inconclusive"].exists)
    XCTAssertTrue(app.staticTexts["No signals detected"].exists)
    XCTAssertTrue(app.staticTexts["Baseline session"].exists)
  }

  // MARK: - Settings

  func testSettingsExposesPrivacyAndDeletion() {
    let app = launchApp(["-sober-onboarding-complete", "-sober-initial-tab", "settings"])

    XCTAssertTrue(app.staticTexts["What Sober stores"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["Delete all local data"].exists)
  }

  /// The privacy screen must keep saying the app does not use these, because it
  /// is the user-facing half of the App Privacy answers.
  func testPrivacyCentreDeclaresUnusedPermissions() {
    let app = launchApp(["-sober-onboarding-complete", "-sober-initial-tab", "settings"])

    app.staticTexts["What Sober stores"].tap()

    XCTAssertTrue(app.staticTexts["Location"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Notifications"].exists)
  }
}
