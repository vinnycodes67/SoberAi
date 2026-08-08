import XCTest

@testable import Sober

@MainActor
final class AppModelTests: XCTestCase {
  private struct Harness {
    let defaults: UserDefaults
    let directory: URL
    let suiteName: String
  }

  private func makeHarness() -> Harness {
    let suiteName = "AppModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    addTeardownBlock {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }
    return Harness(defaults: defaults, directory: directory, suiteName: suiteName)
  }

  private func makeModel(_ harness: Harness, allowsInternalTools: Bool) -> AppModel {
    AppModel(
      defaults: harness.defaults,
      researchStore: ResearchSessionStore(directoryURL: harness.directory),
      automaticallyStartsGuardianServices: false,
      allowsInternalTools: allowsInternalTools
    )
  }

  // MARK: - Public build cannot fabricate a baseline

  /// The founder preview short-circuits `baselineReady`, but `ScreeningEngine`
  /// still discards an unready baseline and scores against population norms. A
  /// public build that entered this state would tell the person it was
  /// comparing against their own steady while doing nothing of the kind.
  func testPublicBuildCannotEnterFounderPreview() {
    let harness = makeHarness()
    let model = makeModel(harness, allowsInternalTools: false)

    model.completeOnboarding(founderPreview: true)

    XCTAssertFalse(model.isFounderPreview)
    XCTAssertFalse(model.baselineReady)
    XCTAssertEqual(model.baselineSessions, 0)
  }

  /// An internal build that is replaced by an App Store build must not leave a
  /// persisted founder flag switched on.
  func testPublicBuildIgnoresPersistedFounderPreviewFlag() {
    let harness = makeHarness()
    harness.defaults.set(true, forKey: "sober.founder.preview")

    let model = makeModel(harness, allowsInternalTools: false)

    XCTAssertFalse(model.isFounderPreview)
    XCTAssertFalse(model.baselineReady)
  }

  /// A stale inflated count from the previous implementation must not be read
  /// back as a ready baseline.
  func testPublicBuildDoesNotTrustInflatedStoredSessionCount() {
    let harness = makeHarness()
    harness.defaults.set(true, forKey: "sober.founder.preview")
    harness.defaults.set(3, forKey: "sober.baseline.sessions")

    let model = makeModel(harness, allowsInternalTools: false)

    XCTAssertEqual(model.baselineSessions, 3, "measured count is the truth on disk")
    XCTAssertFalse(model.baselineReady, "three measured sessions is not a ready baseline")
  }

  func testPublicBuildOnboardingIsAlwaysTheRealBaselinePath() {
    let harness = makeHarness()
    let model = makeModel(harness, allowsInternalTools: false)

    model.completeOnboarding(founderPreview: false)

    XCTAssertTrue(model.hasCompletedOnboarding)
    XCTAssertFalse(model.baselineReady)
  }

  // MARK: - Internal build keeps the demo affordance

  func testInternalBuildCanEnterFounderPreview() {
    let harness = makeHarness()
    let model = makeModel(harness, allowsInternalTools: true)

    model.completeOnboarding(founderPreview: true)

    XCTAssertTrue(model.isFounderPreview)
    XCTAssertTrue(model.baselineReady, "the demo state still unlocks the flow internally")
  }

  /// Even internally, the demo must not write a fake measured count. Freezing
  /// the stored value previously meant real sessions recorded during a demo
  /// never counted toward the actual baseline.
  func testFounderPreviewDoesNotInflateMeasuredSessionCount() {
    let harness = makeHarness()
    let model = makeModel(harness, allowsInternalTools: true)

    model.completeOnboarding(founderPreview: true)

    XCTAssertEqual(model.baselineSessions, 0)
    XCTAssertEqual(model.measuredEligibleSessions, 0)
  }

  func testInternalBuildOptingIntoRealBaselineIsNotPreview() {
    let harness = makeHarness()
    let model = makeModel(harness, allowsInternalTools: true)

    model.completeOnboarding(founderPreview: false)

    XCTAssertFalse(model.isFounderPreview)
    XCTAssertFalse(model.baselineReady)
  }

  // MARK: - Deletion

  func testDeleteAllResearchDataClearsMeasuredSessions() async {
    let harness = makeHarness()
    let model = makeModel(harness, allowsInternalTools: true)
    model.completeOnboarding(founderPreview: false)

    await model.deleteAllResearchData()

    XCTAssertEqual(model.baselineSessions, 0)
    XCTAssertFalse(model.baselineReady)
  }

  // MARK: - Build channel wiring

  /// The unit-test host links the public `Sober` target. This guards against a
  /// project change that accidentally exposes internal routes in public Debug.
  func testPublicTargetDoesNotDefineInternalBuild() {
    XCTAssertFalse(BuildChannel.allowsInternalTools)
  }
}
