import Foundation
import XCTest

@testable import Sober

final class ParentAlertReliabilityTests: XCTestCase {
  private let endpoint = URL(string: "https://alerts.example.test/v1/alerts")!

  func testServiceReusesItsStableEventIDAcrossRetries() async throws {
    let eventID = UUID()
    let recorder = AlertRequestRecorder()
    let service = ParentAlertService(
      configuration: configuredRelay,
      eventID: eventID,
      transport: { request in
        await recorder.capture(request)
        return Self.acceptedResponse(for: request, eventID: eventID)
      }
    )

    _ = try await service.send(outcome: concerningOutcome, safetyPlan: safetyPlan)
    _ = try await service.send(outcome: concerningOutcome, safetyPlan: safetyPlan)

    let capturedEventIDs = await recorder.eventIDs
    XCTAssertEqual(capturedEventIDs.count, 2)
    XCTAssertEqual(capturedEventIDs.map(\.header), [eventID.uuidString, eventID.uuidString])
    XCTAssertEqual(capturedEventIDs.map(\.body), [eventID.uuidString, eventID.uuidString])
  }

  func testPreparedRequestCanBeReusedAcrossServiceInstances() async throws {
    let eventID = UUID()
    let occurredAt = Date(timeIntervalSince1970: 1_800_000_000)
    let payload = ParentAlertRequest(
      outcome: concerningOutcome,
      safetyPlan: safetyPlan,
      eventID: eventID,
      occurredAt: occurredAt
    )
    let recorder = AlertRequestRecorder()
    let transport: ParentAlertService.Transport = { request in
      await recorder.capture(request)
      return Self.acceptedResponse(for: request, eventID: eventID)
    }

    _ = try await ParentAlertService(
      configuration: configuredRelay,
      transport: transport
    ).send(payload)
    _ = try await ParentAlertService(
      configuration: configuredRelay,
      transport: transport
    ).send(payload)

    let capturedEventIDs = await recorder.eventIDs
    XCTAssertEqual(capturedEventIDs.map(\.header), [eventID.uuidString, eventID.uuidString])
    XCTAssertEqual(capturedEventIDs.map(\.body), [eventID.uuidString, eventID.uuidString])
  }

  func testDeduplicatedRelayResponseIsDistinctFromNewAcceptance() async throws {
    let eventID = UUID()
    let data = try JSONSerialization.data(withJSONObject: [
      "submissionStatus": "deduplicated",
      "eventID": eventID.uuidString,
      "reference": "SM-DEDUPE",
    ])
    let service = ParentAlertService(
      configuration: configuredRelay,
      eventID: eventID,
      transport: { request in
        (data, Self.httpResponse(for: request, statusCode: 200))
      }
    )

    let receipt = try await service.send(outcome: concerningOutcome, safetyPlan: safetyPlan)
    XCTAssertEqual(receipt.submissionStatus, .deduplicated)
    XCTAssertEqual(receipt.reference, "SM-DEDUPE")
    XCTAssertEqual(receipt.eventID, eventID)
  }

  func testMalformedRelayResponseIsRejected() async {
    let service = ParentAlertService(
      configuration: configuredRelay,
      transport: { request in
        (Data("not-json".utf8), Self.httpResponse(for: request, statusCode: 202))
      }
    )

    await assertServiceError(.invalidResponse) {
      try await service.send(outcome: concerningOutcome, safetyPlan: safetyPlan)
    }
  }

  func testIncompleteRelayReceiptIsRejected() async {
    let data = try! JSONSerialization.data(withJSONObject: ["reference": "SM123"])
    let service = ParentAlertService(
      configuration: configuredRelay,
      transport: { request in
        (data, Self.httpResponse(for: request, statusCode: 202))
      }
    )

    await assertServiceError(.invalidResponse) {
      try await service.send(outcome: concerningOutcome, safetyPlan: safetyPlan)
    }
  }

  func testMismatchedRelayEventIDIsRejected() async {
    let requestEventID = UUID()
    let responseEventID = UUID()
    let service = ParentAlertService(
      configuration: configuredRelay,
      eventID: requestEventID,
      transport: { request in
        Self.acceptedResponse(for: request, eventID: responseEventID)
      }
    )

    await assertServiceError(.invalidResponse) {
      try await service.send(outcome: concerningOutcome, safetyPlan: safetyPlan)
    }
  }

  func testTransientRelayStatusIsRetryable() async {
    let service = ParentAlertService(
      configuration: configuredRelay,
      transport: { request in
        (Data(), Self.httpResponse(for: request, statusCode: 503))
      }
    )

    await assertServiceError(.temporarilyUnavailable(503)) {
      try await service.send(outcome: concerningOutcome, safetyPlan: safetyPlan)
    }
  }

  private var configuredRelay: ParentAlertConfiguration {
    ParentAlertConfiguration(
      endpoint: endpoint,
      bearerToken: "test-shared-token-at-least-20-characters"
    )
  }

  private var concerningOutcome: ScreeningOutcome {
    ScreeningEngine().evaluate(
      selfReport: .no,
      metrics: .demoClear,
      founderScenario: .signals
    )
  }

  private var safetyPlan: SafetyPlan {
    SafetyPlan(
      userName: "Alex",
      contactName: "Casey",
      contactPhone: "512-555-0147",
      automaticParentAlerts: true,
      parentAlertConsent: true
    )
  }

  private static func acceptedResponse(
    for request: URLRequest,
    eventID: UUID
  ) -> (Data, URLResponse) {
    let data = try! JSONSerialization.data(withJSONObject: [
      "submissionStatus": "accepted",
      "eventID": eventID.uuidString,
      "reference": "SM123",
    ])
    return (data, httpResponse(for: request, statusCode: 202))
  }

  private static func httpResponse(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
      url: request.url!,
      statusCode: statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
  }

  private func assertServiceError(
    _ expected: ParentAlertServiceError,
    operation: () async throws -> ParentAlertReceipt
  ) async {
    do {
      _ = try await operation()
      XCTFail("Expected \(expected)")
    } catch let error as ParentAlertServiceError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }
}

private actor AlertRequestRecorder {
  struct EventIDs: Sendable {
    let header: String?
    let body: String?
  }

  private(set) var eventIDs: [EventIDs] = []

  func capture(_ request: URLRequest) {
    let bodyEventID = request.httpBody.flatMap { data in
      (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["eventID"] as? String
    }
    eventIDs.append(
      EventIDs(
        header: request.value(forHTTPHeaderField: "Idempotency-Key"),
        body: bodyEventID
      )
    )
  }
}
