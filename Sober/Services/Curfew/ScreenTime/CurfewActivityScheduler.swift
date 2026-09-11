import DeviceActivity
import Foundation

// Registers the DeviceActivity schedules that wake the monitor extension.
//
// The slots themselves come from `CurfewSlotPlan` (Services/Curfew/Core), which
// is pure and unit-tested: fourteen repeating daily intervals, one per hour
// from curfew plus grace for each curfew time (`curfew.weeknight.h0 … h6`,
// `curfew.weekend.h0 … h6`). Slot 0 starts when apps may first pause and the
// last slot ends at or after the end of the night, so `intervalDidStart` of
// h0 applies the pause on time and `intervalDidEnd` of h6 lifts it.
//
// Needs on-device verification (the simulator cannot run DeviceActivity):
//   • the cap on concurrently monitored activities (commonly cited ~20; we
//     use 14, so the app must not register others alongside these);
//   • the 15-minute minimum interval (ours is 60);
//   • that a repeating interval whose end is earlier than its start (e.g.
//     23:10 → 00:10) is treated as spanning midnight;
//   • that `intervalDidEnd` is not delivered ahead of the boundary. It is
//     what lifts the pause when the night ends, and a delivery even a second
//     early would leave the shield up until the next slot or app launch.
struct CurfewActivityScheduler: Sendable {
  static let namePrefix = CurfewSlotPlan.namePrefix

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

  /// The fourteen (name, schedule) pairs, in `CurfewSlotPlan` order.
  static func activities(for schedule: CurfewSchedule) -> [(DeviceActivityName, DeviceActivitySchedule)] {
    CurfewSlotPlan.slots(for: schedule).map { slot in
      (
        DeviceActivityName(slot.name),
        DeviceActivitySchedule(
          intervalStart: components(minutesOfDay: slot.startMinuteOfDay),
          intervalEnd: components(minutesOfDay: slot.endMinuteOfDay),
          repeats: true
        )
      )
    }
  }

  private static func components(minutesOfDay: Int) -> DateComponents {
    DateComponents(hour: minutesOfDay / 60, minute: minutesOfDay % 60, second: 0)
  }
}
