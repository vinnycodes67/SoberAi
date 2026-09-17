import Foundation

/// The ride deep link for Curfew's check-in.
///
/// Delegates to `SafetyPlan.rideURL` so the check-in and the result screen open
/// the same ride the same way. This used to mirror the construction by hand,
/// which was the right call when the result screen's builder was private — but
/// the copy carried a real defect: hand-encoding the address and interpolating
/// it next to Uber's square-bracketed parameter name made `URL(string:)`
/// re-encode the whole query, so the destination arrived as the literal text
/// "123%20Main%20Street" and Uber could not resolve it.
enum CurfewRideLink {
  static func url(for safetyPlan: SafetyPlan) -> URL? { safetyPlan.rideURL }
}
