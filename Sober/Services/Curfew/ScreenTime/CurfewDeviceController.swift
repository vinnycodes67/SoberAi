import Combine
import DeviceActivity
@preconcurrency import FamilyControls
import Foundation
import ManagedSettings

// The teen UI's handle on Screen Time: authorization, the two picker
// selections, the pause itself, and the DeviceActivity schedules. Everything
// that decides *whether* to pause lives in `CurfewRuntime`; this class only
// owns the main-actor state the screens observe.
@MainActor
final class CurfewDeviceController: ObservableObject, CurfewDeviceControlling {
  let store: any CurfewStateStoring

  @Published private(set) var authorizationStatus: CurfewAuthorizationStatus = .notDetermined

  private let shield = CurfewShieldController()
  private let scheduler = CurfewActivityScheduler()

  init(store: any CurfewStateStoring = AppGroupCurfewStore()) {
    self.store = store
    refreshAuthorizationStatus()
  }

  // MARK: Authorization

  func refreshAuthorizationStatus() {
    authorizationStatus = Self.map(AuthorizationCenter.shared.authorizationStatus)
  }

  /// Asks for child authorization; the guardian approves through Family
  /// Sharing. Never throws out: a refusal or a device that cannot do Family
  /// Controls (simulator, adult Apple ID) reads as denied or unavailable.
  func requestAuthorization() async -> CurfewAuthorizationStatus {
    do {
      try await AuthorizationCenter.shared.requestAuthorization(for: .child)
      refreshAuthorizationStatus()
    } catch let error as FamilyControlsError {
      refreshAuthorizationStatus()
      if authorizationStatus == .notDetermined {
        authorizationStatus = Self.map(error)
      }
    } catch {
      refreshAuthorizationStatus()
      if authorizationStatus == .notDetermined {
        authorizationStatus = .unavailable
      }
    }
    return authorizationStatus
  }

  private static func map(_ status: AuthorizationStatus) -> CurfewAuthorizationStatus {
    switch status {
    case .notDetermined: .notDetermined
    case .denied: .denied
    case .approved: .approved
    @unknown default: .approved
    }
  }

  private static func map(_ error: FamilyControlsError) -> CurfewAuthorizationStatus {
    switch error {
    case .authorizationCanceled, .restricted: .denied
    case .unavailable, .invalidAccountType, .invalidArgument, .authorizationConflict,
      .networkError, .authenticationMethodUnavailable: .unavailable
    @unknown default: .unavailable
    }
  }

  // MARK: Pause

  @discardableResult
  func reconcile(now: Date = Date()) -> CurfewPauseDecision {
    CurfewRuntime.reconcile(now: now, store: store, shield: shield)
  }

  // MARK: Scheduling

  func syncMonitoring() throws {
    try scheduler.sync(schedule: store.load().schedule)
  }

  var monitoredActivityCount: Int {
    scheduler.registeredActivityNames.count
  }

  // MARK: Picker selections

  /// "What to pause". Throws `CurfewStoreError.appGroupUnavailable` if the
  /// shared container is missing; the tokens never leave this device.
  func savePauseSelection(_ selection: FamilyActivitySelection) throws {
    let data = try CurfewSelectionCodec.encode(selection)
    try store.update { $0.pauseSelectionData = data }
  }

  /// "Always allow": ride apps, Maps, Messages. Exempt from the pause.
  func saveAllowSelection(_ selection: FamilyActivitySelection) throws {
    let data = try CurfewSelectionCodec.encode(selection)
    try store.update { $0.allowSelectionData = data }
  }

  /// Nil until the teen has picked something to pause.
  func loadPauseSelection() -> FamilyActivitySelection? {
    CurfewSelectionCodec.decode(store.load().pauseSelectionData)
  }

  /// Nil until the teen has picked an allow list; the ride path is exempt
  /// regardless because it is never in the pause list by construction.
  func loadAllowSelection() -> FamilyActivitySelection? {
    CurfewSelectionCodec.decode(store.load().allowSelectionData)
  }

  // MARK: Debug

  #if DEBUG
  /// Milestone 1: apply the stored selections right now, ignoring the clock.
  /// The next `reconcile` puts things back the way the evaluator wants them.
  func debugPauseNow() {
    guard let pause = loadPauseSelection() else { return }
    shield.apply(pause: pause, allow: loadAllowSelection() ?? FamilyActivitySelection())
    try? store.update { state in
      state.isShieldApplied = true
      state.shieldChangedAt = Date()
    }
  }

  func debugLiftNow() {
    shield.lift()
    CurfewNotifications.clearCheckInDue()
    try? store.update { state in
      state.isShieldApplied = false
      state.shieldChangedAt = Date()
    }
  }
  #endif
}
