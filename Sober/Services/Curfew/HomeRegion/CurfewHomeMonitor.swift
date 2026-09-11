import CoreLocation
import Foundation

// Home detection for Curfew, in the main app because extensions cannot
// reliably get location. Monitors one circular region around the private
// home anchor already kept in the Keychain and writes `CurfewHomeReading`
// into the App Group store, where the monitor extension reads it.
//
// The anchor itself never leaves this class. Only the derived "home / not
// home" plus a timestamp is shared, and a stale or missing reading counts as
// not home (rule 6): that only ever pauses social apps and asks for a
// ten-second check-in.
@MainActor
final class CurfewHomeMonitor: NSObject, CurfewHomeMonitoring, @MainActor CLLocationManagerDelegate {
  static let regionIdentifier = "curfew.home"
  /// How long a check-in waits for a location before going without one.
  static let oneShotTimeout: Duration = .seconds(5)

  var onAuthorizationChange: ((CurfewHomeAuthorization) -> Void)?
  var onHomeReading: ((CurfewHomeReading) -> Void)?

  private let store: any CurfewStateStoring
  private let homeStore: any GuardianHomeStoring
  private let manager = CLLocationManager()
  private var wantsMonitoring = false
  private var anchor: GuardianHomeAnchor?
  private var oneShot: CheckedContinuation<CurfewLocationFix?, Never>?
  private var oneShotTimeoutTask: Task<Void, Never>?

  init(
    store: any CurfewStateStoring = AppGroupCurfewStore(),
    homeStore: any GuardianHomeStoring = KeychainGuardianHomeStore()
  ) {
    self.store = store
    self.homeStore = homeStore
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    manager.activityType = .other
  }

  var authorization: CurfewHomeAuthorization {
    switch manager.authorizationStatus {
    case .notDetermined: .notDetermined
    case .authorizedWhenInUse: .whenInUse
    case .authorizedAlways: .always
    case .denied: .denied
    case .restricted: .unavailable
    @unknown default: .unavailable
    }
  }

  private var isAuthorized: Bool {
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse: true
    default: false
    }
  }

  /// Region wake-ups in the background need "Always". iOS only shows that
  /// prompt after "When In Use" has been granted, so this asks in two steps.
  func requestAlwaysAuthorization() {
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse:
      manager.requestAlwaysAuthorization()
    default:
      onAuthorizationChange?(authorization)
    }
  }

  /// Starts monitoring the home region. A no-op when no home anchor has been
  /// set: the store's reading stays nil, which the evaluator reads as not home.
  func start() {
    guard let anchor = try? homeStore.load() else {
      wantsMonitoring = false
      self.anchor = nil
      return
    }
    self.anchor = anchor
    wantsMonitoring = true
    guard isAuthorized else { return }
    startMonitoringRegion(around: anchor)
  }

  func stop() {
    wantsMonitoring = false
    for region in curfewRegions {
      manager.stopMonitoring(for: region)
    }
  }

  /// One fix for a check-in payload, or nil after a few seconds. A check-in
  /// is never blocked on location, so only one request is outstanding at a
  /// time and a second concurrent caller simply gets nil.
  func currentLocation() async -> CurfewLocationFix? {
    guard isAuthorized, oneShot == nil, CLLocationManager.locationServicesEnabled() else { return nil }
    return await withCheckedContinuation { continuation in
      oneShot = continuation
      oneShotTimeoutTask = Task { [weak self] in
        try? await Task.sleep(for: Self.oneShotTimeout)
        guard !Task.isCancelled else { return }
        self?.finishOneShot(with: nil)
      }
      manager.requestLocation()
    }
  }

  // MARK: CLLocationManagerDelegate

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    onAuthorizationChange?(authorization)
    guard wantsMonitoring, let anchor else { return }
    if isAuthorized {
      startMonitoringRegion(around: anchor)
    } else {
      finishOneShot(with: nil)
    }
  }

  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    guard region.identifier == Self.regionIdentifier else { return }
    record(isHome: true)
  }

  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    guard region.identifier == Self.regionIdentifier else { return }
    record(isHome: false)
  }

  func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
    guard region.identifier == Self.regionIdentifier else { return }
    switch state {
    case .inside: record(isHome: true)
    case .outside: record(isHome: false)
    // Unknown is not evidence either way; leave the last reading to age out.
    case .unknown: break
    @unknown default: break
    }
  }

  func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: any Error) {
    // Nothing to do: a missing reading already reads as not home.
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last, location.horizontalAccuracy >= 0 else {
      finishOneShot(with: nil)
      return
    }
    let fix = CurfewLocationFix(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      horizontalAccuracyMeters: location.horizontalAccuracy,
      capturedAt: location.timestamp
    )
    finishOneShot(with: fix)
    recordHomeIfDecisive(from: location)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    finishOneShot(with: nil)
    if let coreError = error as? CLError, coreError.code == .denied {
      onAuthorizationChange?(authorization)
    }
  }

  // MARK: Private

  private var curfewRegions: [CLRegion] {
    manager.monitoredRegions.filter { $0.identifier == Self.regionIdentifier }
  }

  private func startMonitoringRegion(around anchor: GuardianHomeAnchor) {
    guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
    let region = CLCircularRegion(
      center: anchor.coordinate,
      radius: GuardianCheckInDueEvaluator.homeRadiusMeters,
      identifier: Self.regionIdentifier
    )
    region.notifyOnEntry = true
    region.notifyOnExit = true
    // Replace rather than stack, in case the anchor moved.
    for stale in curfewRegions where (stale as? CLCircularRegion) != region {
      manager.stopMonitoring(for: stale)
    }
    manager.startMonitoring(for: region)
    manager.requestState(for: region)
  }

  private func record(isHome: Bool, at observedAt: Date = Date()) {
    let reading = CurfewHomeReading(isHome: isHome, observedAt: observedAt)
    try? store.update { $0.home = reading }
    onHomeReading?(reading)
  }

  /// A one-shot fix taken for a check-in is also fresh evidence about home,
  /// judged with the same radius-plus-accuracy rule as the Guardian home
  /// check. An ambiguous fix (accuracy circle straddles the radius) changes
  /// nothing.
  private func recordHomeIfDecisive(from location: CLLocation) {
    guard let anchor else { return }
    let distance = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude).distance(from: location)
    let accuracy = max(location.horizontalAccuracy, 0)
    let radius = GuardianCheckInDueEvaluator.homeRadiusMeters
    if distance + accuracy <= radius {
      record(isHome: true, at: location.timestamp)
    } else if distance - accuracy > radius {
      record(isHome: false, at: location.timestamp)
    }
  }

  /// Resumes the pending one-shot exactly once, whichever of fix, error, or
  /// timeout arrives first.
  private func finishOneShot(with fix: CurfewLocationFix?) {
    guard let continuation = oneShot else { return }
    oneShot = nil
    oneShotTimeoutTask?.cancel()
    oneShotTimeoutTask = nil
    continuation.resume(returning: fix)
  }
}
