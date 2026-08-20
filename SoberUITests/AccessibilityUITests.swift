import XCTest

/// The app at the settings people actually use.
///
/// Sober is opened at night by someone who has been drinking and is deciding
/// whether to drive. Large text and Reduce Motion are not edge cases in that
/// population, and a primary action that has scrolled off or been clipped at
/// AX5 is the same as no primary action.
///
/// These assert the load-bearing controls survive, not that the layout is
/// pretty. Pixel-level checks belong in snapshot tests.
@MainActor
final class AccessibilityUITests: XCTestCase {

  /// The largest accessibility size. If a screen holds together here it holds
  /// together at every step below.
  private static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launchApp(
    textSize: String? = nil,
    _ extraArguments: [String] = []
  ) -> XCUIApplication {
    let app = XCUIApplication()
    var arguments = ["-sober-ui-testing", "-sober-onboarding-complete"] + extraArguments
    if let textSize {
      arguments += ["-UIPreferredContentSizeCategoryName", textSize]
    }
    app.launchArguments = arguments
    app.launch()
    return app
  }

  // MARK: - Dynamic Type

  func testPrimaryActionSurvivesLargestTextSize() {
    let app = launchApp(textSize: Self.ax5)

    let action = app.buttons["Record a baseline session"]
    XCTAssertTrue(action.waitForExistence(timeout: 15))
    XCTAssertTrue(action.isHittable, "the primary action must stay reachable at AX5")
  }

  func testTabBarStaysUsableAtLargestTextSize() {
    let app = launchApp(textSize: Self.ax5)

    for tab in ["Home", "History", "Settings"] {
      let button = app.buttons[tab]
      XCTAssertTrue(button.waitForExistence(timeout: 15), "\(tab) tab missing at AX5")
      XCTAssertTrue(button.isHittable, "\(tab) tab is not tappable at AX5")
    }
  }

  /// Render each destination directly at AX5. End-to-end tab taps are covered by
  /// the journey suite; using the debug-only initial-tab route here isolates the
  /// accessibility question from an XCTest/SwiftUI hit-synthesis flake seen only
  /// on the simulator at AX5. Keep one launch per test: two 60-second waits plus
  /// launch overhead can otherwise exceed XCTest's 120-second per-test ceiling.
  func testHistoryRendersAtLargestTextSize() {
    let history = launchApp(
      textSize: Self.ax5,
      ["-sober-history-fixture", "mixed", "-sober-initial-tab", "history"])
    XCTAssertTrue(history.staticTexts["Changes detected"].waitForExistence(timeout: 60))
  }

  func testSettingsRendersAtLargestTextSize() {
    let settings = launchApp(
      textSize: Self.ax5,
      ["-sober-initial-tab", "settings"])
    XCTAssertTrue(settings.staticTexts["What Sober stores"].waitForExistence(timeout: 60))
  }

  // MARK: - VoiceOver content

  /// Camera readiness was carried by a glyph and its colour. Six tiles that
  /// differ only in hue are six identical tiles to VoiceOver, on the one screen
  /// a person must satisfy before a check can begin.
  func testCalibrationTilesExposeTheirStateAsText() throws {
    let app = launchApp(textSize: nil, ["-sober-baseline-sessions", "5"])
    XCTAssertTrue(app.buttons["Start Sober check"].waitForExistence(timeout: 15))
    app.buttons["Start Sober check"].tap()

    // The self-report gate comes first; answering "No" reaches calibration.
    let no = app.buttons["No"]
    if no.waitForExistence(timeout: 10) {
      no.tap()
      let continueToSetup = app.buttons["Continue to setup"]
      XCTAssertTrue(continueToSetup.waitForExistence(timeout: 10))
      continueToSetup.tap()
    }

    // Query the combined tile directly. A label-only query can select the
    // nested Text node on some OS versions, whose value is correctly empty,
    // instead of the tile that owns the textual readiness state.
    let tile = app.descendants(matching: .any)["calibration-quality-face"].firstMatch

    guard tile.waitForExistence(timeout: 20) else {
      // A simulator has no TrueDepth camera. If calibration could not be
      // reached at all, there is nothing to assert here rather than a failure
      // to report — the unsupported-camera copy has its own coverage.
      throw XCTSkip("calibration was not reachable on this device")
    }

    XCTAssertFalse(
      (tile.value as? String ?? "").isEmpty,
      "each quality tile must expose ready or needs-adjusting as text, not colour alone")
  }

  // MARK: - Reduce Motion

  /// Reduce Motion must not remove function. The check has to remain startable.
  func testAppIsUsableWithReduceMotion() {
    let app = launchApp(
      textSize: nil, ["-sober-baseline-sessions", "5", "-UIAccessibilityReduceMotionEnabled", "1"])

    XCTAssertTrue(app.buttons["Start Sober check"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["Start Sober check"].isHittable)
  }
}
