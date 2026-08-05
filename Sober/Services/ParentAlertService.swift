import Foundation

enum ParentAlertDeliveryState: Equatable, Sendable {
  case notRequired
  case preview
  case notConfigured
  case sending
  case sent
  case failed
}

enum ParentAlertPolicy {
  static func shouldSend(
    outcome: ScreeningOutcome,
    safetyPlan: SafetyPlan,
    isSample: Bool
  ) -> Bool {
    !isSample
      && outcome.state == .signalsDetected
      && safetyPlan.canAutomaticallyAlertParent
  }
}

enum ParentAlertSubmissionStatus: String, Decodable, Equatable, Sendable {
  case accepted
  case deduplicated
}

struct ParentAlertReceipt: Decodable, Equatable, Sendable {
  let submissionStatus: ParentAlertSubmissionStatus
  let reference: String
  let eventID: UUID
}

struct ParentAlertRequest: Encodable, Equatable, Sendable {
  let eventID: UUID
  let occurredAt: Date
  let result: String
  let userName: String
  let parentName: String
  let parentPhone: String
  let message: String

  init(
    outcome: ScreeningOutcome,
    safetyPlan: SafetyPlan,
    eventID: UUID = UUID(),
    occurredAt: Date = Date()
  ) {
    self.eventID = eventID
    self.occurredAt = occurredAt
    result = outcome.state.rawValue
    userName = safetyPlan.userName.trimmingCharacters(in: .whitespacesAndNewlines)
    parentName = safetyPlan.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
    parentPhone = safetyPlan.normalizedContactPhone
    message =
      "Sober safety alert: \(userName)'s check found concerning signals. This is not a diagnosis or a safe-to-drive test. Please contact \(userName) and help arrange a safe ride."
  }
}

enum ParentAlertServiceError: LocalizedError, Equatable {
  case missingConfiguration
  case invalidResponse
  case temporarilyUnavailable(Int)
  case rejected(Int)

  var errorDescription: String? {
    switch self {
    case .missingConfiguration:
      "Automatic delivery isn’t configured in this build."
    case .invalidResponse:
      "The alert service returned an unreadable response."
    case .temporarilyUnavailable:
      "The alert service is temporarily unavailable. Please try again."
    case .rejected:
      "The alert service did not accept the message."
    }
  }
}

struct ParentAlertConfiguration: Sendable {
  let endpoint: URL?
  let bearerToken: String?

  static func from(bundle: Bundle = .main) -> ParentAlertConfiguration {
    let endpointString = bundle.object(forInfoDictionaryKey: "SoberParentAlertAPIURL") as? String
    let token = bundle.object(forInfoDictionaryKey: "SoberParentAlertToken") as? String
    return ParentAlertConfiguration(
      endpoint: endpointString.flatMap { value in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : URL(string: trimmed)
      },
      bearerToken: token.flatMap { value in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
      }
    )
  }
}

struct ParentAlertService: Sendable {
  typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  let configuration: ParentAlertConfiguration
  let eventID: UUID
  let occurredAt: Date
  private let transport: Transport

  init(
    configuration: ParentAlertConfiguration = .from(),
    eventID: UUID = UUID(),
    occurredAt: Date = Date(),
    transport: @escaping Transport = { request in
      try await URLSession.shared.data(for: request)
    }
  ) {
    self.configuration = configuration
    self.eventID = eventID
    self.occurredAt = occurredAt
    self.transport = transport
  }

  func send(
    outcome: ScreeningOutcome,
    safetyPlan: SafetyPlan,
    eventID: UUID? = nil
  ) async throws -> ParentAlertReceipt {
    let payload = ParentAlertRequest(
      outcome: outcome,
      safetyPlan: safetyPlan,
      eventID: eventID ?? self.eventID,
      occurredAt: occurredAt
    )
    return try await send(payload)
  }

