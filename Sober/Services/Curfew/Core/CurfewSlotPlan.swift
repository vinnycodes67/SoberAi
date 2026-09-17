import Foundation

// The wall-clock slots that wake the monitor extension, worked out here without
// DeviceActivity so the arithmetic is unit-tested in SoberTests. The Screen
// Time layer turns each slot into a repeating `DeviceActivitySchedule`.
//
// `DeviceActivityEvent` thresholds measure app usage, not the clock, so the
// hourly re-check is a row of repeating daily intervals instead: one per hour
// from the moment apps may pause (curfew plus grace), for each of the two
// curfew times. Every slot fires every day; the monitor just reconciles, and
// the evaluator decides by weekday which curfew applies.
//
// Two boundaries matter and both are pinned by `CurfewEvaluatorTests`:
//   • slot 0 starts at `pauseStartsAt`, so the pause begins when the evaluator
//     says it should rather than at the end of the first hour;
//   • the last slot ends at or after `CurfewNight.endsAt`, so its
//     `intervalDidEnd` is what lifts the pause when the night is over.
enum CurfewSlotPlan {
  struct Slot: Equatable, Sendable {
    /// `curfew.weeknight.h0` … `curfew.weekend.h6`
    let name: String
    let startMinuteOfDay: Int
    let endMinuteOfDay: Int
  }

  static let namePrefix = "curfew."
  /// Slots after the pause starts. Seven of `intervalMinutes` covers
  /// `CurfewPauseEvaluator.nightLengthMinutes` from `pauseStartsAt` onwards.
  static let slotsPerCurfew = 7
  static let intervalMinutes = 60
  static let minutesPerDay = 24 * 60

  /// The fourteen slots for `schedule`, weeknight first, in a stable order.
  /// Empty when the schedule is missing an hour or minute.
  static func slots(for schedule: CurfewSchedule) -> [Slot] {
    let kinds: [(String, DateComponents)] = [
      ("weeknight", schedule.weeknight),
      ("weekend", schedule.weekend),
    ]
    var result: [Slot] = []
    for (kind, curfew) in kinds {
      guard let hour = curfew.hour, let minute = curfew.minute else { continue }
      let pauseStartMinutes = hour * 60 + minute + schedule.graceMinutes
      for slot in 0..<slotsPerCurfew {
        let start = (pauseStartMinutes + slot * intervalMinutes) % minutesPerDay
        let end = (start + intervalMinutes) % minutesPerDay
        result.append(
          Slot(name: "\(namePrefix)\(kind).h\(slot)", startMinuteOfDay: start, endMinuteOfDay: end)
        )
      }
    }
    return result
  }
}
