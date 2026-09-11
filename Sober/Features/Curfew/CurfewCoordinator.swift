import Combine
import FamilyControls
import Foundation
import UserNotifications

// The teen-side owner of Curfew at runtime. It wires the shared store, the
// Screen Time controller, the home region monitor, the Lock Screen countdown,
// and the outbox together, and exposes one decision to the screens.
//
// It knows nothing about Sober checks. No screening type is imported or read
// here, so there is no code path by which a result could touch the pause.

@MainActor
final class CurfewCoordinator: ObservableObject {
  @Published private(set) var decision: CurfewPauseDecision = .noSchedule
  @Published private(set) var state = CurfewSharedState()
  @Published var isPresentingCheckIn = false
  @Published var lastError: String?
  @Published private(set) var homeAuthorization: CurfewHomeAuthorization = .notDetermined

  let store: any CurfewStateStoring
  let device: CurfewDeviceController
  let home: CurfewHomeMonitor
  let liveActivity: CurfewLiveActivityController

  private let flusher: CurfewOutboxFlusher
  private let notificationDelegate = CurfewNotificationDelegate()
  private var deviceObservation: AnyCancellable?
  private var hasStarted = false

  /// `sender` is the injection point for delivery to the guardian's side.
  /// Vinay's backend has no Curfew route yet, so the default keeps every
  /// check-in queued locally until one exists.
  init(
    store: any CurfewStateStoring = AppGroupCurfewStore(),
    sender: any CurfewCheckInSending = UnconfiguredCurfewCheckInSender()
  ) {
    self.store = store
    device = CurfewDeviceController(store: store)
    home = CurfewHomeMonitor(store: store)
    liveActivity = CurfewLiveActivityController()
    flusher = CurfewOutboxFlusher(store: store, sender: sender)
    state = store.load()
    // The controller publishes authorization on its own; re-emit so a screen
    // observing only the coordinator still redraws.
    deviceObservation = device.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
    }
  }

  var screenTimeAuthorization: CurfewAuthorizationStatus { device.authorizationStatus }

  // MARK: - Lifecycle

  func start() {
    guard !hasStarted else { return }
    hasStarted = true

    CurfewNotifications.registerCategories()
    notificationDelegate.onCheckInResponse = { [weak self] in self?.openCheckIn() }
    UNUserNotificationCenter.current().delegate = notificationDelegate

    home.onAuthorizationChange = { [weak self] authorization in
      self?.homeAuthorization = authorization
    }
    home.onHomeReading = { [weak self] _ in self?.refresh() }
    homeAuthorization = home.authorization
    home.start()

    device.refreshAuthorizationStatus()
    sceneBecameActive()
    Task { await flusher.flush() }
  }

  /// Reconciles, then consumes a route left by the shield action extension.
  func sceneBecameActive() {
    refresh()
    var shouldPresent = decision.shouldPause
    if state.pendingRoute == .checkIn {
      do {
        try store.update { $0.pendingRoute = nil }
      } catch {
        lastError = Self.message(for: error)
      }
      state = store.load()
      shouldPresent = true
    }
    if shouldPresent { openCheckIn() }
  }

  /// `sober-internal://curfew/check-in`, posted by the shield action button.
  @discardableResult
  func handle(url: URL) -> Bool {
    guard url.scheme?.lowercased() == "sober-internal",
      url.host?.lowercased() == "curfew",
      url.path == "/check-in"
    else { return false }
    openCheckIn()
    return true
  }

  /// Re-reads the store, re-applies or lifts the pause, and updates the countdown.
  func refresh(now: Date = Date()) {
    decision = device.reconcile(now: now)
    state = store.load()
    let decision = decision
    let guardianName = state.guardianDisplayName
    Task { await liveActivity.sync(decision: decision, guardianName: guardianName) }
  }

  // MARK: - Setup

  func requestScreenTimeAuthorization() async {
    _ = await device.requestAuthorization()
    _ = await CurfewNotifications.requestAuthorizationIfNeeded()
    refresh()
  }

  func requestHomeAuthorization() {
    home.requestAlwaysAuthorization()
    homeAuthorization = home.authorization
  }

  func saveSchedule(_ schedule: CurfewSchedule) {
    do {
      try store.update { $0.schedule = schedule }
      try device.syncMonitoring()
      lastError = nil
    } catch {
      lastError = Self.message(for: error)
    }
    refresh()
    Task { _ = await CurfewNotifications.requestAuthorizationIfNeeded() }
  }

  func savePauseSelection(_ selection: FamilyActivitySelection) {
    do {
      try device.savePauseSelection(selection)
      lastError = nil
    } catch {
      lastError = Self.message(for: error)
    }
    refresh()
  }

  func saveAllowSelection(_ selection: FamilyActivitySelection) {
    do {
      try device.saveAllowSelection(selection)
      lastError = nil
    } catch {
      lastError = Self.message(for: error)
    }
    refresh()
  }

  func setGuardianName(_ name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      try store.update { $0.guardianDisplayName = trimmed.isEmpty ? nil : trimmed }
    } catch {
      lastError = Self.message(for: error)
    }
    state = store.load()
  }

  /// Placeholder. The Safe Ride Promise is signed on the guardian's phone and
  /// will arrive through the shared contract once Vinay's side supplies it;
  /// until then this only stamps the local state so the screens can render.
  func signSafeRidePromise() {
    do {
      try store.update { $0.safeRidePromiseSignedAt = Date() }
    } catch {
      lastError = Self.message(for: error)
    }
    state = store.load()
  }

  // MARK: - Check-in

  /// Records "I'm OK" or "I need a ride" and lifts the pause. The payload is
  /// the same whether or not a Sober check was run tonight.
  ///
  /// `dismissingCheckIn` is false for the ride path so the sheet can stay up
  /// long enough to show the Safe Ride Promise after the ride app opens.
  func checkIn(_ status: CurfewStatus, dismissingCheckIn: Bool = true) async {
    guard status.isReportable else { return }

    // The monitor gives up on its own after a few seconds; nil is fine.
    let fix = await home.currentLocation()
    let now = Date()
    let checkIn = CurfewCheckIn(
      at: now,
      status: status,
      latitude: fix?.latitude,
      longitude: fix?.longitude,
      horizontalAccuracyMeters: fix?.horizontalAccuracyMeters
    )

    // Evaluate against the current clock so the record lands on the right
    // night. `.beforeCurfew` still carries the next night, so an early check-in
    // is kept rather than lost; only "no schedule at all" is refused.
    decision = device.reconcile(now: now)
    guard let night = decision.night else {
      lastError = "There is no curfew schedule on this iPhone yet, so there is nothing to check in to."
      if dismissingCheckIn { isPresentingCheckIn = false }
      return
    }

    do {
      try store.update { $0.record(checkIn, for: night) }
      lastError = nil
    } catch {
      lastError = Self.message(for: error)
    }

    refresh(now: now)
    CurfewNotifications.clearCheckInDue()
    await liveActivity.sync(decision: decision, guardianName: state.guardianDisplayName)
    await flusher.flush()
    state = store.load()
    if dismissingCheckIn { isPresentingCheckIn = false }
  }

  // MARK: - Debug

  #if DEBUG
  /// Applies the shield directly. Not followed by a reconcile, which would
  /// lift it again straight away.
  func debugPauseNow() {
    device.debugPauseNow()
    state = store.load()
  }

  func debugLiftNow() {
    device.debugLiftNow()
    state = store.load()
  }
  #endif

  // MARK: - Private

  private func openCheckIn() {
    refresh()
    CurfewNotifications.clearCheckInDue()
    isPresentingCheckIn = true
  }

  private static func message(for error: Error) -> String {
    if let storeError = error as? CurfewStoreError, storeError == .appGroupUnavailable {
      return "This iPhone could not save Curfew settings. Reinstall Sober Internal to fix the shared container."
    }
    return error.localizedDescription
  }
}

/// Receives notification taps off the main actor and forwards the Curfew ones
/// on it. Only the check-in category is handled; the Guardian reminder keeps
/// its own `route` and is left alone.
final class CurfewNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  @MainActor var onCheckInResponse: (() -> Void)?

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let content = response.notification.request.content
    let isCurfew = content.categoryIdentifier == CurfewNotifications.checkInCategoryIdentifier
      || content.userInfo[CurfewNotifications.routeUserInfoKey] != nil
    guard isCurfew else { return }
    await MainActor.run { onCheckInResponse?() }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }
}