  func send(_ payload: ParentAlertRequest) async throws -> ParentAlertReceipt {
    guard let endpoint = configuration.endpoint,
      let bearerToken = configuration.bearerToken
    else {
      throw ParentAlertServiceError.missingConfiguration
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 12
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(payload.eventID.uuidString, forHTTPHeaderField: "Idempotency-Key")
    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder.soberAlertEncoder.encode(payload)

    let (data, response) = try await transport(request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ParentAlertServiceError.invalidResponse
    }
    if httpResponse.statusCode == 408
      || httpResponse.statusCode == 425
      || httpResponse.statusCode == 429
      || (500..<600).contains(httpResponse.statusCode)
    {
      throw ParentAlertServiceError.temporarilyUnavailable(httpResponse.statusCode)
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw ParentAlertServiceError.rejected(httpResponse.statusCode)
    }

    if data.isEmpty {
      throw ParentAlertServiceError.invalidResponse
    }
    do {
      let receipt = try JSONDecoder().decode(ParentAlertReceipt.self, from: data)
      let statusMatchesResponse =
        (httpResponse.statusCode == 202 && receipt.submissionStatus == .accepted)
        || (httpResponse.statusCode == 200 && receipt.submissionStatus == .deduplicated)
      guard receipt.eventID == payload.eventID,
        !receipt.reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        statusMatchesResponse
      else {
        throw ParentAlertServiceError.invalidResponse
      }
      return receipt
    } catch {
      throw ParentAlertServiceError.invalidResponse
    }
  }
}

/// Owns one screening run's parent-alert lifecycle.
///
/// The event ID has to outlive SwiftUI view re-creation. A `let` on a `View`
/// struct is re-initialised whenever SwiftUI rebuilds that struct, which would
/// hand every retry a fresh event ID and defeat relay deduplication — the
/// parent would receive one SMS per retry. Holding this as a `@StateObject`
/// keeps a single ID for the whole run.
@MainActor
final class ParentAlertCoordinator: ObservableObject {
  @Published private(set) var state: ParentAlertDeliveryState

  let eventID: UUID
  private let occurredAt: Date
  private let makeService: @MainActor (UUID, Date) -> ParentAlertService
  private var inFlight: Task<Void, Never>?

  init(
    state: ParentAlertDeliveryState = .notRequired,
    eventID: UUID = UUID(),
    occurredAt: Date = Date(),
    makeService: @escaping @MainActor (UUID, Date) -> ParentAlertService = { eventID, occurredAt in
      ParentAlertService(eventID: eventID, occurredAt: occurredAt)
    }
  ) {
    self.state = state
    self.eventID = eventID
    self.occurredAt = occurredAt
    self.makeService = makeService
  }

  /// Founder previews and sample results never contact the relay.
  func presentSample(for outcome: ScreeningOutcome) {
    state = outcome.state == .signalsDetected ? .preview : .notRequired
  }

  /// Starts delivery for a live result. Concerning results send immediately;
  /// anything else resolves to `notRequired` without contacting the relay.
  func send(outcome: ScreeningOutcome, safetyPlan: SafetyPlan) {
    guard outcome.state == .signalsDetected else {
      state = .notRequired
      return
    }
    guard ParentAlertPolicy.shouldSend(
      outcome: outcome,
      safetyPlan: safetyPlan,
      isSample: false
    ) else {
      state = .notConfigured
      return
    }
    // A retry while a send is already running, or after one succeeded, must not
    // produce a second provider submission.
    guard inFlight == nil, state != .sent else { return }

    state = .sending
    let service = makeService(eventID, occurredAt)
    inFlight = Task { [weak self] in
      defer { self?.inFlight = nil }
      do {
        _ = try await service.send(
          outcome: outcome,
          safetyPlan: safetyPlan,
          eventID: self?.eventID
        )
        self?.state = .sent
      } catch ParentAlertServiceError.missingConfiguration {
        self?.state = .notConfigured
      } catch {
        self?.state = .failed
      }
    }
  }

  /// Test hook: waits for any in-flight delivery to settle.
  func waitForDelivery() async {
    await inFlight?.value
  }
}

extension JSONEncoder {
  fileprivate static var soberAlertEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}
