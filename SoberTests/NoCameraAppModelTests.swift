import XCTest

@testable import Sober

/// The app-model half of the no-camera check.
///
/// A device with no TrueDepth camera -- every iPhone without Face ID, and every
/// simulator -- could never produce a result: the eye task cannot run, so no
/// baseline session counted and no check ever compared. The engine side is in
/// NoCameraProtocolTests; these cover how sessions are filed and shown.
@MainActor
final class NoCameraAppModelTests: XCTestCase {

  private func makeModel() -> AppModel {
    let suiteName = "NoCameraAppModelTests.\(UUID().uuidString)"
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
      allowsInternalTools: false
    )
  }

  /// What a completed camera-free session looks like: three measured tasks, no
  /// gaze, and no camera capture quality to speak of.
  private let noCameraMetrics = ScreeningMetrics(
    reactionTimeMilliseconds: 340,
    reactionMisses: 0,
    trackingError: 0.2,
    timeEstimateError: 0.09,
    gazeSmoothness: nil,
    qualityScore: 1,
    completedAllTasks: true
  )

  private func recordBaseline(_ model: AppModel, variant: OcularProtocolVariant?) async {
    await model.recordCompletedSession(
      mode: .baseline,
      selfReport: .no,
      metrics: noCameraMetrics,
      reactionSummary: nil,
      ocularSummary: nil,
      startedAt: Date(),
      protocolVariant: variant
    )
  }

  /// The data bug this fixes. With no ocular summary the variant fell back to
  /// `.full`, filing camera-free sessions into the camera baseline.
  func testACameraFreeSessionIsFiledUnderItsOwnVariant() async {
    let model = makeModel()
    await recordBaseline(model, variant: .noCamera)

    XCTAssertEqual(model.researchSessions.last?.protocolVariant, .noCamera)
  }

  /// History says how good the capture was. A camera-free session captured
  /// nothing, so it must not borrow a capture band -- "strong capture" about a
  /// run that never opened the camera is simply untrue.
  func testACameraFreeSessionRecordsThatNothingWasCaptured() async {
    let model = makeModel()
    await recordBaseline(model, variant: .noCamera)

    XCTAssertEqual(model.checkHistory.count, 1)
    XCTAssertEqual(model.checkHistory.first?.measuredCapture, false)
  }

  func testACameraSessionStillRecordsItsCapture() async {
    let model = makeModel()
    await recordBaseline(model, variant: .full)

    XCTAssertEqual(model.checkHistory.first?.measuredCapture, true)
  }

  /// Every entry written before camera-free checks existed ran the camera, so
  /// a record with no flag must read as a captured one rather than as a
  /// camera-free session that never happened.
  func testHistoryWrittenBeforeTheFlagExistedStillReadsAsCaptured() throws {
    let json = Data(
      """
      {
        "id": "10000000-0000-0000-0000-000000000009",
        "startedAt": 780000000,
        "kind": "check",
        "outcome": "inconclusive",
        "qualityScore": 0.88,
        "completedAllTasks": true,
        "schemaVersion": 1
      }
      """.utf8)

    let decoder = JSONDecoder()
    let entry = try decoder.decode(CheckHistoryEntry.self, from: json)

    XCTAssertTrue(entry.measuredCapture)
    XCTAssertEqual(entry.qualityScore, 0.88, accuracy: 0.0001)
  }

  /// Callers that pass no variant keep today's behaviour exactly.
  func testOmittingTheVariantKeepsTheExistingFallback() async {
    let model = makeModel()
    await recordBaseline(model, variant: nil)

    XCTAssertEqual(model.researchSessions.last?.protocolVariant, .full)
  }

  func testTheBreakdownCoversEveryVariant() async {
    let model = makeModel()
    await recordBaseline(model, variant: .noCamera)

    for variant in OcularProtocolVariant.allCases {
      XCTAssertNotNil(
        model.baselineVariantBreakdown[variant],
        "\(variant) must have a summary or its sessions are invisible")
    }
  }

  /// The end-to-end point: a device with no camera can now become ready, and
  /// Your Steady shows the partition that got it there rather than an empty
  /// camera baseline.
  func testEnoughCameraFreeSessionsMakeTheAppReady() async {
    let model = makeModel()
    for _ in 0..<BaselineThresholds.requiredSessions {
      await recordBaseline(model, variant: .noCamera)
    }

    XCTAssertTrue(model.baselineReady, "a no-camera device must be able to reach a result")
    XCTAssertEqual(
      model.baselineProfile?.eligibleSessionCount,
      model.baselineVariantBreakdown[.noCamera]?.eligibleSessionCount,
      "Your Steady must show the partition that is driving readiness")
    XCTAssertEqual(
      model.baselineVariantBreakdown[.full]?.eligibleSessionCount ?? 0, 0,
      "camera-free sessions must never count toward the camera baseline")
  }
}
