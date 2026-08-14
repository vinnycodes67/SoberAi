import XCTest

/// Smoke coverage for the states a person actually lands on.
///
/// Every case runs off a named fixture and an isolated store, so these assert
/// behaviour rather than whatever the simulator happened to be left in.
@MainActor
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

  /// Simulators and non-TrueDepth iPhones cannot run AR face tracking. That
  /// must degrade to an explicitly limited, inconclusive path rather than
  /// stranding someone at camera setup.
  func testUnsupportedCameraStillOffersALimitedCapturePath() {
    let app = launchApp([
      "-sober-onboarding-complete", "-sober-baseline-sessions", "5",
    ])

    let start = app.buttons["Start Sober check"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()

    let no = app.buttons["No"]
    XCTAssertTrue(no.waitForExistence(timeout: 10))
    no.tap()

    let continueToSetup = app.buttons["Continue to setup"]
    XCTAssertTrue(continueToSetup.waitForExistence(timeout: 10))
    continueToSetup.tap()

    let limitedCapture = app.buttons["Continue with limited capture"]
    XCTAssertTrue(limitedCapture.waitForExistence(timeout: 20))
    for _ in 0..<4 where !limitedCapture.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(limitedCapture.isHittable)
    XCTAssertTrue(
      app.staticTexts[
        "A live check can continue, but its result will be inconclusive without usable camera capture."
      ].exists)
  }

  func testHowResultsWorkDoesNotCreateHistoryOrABaseline() {
    let app = launchApp(["-sober-onboarding-complete"])

    let education = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "How results work")
    ).firstMatch
    for _ in 0..<5 where !education.exists || !education.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(education.waitForExistence(timeout: 10))
    education.tap()

    XCTAssertTrue(app.staticTexts["No result is a green light."].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Changes detected"].exists)
    XCTAssertTrue(app.staticTexts["No clear read"].exists)
    XCTAssertTrue(app.staticTexts["No changes detected"].exists)
    XCTAssertTrue(app.staticTexts["Examples only. No data is recorded."].exists)

    app.buttons["Done"].tap()
    XCTAssertTrue(app.buttons["Record a baseline session"].waitForExistence(timeout: 10))
    app.buttons["History"].tap()
    XCTAssertTrue(app.staticTexts["Nothing recorded yet"].waitForExistence(timeout: 10))
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

    XCTAssertTrue(app.staticTexts["Changes detected"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Inconclusive"].exists)
    XCTAssertTrue(app.staticTexts["No changes detected"].exists)
    XCTAssertTrue(app.staticTexts["Baseline session"].exists)
  }

  // MARK: - Settings

  func testSettingsExposesPrivacyAndDeletion() {
    let app = launchApp(["-sober-onboarding-complete", "-sober-initial-tab", "settings"])

    XCTAssertTrue(app.staticTexts["What Sober stores"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["Delete all local data"].exists)
  }

  func testPrivacyPolicyIsReachableInsideTheApp() {
    let app = launchApp(["-sober-onboarding-complete", "-sober-initial-tab", "settings"])

    // Activate the row's Button rather than its nested title. Tapping the
    // StaticText can synthesize an event on the label without firing the
    // surrounding Button after a long sequential UI run.
    let policy = app.buttons["privacy-policy-row"]
    XCTAssertTrue(policy.waitForExistence(timeout: 10))
    XCTAssertTrue(policy.isHittable)
    policy.tap()

    XCTAssertTrue(app.navigationBars["Privacy policy"].waitForExistence(timeout: 10))
    // DesignKit eyebrow labels expose their rendered uppercase value.
    XCTAssertTrue(app.staticTexts["CAMERA PROCESSING"].exists)
    XCTAssertTrue(app.staticTexts["DATA COLLECTION AND SHARING"].exists)
    XCTAssertTrue(app.buttons["Done"].isHittable)
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
