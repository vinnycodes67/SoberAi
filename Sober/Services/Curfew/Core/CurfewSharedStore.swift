import Foundation

// State shared between SoberInternal and its four Curfew extensions through
// one App Group container. Everything here stays on the teen's phone except
// the `outbox`, which holds check-ins waiting to reach Vinay's backend.
//
// Compiles into every target, so: Foundation only.

enum CurfewAppGroup {
  /// Must match `com.apple.security.application-groups` in every Curfew
  /// entitlements file (see project.yml).
  static let identifier = "group.com.soberprototype.internal.curfew"
  static let stateKey = "curfew.shared-state.v1"
}

/// The pending in-app destination written by the shield action extension and
/// consumed by the app on its next activation.
enum CurfewPendingRoute: String, Codable, Sendable {
  case checkIn
}

struct CurfewSharedState: Codable, Equatable, Sendable {
  var schedule: CurfewSchedule?
  /// `FamilyActivitySelection` for "What to pause", JSON-encoded. Opaque here;
  /// only the Screen Time layer decodes it. Never leaves the device.
  var pauseSelectionData: Data?
  /// `FamilyActivitySelection` for "Always allow" (ride apps, Maps).
  var allowSelectionData: Data?
  var home: CurfewHomeReading?
  var tonight: CurfewTonight?
  /// Check-ins recorded locally but not yet delivered. Oldest first.
  var outbox: [CurfewCheckIn]
  /// For "Jordan promised: no questions tonight." Nil until the guardian signs.
  var guardianDisplayName: String?
  var safeRidePromiseSignedAt: Date?
  var pendingRoute: CurfewPendingRoute?
  /// Last thing the runtime did to the named ManagedSettings store.
  var isShieldApplied: Bool
  var shieldChangedAt: Date?

  init(
    schedule: CurfewSchedule? = nil,
    pauseSelectionData: Data? = nil,
    allowSelectionData: Data? = nil,
    home: CurfewHomeReading? = nil,
    tonight: CurfewTonight? = nil,
    outbox: [CurfewCheckIn] = [],
    guardianDisplayName: String? = nil,
    safeRidePromiseSignedAt: Date? = nil,
    pendingRoute: CurfewPendingRoute? = nil,
    isShieldApplied: Bool = false,
    shieldChangedAt: Date? = nil
  ) {
    self.schedule = schedule
    self.pauseSelectionData = pauseSelectionData
    self.allowSelectionData = allowSelectionData
    self.home = home
    self.tonight = tonight
    self.outbox = outbox
    self.guardianDisplayName = guardianDisplayName
    self.safeRidePromiseSignedAt = safeRidePromiseSignedAt
    self.pendingRoute = pendingRoute
    self.isShieldApplied = isShieldApplied
    self.shieldChangedAt = shieldChangedAt
  }

  /// Setup is complete once there is a schedule and a pause selection. The
  /// allow list may legitimately be empty; the ride path is exempt regardless.
  var isConfigured: Bool { schedule != nil && pauseSelectionData != nil }

  /// Records a check-in for `night`, starting a fresh record when the night
  /// changed, and queues it for delivery. Non-reportable statuses are refused.
  @discardableResult
  mutating func record(_ checkIn: CurfewCheckIn, for night: CurfewNight) -> Bool {
    guard checkIn.isReportable else { return false }
    if tonight?.nightID != night.id {
      tonight = CurfewTonight(nightID: night.id)
    }
    tonight?.checkIns.append(checkIn)
    outbox.append(checkIn)
    return true
  }

  mutating func markDelivered(_ ids: Set<UUID>) {
    outbox.removeAll { ids.contains($0.id) }
  }
}

protocol CurfewStateStoring: Sendable {
  func load() -> CurfewSharedState
  func save(_ state: CurfewSharedState) throws
}

extension CurfewStateStoring {
  /// Read-modify-write in one place so callers cannot forget to save.
  @discardableResult
  func update<T>(_ body: (inout CurfewSharedState) throws -> T) throws -> T {
    var state = load()
    let result = try body(&state)
    try save(state)
    return result
  }
}

enum CurfewStoreError: Error, Equatable {
  case appGroupUnavailable
}

/// App Group `UserDefaults`, JSON-encoded under one key. A missing container
/// (an extension built without the entitlement, or a simulator quirk) reads as
/// an empty state — which pauses nothing — and refuses to save rather than
/// silently writing somewhere the extensions cannot see.
struct AppGroupCurfewStore: CurfewStateStoring {
  let suiteName: String

  init(suiteName: String = CurfewAppGroup.identifier) {
    self.suiteName = suiteName
  }

  func load() -> CurfewSharedState {
    guard let defaults = UserDefaults(suiteName: suiteName),
      let data = defaults.data(forKey: CurfewAppGroup.stateKey),
      let state = try? Self.decoder.decode(CurfewSharedState.self, from: data)
    else { return CurfewSharedState() }
    return state
  }

  func save(_ state: CurfewSharedState) throws {
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw CurfewStoreError.appGroupUnavailable
    }
    let data = try Self.encoder.encode(state)
    defaults.set(data, forKey: CurfewAppGroup.stateKey)
  }

  private static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  private static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

/// For tests and previews.
final class InMemoryCurfewStore: CurfewStateStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var state: CurfewSharedState

  init(state: CurfewSharedState = CurfewSharedState()) {
    self.state = state
  }

  func load() -> CurfewSharedState {
    lock.lock()
    defer { lock.unlock() }
    return state
  }

  func save(_ state: CurfewSharedState) throws {
    lock.lock()
    defer { lock.unlock() }
    self.state = state
  }
}
