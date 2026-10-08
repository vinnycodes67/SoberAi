import XCTest

@testable import Sober

/// "Ready" on Home has to mean the next check compares against this person.
///
/// Each protocol variant keeps its own baseline, and readiness used to follow
/// whichever variant had the most sessions. Five camera sessions made an iPhone
/// without Reduce Motion's partition -- or without a camera at all -- say
/// "Ready" while its check was silently scored against population ranges.
@MainActor
final class NextCheckReadinessTests: XCTestCase {

  private func makeModel(supportsFaceTracking: Bool) -> AppModel {
    let suiteName = "NextCheckReadinessTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let research = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let history = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    addTeardownBlock {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: research)
      try? FileManager.default.removeItem(at: history)
    }
    return AppModel(
      defaults: defaults,
      baselineStore: LocalBaselineStore(
        defaults: defaults,
        archive: ResearchSessionStore(directoryURL: research)
      ),
      checkHistoryStore: CheckHistoryStore(directoryURL: history),
      automaticallyStartsGuardianServices: false,
      allowsInternalTools: false,
      supportsFaceTracking: supportsFaceTracking
    )
  }

  private func recordBaselines(
    _ model: AppModel, variant: OcularProtocolVariant, count: Int = BaselineThresholds.requiredSessions
  ) async {
    let usesCamera = variant != .noCamera
    for index in 0..<count {
      await model.recordCompletedSession(
        mode: .baseline,
        selfReport: .no,
        metrics: ScreeningMetrics(
          reactionTimeMilliseconds: 330 + Double(index) * 4,
          reactionMisses: 0,
          trackingError: 0.18 + Double(index) * 0.004,
          timeEstimateError: 0.08 + Double(index) * 0.003,
          gazeSmoothness: usesCamera ? 0.16 + Double(index) * 0.003 : nil,
          qualityScore: usesCamera ? 0.92 : 0,
          completedAllTasks: true
        ),
        reactionSummary: nil,
        ocularSummary: nil,
        startedAt: Date().addingTimeInterval(Double(index)),
        protocolVariant: variant
      )
    }
  }

  func testCameraSessionsDoNotMakeACameraFreeIPhoneReady() async {
    let model = makeModel(supportsFaceTracking: false)
    await recordBaselines(model, variant: .full)

    XCTAssertEqual(model.nextCheckVariant, .noCamera)
    XCTAssertEqual(model.measuredEligibleSessions, 0)
    XCTAssertFalse(model.baselineReady)
  }

  func testCameraFreeSessionsDoNotMakeACameraIPhoneReady() async {
    let model = makeModel(supportsFaceTracking: true)
    await recordBaselines(model, variant: .noCamera)

    XCTAssertEqual(model.nextCheckVariant, .full)
    XCTAssertFalse(model.baselineReady)
  }

  func testSessionsOfTheNextChecksVariantMakeItReady() async {
    let model = makeModel(supportsFaceTracking: false)
    await recordBaselines(model, variant: .noCamera)

    XCTAssertTrue(model.baselineReady)
    XCTAssertEqual(model.personalBaseline(for: .noCamera)?.isReady, true)
  }

  /// Turning on Reduce Motion changes which check runs, so it changes which
  /// baseline counts, both ways.
  func testReduceMotionSwitchesThePartitionReadinessReads() async {
    let model = makeModel(supportsFaceTracking: true)
    await recordBaselines(model, variant: .full)
    XCTAssertTrue(model.baselineReady)

    model.setReduceMotion(true)
    XCTAssertEqual(model.nextCheckVariant, .reducedMotion)
    XCTAssertFalse(model.baselineReady)

    model.setReduceMotion(false)
    XCTAssertTrue(model.baselineReady)
  }
}
