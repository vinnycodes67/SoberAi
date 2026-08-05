import CoreLocation
import Foundation

enum GuardianLocationAuthorizationState: Equatable, Sendable {
  case notDetermined
  case foregroundOnly
  case background
  case denied
  case restricted
  case unavailable
}

struct GuardianLiveLocationUpdate: Equatable, Sendable {
  let coordinate: GuardianCoordinate
  let capturedAt: Date
}

@MainActor
protocol GuardianLiveLocationProviding: AnyObject {
  var onLocation: ((GuardianLiveLocationUpdate) -> Void)? { get set }
  var onAuthorizationChange: ((GuardianLocationAuthorizationState) -> Void)? { get set }
  var authorizationState: GuardianLocationAuthorizationState { get }
  func startForegroundSharing()
  func requestBackgroundAccess()
  func resumeIfAuthorized()
  func stopSharing()
}

/// A visible, consent-gated Core Location session for Circle sharing.
/// Standard updates provide accuracy while the app is in use. “Always” access
/// adds background and significant-change delivery without hiding the system’s
/// location indicator or preventing the person from revoking permission.
@MainActor
final class GuardianLiveLocationService: NSObject, GuardianLiveLocationProviding,
  @MainActor CLLocationManagerDelegate
{
  var onLocation: ((GuardianLiveLocationUpdate) -> Void)?
  var onAuthorizationChange: ((GuardianLocationAuthorizationState) -> Void)?

  private let manager = CLLocationManager()
  private var shouldShare = false

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = 25
    manager.activityType = .other
    manager.pausesLocationUpdatesAutomatically = true
  }

  var authorizationState: GuardianLocationAuthorizationState {
    guard CLLocationManager.locationServicesEnabled() else { return .unavailable }
    return switch manager.authorizationStatus {
    case .notDetermined: .notDetermined
    case .authorizedWhenInUse: .foregroundOnly
    case .authorizedAlways: .background
    case .denied: .denied
    case .restricted: .restricted
    @unknown default: .unavailable
    }
  }

  func startForegroundSharing() {
    shouldShare = true
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse, .authorizedAlways:
      startAuthorizedServices()
    case .denied, .restricted:
      onAuthorizationChange?(authorizationState)
    @unknown default:
      onAuthorizationChange?(.unavailable)
    }
  }

  func requestBackgroundAccess() {
    shouldShare = true
    switch manager.authorizationStatus {
    case .authorizedWhenInUse:
      manager.requestAlwaysAuthorization()
    case .authorizedAlways:
      startAuthorizedServices()
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .denied, .restricted:
      onAuthorizationChange?(authorizationState)
    @unknown default:
      onAuthorizationChange?(.unavailable)
    }
  }

  func resumeIfAuthorized() {
    shouldShare = true
    guard manager.authorizationStatus == .authorizedAlways
      || manager.authorizationStatus == .authorizedWhenInUse
    else {
      onAuthorizationChange?(authorizationState)
      return
    }
    startAuthorizedServices()
  }

  func stopSharing() {
    shouldShare = false
    manager.stopUpdatingLocation()
    manager.stopMonitoringSignificantLocationChanges()
    manager.allowsBackgroundLocationUpdates = false
    manager.showsBackgroundLocationIndicator = false
    onAuthorizationChange?(authorizationState)
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    onAuthorizationChange?(authorizationState)
    guard shouldShare else { return }
    if manager.authorizationStatus == .authorizedAlways
      || manager.authorizationStatus == .authorizedWhenInUse
    {
      startAuthorizedServices()
    } else if manager.authorizationStatus == .denied
      || manager.authorizationStatus == .restricted
    {
      manager.stopUpdatingLocation()
      manager.stopMonitoringSignificantLocationChanges()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard shouldShare,
      let location = locations.last,
      location.horizontalAccuracy >= 0,
      location.horizontalAccuracy <= 1_000,
      abs(location.timestamp.timeIntervalSinceNow) <= 120
    else { return }
    onLocation?(GuardianLiveLocationUpdate(
      coordinate: GuardianCoordinate(
        latitude: location.coordinate.latitude,
        longitude: location.coordinate.longitude,
        horizontalAccuracy: location.horizontalAccuracy
      ),
      capturedAt: location.timestamp
    ))
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    if let coreError = error as? CLError, coreError.code == .denied {
      onAuthorizationChange?(authorizationState)
    }
  }

  private func startAuthorizedServices() {
    let backgroundAuthorized = manager.authorizationStatus == .authorizedAlways
    manager.allowsBackgroundLocationUpdates = backgroundAuthorized
    manager.showsBackgroundLocationIndicator = backgroundAuthorized
    manager.startUpdatingLocation()
    if backgroundAuthorized, CLLocationManager.significantLocationChangeMonitoringAvailable() {
      manager.startMonitoringSignificantLocationChanges()
    }
    onAuthorizationChange?(authorizationState)
  }
}
