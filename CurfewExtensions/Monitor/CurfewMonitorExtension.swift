import DeviceActivity
import Foundation

/// Applies or lifts the curfew pause on schedule. Stub; the Screen Time agent
/// fills this in by delegating to the shared runtime.
final class CurfewMonitorExtension: DeviceActivityMonitor {
  override func intervalDidStart(for activity: DeviceActivityName) {
    super.intervalDidStart(for: activity)
  }

  override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
  }
}
