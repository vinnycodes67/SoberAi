import Foundation

enum GuardianRole: String, Codable, Sendable {
  case person
  case guardian
}

enum GuardianRelationshipState: String, Codable, Sendable {
  case pendingGuardian
  case active
  case revoked
  case expired
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }
}

enum GuardianPersonActionState: String, Codable, Sendable {
  case requestingHelp
  case guardianConfirmed
  case actNow
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }
}

enum GuardianAlertPresentationState: Equatable, Sendable {
  case notRequired
  case preview
  case notConfigured
  case requestingHelp
  case guardianConfirmed
  case actNow
}

struct GuardianSession: Codable, Equatable, Sendable {
  let role: GuardianRole
  let relationshipID: String
  let capabilityID: String
  let privateKey: Data
  var inviteCode: String?
  var activeEventID: String?
}

struct GuardianRelationshipSnapshot: Codable, Equatable, Sendable {
  let relationshipId: String
  let state: GuardianRelationshipState
  let role: GuardianRole
  let personDisplayName: String
  let activatedAt: String?
  let expiresAt: String
  let guardianReachability: String
  let guardianCapabilityId: String?
}

struct GuardianAlertSnapshot: Codable, Equatable, Sendable {
  struct GuardianStatus: Codable, Equatable, Sendable {
    let acknowledgedAt: String?
  }

  let requestedEventId: String
  let canonicalEventId: String
  let workflowState: String
  let personActionState: GuardianPersonActionState
  let version: Int
  let createdAt: String
  let updatedAt: String
  let expiresAt: String
  let guardian: GuardianStatus
  let nextPollAfterMilliseconds: Int
}

struct GuardianSetupResult: Sendable {
  let session: GuardianSession
  let relationship: GuardianRelationshipSnapshot?
}

struct GuardianRelationshipEnvelope: Decodable, Sendable {
  let relationship: GuardianRelationshipSnapshot
  let activeAlert: GuardianAlertSnapshot?
}

struct GuardianAlertEnvelope: Decodable, Sendable {
  let alert: GuardianAlertSnapshot
}

enum GuardianAPIError: LocalizedError, Equatable, Sendable {
  case missingConfiguration
  case invalidInvite
  case invalidResponse
  case relationshipUnavailable
  case server(code: String, retryable: Bool)

  var errorDescription: String? {
    switch self {
    case .missingConfiguration:
      "Guardian Mode needs a relay URL in this build."
    case .invalidInvite:
      "That invite is invalid, expired, or already used."
    case .invalidResponse:
      "Guardian Mode received an unreadable response."
    case .relationshipUnavailable:
      "This Guardian relationship is no longer available."
    case let .server(_, retryable):
      retryable
        ? "Guardian Mode is temporarily unavailable. Try again."
        : "The Guardian request could not be completed."
    }
  }
}

