import DeviceActivity
import Foundation

// Registers the DeviceActivity schedules that wake the monitor extension.
//
// `DeviceActivityEvent` thresholds measure app usage, not the clock, so the
// hourly re-check is fourteen repeating daily intervals instead: one per hour
// after the weeknight curfew (`curfew.weeknight.h0 … h6`) and one per hour
// after the weekend curfew (`curfew.weekend.h0 … h6`). Every slot fires every
// day; the monitor just calls `CurfewRuntime.reconcile`, and the evaluator
// decides by weekday which curfew applies. Each interval is 59 minutes so
// `intervalDidEnd` of slot h6 lands at the end of the seven-hour night.
//
// Needs on-device verification (the simulator cannot run DeviceActivity):
//   • the cap on concurrently monitored activities (commonly cited ~20; we
//     use 14, so the app must not register others alongside these);
//   • the 15-minute minimum interval (ours is 59);
//   • that a repeating interval whose end is earlier than its start (e.g.
//     23:30 → 00:29) is treated as spanning midnight.
struct CurfewActivityScheduler: Sendable {
  static let namePrefix = "curfew."
  /// Slots after curfew. Seven covers `CurfewPauseEvaluator.nightLengthMinutes`.
  static let hourlySlots = 0..<7
  static let intervalMinutes = 59

  /// Every `curfew.*` activity currently registered with the system.
  var registeredActivityNames: [DeviceActivityName] {
    DeviceActivityCenter().activities.filter { $0.rawValue.hasPrefix(Self.namePrefix) }
  }

  /// Registers the fourteen slots for `schedule`, replacing whatever was
  /// registered before. A nil or invalid schedule stops every `curfew.*`
  /// activity and leaves everything else the app monitors alone.
  func sync(schedule: CurfewSchedule?) throws {
    let center = DeviceActivityCenter()
    let existing = registeredActivityNames
    if !existing.isEmpty {
      center.stopMonitoring(existing)
    }
    guard let schedule, schedule.isValid else { return }

    for (name, activitySchedule) in Self.activities(for: schedule) {
      try center.startMonitoring(name, during: activitySchedule)
    }
  }

  /// The fourteen (name, schedule) pairs, in a stable order.
  static func activities(for schedule: CurfewSchedule) -> [(DeviceActivityName, DeviceActivitySchedule)] {
    let kinds: [(String, DateComponents)] = [
      ("weeknight", schedule.weeknight),
      ("weekend", schedule.weekend),
    ]
    var result: [(DeviceActivityName, DeviceActivitySchedule)] = []
    for (kind, curfew) in kinds {
      guard let hour = curfew.hour, let minute = curfew.minute else { continue }
      for slot in hourlySlots {
        let startMinutes = (hour * 60 + minute + slot * 60) % (24 * 60)
        let endMinutes = (startMinutes + intervalMinutes) % (24 * 60)
        let name = DeviceActivityName("\(namePrefix)\(kind).h\(slot)")
        let activity = DeviceActivitySchedule(
          intervalStart: components(minutesOfDay: startMinutes),
          intervalEnd: components(minutesOfDay: endMinutes),
          repeats: true
        )
        result.append((name, activity))
      }
    }
    return result
  }

  private static func components(minutesOfDay: Int) -> DateComponents {
    DateComponents(hour: minutesOfDay / 60, minute: minutesOfDay % 60, second: 0)
  }
}
