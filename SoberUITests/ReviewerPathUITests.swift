import XCTest

/// The path an App Reviewer has to be able to walk.
///
/// A check needs five accepted sober sessions before it will compare anything,
/// which nobody can produce on a review device. Without a static explanation the
/// reviewer's only options are to reject on "could not test the core feature" or
/// to guess what the app does.
///
/// This is also the screen that has to hold the line on claims. If a "safe to
/// drive" or "you are sober" phrasing ever creeps into the examples, it reaches
/// both a reviewer and every user, so it is asserted rather than trusted.
///
/// `Scripts/check-public-binary.sh` separately requires this page's copy to be
/// present in the Release binary. That proves the strings ship; this proves they
/// are reachable and say the right thing.
@MainActor
final class ReviewerPathUITests: XCTestCase {

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  /// Reached from Settings. Home offers it too, before a baseline exists.
  private func launchToExamples() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "-sober-ui-testing", "-sober-onboarding-complete", "-sober-initial-tab", "settings",
    ]
    app.launch()

    XCTAssertTrue(app.staticTexts["How results work"].waitForExistence(timeout: 60))
    app.staticTexts["How results work"].tap()
    return app
  }

  func testExamplesAreReachableWithoutABaseline() {
    let app = launchToExamples()

    XCTAssertTrue(app.staticTexts["No result is a green light."].waitForExistence(timeout: 60))
    XCTAssertTrue(app.staticTexts["Changes detected"].exists)
    XCTAssertTrue(app.staticTexts["No clear read"].exists)
    XCTAssertTrue(app.staticTexts["No changes detected"].exists)
  }

  /// Every card is labelled. A screenshot of one card has to carry its own
  /// disclaimer rather than relying on a heading further up the page.
  func testEveryExampleIsLabelledAsAnExample() {
    let app = launchToExamples()
    XCTAssertTrue(app.staticTexts["No result is a green light."].waitForExistence(timeout: 60))

    let badges = app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH[c] %@", "Example "))
    XCTAssertEqual(badges.count, 3, "each of the three example cards must be labelled")
  }

  /// The claims matrix, enforced on the surface most likely to drift toward
  /// reassurance.
  func testExamplesMakeNoClearanceClaim() {
    let app = launchToExamples()
    XCTAssertTrue(app.staticTexts["No result is a green light."].waitForExistence(timeout: 60))

    let forbidden = ["safe to drive", "you are sober", "you're sober", "passed", "cleared"]
    for phrase in forbidden {
      let matches = app.staticTexts.matching(
        NSPredicate(format: "label CONTAINS[c] %@", phrase))
      for index in 0..<matches.count {
        let text = matches.element(boundBy: index).label
        // A negated mention is the point of the page — "cannot establish
        // sobriety or driving safety" has to be allowed. Only a bare claim is a
        // failure.
        let negators = ["not", "cannot", "never", "none", "n't", "no result"]
        let negated = negators.contains { text.range(of: $0, options: .caseInsensitive) != nil }
        XCTAssertTrue(negated, "\"\(phrase)\" appears without negation in: \(text)")
      }
    }
  }
}
