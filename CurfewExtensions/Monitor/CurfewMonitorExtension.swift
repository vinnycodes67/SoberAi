import DeviceActivity
import Foundation

/// Wakes at each hourly curfew slot and makes the phone match the evaluator.
/// This process has a few megabytes of memory, so it does exactly one thing:
/// call the shared runtime. Which curfew applies, whether the teen is home,
/// and whether they checked in are all decided inside `CurfewRuntime`.
final class CurfewMonitorExtension: DeviceActivityMonitor {
  override func intervalDidStart(for activity: DeviceActivityName) {
    super.intervalDidStart(for: activity)
    CurfewRuntime.reconcile(store: AppGroupCurfewStore())
  }

  override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
    CurfewRuntime.reconcile(store: AppGroupCurfewStore())
  }

  override func intervalWillStartWarning(for activity: DeviceActivityName) {
    super.intervalWillStartWarning(for: activity)
    CurfewRuntime.reconcile(store: AppGroupCurfewStore())
  }
}
