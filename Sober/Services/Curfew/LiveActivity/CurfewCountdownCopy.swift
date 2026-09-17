import Foundation

// Every string the Lock Screen and Dynamic Island countdown shows, in one
// place so the words can be tested against `CurfewCopy.forbiddenWords`.
// Times are rendered by SwiftUI (`Text(date, style: .time)`) so they follow
// the phone's 12/24-hour setting; only the words around them live here.
enum CurfewCountdownCopy {
  /// "Home by 11:00 PM"
  static let homeByPrefix = CurfewCopy.countdownPrefix
  /// "Curfew 11:00 PM · apps pause soon"
  static let gracePrefix = "Curfew"
  static let graceSuffix = "apps pause soon"
  /// "Checked in · next check-in 12:42 AM"
  static let checkedInPrefix = "Checked in"
  static let nextCheckInPrefix = "next check-in"
  /// Under the Safe Ride Promise. Nothing else is asked tonight.
  static let rideDetail = "Nothing more is asked of you tonight."

  /// Compact Dynamic Island labels. Short because the space is.
  static let compactCheckIn = "Check in"
  static let compactRide = "Ride"

  static let separator = " · "

  /// Everything above, for the copy test.
  static var allStrings: [String] {
    [
      homeByPrefix, gracePrefix, graceSuffix, checkedInPrefix, nextCheckInPrefix,
      rideDetail, compactCheckIn, compactRide,
    ]
  }
}
