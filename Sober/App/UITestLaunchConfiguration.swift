#if DEBUG
import Foundation
import SwiftUI

/// Debug-only launch configuration used by XCUITest and manual QA.
///
/// Nothing is activated unless `-sober-ui-test-fixture` is present. Keeping the
/// fixture parser and seeded records behind `DEBUG` means production binaries
/// cannot erase, fabricate, or route around a person's real state.
@MainActor
struct UITestLaunchConfiguration {
  enum Fixture: String, CaseIterable {
    case onboarding
    case home
    case history
    case settings
    case privacy
    case resultSignals = "result-signals"
    case resultInconclusive = "result-inconclusive"
    case resultClear = "result-clear"
    case interrupted
    case captureRecovery = "capture-recovery"
  }

  enum DirectDestination: Equatable {
    case privacy
    case result(FounderScenario)
    case interrupted
    case captureRecovery
  }

  static let current = UITestLaunchConfiguration(
    arguments: ProcessInfo.processInfo.arguments
  )

  let fixture: Fixture?
  let dynamicTypeSize: DynamicTypeSize?
  let reduceMotion: Bool

  init(arguments: [String]) {
    fixture = Self.value(after: "-sober-ui-test-fixture", in: arguments)
      .flatMap(Fixture.init(rawValue:))

    switch Self.value(after: "-sober-ui-test-content-size", in: arguments) {
    case "accessibility3":
      dynamicTypeSize = .accessibility3
    default:
      dynamicTypeSize = nil
    }

    reduceMotion = arguments.contains("-sober-ui-test-reduce-motion")
  }

  var isActive: Bool { fixture != nil }

  var directDestination: DirectDestination? {
    switch fixture {
    case .privacy:
      return .privacy
    case .resultSignals:
      return .result(.signals)
    case .resultInconclusive:
      return .result(.inconclusive)
    case .resultClear:
      return .result(.noSignals)
    case .interrupted:
      return .interrupted
    case .captureRecovery:
      return .captureRecovery
    case .onboarding, .home, .history, .settings, .none:
      return nil
    }
  }

  /// Rebuilds only the app-owned local state used by deterministic UI tests.
  /// This runs before `AppModel` is created, so no cached state can race the
  /// fixture write. Production launches never call it.
  func prepare() {
    guard let fixture else { return }

    let defaults = UserDefaults.standard
    if let bundleIdentifier = Bundle.main.bundleIdentifier {
      defaults.removePersistentDomain(forName: bundleIdentifier)
    }
    removeAppOwnedFiles()

    guard fixture != .onboarding else { return }

    defaults.set(true, forKey: "sober.onboarding.complete")
    let privacyStore = UserDefaultsPrivacyStore(defaults: defaults)
    privacyStore.saveUserProfile(UserProfile(displayName: "Alex", ageYears: 21))
    privacyStore.saveSafetyPlan(
      SafetyPlan(
        userName: "Alex",
        contactName: "Jordan",
        contactPhone: "3125550100",
        homeLabel: "Home",
        homeAddress: "123 Main Street, Chicago, IL",
        preferredRide: "Uber"
      )
    )

    if fixture == .history {
      seedHistory()
    }
  }

  private func removeAppOwnedFiles() {
    let fileManager = FileManager.default
    let applicationSupport =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    let soberDirectory = applicationSupport.appendingPathComponent("Sober", isDirectory: true)
    try? fileManager.removeItem(at: soberDirectory)

    // Exports are app-created temporary files. Scope deletion to the exact
    // prefix used by the research exporter rather than clearing the temp area.
    if let temporaryFiles = try? fileManager.contentsOfDirectory(
      at: fileManager.temporaryDirectory,
      includingPropertiesForKeys: nil
    ) {
      for file in temporaryFiles where file.lastPathComponent.hasPrefix("sober-research-export-") {
        try? fileManager.removeItem(at: file)
      }
    }
  }

  private func seedHistory() {
    struct HistoryDocument: Encodable {
      let schemaVersion: Int
      let entries: [CheckHistoryEntry]
    }

    let now = Date()
    let entries = [
      CheckHistoryEntry(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        startedAt: now.addingTimeInterval(-60 * 60),
        kind: .check,
        outcome: .signalsDetected,
        qualityScore: 0.91,
        completedAllTasks: true
      ),
      CheckHistoryEntry(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
        startedAt: now.addingTimeInterval(-24 * 60 * 60),
        kind: .check,
        outcome: .inconclusive,
        qualityScore: 0.64,
        completedAllTasks: false
      ),
      CheckHistoryEntry(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
        startedAt: now.addingTimeInterval(-48 * 60 * 60),
        kind: .baseline,
        outcome: nil,
        qualityScore: 0.88,
        completedAllTasks: true
      ),
    ]

    let fileManager = FileManager.default
    let applicationSupport =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    let historyDirectory = applicationSupport
      .appendingPathComponent("Sober", isDirectory: true)
      .appendingPathComponent("History", isDirectory: true)
    let historyURL = historyDirectory.appendingPathComponent(
      CheckHistoryStore.currentFileName,
      isDirectory: false
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(
      HistoryDocument(
        schemaVersion: CheckHistoryStore.currentStoreSchemaVersion,
        entries: entries
      )
    ) else { return }

    try? fileManager.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
    try? data.write(to: historyURL, options: .atomic)
  }

  private static func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag) else { return nil }
    let valueIndex = arguments.index(after: index)
    guard arguments.indices.contains(valueIndex) else { return nil }
    return arguments[valueIndex]
  }
}

struct UITestFixtureView: View {
  let destination: UITestLaunchConfiguration.DirectDestination

  @ViewBuilder
  var body: some View {
    switch destination {
    case .privacy:
      PrivacyCenterView()
    case .result(let scenario):
      ScreeningFlowView(
        configuration: ScreeningLaunch(mode: .check, scenario: scenario)
      )
    case .interrupted:
      InterruptedTaskView(
        taskName: "the reaction task",
        onRestartTask: {},
        onEndCheck: {}
      )
    case .captureRecovery:
      CaptureRecoveryOverlay(
        guidance: "Center your face and move somewhere brighter.",
        onRetryCalibration: {},
        onEndCheck: {}
      )
    }
  }
}

struct UITestEnvironmentModifier: ViewModifier {
  let configuration: UITestLaunchConfiguration

  @ViewBuilder
  func body(content: Content) -> some View {
    if configuration.isActive {
      if configuration.reduceMotion {
        content
          .dynamicTypeSize(configuration.dynamicTypeSize ?? .large)
          .transaction { transaction in
            transaction.disablesAnimations = true
          }
      } else {
        content.dynamicTypeSize(configuration.dynamicTypeSize ?? .large)
      }
    } else {
      content
    }
  }
}
#endif
