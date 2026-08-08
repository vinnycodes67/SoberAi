import Foundation

/// Identity collected during onboarding. These fields are **app-local only**.
/// They are deliberately absent from `ResearchSessionEnvelope`: the research
/// archive stays pseudonymous, and `testOnboardingIdentityNeverReachesResearchExport`
/// pins that separation.
struct UserProfile: Codable, Equatable, Sendable {
  var displayName: String
  var ageYears: Int?
  var familyCode: FamilyReferralCode?

  init(
    displayName: String = "",
    ageYears: Int? = nil,
    familyCode: FamilyReferralCode? = nil
  ) {
    self.displayName = displayName
    self.ageYears = ageYears
    self.familyCode = familyCode
  }

  var trimmedName: String {
    displayName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// A minor still gets the full product; the difference is that an automatic
  /// guardian alert must be configured before a live check can send one.
  var isMinor: Bool {
    guard let ageYears else { return false }
    return ageYears < OnboardingValidator.guardianConsentAgeYears
  }

  private enum CodingKeys: String, CodingKey {
    case displayName
    case ageYears
    case familyCode
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    displayName = try values.decodeIfPresent(String.self, forKey: .displayName) ?? ""
    ageYears = try values.decodeIfPresent(Int.self, forKey: .ageYears)
    familyCode = try values.decodeIfPresent(FamilyReferralCode.self, forKey: .familyCode)
  }
}

/// The user-facing name for a guardian relationship invite.
///
/// This type only normalizes and shape-checks the code. Redemption itself is the
/// `POST /v1/guardian-relationships/{id}/redeem` call in `Docs/GUARDIAN_API.md` —
/// this is deliberately *not* a second invite mechanism, because a parallel one
/// would not carry the replay, self-guardianship, and revocation guarantees the
/// capability contract provides.
struct FamilyReferralCode: Codable, Equatable, Hashable, Sendable {
  /// Crockford-style base32 without I, L, O, or U so a code read aloud at night
  /// cannot be transcribed ambiguously.
  static let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
  static let length = 8

  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Uppercases and strips separators so "sober-a1b2 c3d4" and "A1B2C3D4" agree.
  static func normalized(_ input: String) -> FamilyReferralCode? {
    let stripped = input
      .uppercased()
      .filter { alphabet.contains($0) }
    guard stripped.count == length else { return nil }
    return FamilyReferralCode(rawValue: stripped)
  }

  var formatted: String {
    let midpoint = rawValue.index(rawValue.startIndex, offsetBy: Self.length / 2)
    return "\(rawValue[..<midpoint])-\(rawValue[midpoint...])"
  }
}

/// Anything out of the ordinary in onboarding input.
///
/// A flag never changes a screening result. `ScreeningEngine` takes no profile
/// input and its constants are untouched — these gate *setup*, so a safety net
/// that would silently fail is caught before anyone relies on it.
enum OnboardingRiskFlag: String, Codable, CaseIterable, Sendable {
  case nameMissing
  case nameImplausible
  case ageMissing
  case ageBelowMinimum
  case ageImplausible
  case minorRequiresGuardianContact
  case familyCodeMalformed
  case familyCodeIsSelfIssued
  case familyAlreadyJoined
  case guardianPhoneMalformed
  case guardianPhoneMatchesUser
  case duplicateGuardianPhones

  /// Blocking flags stop onboarding. Review flags are surfaced but allow the
  /// user to continue — the product must not strand someone mid-setup.
  var isBlocking: Bool {
    switch self {
    case .nameMissing,
      .nameImplausible,
      .ageMissing,
      .ageBelowMinimum,
      .ageImplausible,
      .familyCodeMalformed,
      .familyCodeIsSelfIssued,
      .guardianPhoneMatchesUser:
      return true
    case .minorRequiresGuardianContact,
      .familyAlreadyJoined,
      .guardianPhoneMalformed,
      .duplicateGuardianPhones:
      return false
    }
  }

  var message: String {
    switch self {
    case .nameMissing:
      return "Enter the name you want your family to see."
    case .nameImplausible:
      return "That name contains characters we can't display. Use letters, spaces, and hyphens."
    case .ageMissing:
      return "Enter your age."
    case .ageBelowMinimum:
      return "Sober isn't available under \(OnboardingValidator.minimumAgeYears)."
    case .ageImplausible:
      return "Enter an age between \(OnboardingValidator.minimumAgeYears) and \(OnboardingValidator.maximumAgeYears)."
    case .minorRequiresGuardianContact:
      return "Under \(OnboardingValidator.guardianConsentAgeYears), a guardian contact is required before automatic alerts can send."
    case .familyCodeMalformed:
      return "That family code doesn't look right. It's \(FamilyReferralCode.length) characters."
    case .familyCodeIsSelfIssued:
      return "That's your own family code. Ask the person inviting you for theirs."
    case .familyAlreadyJoined:
      return "You're already in this family."
    case .guardianPhoneMalformed:
      return "Check that phone number — alerts can't send to it as written."
    case .guardianPhoneMatchesUser:
      return "Your guardian's number can't be your own number."
    case .duplicateGuardianPhones:
      return "Two contacts share a number. Only one alert would send."
    }
  }
}

struct OnboardingValidation: Equatable, Sendable {
  let flags: [OnboardingRiskFlag]

  var isBlocked: Bool { flags.contains(where: \.isBlocking) }

  /// True when anything at all was out of the ordinary, blocking or not.
  var isOutOfOrdinary: Bool { !flags.isEmpty }
}
