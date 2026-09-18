import Foundation

/// The numbers that decide whether someone has a usable baseline.
///
/// These were duplicated across the engine, the app model, the screening flow
/// and several screens. Readiness lived in `AppModel` as a bare `>= 5`, and
/// acceptance lived in `ScreeningFlowView` as a bare `>= 0.72`, both independent
/// of `BaselineProfileEngine`'s own defaults. Tuning the engine therefore moved
/// the scoring rule while leaving the UI insisting on the old one — the app
/// would say "ready" and then refuse to compare, or accept a session the engine
/// discarded.
///
/// Device testing is expected to move `minimumQuality`. It has to move in one
/// place.
enum BaselineThresholds {
  /// Capture quality a session must reach to count toward a baseline.
  ///
  /// Provisional. No session has ever been recorded on physical hardware, so
  /// this has never been checked against a real capture. See
  /// `Docs/PHASE_4_DEVICE_GATES.md`.
  static let minimumQuality = 0.72

  /// Eligible sober sessions required before any check will compare.
  static let requiredSessions = 5

  /// How many of the most recent eligible sessions a check actually scores
  /// against. Smaller than `requiredSessions` on purpose: five proves the
  /// person can produce consistent captures, three keeps the comparison recent.
  /// Any copy that says all five "build the range" is wrong.
  static let scoringWindow = 3
}
