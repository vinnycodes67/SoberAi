import XCTest

/// The last row of every tab must be fully readable above the floating tab bar.
///
/// The bar is attached with `safeAreaInset`, which insets the scroll content --
/// but the bar is a floating capsule with transparent space around and below it,
/// so text scrolling beneath it showed through the gaps and read as cut off.
@MainActor
final class TabBarClearanceUITests: XCTestCase {

  override func setUp() {
    super.setUp()
    continueAfterFailure = true
  }

  private func launch(_ fixture: String, tab: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    var args = ["-sober-ui-test-fixture", fixture, "-sober-ui-test-reduce-motion"]
    if let tab { args += ["-sober-initial-tab", tab] }
    app.launchArguments = args
    app.launch()
    return app
  }

  private func scrollToBottom(_ app: XCUIApplication) {
    for _ in 0..<6 { app.swipeUp(velocity: .fast) }
    Thread.sleep(forTimeInterval: 1.0)
  }

  private func attach(_ app: XCUIApplication, named name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }

  /// A last element is clear of the bar when its bottom edge sits above the
  /// bar's top edge.
  private func assertClearOfTabBar(_ element: XCUIElement, _ app: XCUIApplication, _ label: String) {
    let bar = app.buttons["Home"]
    XCTAssertTrue(bar.waitForExistence(timeout: 30), "tab bar should be on screen")
    XCTAssertTrue(element.waitForExistence(timeout: 30), "\(label) should exist")
    XCTAssertLessThanOrEqual(
      element.frame.maxY, bar.frame.minY + 1,
      "\(label) ends at y=\(element.frame.maxY) but the tab bar starts at y=\(bar.frame.minY)")
  }

  func testHomeLastSectionIsClearOfTheTabBar() {
    let app = launch("home")
    XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 60))
    scrollToBottom(app)
    attach(app, named: "home-bottom")
    assertClearOfTabBar(app.staticTexts["How results work"], app, "Home's last section")
  }

  func testSettingsVersionRowIsClearOfTheTabBar() {
    let app = launch("settings", tab: "settings")
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 60))
    scrollToBottom(app)
    attach(app, named: "settings-bottom")
    assertClearOfTabBar(app.staticTexts["Version"], app, "the Version row")
  }
}
