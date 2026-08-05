import Foundation

/// Pure validation for onboarding input. Holds no state and touches no scoring.
///
/// The point of this type is that a safety net configured wrong should fail
/// *loudly at setup*, not silently at 2am. Every check here answers one
/// question: would this configuration still alert someone?
struct OnboardingValidator: Sendable {
  static let minimumAgeYears = 13
  static let guardianConsentAgeYears = 18
  static let maximumAgeYears = 120
  static let maximumNameLength = 40

  /// Digits, links, and control characters in a display name are the signature
  /// of a paste error or an injection attempt, not a person's name.
  private static let disallowedNameCharacters = CharacterSet
    .decimalDigits
    .union(.controlCharacters)
    .union(CharacterSet(charactersIn: "<>{}[]|\\^~`@#$%*_=+/"))

  init() {}

  func validate(
    profile: UserProfile,
    safetyPlan: SafetyPlan,
    issuedFamilyCode: FamilyReferralCode? = nil,
    joinedFamilyCodes: Set<FamilyReferralCode> = []
  ) -> OnboardingValidation {
    var flags: [OnboardingRiskFlag] = []

    flags.append(contentsOf: nameFlags(profile.trimmedName))
    flags.append(contentsOf: ageFlags(profile.ageYears))
    flags.append(
      contentsOf: familyCodeFlags(
        profile.familyCode,
        issuedFamilyCode: issuedFamilyCode,
        joinedFamilyCodes: joinedFamilyCodes
      )
    )
    flags.append(contentsOf: guardianFlags(profile: profile, safetyPlan: safetyPlan))

    return OnboardingValidation(flags: flags)
  }

  /// Normalizes free text into a code, returning nil when the input cannot be a
  /// code at all. Callers map nil onto `.familyCodeMalformed`.
  func normalizeFamilyCode(_ input: String) -> FamilyReferralCode? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return FamilyReferralCode.normalized(trimmed)
  }

  // MARK: - Individual checks

  private func nameFlags(_ name: String) -> [OnboardingRiskFlag] {
    guard !name.isEmpty else { return [.nameMissing] }
    if name.count > Self.maximumNameLength {
      return [.nameImplausible]
    }
    if name.rangeOfCharacter(from: Self.disallowedNameCharacters) != nil {
      return [.nameImplausible]
    }
    return []
  }

  private func ageFlags(_ age: Int?) -> [OnboardingRiskFlag] {
    guard let age else { return [.ageMissing] }
    if age <= 0 || age > Self.maximumAgeYears {
      return [.ageImplausible]
    }
    if age < Self.minimumAgeYears {
      return [.ageBelowMinimum]
    }
    return []
  }

  private func familyCodeFlags(
    _ code: FamilyReferralCode?,
    issuedFamilyCode: FamilyReferralCode?,
    joinedFamilyCodes: Set<FamilyReferralCode>
  ) -> [OnboardingRiskFlag] {
    // Joining a family is optional; only a *present but wrong* code is a flag.
    guard let code else { return [] }

    if FamilyReferralCode.normalized(code.rawValue) == nil {
      return [.familyCodeMalformed]
    }
    // The app-side mirror of the contract's same-key rejection: redeeming your
    // own invite produces a "family" with one person in it and no second human
    // to acknowledge anything.
    if let issuedFamilyCode, code == issuedFamilyCode {
      return [.familyCodeIsSelfIssued]
    }
    if joinedFamilyCodes.contains(code) {
      return [.familyAlreadyJoined]
    }
    return []
  }

  private func guardianFlags(
    profile: UserProfile,
    safetyPlan: SafetyPlan
  ) -> [OnboardingRiskFlag] {
    var flags: [OnboardingRiskFlag] = []
    let guardianDigits = safetyPlan.normalizedContactPhone

    if !guardianDigits.isEmpty {
      if guardianDigits.count < 10 || guardianDigits.count > 15 {
        flags.append(.guardianPhoneMalformed)
      }
      // Same rule as G0-7 in the guardian contract: a guardian who is you is
      // not a guardian.
      if let selfDigits = safetyPlan.selfPhoneDigits,
        !selfDigits.isEmpty,
        selfDigits == guardianDigits
      {
        flags.append(.guardianPhoneMatchesUser)
      }
    }

    if safetyPlan.hasDuplicateContactPhones {
      flags.append(.duplicateGuardianPhones)
    }

    // A minor with no reachable guardian is the configuration most likely to
    // look complete and do nothing.
    if profile.isMinor, !safetyPlan.canAutomaticallyAlertParent {
      flags.append(.minorRequiresGuardianContact)
    }

    return flags
  }
}
