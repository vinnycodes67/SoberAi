import XCTest

@testable import Sober

/// Which steps count as timed measurement.
///
/// Reaction latency is `Date().timeIntervalSince(targetAppearedAt)`, and the
/// timing and gaze tasks run on elapsed time. Time spent outside the foreground
/// lands inside those numbers, and a check scored against someone's own baseline
/// would read a phone call as a large slowdown in them — a false signal in a
/// product whose whole job is to be honest about what it measured.
///
/// The opposite error matters too: raising a recovery screen on a step where
/// nothing is running would make the app feel broken every time a notification
/// arrives during setup.
final class InterruptionPolicyTests: XCTestCase {

  func testTimedTasksAreTreatedAsInterruptible() {
    for step in ScreeningStep.timedTasks {
      XCTAssertTrue(
        ScreeningStep.isTimedTask(step),
        "\(step) measures against the wall clock and must discard on interruption")
    }
  }

  func testNonMeasuringStepsAreNotInterruptible() {
    let untimed: [ScreeningStep] = [
      .attestation, .environment, .analyzing, .result, .baselineComplete,
    ]
    for step in untimed {
      XCTAssertFalse(
        ScreeningStep.isTimedTask(step),
        "\(step) has no running measurement, so leaving the app there costs nothing")
    }
  }

  /// Every case is classified one way or the other. A step added later without
  /// a decision would silently default to "safe to background".
  func testEveryStepIsClassified() {
    let classified = Set(ScreeningStep.allCases.map(\.rawValue))
    XCTAssertEqual(
      classified.count, ScreeningStep.allCases.count,
      "each screening step must be considered exactly once")
  }

  func testEveryTimedTaskNamesItselfForTheRecoveryScreen() {
    for step in ScreeningStep.timedTasks {
      let name = ScreeningStep.taskName(for: step)
      XCTAssertFalse(
        name == "that task",
        "\(step) falls back to generic copy; the recovery screen should name it")
    }
  }
}
