import XCTest

/// Drives the app through real screens for a screen-recorded App Review demo
/// video. Not part of CI — run manually alongside `simctl io recordVideo`.
///
/// Every step uses the same public UI a person taps. No mocked gestures, no
/// synthetic results: on a TrueDepth-less simulator the ocular task correctly
/// falls back to "Continue with inconclusive capture", which is the same
/// honest degradation a reviewer's own device would show.
@MainActor
final class DemoRecordingUITests: XCTestCase {

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func pause(_ seconds: Double) {
    Thread.sleep(forTimeInterval: seconds)
  }

  private func runReactionTask(_ app: XCUIApplication) {
    XCTAssertTrue(app.buttons["Begin reaction task"].waitForExistence(timeout: 10))
    app.buttons["Begin reaction task"].tap()

    let choices = ["Blue circle", "Pink circle", "Blue diamond", "Pink diamond"]
    for _ in 0..<6 {
      pause(1.0)
      for label in choices where app.buttons[label].exists && app.buttons[label].isHittable {
        app.buttons[label].tap()
        break
      }
    }
  }

  private func runMotorTrackingTask(_ app: XCUIApplication) {
    let path = app.otherElements["Motor tracking path"]
    XCTAssertTrue(path.waitForExistence(timeout: 10))
    pause(0.5)
    let start = path.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
    let end = path.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    pause(0.5)
  }

  private func runTimeEstimateTask(_ app: XCUIApplication) {
    XCTAssertTrue(app.buttons["Start counting"].waitForExistence(timeout: 10))
    app.buttons["Start counting"].tap()
    pause(3.0)
    app.buttons["Stop now"].tap()
    pause(0.5)
  }

  private func passUnsupportedCamera(_ app: XCUIApplication) {
    let button = app.buttons["Continue with limited capture"]
    XCTAssertTrue(button.waitForExistence(timeout: 20))
    pause(1.0)
    button.tap()
  }

  private func finishOcularTaskInconclusively(_ app: XCUIApplication) {
    let button = app.buttons["Continue with inconclusive capture"]
    XCTAssertTrue(button.waitForExistence(timeout: 10))
    pause(1.0)
    button.tap()
  }

  // MARK: - Segment 1: baseline session

  func testDemoBaselineSession() {
    let app = XCUIApplication()
    app.launchArguments = ["-sober-ui-testing", "-sober-onboarding-complete"]
    app.launch()

    let record = app.buttons["Record a baseline session"]
    XCTAssertTrue(record.waitForExistence(timeout: 10))
    pause(1.0)
    record.tap()

    let toggle = app.switches.firstMatch
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    pause(0.8)
    toggle.tap()
    pause(0.5)
    app.buttons["Begin baseline session"].tap()

    passUnsupportedCamera(app)
    runReactionTask(app)
    runMotorTrackingTask(app)
    runTimeEstimateTask(app)
    finishOcularTaskInconclusively(app)

    XCTAssertTrue(app.buttons["Return home"].waitForExistence(timeout: 15))
    pause(2.0)
    app.buttons["Return home"].tap()
    pause(1.0)
  }

  // MARK: - Segment 2: live check

  func testDemoLiveCheck() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-sober-ui-testing", "-sober-onboarding-complete", "-sober-baseline-sessions", "5",
    ]
    app.launch()

    let start = app.buttons["Start Sober check"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    pause(1.0)
    start.tap()

    XCTAssertTrue(app.buttons["No"].waitForExistence(timeout: 10))
    pause(0.8)
    app.buttons["No"].tap()
    pause(0.5)
    app.buttons["Continue to setup"].tap()

    passUnsupportedCamera(app)
    runReactionTask(app)
    runMotorTrackingTask(app)
    runTimeEstimateTask(app)
    finishOcularTaskInconclusively(app)

    pause(2.0)
    XCTAssertTrue(app.buttons["Return home"].waitForExistence(timeout: 15))
    pause(3.0)
  }

  // MARK: - Segment 3: how results work

  func testDemoHowResultsWork() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-sober-ui-testing", "-sober-onboarding-complete", "-sober-initial-tab", "settings",
    ]
    app.launch()

    let entry = app.staticTexts["How results work"]
    XCTAssertTrue(entry.waitForExistence(timeout: 10))
    pause(1.0)
    entry.tap()

    XCTAssertTrue(app.staticTexts["No result is a green light."].waitForExistence(timeout: 10))
    pause(3.0)
    app.swipeUp()
    pause(3.0)
  }

  // MARK: - Segment 4: history

  func testDemoHistory() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-sober-ui-testing", "-sober-onboarding-complete", "-sober-initial-tab", "history",
      "-sober-history-fixture", "mixed",
    ]
    app.launch()

    XCTAssertTrue(app.staticTexts["Changes detected"].waitForExistence(timeout: 10))
    pause(3.0)
  }
}
