import Foundation

// Interfaces the teen UI codes against. The Screen Time and Live Activity
// layers implement them; tests use the in-memory fakes at the bottom.

enum CurfewAuthorizationStatus: Equatable, Sendable {
  case notDetermined
  case approved
  case denied
  /// Family Controls is unavailable here (simulator, or the framework refused).
  case unavailable
}

enum CurfewHomeAuthorization: Equatable, Sendable {
  case notDetermined
  case whenInUse
  case always
  case denied
  case unavailable
}

/// Screen Time authorization, pause/lift, and DeviceActivity scheduling.
/// Implemented by `CurfewDeviceController` in Services/Curfew/ScreenTime.
@MainActor
protocol CurfewDeviceControlling: AnyObject {
  var authorizationStatus: CurfewAuthorizationStatus { get }
  func refreshAuthorizationStatus()
  func requestAuthorization() async -> CurfewAuthorizationStatus

  /// Reads the shared store, evaluates, applies or lifts the pause, and
  /// returns the decision. Safe to call often; idempotent.
  @discardableResult
  func reconcile(now: Date) -> CurfewPauseDecision

  /// (Re)registers DeviceActivity schedules for the stored schedule, or stops
  /// monitoring when there is none.
  func syncMonitoring() throws

  /// Number of hourly activities currently registered. For the setup screen.
  var monitoredActivityCount: Int { get }

  #if DEBUG
  func debugPauseNow()
  func debugLiftNow()
  #endif
}

/// Home region monitoring in the main app. Writes `CurfewHomeReading` into the
/// shared store. Implemented by `CurfewHomeMonitor` in Services/Curfew/HomeRegion.
@MainActor
protocol CurfewHomeMonitoring: AnyObject {
  var authorization: CurfewHomeAuthorization { get }
  var onAuthorizationChange: ((CurfewHomeAuthorization) -> Void)? { get set }
  var onHomeReading: ((CurfewHomeReading) -> Void)? { get set }
  func requestAlwaysAuthorization()
  /// Starts monitoring the private home anchor, if one is configured.
  func start()
  func stop()
  /// One-shot location for a check-in payload. Nil if unavailable within a
  /// few seconds; a check-in is never blocked on location.
  func currentLocation() async -> CurfewLocationFix?
}

struct CurfewLocationFix: Equatable, Sendable {
  let latitude: Double
  let longitude: Double
  let horizontalAccuracyMeters: Double
  let capturedAt: Date
}

/// Lock Screen / Dynamic Island countdown. Implemented by
/// `CurfewLiveActivityController` in Services/Curfew/LiveActivity.
@MainActor
protocol CurfewLiveActivityControlling: AnyObject {
  /// Starts, updates, or ends the countdown to match `decision`.
  func sync(decision: CurfewPauseDecision, guardianName: String?) async
  func endAll() async
}

/// Delivery of queued check-ins to the guardian's side. Vinay's backend does
/// not expose a Curfew route yet; `UnconfiguredCurfewCheckInSender` keeps every
/// check-in queued locally until it does.
protocol CurfewCheckInSending: Sendable {
  func send(_ checkIn: CurfewCheckIn) async throws
}

enum CurfewCheckInSendError: Error, Equatable {
  case notConfigured
}

struct UnconfiguredCurfewCheckInSender: CurfewCheckInSending {
  func send(_ checkIn: CurfewCheckIn) async throws {
    throw CurfewCheckInSendError.notConfigured
  }
}

/// Drains the outbox oldest-first and stops at the first failure so ordering
/// is preserved. Nothing is dropped on failure — a dead phone is not a missed
/// curfew, and neither is a dead network.
struct CurfewOutboxFlusher: Sendable {
  let store: any CurfewStateStoring
  let sender: any CurfewCheckInSending

  /// Returns the number of check-ins delivered.
  @discardableResult
  func flush() async -> Int {
    let pending = store.load().outbox.filter(\.isReportable)
    var delivered: Set<UUID> = []
    for checkIn in pending {
      do {
        try await sender.send(checkIn)
        delivered.insert(checkIn.id)
      } catch {
        break
      }
    }
    if !delivered.isEmpty {
      try? store.update { $0.markDelivered(delivered) }
    }
    return delivered.count
  }
}
