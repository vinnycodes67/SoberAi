import BackgroundTasks
import CloudKit
import Foundation

/// Ties the driving schedule, drive detection, and CloudKit pairing
/// together. Owned once at the app level (not per-screening-session) so
/// drive detection keeps running for the whole time the app process is
/// alive, independent of which screen is on top.
///
/// This coordinator never sees a biometric score. The teen side calls
/// `recordScreeningResult(isValid:)` with only the fact that a check
/// finished and whether it was conclusive — the actual `ScreeningOutcome`
/// never crosses this boundary.
@MainActor
final class GuardianCoordinator: ObservableObject {
  @Published private(set) var parentEvents: [GuardianSyncEvent] = []
  @Published private(set) var lastSyncError: String?

  let pairing = GuardianPairingService()
  private let detector = DrivingDetectionService()

  private weak var model: AppModel?
  private var subscriptionConfigured = false

  func configure(model: AppModel) {
    self.model = model
    detector.onDriveDetected = { [weak self] in
      Task { @MainActor [weak self] in
        await self?.handleDriveDetected()
      }
    }
  }

  // MARK: - Teen side

  func startTeenMonitoring() {
    guard model?.guardianRole == .teen else { return }
    detector.start()
    detector.scheduleBackgroundCatchUp()
  }

  func stopTeenMonitoring() {
    detector.stop()
  }

  /// Called whenever a screening check finishes, live (never a sample).
  /// `isValid` is false for INCONCLUSIVE, which never counts toward
  /// satisfying the window and never syncs anything.
  func recordScreeningResult(isValid: Bool, at date: Date = Date()) async {
    guard let model, model.guardianRole == .teen,
      let window = model.drivingSchedule.window(containing: date)
    else { return }

    var state = model.guardianCheckWindowState(for: window.id)
    guard isValid else { return }

    let wasAlreadySatisfied = state.isSatisfied
    state.recordValidResult(at: date)
    model.setGuardianCheckWindowState(state)

    guard !wasAlreadySatisfied else { return }
    do {
      try await pairing.send(
        GuardianSyncEvent(windowID: window.id, outcome: .completed, occurredAt: date))
    } catch {
      lastSyncError = error.localizedDescription
    }
  }

  private func handleDriveDetected() async {
    guard let model, model.guardianRole == .teen,
      let window = model.drivingSchedule.window(containing: Date())
    else { return }

    var state = model.guardianCheckWindowState(for: window.id)
    guard !state.isSatisfied, !state.missedAlertSent else { return }

    state.missedAlertSent = true
    model.setGuardianCheckWindowState(state)

    do {
      try await pairing.send(
        GuardianSyncEvent(windowID: window.id, outcome: .missed, occurredAt: Date()))
    } catch {
      lastSyncError = error.localizedDescription
    }
  }

  // MARK: - Parent side

  func startParentMonitoring() {
    guard model?.guardianRole == .parent else { return }
    Task { await configureSubscriptionIfNeeded() }
    Task { await refreshParentEvents() }
  }

  /// Subscribes to "missed" events in the shared zone so CloudKit delivers
  /// a push automatically — no custom server involved. Idempotent: safe to
  /// call every launch.
  private func configureSubscriptionIfNeeded() async {
    guard !subscriptionConfigured, let zoneID = pairing.sharedZoneID else { return }
    subscriptionConfigured = true

    let predicate = NSPredicate(format: "outcome == %@", GuardianCheckOutcome.missed.rawValue)
    let subscription = CKQuerySubscription(
      recordType: GuardianPairingService.checkEventRecordType,
      predicate: predicate,
      subscriptionID: "guardian-missed-check",
      options: [.firesOnRecordCreation]
    )
    let notificationInfo = CKSubscription.NotificationInfo()
    notificationInfo.alertBody = "Your teen hasn't completed tonight's check yet."
    notificationInfo.soundName = "default"
    notificationInfo.shouldSendContentAvailable = true
    subscription.notificationInfo = notificationInfo
    subscription.zoneID = zoneID

    do {
      _ = try await CKContainer.default().sharedCloudDatabase.modifySubscriptions(
        saving: [subscription], deleting: [])
    } catch {
      lastSyncError = error.localizedDescription
    }
  }

  /// Refreshes the parent's local view of recent completed/missed facts.
  /// Called on launch and whenever a CloudKit push arrives.
  func refreshParentEvents() async {
    guard let zoneID = pairing.sharedZoneID else { return }
    do {
      let query = CKQuery(
        recordType: GuardianPairingService.checkEventRecordType,
        predicate: NSPredicate(value: true)
      )
      query.sortDescriptors = [NSSortDescriptor(key: "occurredAt", ascending: false)]
      let (results, _) = try await CKContainer.default().sharedCloudDatabase.records(
        matching: query, inZoneWith: zoneID, resultsLimit: 20)

      parentEvents = results.compactMap { _, result -> GuardianSyncEvent? in
        guard case .success(let record) = result,
          let windowID = record["windowID"] as? Date,
          let outcomeRaw = record["outcome"] as? String,
          let outcome = GuardianCheckOutcome(rawValue: outcomeRaw),
          let occurredAt = record["occurredAt"] as? Date
        else { return nil }
        return GuardianSyncEvent(windowID: windowID, outcome: outcome, occurredAt: occurredAt)
      }
      lastSyncError = nil
    } catch {
      lastSyncError = error.localizedDescription
    }
  }

  /// Called from the app delegate when a CloudKit remote notification
  /// arrives, so the parent's dashboard reflects a missed check without
  /// needing to reopen the app.
  func handleRemoteNotification() async {
    await refreshParentEvents()
  }

  func runBackgroundCatchUp(task: BGAppRefreshTask) {
    detector.runBackgroundCatchUp(task: task)
  }

  static func registerBackgroundTask(handler: @escaping (BGAppRefreshTask) -> Void) {
    DrivingDetectionService.registerBackgroundTask(handler: handler)
  }
}
