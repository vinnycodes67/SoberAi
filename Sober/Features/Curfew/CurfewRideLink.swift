import Foundation

/// The ride deep link, built exactly as `DSIntegratedResultScreen.openRide()`
/// builds it. That method is private to the result screen and DesignKit is not
/// ours to edit, so the construction is mirrored here rather than forked: same
/// providers, same Uber universal link, same drop-off from the Safety Plan.
/// Keep the two in step.
enum CurfewRideLink {
  static func url(for safetyPlan: SafetyPlan) -> URL? {
    let destination = safetyPlan.trimmedHomeAddress.addingPercentEncoding(
      withAllowedCharacters: .urlQueryAllowed
    )
    let rawURL: String
    if safetyPlan.preferredRide == "Lyft" {
      rawURL = "https://www.lyft.com/rider"
    } else if let destination, !destination.isEmpty {
      rawURL = "https://m.uber.com/ul/?action=setPickup&pickup=my_location&dropoff[formatted_address]=\(destination)"
    } else {
      rawURL = "https://m.uber.com/ul/?action=setPickup&pickup=my_location"
    }
    return URL(string: rawURL)
  }
}
