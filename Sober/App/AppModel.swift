import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
  @Published var hasCompletedOnboarding: Bool
  @Published var baselineSessions: Int
  @Published var isFounderPreview: Bool
  @Published var safetyPlan: SafetyPlan {
    didSet {
      if let data = try? JSONEncoder().encode(safetyPlan) {
        defaults.set(data, forKey: Keys.safetyPlan)
      }
    }
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
    baselineSessions = defaults.integer(forKey: Keys.baselines)
    isFounderPreview = defaults.bool(forKey: Keys.founderPreview)
    if let data = defaults.data(forKey: Keys.safetyPlan),
      let storedPlan = try? JSONDecoder().decode(SafetyPlan.self, from: data)
    {
      safetyPlan = storedPlan
    } else {
      safetyPlan = SafetyPlan()
    }
  }

  var baselineReady: Bool { baselineSessions >= 3 }

  func completeOnboarding(founderPreview: Bool) {
    isFounderPreview = founderPreview
    hasCompletedOnboarding = true
    if founderPreview {
      baselineSessions = 3
    }
    defaults.set("prototype-v1", forKey: Keys.consentVersion)
    defaults.set(Date(), forKey: Keys.consentDate)
    persist()
  }

  func recordBaseline() {
    baselineSessions = min(baselineSessions + 1, 3)
    persist()
  }

  func resetPrototype() {
    hasCompletedOnboarding = false
    baselineSessions = 0
    isFounderPreview = false
    safetyPlan = SafetyPlan()
    defaults.removeObject(forKey: Keys.onboarding)
    defaults.removeObject(forKey: Keys.baselines)
    defaults.removeObject(forKey: Keys.founderPreview)
    defaults.removeObject(forKey: Keys.safetyPlan)
    defaults.removeObject(forKey: Keys.consentVersion)
    defaults.removeObject(forKey: Keys.consentDate)
  }

  private func persist() {
    defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding)
    defaults.set(baselineSessions, forKey: Keys.baselines)
    defaults.set(isFounderPreview, forKey: Keys.founderPreview)
  }

  private enum Keys {
    static let onboarding = "sober.onboarding.complete"
    static let baselines = "sober.baseline.sessions"
    static let founderPreview = "sober.founder.preview"
    static let safetyPlan = "sober.safety.plan"
    static let consentVersion = "sober.consent.version"
    static let consentDate = "sober.consent.date"
  }
}
