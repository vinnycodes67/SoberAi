import CryptoKit
import Foundation

struct GuardianAPIConfiguration: Sendable {
  let baseURL: URL?

  static func from(bundle: Bundle = .main) -> Self {
    let rawValue = bundle.object(forInfoDictionaryKey: "SoberGuardianAPIURL") as? String
    let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return Self(baseURL: trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : URL(string: trimmed))
  }
}

struct GuardianAPIClient: Sendable {
  typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  let configuration: GuardianAPIConfiguration
  private let transport: Transport
  private let encoder: JSONEncoder

  init(
    configuration: GuardianAPIConfiguration = .from(),
    transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
  ) {
    self.configuration = configuration
    self.transport = transport
    encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  }

  func createRelationship(personDisplayName: String) async throws -> GuardianSetupResult {
    let identity = P256.Signing.PrivateKey()
    let payload = CreateRelationshipRequest(
      personPublicKeyJwk: Self.publicJWK(for: identity.publicKey),
      personDisplayName: personDisplayName,
      senderConsentVersion: "guardian-sender-v1"
    )
    let response: CreateRelationshipResponse = try await sendUnsigned(
      method: "POST",
      path: "/v1/guardian-relationships",
      body: payload
    )
    return GuardianSetupResult(
      session: GuardianSession(
        role: .person,
        relationshipID: response.relationshipId,
        capabilityID: response.personCapabilityId,
        privateKey: identity.rawRepresentation,
        inviteCode: response.inviteCode,
        activeEventID: nil
      ),
      relationship: nil
    )
  }

