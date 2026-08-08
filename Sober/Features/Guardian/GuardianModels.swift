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
  let checkInPlan: GuardianCheckInPlanSnapshot?
  let locationSharing: GuardianLocationSharingSnapshot?
}

struct GuardianAlertEnvelope: Decodable, Sendable {
  let alert: GuardianAlertSnapshot
}

enum GuardianCheckInCondition: String, Codable, CaseIterable, Sendable {
  case always
  case awayFromHome

  var title: String {
    switch self {
    case .always: "Every day"
    case .awayFromHome: "Only when away from Home"
    }
  }
}

enum GuardianCheckInPlanState: String, Codable, Sendable {
  case pendingPersonConsent
  case active
  case declined
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }
}

struct GuardianCheckInCompletion: Codable, Equatable, Sendable {
  let occurrenceId: String
  let completedAt: String
}

struct GuardianCheckInPlanSnapshot: Codable, Equatable, Sendable {
  let proposalId: String
  let version: Int
  let state: GuardianCheckInPlanState
  let cadence: String
  let localTime: String
  let timeZoneIdentifier: String
  let condition: GuardianCheckInCondition
  let graceMinutes: Int
  let proposedAt: String
  let decidedAt: String?
  let lastCompletion: GuardianCheckInCompletion?

  var displayTime: String {
    guard let components = timeComponents else { return localTime }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone ?? .current
    guard let date = calendar.date(from: components) else { return localTime }
    return date.formatted(date: .omitted, time: .shortened)
  }

  var timeZone: TimeZone? { TimeZone(identifier: timeZoneIdentifier) }

  var timeComponents: DateComponents? {
    let values = localTime.split(separator: ":")
    guard values.count == 2, let hour = Int(values[0]), let minute = Int(values[1]) else {
      return nil
    }
    return DateComponents(hour: hour, minute: minute)
  }
}

struct GuardianCheckInPlanEnvelope: Decodable, Sendable {
  let checkInPlan: GuardianCheckInPlanSnapshot
}

struct GuardianSharedLocationSnapshot: Codable, Equatable, Sendable {
  let latitude: Double
  let longitude: Double
  let horizontalAccuracyMeters: Double
  let capturedAt: String

  var capturedDate: Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: capturedAt) ?? ISO8601DateFormatter().date(from: capturedAt)
  }
}

struct GuardianLocationSharingSnapshot: Codable, Equatable, Sendable {
  let enabled: Bool
  let updatedAt: String?
  let latestLocation: GuardianSharedLocationSnapshot?
}

struct GuardianLocationSharingEnvelope: Decodable, Sendable {
  let locationSharing: GuardianLocationSharingSnapshot
}

struct GuardianCheckInOccurrence: Equatable, Sendable {
  let id: String
  let dueAt: Date
  let graceEndsAt: Date
}

enum GuardianCheckInEvaluation: Equatable, Sendable {
  case inactive
  case upcoming(GuardianCheckInOccurrence)
  case needsHome(GuardianCheckInOccurrence)
  case needsLocation(GuardianCheckInOccurrence)
  case locationUncertain(GuardianCheckInOccurrence)
  case due(GuardianCheckInOccurrence)
  case completed(GuardianCheckInOccurrence)
  case waivedAtHome(GuardianCheckInOccurrence)
}

enum GuardianCheckInDueEvaluator {
  static let homeRadiusMeters = 200.0

  static func evaluate(
    plan: GuardianCheckInPlanSnapshot?,
    now: Date = Date(),
    homeIsConfigured: Bool,
    distanceFromHomeMeters: Double? = nil,
    locationAccuracyMeters: Double? = nil
  ) -> GuardianCheckInEvaluation {
    guard let plan, plan.state == .active,
      let zone = plan.timeZone,
      let time = plan.timeComponents,
      let hour = time.hour,
      let minute = time.minute
    else { return .inactive }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    guard let dueAt = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else {
      return .inactive
    }
    let occurrence = GuardianCheckInOccurrence(
      id: occurrenceID(plan: plan, dueAt: dueAt, calendar: calendar),
      dueAt: dueAt,
      graceEndsAt: dueAt.addingTimeInterval(TimeInterval(plan.graceMinutes * 60))
    )
    guard now >= dueAt else { return .upcoming(occurrence) }
    if plan.lastCompletion?.occurrenceId == occurrence.id { return .completed(occurrence) }

    switch plan.condition {
    case .always:
      return .due(occurrence)
    case .awayFromHome:
      guard homeIsConfigured else { return .needsHome(occurrence) }
      guard let distanceFromHomeMeters else { return .needsLocation(occurrence) }
      guard let locationAccuracyMeters, locationAccuracyMeters >= 0 else {
        return .locationUncertain(occurrence)
      }
      if distanceFromHomeMeters + locationAccuracyMeters <= homeRadiusMeters {
        return .waivedAtHome(occurrence)
      }
      if distanceFromHomeMeters - locationAccuracyMeters > homeRadiusMeters {
        return .due(occurrence)
      }
      return .locationUncertain(occurrence)
    }
  }

  private static func occurrenceID(
    plan: GuardianCheckInPlanSnapshot,
    dueAt: Date,
    calendar: Calendar
  ) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: dueAt)
    return String(
      format: "plan%d-%04d%02d%02d-%@",
      plan.version,
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0,
      plan.localTime.replacingOccurrences(of: ":", with: "")
    )
  }
}

enum GuardianAPIError: LocalizedError, Equatable, Sendable {
  case missingConfiguration
  case invalidInvite
  case invalidResponse
  case relationshipUnavailable
  case alertUnavailable
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
    case .alertUnavailable:
      "That Guardian help request is no longer available."
    case let .server(_, retryable):
      retryable
        ? "Guardian Mode is temporarily unavailable. Try again."
        : "The Guardian request could not be completed."
    }
  }
}
