import CoreLocation
import Foundation
import Security
import UserNotifications

struct GuardianHomeAnchor: Codable, Equatable, Sendable {
  let latitude: Double
  let longitude: Double
  let savedAt: Date

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  func distance(to other: GuardianCoordinate) -> Double {
    CLLocation(latitude: latitude, longitude: longitude).distance(
      from: CLLocation(latitude: other.latitude, longitude: other.longitude)
    )
  }
}

protocol GuardianHomeStoring: Sendable {
  func load() throws -> GuardianHomeAnchor?
  func save(_ anchor: GuardianHomeAnchor) throws
  func delete() throws
}

struct KeychainGuardianHomeStore: GuardianHomeStoring {
  private let service = "com.soberprototype.app.guardian"
  private let account = "private-home-anchor-v1"

  func load() throws -> GuardianHomeAnchor? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw GuardianSessionStoreError.keychain(status)
    }
    return try JSONDecoder().decode(GuardianHomeAnchor.self, from: data)
  }

  func save(_ anchor: GuardianHomeAnchor) throws {
    let data = try JSONEncoder().encode(anchor)
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecItemNotFound {
      var addition = baseQuery
      attributes.forEach { addition[$0.key] = $0.value }
      let addStatus = SecItemAdd(addition as CFDictionary, nil)
      guard addStatus == errSecSuccess else { throw GuardianSessionStoreError.keychain(addStatus) }
    } else if updateStatus != errSecSuccess {
      throw GuardianSessionStoreError.keychain(updateStatus)
    }
  }

  func delete() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw GuardianSessionStoreError.keychain(status)
    }
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

struct GuardianCoordinate: Equatable, Sendable {
  let latitude: Double
  let longitude: Double
  let horizontalAccuracy: Double
}

@MainActor
protocol GuardianLocationProviding: Sendable {
  func currentCoordinate() async throws -> GuardianCoordinate
}

@MainActor
final class GuardianLocationService: NSObject, GuardianLocationProviding, @MainActor CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private var continuation: CheckedContinuation<GuardianCoordinate, any Error>?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
  }

  func currentCoordinate() async throws -> GuardianCoordinate {
    guard continuation == nil else { throw GuardianLocationError.requestInProgress }
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      continueAfterAuthorization(manager.authorizationStatus)
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard continuation != nil else { return }
    continueAfterAuthorization(manager.authorizationStatus)
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else {
      finish(.failure(GuardianLocationError.locationUnavailable))
      return
    }
    finish(.success(GuardianCoordinate(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      horizontalAccuracy: location.horizontalAccuracy
    )))
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    finish(.failure(error))
  }

  private func continueAfterAuthorization(_ status: CLAuthorizationStatus) {
    switch status {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      finish(.failure(GuardianLocationError.permissionDenied))
    @unknown default:
      finish(.failure(GuardianLocationError.locationUnavailable))
    }
  }

  private func finish(_ result: Result<GuardianCoordinate, any Error>) {
    let pending = continuation
    continuation = nil
    pending?.resume(with: result)
  }
}

enum GuardianLocationError: LocalizedError {
  case permissionDenied
  case locationUnavailable
  case preciseLocationRequired
  case requestInProgress

  var errorDescription: String? {
    switch self {
    case .permissionDenied: "Allow location while using Sober to check whether you’re at Home."
    case .locationUnavailable: "Sober couldn’t get a current location. Try again."
    case .preciseLocationRequired: "Sober needs a more precise location to save or compare Home. Turn on Precise Location in Settings and try again."
    case .requestInProgress: "Sober is already checking your location."
    }
  }
}

protocol GuardianCheckInScheduling: Sendable {
  func schedule(plan: GuardianCheckInPlanSnapshot) async throws -> Bool
  func cancel() async
}

actor SystemGuardianCheckInScheduler: GuardianCheckInScheduling {
  private let identifier = "sober.guardian.daily-check-in"

  func schedule(plan: GuardianCheckInPlanSnapshot) async throws -> Bool {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    let authorized: Bool
    switch settings.authorizationStatus {
    case .notDetermined:
      authorized = try await center.requestAuthorization(options: [.alert, .sound])
    case .authorized, .provisional, .ephemeral:
      authorized = true
    case .denied:
      authorized = false
    @unknown default:
      authorized = false
    }
    guard authorized, let time = plan.timeComponents else { return false }

    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = plan.timeZone
    components.hour = time.hour
    components.minute = time.minute

    let content = UNMutableNotificationContent()
    content.title = "Sober check-in"
    content.body = plan.condition == .awayFromHome
      ? "Open Sober to privately check whether tonight’s test applies."
      : "Your accepted Guardian check-in is ready."
    content.sound = .default
    content.userInfo = ["route": "guardian-check-in"]

    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    try await center.add(UNNotificationRequest(
      identifier: identifier,
      content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    ))
    return true
  }

  func cancel() async {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
  }
}
