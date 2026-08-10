import XCTest

@testable import Sober

@MainActor
final class AppModelTests: XCTestCase {
  @MainActor
  private final class PrivacyAuthenticatorStub: PrivacyLockAuthenticating {
    var isAvailable: Bool
    var results: [PrivacyLockAuthenticationResult]
    private(set) var reasons: [String] = []

    init(
      isAvailable: Bool = true,
      results: [PrivacyLockAuthenticationResult] = [.success]
    ) {
      self.isAvailable = isAvailable
      self.results = results
    }

    func authenticate(reason: String) async -> PrivacyLockAuthenticationResult {
      reasons.append(reason)
      guard !results.isEmpty else { return .failed }
      return results.removeFirst()
    }
  }

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

  private func makeModel(
    _ harness: Harness,
    allowsInternalTools: Bool,
    privacyLockAuthenticator: (any PrivacyLockAuthenticating)? = nil,
    privacyLockPolicy: PrivacyLockPolicy = .standard
  ) -> AppModel {
    let archive = ResearchSessionStore(directoryURL: harness.directory)
    let authenticator: any PrivacyLockAuthenticating =
      privacyLockAuthenticator ?? SystemPrivacyLockAuthenticator()
    return AppModel(
      defaults: harness.defaults,
      baselineStore: LocalBaselineStore(defaults: harness.defaults, archive: archive),
      privacyLockAuthenticator: authenticator,
      privacyLockPolicy: privacyLockPolicy,
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

    XCTAssertEqual(model.baselineSessions, 0, "a cache without records is never measurement truth")
    XCTAssertFalse(model.baselineReady)
    XCTAssertNil(harness.defaults.object(forKey: "sober.baseline.sessions"))
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

  func testDeletingDataAlsoEndsInternalSyntheticReadiness() async {
    let harness = makeHarness()
    let model = makeModel(harness, allowsInternalTools: true)
    model.completeOnboarding(founderPreview: true)
    XCTAssertTrue(model.baselineReady)

    await model.deleteAllResearchData()

    XCTAssertFalse(model.isFounderPreview)
    XCTAssertFalse(model.baselineReady)
    XCTAssertEqual(model.baselineSessions, 0)
    XCTAssertTrue(model.researchSessions.isEmpty)
  }

  func testResetClearsSyntheticStateBeforeAsynchronousDeletionReturns() {
    let harness = makeHarness()
    let model = makeModel(harness, allowsInternalTools: true)
    model.completeOnboarding(founderPreview: true)
    XCTAssertTrue(model.baselineReady)

    model.resetPrototype()

    XCTAssertFalse(model.isFounderPreview)
    XCTAssertFalse(model.baselineReady)
    XCTAssertEqual(model.baselineSessions, 0)
    XCTAssertTrue(model.researchSessions.isEmpty)
    XCTAssertTrue(harness.defaults.bool(forKey: "sober.baseline.deletion-pending"))
  }

  // MARK: - Privacy Lock

  func testPrivacyLockEnablesOnlyAfterSystemAuthentication() async {
    let harness = makeHarness()
    let authenticator = PrivacyAuthenticatorStub(results: [.cancelled, .success])
    let model = makeModel(
      harness,
      allowsInternalTools: false,
      privacyLockAuthenticator: authenticator
    )

    let cancelled = await model.setPrivacyLockEnabled(true)

    XCTAssertFalse(cancelled)
    XCTAssertFalse(model.privacyLockEnabled)
    XCTAssertFalse(harness.defaults.bool(forKey: "sober.privacy-lock.enabled"))
    XCTAssertNotNil(model.privacyLockError)

    let enabled = await model.setPrivacyLockEnabled(true)

    XCTAssertTrue(enabled)
    XCTAssertTrue(model.privacyLockEnabled)
    XCTAssertFalse(model.privacyLockIsLocked)
    XCTAssertTrue(harness.defaults.bool(forKey: "sober.privacy-lock.enabled"))
    XCTAssertEqual(authenticator.reasons.count, 2)
  }

  func testPrivacyLockCannotEnableWithoutDeviceOwnerAuthentication() async {
    let harness = makeHarness()
    let authenticator = PrivacyAuthenticatorStub(isAvailable: false)
    let model = makeModel(
      harness,
      allowsInternalTools: false,
      privacyLockAuthenticator: authenticator
    )

    let enabled = await model.setPrivacyLockEnabled(true)

    XCTAssertFalse(enabled)
    XCTAssertFalse(model.privacyLockEnabled)
    XCTAssertFalse(model.privacyLockIsLocked)
    XCTAssertTrue(authenticator.reasons.isEmpty)
    XCTAssertNotNil(model.privacyLockError)
  }

  func testPrivacyLockShieldsImmediatelyAndLocksOnlyAfterInactivityWindow() async {
    let harness = makeHarness()
    let authenticator = PrivacyAuthenticatorStub(results: [.success])
    let model = makeModel(
      harness,
      allowsInternalTools: false,
      privacyLockAuthenticator: authenticator,
      privacyLockPolicy: PrivacyLockPolicy(inactivityInterval: 30)
    )
    let enabled = await model.setPrivacyLockEnabled(true)
    XCTAssertTrue(enabled)

    model.privacySceneBecameInactive(at: 100)
    XCTAssertTrue(model.privacyShieldIsVisible)
    XCTAssertFalse(model.privacyLockIsLocked)

    model.privacySceneBecameActive(at: 129.9)
    XCTAssertFalse(model.privacyShieldIsVisible)
    XCTAssertFalse(model.privacyLockIsLocked)

    model.privacySceneEnteredBackground(at: 200)
    model.privacySceneBecameActive(at: 230)

    XCTAssertFalse(model.privacyShieldIsVisible)
    XCTAssertTrue(model.privacyLockIsLocked)
  }

  func testPersistedPrivacyLockStartsClosedAndFailedUnlockStaysClosed() async {
    let harness = makeHarness()
    UserDefaultsPrivacyStore(defaults: harness.defaults).savePrivacyLockEnabled(true)
    let authenticator = PrivacyAuthenticatorStub(results: [.failed, .success])
    let model = makeModel(
      harness,
      allowsInternalTools: false,
      privacyLockAuthenticator: authenticator
    )

    XCTAssertTrue(model.privacyLockEnabled)
    XCTAssertTrue(model.privacyLockIsLocked)
    let failedUnlock = await model.unlockProtectedContent()
    XCTAssertFalse(failedUnlock)
    XCTAssertTrue(model.privacyLockIsLocked)
    XCTAssertNotNil(model.privacyLockError)

    let successfulUnlock = await model.unlockProtectedContent()
    XCTAssertTrue(successfulUnlock)
    XCTAssertFalse(model.privacyLockIsLocked)
    XCTAssertNil(model.privacyLockError)
  }

  func testResetClearsPersistedAndInMemoryPrivacyLock() async {
    let harness = makeHarness()
    let authenticator = PrivacyAuthenticatorStub(results: [.success])
    let model = makeModel(
      harness,
      allowsInternalTools: false,
      privacyLockAuthenticator: authenticator
    )
    let enabled = await model.setPrivacyLockEnabled(true)
    XCTAssertTrue(enabled)

    model.resetPrototype()

    XCTAssertFalse(model.privacyLockEnabled)
    XCTAssertFalse(model.privacyLockIsLocked)
    XCTAssertFalse(model.privacyShieldIsVisible)
    XCTAssertFalse(
      UserDefaultsPrivacyStore(defaults: harness.defaults).load().privacyLockEnabled
    )
  }

  func testPrivacyLockNeverGatesHomeSafetyRoute() {
    XCTAssertFalse(DSTab.home.requiresPrivacyLock)
    XCTAssertTrue(DSTab.history.requiresPrivacyLock)
    XCTAssertTrue(DSTab.settings.requiresPrivacyLock)
    XCTAssertFalse(DSTab.circle.requiresPrivacyLock)
  }

  // MARK: - Build channel wiring

  /// The unit-test host links the public `Sober` target. This guards against a
  /// project change that accidentally exposes internal routes in public Debug.
  func testPublicTargetDoesNotDefineInternalBuild() {
    XCTAssertFalse(BuildChannel.allowsInternalTools)
  }
}
