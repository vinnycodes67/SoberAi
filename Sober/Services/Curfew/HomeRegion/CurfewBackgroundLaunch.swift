import Foundation

// iOS relaunches the app in the background when the teen crosses the home
// region, but only hands the event to a `CLLocationManager` delegate that
// exists by the end of launch. A background launch connects no scene, so
// nothing in the view tree (and so no `CurfewCoordinator`) is ever created.
// This holds one `CurfewHomeMonitor` from `SoberApp.init` for the life of the
// process, so the arrival is recorded and the pause lifted through
// `CurfewRuntime.reconcile` whether or not a screen ever appears. The
// coordinator shares this same monitor rather than creating a second one.
@MainActor
enum CurfewBackgroundLaunch {
  private(set) static var homeMonitor: CurfewHomeMonitor?
  private static let liveActivity = CurfewLiveActivityController()

  /// Call once, as early in launch as possible. Idempotent.
  static func prepare() {
    guard homeMonitor == nil else { return }
    let monitor = CurfewHomeMonitor()
    // Until a coordinator takes over this callback, keep the Lock Screen in
    // step too: ending or updating an activity is allowed from the background,
    // and a "Check-in due" banner must not outlive the arrival home.
    monitor.onHomeReading = { _ in syncLiveActivity() }
    monitor.start()
    homeMonitor = monitor
  }

  private static func syncLiveActivity() {
    let state = AppGroupCurfewStore().load()
    let decision = CurfewPauseEvaluator.evaluate(
      now: Date(),
      schedule: state.schedule,
      home: state.home,
      tonight: state.tonight
    )
    let guardianName = state.guardianDisplayName
    Task { await liveActivity.sync(decision: decision, guardianName: guardianName) }
  }
}
