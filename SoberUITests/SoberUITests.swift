import XCTest

@MainActor
final class SoberUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testOnboardingStartsAtProductBoundaryAndAdvances() {
    let app = launch(fixture: "onboarding")

    XCTAssertTrue(app.staticTexts["Take a beat before you move."].waitForExistence(timeout: 30))
    XCTAssertTrue(app.staticTexts["1 / 4"].exists)
    capture(app, named: "onboarding-introduction")

    app.buttons["Continue"].tap()
    XCTAssertTrue(app.staticTexts["A signal, never a green light."].waitForExistence(timeout: 30))
  }

  func testPublicShellKeepsSafetyActionAndAllPublicTabsReachable() {
    let app = launch(fixture: "home")

    XCTAssertTrue(app.staticTexts["Learn your steady."].waitForExistence(timeout: 30))
    XCTAssertTrue(app.buttons["Record a baseline session"].isHittable)
    XCTAssertTrue(app.buttons["Home"].exists)
    XCTAssertTrue(app.buttons["History"].exists)
    XCTAssertTrue(app.buttons["Settings"].exists)
    XCTAssertFalse(app.buttons["Circle"].exists)
    capture(app, named: "public-home")

    app.buttons["History"].tap()
    XCTAssertTrue(app.staticTexts["What you have recorded."].waitForExistence(timeout: 30))
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.staticTexts["SETTINGS"].waitForExistence(timeout: 30))
  }

  func testSeededHistoryShowsBoundedRowsWithoutAggregateClaims() {
    let app = launch(fixture: "history", initialTab: "history")

    XCTAssertTrue(app.staticTexts["Signals detected"].waitForExistence(timeout: 30))
    XCTAssertTrue(app.staticTexts["Inconclusive"].exists)
    XCTAssertTrue(app.staticTexts["Baseline session"].exists)
    XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'streak'")).firstMatch.exists)
    XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'trend'")).firstMatch.exists)
    capture(app, named: "history-seeded")
  }

  func testSettingsOpensPlainLanguagePrivacyInventory() {
    let app = launch(fixture: "settings", initialTab: "settings")

    let stores = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "What Sober stores")
    ).firstMatch
    XCTAssertTrue(stores.waitForExistence(timeout: 30))
    stores.tap()

    XCTAssertTrue(app.staticTexts["Everything stays on this iPhone."].waitForExistence(timeout: 30))
    XCTAssertTrue(app.staticTexts["NEVER STORED"].exists)
    capture(app, named: "privacy-center")
  }

  func testHowResultsWorkShowsAllStatesAsEducation() {
    let app = launch(fixture: "how-results-work")

    XCTAssertTrue(app.staticTexts["No result is a green light."].waitForExistence(timeout: 30))
    XCTAssertTrue(app.staticTexts["Signals detected"].exists)
    XCTAssertTrue(app.staticTexts["No clear read"].exists)
    XCTAssertTrue(app.staticTexts["No signals detected"].exists)
    XCTAssertTrue(app.staticTexts["Examples only. No data is recorded."].exists)
    XCTAssertFalse(app.buttons["Open Uber"].exists)
    capture(app, named: "how-results-work")
  }

  func testSignalsResultKeepsNoDriveActionAndSampleDisclosureVisible() {
    let app = launch(fixture: "result-signals")

    XCTAssertTrue(app.staticTexts["Signals detected"].waitForExistence(timeout: 30))
    XCTAssertTrue(app.staticTexts["We saw signs consistent with impairment. Don’t drive."].exists)
    XCTAssertTrue(app.staticTexts["Sample result"].exists)
    XCTAssertTrue(app.buttons["Open Uber"].exists)
    capture(app, named: "result-signals")
  }

  func testInconclusiveResultRefusesAFalseClearance() {
    let app = launch(fixture: "result-inconclusive")

    XCTAssertTrue(app.staticTexts["No clear read"].waitForExistence(timeout: 30))
    XCTAssertTrue(
      app.staticTexts["We couldn’t get a clear read. If you’ve had anything, don’t drive."].exists
    )
    capture(app, named: "result-inconclusive")
  }

  func testNoSignalsResultRetainsExplicitSafetyLimit() {
    let app = launch(fixture: "result-clear")

    XCTAssertTrue(app.staticTexts["No signals detected"].waitForExistence(timeout: 30))
    XCTAssertTrue(
      app.staticTexts["We didn’t detect signals. This does not mean you’re sober or safe to drive."].exists
    )
    capture(app, named: "result-no-signals")
  }

  func testInterruptedTaskOffersOnlyRedoOrEnd() {
    let app = launch(fixture: "interrupted")

    XCTAssertTrue(app.staticTexts["That task was interrupted."].waitForExistence(timeout: 30))
    XCTAssertTrue(app.buttons["Redo this task"].isHittable)
    XCTAssertTrue(app.buttons["End check"].isHittable)
    XCTAssertFalse(app.buttons["Resume"].exists)
    capture(app, named: "interrupted-task")
  }

  func testCaptureRecoveryExplainsDiscardAndAction() {
    let app = launch(fixture: "capture-recovery")

    XCTAssertTrue(
      app.staticTexts["The camera lost a usable reading."].waitForExistence(timeout: 30)
    )
    XCTAssertTrue(app.staticTexts["Center your face and move somewhere brighter."].exists)
    XCTAssertTrue(app.buttons["Set the camera up again"].isHittable)
    capture(app, named: "capture-recovery")
  }

  @discardableResult
  private func launch(
    fixture: String,
    initialTab: String? = nil,
    contentSize: String? = nil,
    reduceMotion: Bool = true
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "-sober-ui-test-fixture", fixture,
      "-AppleLanguages", "(en)",
      "-AppleLocale", "en_US_POSIX",
    ]
    if let initialTab {
      app.launchArguments += ["-sober-initial-tab", initialTab]
    }
    if let contentSize {
      app.launchArguments += ["-sober-ui-test-content-size", contentSize]
    }
    if reduceMotion {
      app.launchArguments.append("-sober-ui-test-reduce-motion")
    }
    app.launch()
    return app
  }

  private func capture(_ app: XCUIApplication, named name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}

@MainActor
final class SoberAccessibilityUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testHomeAtAccessibilityThreeKeepsPrimaryActionReachable() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-sober-ui-test-fixture", "home",
      "-sober-ui-test-content-size", "accessibility3",
      "-sober-ui-test-reduce-motion",
      "-AppleLanguages", "(en)",
      "-AppleLocale", "en_US_POSIX",
    ]
    app.launch()

    XCTAssertTrue(app.staticTexts["Learn your steady."].waitForExistence(timeout: 30))
    let action = app.buttons["Record a baseline session"]
    if !action.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(action.isHittable)

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "home-accessibility3"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
