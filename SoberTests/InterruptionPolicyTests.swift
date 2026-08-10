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
  /// being added to `timedTasks` must still agree with the exhaustive switch.
  func testEveryStepIsClassified() {
    let declaredTimedTasks = Set(ScreeningStep.timedTasks)
    XCTAssertEqual(declaredTimedTasks.count, ScreeningStep.timedTasks.count)
    for step in ScreeningStep.allCases {
      XCTAssertEqual(
        ScreeningStep.isTimedTask(step),
        declaredTimedTasks.contains(step),
        "\(step) disagrees between the timed-task declaration and policy switch"
      )
    }
  }

  func testEveryTimedTaskNamesItselfForTheRecoveryScreen() {
    for step in ScreeningStep.timedTasks {
      let name = ScreeningStep.taskName(for: step)
      XCTAssertFalse(
        name == "that task",
        "\(step) falls back to generic copy; the recovery screen should name it")
    }
  }

  func testCaptureLossUsesAThreeSecondGracePeriod() {
    XCTAssertEqual(CaptureRecoveryPolicy.sustainedLossSeconds, 3)
  }
}
