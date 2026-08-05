import CryptoKit
import XCTest

@testable import Sober

final class GuardianModeTests: XCTestCase {
  func testSignedRelationshipRequestMatchesFrozenCanonicalContract() async throws {
    let key = P256.Signing.PrivateKey()
    let session = GuardianSession(
      role: .person,
      relationshipID: "rel_test123",
      capabilityID: "rcap_person123",
      privateKey: key.rawRepresentation,
      inviteCode: nil,
      activeEventID: nil
    )
    let client = GuardianAPIClient(
      configuration: .init(baseURL: URL(string: "https://guardian.example.test")!),
      transport: { request in
        let path = request.url!.path
        let timestamp = request.value(forHTTPHeaderField: "Sober-Timestamp")!
        let nonce = request.value(forHTTPHeaderField: "Sober-Nonce")!
        let body = request.httpBody ?? Data()
        let canonical = [
          "guardian-api-v1", "GET", path, GuardianAPIClient.sha256Hex(body),
          session.relationshipID, session.capabilityID, timestamp, nonce, "",
        ].joined(separator: "\n")
        let signatureData = Self.decodeBase64URL(
          request.value(forHTTPHeaderField: "Sober-Signature")!
        )
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        XCTAssertTrue(key.publicKey.isValidSignature(signature, for: Data(canonical.utf8)))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), nil)
        return Self.relationshipResponse(role: "person")
      }
    )

    let envelope = try await client.relationship(for: session)
    XCTAssertEqual(envelope.relationship.relationshipId, session.relationshipID)
  }

  func testAlertRequestContainsOnlyMinimalServerTemplatedFields() async throws {
    let key = P256.Signing.PrivateKey()
    let eventID = UUID().uuidString.lowercased()
    let session = GuardianSession(
      role: .person,
      relationshipID: "rel_test123",
      capabilityID: "rcap_person123",
      privateKey: key.rawRepresentation,
      inviteCode: nil,
      activeEventID: eventID
    )
    let client = GuardianAPIClient(
      configuration: .init(baseURL: URL(string: "https://guardian.example.test")!),
      transport: { request in
        let object = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(Set(object.keys), [
          "occurredAt", "result", "source", "messageTemplateVersion",
        ])
        XCTAssertEqual(object["result"] as? String, "SIGNALS_DETECTED")
        XCTAssertEqual(object["source"] as? String, "liveCheck")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), eventID)
        let body = Self.alertJSON(eventID: eventID, state: "requestingHelp")
        return (body, Self.httpResponse(status: 202))
      }
    )

    let result = try await client.submitAlert(session: session, eventID: eventID, occurredAt: Date())
    XCTAssertEqual(result.alert.canonicalEventId, eventID)
    XCTAssertEqual(result.alert.personActionState, .requestingHelp)
  }

  func testGuardianCheckInProposalContainsNoLocationOrResultData() async throws {
    let key = P256.Signing.PrivateKey()
    let session = GuardianSession(
      role: .guardian,
      relationshipID: "rel_test123",
      capabilityID: "rcap_guardian123",
      privateKey: key.rawRepresentation,
      inviteCode: nil,
      activeEventID: nil
    )
    let client = GuardianAPIClient(
      configuration: .init(baseURL: URL(string: "https://guardian.example.test")!),
      transport: { request in
        let object = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(Set(object.keys), [
          "proposalId", "cadence", "localTime", "timeZoneIdentifier", "condition",
          "graceMinutes", "proposalConsentVersion",
        ])
        XCTAssertNil(object["latitude"])
        XCTAssertNil(object["longitude"])
        XCTAssertNil(object["result"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), object["proposalId"] as? String)
        return (
          Self.checkInJSON(state: "pendingPersonConsent", condition: "awayFromHome"),
          Self.httpResponse(status: 202)
        )
      }
    )

    let result = try await client.proposeCheckInPlan(
      session: session,
      localTime: "22:30",
      timeZoneIdentifier: "America/Chicago",
      condition: .awayFromHome,
      graceMinutes: 15
    )
    XCTAssertEqual(result.checkInPlan.state, .pendingPersonConsent)
  }

  func testAcceptedDailyCheckInBecomesDueAtConfiguredLocalTime() throws {
    let plan = Self.checkInPlan(condition: .always)
    let before = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-06T03:29:00Z"))
    let after = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-06T03:31:00Z"))

    guard case .upcoming = GuardianCheckInDueEvaluator.evaluate(
      plan: plan, now: before, homeIsConfigured: false
    ) else { return XCTFail("Expected upcoming before 10:30 PM Chicago time") }
    guard case let .due(occurrence) = GuardianCheckInDueEvaluator.evaluate(
      plan: plan, now: after, homeIsConfigured: false
    ) else { return XCTFail("Expected due after 10:30 PM Chicago time") }
    XCTAssertEqual(occurrence.id, "plan3-20260805-2230")
  }

  func testAwayFromHomeConditionUsesPrivateDistanceWithoutInferringImpairment() throws {
    let plan = Self.checkInPlan(condition: .awayFromHome)
    let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-06T03:31:00Z"))

    guard case .needsHome = GuardianCheckInDueEvaluator.evaluate(
      plan: plan, now: now, homeIsConfigured: false
    ) else { return XCTFail("Expected Home setup gate") }
    guard case .needsLocation = GuardianCheckInDueEvaluator.evaluate(
      plan: plan, now: now, homeIsConfigured: true
    ) else { return XCTFail("Expected explicit one-time location check") }
    guard case .waivedAtHome = GuardianCheckInDueEvaluator.evaluate(
      plan: plan, now: now, homeIsConfigured: true, distanceFromHomeMeters: 120,
      locationAccuracyMeters: 30
    ) else { return XCTFail("Expected at-Home waiver") }
    guard case .due = GuardianCheckInDueEvaluator.evaluate(
      plan: plan, now: now, homeIsConfigured: true, distanceFromHomeMeters: 450,
      locationAccuracyMeters: 40
    ) else { return XCTFail("Expected check-in due away from Home") }
    guard case .locationUncertain = GuardianCheckInDueEvaluator.evaluate(
      plan: plan, now: now, homeIsConfigured: true, distanceFromHomeMeters: 190,
      locationAccuracyMeters: 40
    ) else { return XCTFail("Expected uncertainty near the Home boundary") }
  }

  func testCompletedOccurrenceDoesNotExposeTheScreeningOutcome() throws {
    let completion = GuardianCheckInCompletion(
      occurrenceId: "plan3-20260805-2230",
      completedAt: "2026-08-06T03:40:00.000Z"
    )
    let plan = Self.checkInPlan(condition: .always, completion: completion)
    let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-06T03:41:00Z"))
    guard case .completed = GuardianCheckInDueEvaluator.evaluate(
      plan: plan, now: now, homeIsConfigured: false
    ) else { return XCTFail("Expected completed state") }
    let encoded = String(data: try JSONEncoder().encode(completion), encoding: .utf8)!
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("result"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("signal"))
    XCTAssertFalse(encoded.localizedCaseInsensitiveContains("score"))
  }

  func testScreeningLaunchCarriesScheduledOccurrenceOnlyWhenRequested() {
    let scheduled = ScreeningLaunch(
      mode: .check,
      scenario: .live,
      guardianCheckInOccurrenceID: "plan3-20260805-2230"
    )
    let ordinary = ScreeningLaunch(mode: .check, scenario: .live)
    XCTAssertEqual(scheduled.guardianCheckInOccurrenceID, "plan3-20260805-2230")
    XCTAssertNil(ordinary.guardianCheckInOccurrenceID)
  }

  @MainActor
  func testPendingEventIDIsPersistedBeforeSubmissionAndReused() async throws {
    let key = P256.Signing.PrivateKey()
    let initial = GuardianSession(
      role: .person,
      relationshipID: "rel_test123",
      capabilityID: "rcap_person123",
      privateKey: key.rawRepresentation,
      inviteCode: nil,
      activeEventID: nil
    )
    let store = MemoryGuardianStore(initial)
    let recorder = RequestRecorder()
    let client = GuardianAPIClient(
      configuration: .init(baseURL: URL(string: "https://guardian.example.test")!),
      transport: { request in
        await recorder.record(request)
        if request.httpMethod == "GET" {
          return Self.relationshipResponse(role: "person")
        }
        let eventID = request.url!.lastPathComponent
        return (Self.alertJSON(eventID: eventID, state: "requestingHelp"), Self.httpResponse(status: 202))
      }
    )
    let suiteName = "GuardianModeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }
    let model = AppModel(
      defaults: defaults,
      researchStore: ResearchSessionStore(directoryURL: directory),
      guardianStore: store,
      guardianAPI: client
    )
    await model.refreshGuardian()
    let eventID = UUID()
    await model.beginConcerningGuardianAlert(eventID: eventID)

    XCTAssertEqual(store.session?.activeEventID, eventID.uuidString.lowercased())
    XCTAssertEqual(model.guardianAlertState, .requestingHelp)
    let requests = await recorder.requests
    XCTAssertTrue(requests.contains { $0.url?.lastPathComponent == eventID.uuidString.lowercased() })
  }

  private static func relationshipResponse(role: String) -> (Data, URLResponse) {
    let data = Data("""
      {"relationship":{"relationshipId":"rel_test123","state":"active","role":"\(role)","personDisplayName":"Alex","activatedAt":"2026-08-05T12:00:00.000Z","expiresAt":"2026-11-03T12:00:00.000Z","guardianReachability":"inApp","guardianCapabilityId":null},"activeAlert":null,"requestId":"req_test"}
      """.utf8)
    return (data, httpResponse(status: 200))
  }

  private static func alertJSON(eventID: String, state: String) -> Data {
    Data("""
      {"alert":{"requestedEventId":"\(eventID)","canonicalEventId":"\(eventID)","workflowState":"reserved","personActionState":"\(state)","version":1,"createdAt":"2026-08-05T12:00:00.000Z","updatedAt":"2026-08-05T12:00:00.000Z","expiresAt":"2026-08-06T12:00:00.000Z","guardian":{"acknowledgedAt":null},"nextPollAfterMilliseconds":2000},"requestId":"req_test"}
      """.utf8)
  }

  private static func checkInPlan(
    condition: GuardianCheckInCondition,
    completion: GuardianCheckInCompletion? = nil
  ) -> GuardianCheckInPlanSnapshot {
    GuardianCheckInPlanSnapshot(
      proposalId: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
      version: 3,
      state: .active,
      cadence: "daily",
      localTime: "22:30",
      timeZoneIdentifier: "America/Chicago",
      condition: condition,
      graceMinutes: 15,
      proposedAt: "2026-08-05T15:00:00.000Z",
      decidedAt: "2026-08-05T15:05:00.000Z",
      lastCompletion: completion
    )
  }

  private static func checkInJSON(state: String, condition: String) -> Data {
    Data("""
      {"checkInPlan":{"proposalId":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","version":3,"state":"\(state)","cadence":"daily","localTime":"22:30","timeZoneIdentifier":"America/Chicago","condition":"\(condition)","graceMinutes":15,"proposedAt":"2026-08-05T15:00:00.000Z","decidedAt":null,"lastCompletion":null},"requestId":"req_test"}
      """.utf8)
  }

  private static func httpResponse(status: Int) -> HTTPURLResponse {
    HTTPURLResponse(
      url: URL(string: "https://guardian.example.test")!, statusCode: status,
      httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
    )!
  }

  private static func decodeBase64URL(_ value: String) -> Data {
    let normalized = value.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    return Data(base64Encoded: normalized.padding(
      toLength: ((normalized.count + 3) / 4) * 4,
      withPad: "=",
      startingAt: 0
    ))!
  }
}

private final class MemoryGuardianStore: GuardianSessionStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var value: GuardianSession?

  init(_ value: GuardianSession?) { self.value = value }

  var session: GuardianSession? {
    lock.withLock { value }
  }

  func load() throws -> GuardianSession? { lock.withLock { value } }
  func save(_ session: GuardianSession) throws { lock.withLock { value = session } }
  func delete() throws { lock.withLock { value = nil } }
}

private actor RequestRecorder {
  private(set) var requests: [URLRequest] = []
  func record(_ request: URLRequest) { requests.append(request) }
}
