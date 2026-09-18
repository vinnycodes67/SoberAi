import XCTest

/// The age gate has to hold against the swipe, not just the button.
///
/// `OnboardingView` uses a page-style `TabView`, which writes `selection`
/// directly. Binding it to `page` meant the Continue button's `.disabled` state
/// governed only the button: a swipe carried someone from the profile step
/// straight to consent without ever committing a name or an age, and the finish
/// button there checks consent alone. On an app with an age requirement, that
/// is the requirement being optional.
@MainActor
final class OnboardingGateUITests: XCTestCase {

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launchToProfileStep() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-sober-ui-test-fixture", "onboarding"]
    app.launch()

    XCTAssertTrue(
      app.staticTexts["Take a beat before you move."].waitForExistence(timeout: 60),
      "onboarding should open on its first page")

    // Page 1 -> 2 -> the profile step, through the button, which is allowed.
    app.buttons["Continue"].tap()
    XCTAssertTrue(app.staticTexts["A signal, never a green light."].waitForExistence(timeout: 30))
    app.buttons["Continue"].tap()
    return app
  }

  func testSwipingPastTheProfileStepIsRefusedWhenItIsIncomplete() {
    let app = launchToProfileStep()

    // Nothing entered: the step is invalid, so neither the button nor the
    // gesture may advance past it.
    XCTAssertFalse(
      app.buttons["Continue"].isEnabled,
      "an empty profile must leave Continue disabled")

    app.swipeLeft()
    app.swipeLeft()

    XCTAssertTrue(
      app.buttons["Continue"].exists,
      "still on a step that offers Continue, i.e. not the final consent step")
    XCTAssertFalse(
      app.buttons["Start with a real baseline"].exists,
      "a swipe must not reach the consent step with no age committed")
  }

  /// Going back is always allowed — that is how someone fixes an entry.
  func testSwipingBackwardStillWorks() {
    let app = launchToProfileStep()

    app.swipeRight()

    XCTAssertTrue(
      app.staticTexts["A signal, never a green light."].waitForExistence(timeout: 30),
      "swiping back to an earlier, already-valid step must keep working")
  }
}
