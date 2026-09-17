import FamilyControls
import ManagedSettings

// The only writer to the named "curfew" ManagedSettings store. Both the app
// and the monitor extension go through this, so the pause is always the same
// shape: the "What to pause" selection minus the "Always allow" selection.
//
// Only `shield` is ever set. Nothing here touches app removal, Safari, media,
// or any other setting — the ride path must keep working (rule 2).
struct CurfewShieldController: Sendable {
  /// Raw name kept as a String because `ManagedSettingsStore.Name` is not
  /// declared Sendable. A fresh store handle is cheap.
  static let storeName = "curfew"

  private var store: ManagedSettingsStore {
    ManagedSettingsStore(named: ManagedSettingsStore.Name(Self.storeName))
  }

  /// Pauses `pause`, except anything in `allow`. Idempotent.
  func apply(pause: FamilyActivitySelection, allow: FamilyActivitySelection) {
    let store = store
    store.shield.applicationCategories = pause.categoryTokens.isEmpty
      ? nil
      : .specific(pause.categoryTokens, except: allow.applicationTokens)
    let applications = pause.applicationTokens.subtracting(allow.applicationTokens)
    store.shield.applications = applications.isEmpty ? nil : applications
    // Web categories share the app category tokens; only the exception type
    // differs (`ShieldSettings.ActivityCategoryPolicy<WebDomain>`).
    store.shield.webDomainCategories = pause.categoryTokens.isEmpty
      ? nil
      : .specific(pause.categoryTokens, except: allow.webDomainTokens)
    let webDomains = pause.webDomainTokens.subtracting(allow.webDomainTokens)
    store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
  }

  /// Lifts everything this store ever set. Idempotent.
  func lift() {
    store.clearAllSettings()
  }
}
