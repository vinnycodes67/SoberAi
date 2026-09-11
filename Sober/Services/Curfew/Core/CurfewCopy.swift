import Foundation

// Every teen-facing Curfew string, in one place, so the words can be tested.
// Pause, not lock or punish. Always say what still works. Never: failed,
// passed, cleared, safe, sober (as a state), caught, violation.
//
// Shared with the shield extensions, which have no DesignKit.
enum CurfewCopy {
  static let pausedTitle = "Apps paused until you check in."
  static let stillWorks = "Calls, messages, maps and rides still work."

  /// Block screen (ShieldConfiguration). The system renders these in its own
  /// font; only the words and colours are ours.
  static let shieldTitle = "Check-in due"
  static let shieldSubtitle = "Calls, messages, maps and rides still work. Open Sober to check in."
  static let shieldPrimaryButton = "Open Sober to check in"
  static let shieldSecondaryButton = "Not now"

  /// Local notification posted at curfew and by the shield action button.
  static let notificationTitle = "Check-in due"
  static let notificationBody = "Apps paused until you check in. Calls, messages, maps and rides still work."

  static let checkInOK = "I’m OK"
  static let checkInRide = "I need a ride"
  static let optionalCheck = "Run a private Sober check"
  static let optionalCheckDetail = "Optional. The result stays on this iPhone and is never part of a check-in."

  static let countdownPrefix = "Home by"

  static func safeRidePromise(guardianName: String?) -> String {
    let name = guardianName?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let name, !name.isEmpty {
      return "\(name) promised: no questions tonight."
    }
    return "Your guardian promised: no questions tonight."
  }

  /// Words that must never appear in teen-facing Curfew copy. "Safe" is
  /// allowed only inside the feature name "Safe Ride Promise".
  static let forbiddenWords = ["failed", "passed", "cleared", "safe", "caught", "violation", "locked", "punish"]

  /// Everything above, for the copy test.
  static var allStrings: [String] {
    [
      pausedTitle, stillWorks, shieldTitle, shieldSubtitle, shieldPrimaryButton,
      shieldSecondaryButton, notificationTitle, notificationBody, checkInOK, checkInRide,
      optionalCheck, optionalCheckDetail, countdownPrefix,
      safeRidePromise(guardianName: "Jordan"), safeRidePromise(guardianName: nil),
    ]
  }
}
