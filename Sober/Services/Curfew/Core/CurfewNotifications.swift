import Foundation
import UserNotifications

// The one local notification Curfew ever posts: "Check-in due", tapped
// through to the check-in screen. Posted by the monitor extension when the
// pause starts and by the shield action extension when the teen taps the
// block screen's button, so this stays Foundation + UserNotifications only
// and has no actor requirement.
//
// A notification is a nudge, never a gate. It never mentions a Sober result.
enum CurfewNotifications {
  static let checkInCategoryIdentifier = "curfew.check-in"
  static let checkInDueRequestIdentifier = "curfew.check-in-due"
  /// Handled by SoberInternal's `sober-internal` URL scheme (project.yml).
  static let deepLinkURL = URL(string: "sober-internal://curfew/check-in")!
  /// `userInfo` key whose value is a `CurfewPendingRoute.rawValue`.
  static let routeUserInfoKey = "curfewRoute"

  /// Asks once; afterwards reports whatever the person decided.
  static func requestAuthorizationIfNeeded() async -> Bool {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .notDetermined:
      return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    case .authorized, .provisional, .ephemeral:
      return true
    case .denied:
      return false
    @unknown default:
      return false
    }
  }

  /// Registers the check-in category without disturbing categories other
  /// features may have registered. Call from the app at launch.
  static func registerCategories() {
    let center = UNUserNotificationCenter.current()
    let category = UNNotificationCategory(
      identifier: checkInCategoryIdentifier,
      actions: [],
      intentIdentifiers: [],
      options: []
    )
    center.getNotificationCategories { existing in
      var categories = existing.filter { $0.identifier != checkInCategoryIdentifier }
      categories.insert(category)
      center.setNotificationCategories(categories)
    }
  }

  /// Posts "Check-in due" now, replacing any earlier copy so the teen never
  /// sees a stack of them. One thread per night.
  static func postCheckInDue(nightID: String) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      enqueueCheckInDue(nightID: nightID) { continuation.resume() }
    }
  }

  /// Synchronous form of `postCheckInDue(nightID:)` for the extensions, whose
  /// process may be torn down as soon as the delegate callback returns. The
  /// request is handed to the notification daemon before this returns.
  static func enqueueCheckInDue(nightID: String, completion: (@Sendable () -> Void)? = nil) {
    let center = UNUserNotificationCenter.current()
    let content = UNMutableNotificationContent()
    content.title = CurfewCopy.notificationTitle
    content.body = CurfewCopy.notificationBody
    content.sound = .default
    content.categoryIdentifier = checkInCategoryIdentifier
    content.threadIdentifier = nightID
    content.userInfo = [routeUserInfoKey: CurfewPendingRoute.checkIn.rawValue]
    // Breaks through Focus only if SoberInternal carries the time-sensitive
    // entitlement; without it the system quietly downgrades to `.active`.
    content.interruptionLevel = .timeSensitive

    center.removePendingNotificationRequests(withIdentifiers: [checkInDueRequestIdentifier])
    center.removeDeliveredNotifications(withIdentifiers: [checkInDueRequestIdentifier])
    let request = UNNotificationRequest(
      identifier: checkInDueRequestIdentifier,
      content: content,
      trigger: nil
    )
    center.add(request) { _ in completion?() }
  }

  /// Removes the pending and delivered "Check-in due" notification. Called
  /// whenever the pause is not in effect, so it is safe to call repeatedly.
  static func clearCheckInDue() {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [checkInDueRequestIdentifier])
    center.removeDeliveredNotifications(withIdentifiers: [checkInDueRequestIdentifier])
  }

  /// True when a tapped notification (or a `deepLinkURL` open) should land on
  /// the check-in screen.
  static func pendingRoute(from userInfo: [AnyHashable: Any]) -> CurfewPendingRoute? {
    guard let raw = userInfo[routeUserInfoKey] as? String else { return nil }
    return CurfewPendingRoute(rawValue: raw)
  }
}
