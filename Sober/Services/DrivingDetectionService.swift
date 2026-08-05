import AVFoundation
import BackgroundTasks
import CoreMotion
import Foundation

/// Detects the start of a drive using two independent, corroborating
/// signals rather than one: Core Motion's `.automotive` activity state and
/// a Bluetooth/CarPlay audio-route connection. Either signal alone is
/// enough to raise `onDriveDetected` — requiring both at once would miss a
/// car with no phone-paired audio, and requiring motion alone misses the
/// moment right after connecting before the phone has accelerated.
///
/// Background delivery of both signals is opportunistic. Core Motion can
/// wake a suspended app for activity updates, but iOS controls the timing;
/// `scheduleBackgroundCatchUp()` submits a `BGAppRefreshTask` that queries
/// Core Motion's on-device history to catch drives that started while the
/// app was fully suspended. There is no way to query Bluetooth route
/// history retroactively, so a Bluetooth-only connection made while fully
/// suspended can be missed until the app is next foregrounded. This
/// service never reports a drive it didn't actually observe — a phone
/// that's off or left behind produces no signal and triggers no alert.
@MainActor
final class DrivingDetectionService: NSObject, ObservableObject {
  @Published private(set) var isLikelyDriving = false

  var onDriveDetected: (() -> Void)?

  static let backgroundTaskIdentifier = "com.soberprototype.app.driving-catchup"

  private let motionManager = CMMotionActivityManager()
  private var lastMotionQueryEndedAt: Date?
  private var hasSignaledCurrentDrive = false

  var isMotionAvailable: Bool { CMMotionActivityManager.isActivityAvailable() }

  func start() {
    lastMotionQueryEndedAt = lastMotionQueryEndedAt ?? Date()
    startMotionUpdates()
    startAudioRouteObservation()
  }

  func stop() {
    motionManager.stopActivityUpdates()
    NotificationCenter.default.removeObserver(
      self, name: AVAudioSession.routeChangeNotification, object: nil)
  }

  private func startMotionUpdates() {
    guard isMotionAvailable else { return }
    motionManager.startActivityUpdates(to: .main) { [weak self] activity in
      guard let self, let activity else { return }
      self.evaluateDrivingSignal(
        motionSaysAutomotive: activity.automotive && activity.confidence != .low)
    }
  }

  private func startAudioRouteObservation() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(audioRouteChanged),
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )
    evaluateDrivingSignal(motionSaysAutomotive: false)
  }

  @objc private func audioRouteChanged(_ notification: Notification) {
    evaluateDrivingSignal(motionSaysAutomotive: false)
  }

  private func currentRouteLooksLikeCar() -> Bool {
    let carPortTypes: Set<AVAudioSession.Port> = [
      .carAudio, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE,
    ]
    return AVAudioSession.sharedInstance().currentRoute.outputs.contains {
      carPortTypes.contains($0.portType)
    }
  }

  /// Combines both signals every time, regardless of which one triggered
  /// this call — a motion update re-checks the current audio route too,
  /// and an audio route change re-evaluates against the last motion
  /// reading being implicitly "not automotive" until the next update.
  private func evaluateDrivingSignal(motionSaysAutomotive: Bool) {
    isLikelyDriving = motionSaysAutomotive || currentRouteLooksLikeCar()
    if isLikelyDriving, !hasSignaledCurrentDrive {
      hasSignaledCurrentDrive = true
      onDriveDetected?()
    } else if !isLikelyDriving {
      hasSignaledCurrentDrive = false
    }
  }

  // MARK: - Background catch-up

  /// Call once at app launch, before the app finishes launching, so the
  /// system can hand control back to `handler` even after the process was
  /// fully suspended.
  static func registerBackgroundTask(handler: @escaping (BGAppRefreshTask) -> Void) {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: backgroundTaskIdentifier, using: nil
    ) { task in
      guard let refreshTask = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      handler(refreshTask)
    }
  }

  func scheduleBackgroundCatchUp() {
    let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }

  /// Queries Core Motion's on-device activity history since the last
  /// check-in to catch a drive that started while the app was suspended.
  /// Completes the task itself; the caller only needs to reschedule.
  func runBackgroundCatchUp(task: BGAppRefreshTask) {
    scheduleBackgroundCatchUp()

    guard isMotionAvailable else {
      task.setTaskCompleted(success: true)
      return
    }

    let start = lastMotionQueryEndedAt ?? Date(timeIntervalSinceNow: -30 * 60)
    let end = Date()
    task.expirationHandler = { [weak self] in
      self?.motionManager.stopActivityUpdates()
    }

    motionManager.queryActivityStarting(from: start, to: end, to: .main) { [weak self] activities, _ in
      guard let self else {
        task.setTaskCompleted(success: false)
        return
      }
      self.lastMotionQueryEndedAt = end
      let sawDriving = activities?.contains { $0.automotive && $0.confidence != .low } ?? false
      if sawDriving {
        self.evaluateDrivingSignal(motionSaysAutomotive: true)
      }
      task.setTaskCompleted(success: true)
    }
  }
}
