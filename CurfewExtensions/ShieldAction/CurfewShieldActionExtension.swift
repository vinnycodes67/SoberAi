import Foundation
import ManagedSettings

/// Block screen buttons. This extension cannot open Sober itself, so the
/// primary button leaves a pending route in the shared store and posts the
/// "Check-in due" notification, which deep-links into the check-in.
///
/// It never lifts the shield. A check-in lifts the pause; a button press does
/// not (rule 1). `.close` only dismisses the paused app; the shield is back
/// the next time it is opened. `.defer` is never returned: it keeps the shield
/// on screen waiting for the app to change the settings, and nothing here
/// ever will.
final class CurfewShieldActionExtension: ShieldActionDelegate {
  override func handle(
    action: ShieldAction,
    for application: ApplicationToken,
    completionHandler: @escaping (ShieldActionResponse) -> Void
  ) {
    completionHandler(Self.respond(to: action))
  }

  override func handle(
    action: ShieldAction,
    for webDomain: WebDomainToken,
    completionHandler: @escaping (ShieldActionResponse) -> Void
  ) {
    completionHandler(Self.respond(to: action))
  }

  override func handle(
    action: ShieldAction,
    for category: ActivityCategoryToken,
    completionHandler: @escaping (ShieldActionResponse) -> Void
  ) {
    completionHandler(Self.respond(to: action))
  }

  private static func respond(to action: ShieldAction) -> ShieldActionResponse {
    switch action {
    case .primaryButtonPressed:
      let store = AppGroupCurfewStore()
      let nightID = store.load().tonight?.nightID ?? "curfew"
      try? store.update { $0.pendingRoute = .checkIn }
      // Synchronous hand-off to the notification daemon: this process may be
      // gone before a detached Task would get to run.
      CurfewNotifications.enqueueCheckInDue(nightID: nightID)
      return .close
    case .secondaryButtonPressed:
      // "Not now": leave the paused app. It is still paused.
      return .close
    @unknown default:
      return .none
    }
  }
}
