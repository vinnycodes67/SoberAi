import XCTest

@testable import Sober

@MainActor
final class AppModelTests: XCTestCase {
  func testLegacyFounderPreviewMigratesToFiveSessionDisplay() {
    let suiteName = "AppModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    defaults.set(true, forKey: "sober.founder.preview")
    defaults.set(3, forKey: "sober.baseline.sessions")

    let model = AppModel(
      defaults: defaults,
      researchStore: ResearchSessionStore(directoryURL: directory),
      automaticallyStartsGuardianServices: false
    )

    XCTAssertTrue(model.baselineReady)
    XCTAssertEqual(model.baselineSessions, 5)
  }
}