  func redeem(inviteCode: String) async throws -> GuardianSetupResult {
    let parts = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).split(
      separator: ".", maxSplits: 1, omittingEmptySubsequences: true
    )
    guard parts.count == 2, parts[0].hasPrefix("rel_") else { throw GuardianAPIError.invalidInvite }
    let relationshipID = String(parts[0])
    let identity = P256.Signing.PrivateKey()
    let payload = RedeemRelationshipRequest(
      inviteToken: String(parts[1]),
      guardianPublicKeyJwk: Self.publicJWK(for: identity.publicKey),
      guardianConsentVersion: "guardian-recipient-v1",
      notificationDisclosureVersion: "notification-disclosure-v1",
      differentPersonAttestation: true
    )
    let response: RedeemRelationshipResponse
    do {
      response = try await sendUnsigned(
        method: "POST",
        path: "/v1/guardian-relationships/\(relationshipID)/redeem",
        body: payload
      )
    } catch GuardianAPIError.relationshipUnavailable {
      throw GuardianAPIError.invalidInvite
    }
    guard let capabilityID = response.relationship.guardianCapabilityId else {
      throw GuardianAPIError.invalidResponse
    }
    return GuardianSetupResult(
      session: GuardianSession(
        role: .guardian,
        relationshipID: relationshipID,
        capabilityID: capabilityID,
        privateKey: identity.rawRepresentation,
        inviteCode: nil,
        activeEventID: nil
      ),
      relationship: response.relationship
    )
  }

  func relationship(for session: GuardianSession) async throws -> GuardianRelationshipEnvelope {
    try await sendSigned(
      session: session,
      method: "GET",
      path: "/v1/guardian-relationships/\(session.relationshipID)",
      body: Optional<EmptyBody>.none,
      idempotencyKey: nil
    )
  }

  func submitAlert(
    session: GuardianSession,
    eventID: String,
    occurredAt: Date
  ) async throws -> GuardianAlertEnvelope {
    let payload = CreateAlertRequest(
      occurredAt: Self.timestamp(occurredAt),
      result: "SIGNALS_DETECTED",
      source: "liveCheck",
      messageTemplateVersion: "guardian-help-v1"
    )
    return try await sendSigned(
      session: session,
      method: "PUT",
      path: "/v1/guardian-relationships/\(session.relationshipID)/alerts/\(eventID)",
      body: payload,
      idempotencyKey: eventID
    )
  }

  func alert(session: GuardianSession, eventID: String) async throws -> GuardianAlertEnvelope {
    try await sendSigned(
      session: session,
      method: "GET",
      path: "/v1/guardian-relationships/\(session.relationshipID)/alerts/\(eventID)",
      body: Optional<EmptyBody>.none,
      idempotencyKey: nil
    )
  }

  func acknowledge(session: GuardianSession, eventID: String) async throws -> GuardianAlertEnvelope {
    try await sendSigned(
      session: session,
      method: "PUT",
      path: "/v1/guardian-relationships/\(session.relationshipID)/alerts/\(eventID)/acknowledgment",
      body: AcknowledgmentRequest(action: "helping"),
      idempotencyKey: eventID
    )
  }

  func revoke(session: GuardianSession) async throws {
    let _: EmptyResponse = try await sendSigned(
      session: session,
      method: "DELETE",
      path: "/v1/guardian-relationships/\(session.relationshipID)",
      body: Optional<EmptyBody>.none,
      idempotencyKey: nil
    )
  }

  private func sendUnsigned<Body: Encodable, Response: Decodable>(
    method: String,
    path: String,
    body: Body
  ) async throws -> Response {
    let bodyData = try encoder.encode(body)
    var request = try makeRequest(path: path, method: method)
    request.httpBody = bodyData
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    return try await perform(request)
  }

  private func sendSigned<Body: Encodable, Response: Decodable>(
    session: GuardianSession,
    method: String,
    path: String,
    body: Body?,
    idempotencyKey: String?
  ) async throws -> Response {
    let bodyData = try body.map { try encoder.encode($0) } ?? Data()
    let timestamp = Self.timestamp(Date())
    let nonce = Self.base64URL(Data((0..<18).map { _ in UInt8.random(in: .min ... .max) }))
    let canonical = [
      "guardian-api-v1", method, path, Self.sha256Hex(bodyData), session.relationshipID,
      session.capabilityID, timestamp, nonce, idempotencyKey ?? "",
    ].joined(separator: "\n")
    let key = try P256.Signing.PrivateKey(rawRepresentation: session.privateKey)
    let signature = try key.signature(for: Data(canonical.utf8)).rawRepresentation

    var request = try makeRequest(path: path, method: method)
    if !bodyData.isEmpty {
      request.httpBody = bodyData
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    request.setValue(session.relationshipID, forHTTPHeaderField: "Sober-Relationship-ID")
    request.setValue(session.capabilityID, forHTTPHeaderField: "Sober-Capability-ID")
    request.setValue(timestamp, forHTTPHeaderField: "Sober-Timestamp")
    request.setValue(nonce, forHTTPHeaderField: "Sober-Nonce")
    request.setValue(Self.base64URL(signature), forHTTPHeaderField: "Sober-Signature")
    if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
    return try await perform(request)
  }

  private func makeRequest(path: String, method: String) throws -> URLRequest {
    guard let baseURL = configuration.baseURL,
      let url = URL(string: path, relativeTo: baseURL)?.absoluteURL
    else { throw GuardianAPIError.missingConfiguration }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 12
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
    let (data, rawResponse) = try await transport(request)
    guard let response = rawResponse as? HTTPURLResponse else { throw GuardianAPIError.invalidResponse }
    if response.statusCode == 204, Response.self == EmptyResponse.self {
      return EmptyResponse() as! Response
    }
    guard (200..<300).contains(response.statusCode) else {
      if response.statusCode == 404 { throw GuardianAPIError.relationshipUnavailable }
      if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
        throw GuardianAPIError.server(code: envelope.error.code, retryable: envelope.error.retryable)
      }
      throw GuardianAPIError.invalidResponse
    }
    do { return try JSONDecoder().decode(Response.self, from: data) }
    catch { throw GuardianAPIError.invalidResponse }
  }

  private static func publicJWK(for publicKey: P256.Signing.PublicKey) -> PublicJWK {
    let bytes = publicKey.x963Representation
    return PublicJWK(
      kty: "EC",
      crv: "P-256",
      x: base64URL(bytes.subdata(in: 1..<33)),
      y: base64URL(bytes.subdata(in: 33..<65))
    )
  }

  static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  static func timestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}

private struct PublicJWK: Codable, Sendable {
  let kty: String
  let crv: String
  let x: String
  let y: String
}

private struct CreateRelationshipRequest: Encodable {
  let personPublicKeyJwk: PublicJWK
  let personDisplayName: String
  let senderConsentVersion: String
}

private struct CreateRelationshipResponse: Decodable {
  let relationshipId: String
  let personCapabilityId: String
  let inviteCode: String
}

private struct RedeemRelationshipRequest: Encodable {
  let inviteToken: String
  let guardianPublicKeyJwk: PublicJWK
  let guardianConsentVersion: String
  let notificationDisclosureVersion: String
  let differentPersonAttestation: Bool
}

private struct RedeemRelationshipResponse: Decodable {
  let relationship: GuardianRelationshipSnapshot
}

private struct CreateAlertRequest: Encodable {
  let occurredAt: String
  let result: String
  let source: String
  let messageTemplateVersion: String
}

private struct AcknowledgmentRequest: Encodable { let action: String }
private struct EmptyBody: Encodable {}
private struct EmptyResponse: Decodable {}
private struct ErrorEnvelope: Decodable {
  struct APIError: Decodable { let code: String; let retryable: Bool }
  let error: APIError
}
