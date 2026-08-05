import XCTest

@testable import Sober

/// Onboarding is where a safety net gets configured wrong in a way that still
/// *looks* complete. These tests assert that anything out of the ordinary is
/// caught at setup, and that catching it never touches a screening result.
final class OnboardingRiskTests: XCTestCase {
  private let validator = OnboardingValidator()

  private func plan(
    contactPhone: String = "3125550142",
    selfPhone: String = "",
    additional: [String] = [],
    automatic: Bool = true,
    consent: Bool = true
  ) -> SafetyPlan {
    SafetyPlan(
      isActive: true,
      userName: "Vinay",
      contactName: "Parent",
      contactPhone: contactPhone,
      selfPhone: selfPhone,
      additionalContactPhones: additional,
      automaticParentAlerts: automatic,
      parentAlertConsent: consent
    )
  }

  private func profile(
    name: String = "Vinay",
    age: Int? = 22,
    code: FamilyReferralCode? = nil
  ) -> UserProfile {
    UserProfile(displayName: name, ageYears: age, familyCode: code)
  }

  // MARK: - The ordinary case

  func testCompleteOrdinaryOnboardingRaisesNoFlags() {
    let result = validator.validate(profile: profile(), safetyPlan: plan())
    XCTAssertFalse(result.isOutOfOrdinary)
    XCTAssertFalse(result.isBlocked)
    XCTAssertEqual(result.flags, [])
  }

  // MARK: - Name

  func testMissingNameBlocks() {
    let result = validator.validate(profile: profile(name: "   "), safetyPlan: plan())
    XCTAssertTrue(result.flags.contains(.nameMissing))
    XCTAssertTrue(result.isBlocked)
  }

  func testNameWithDigitsOrMarkupIsRejected() {
    for candidate in ["Vinay123", "<script>", "a@b.com", "name|pipe"] {
      let result = validator.validate(profile: profile(name: candidate), safetyPlan: plan())
      XCTAssertTrue(
        result.flags.contains(.nameImplausible),
        "expected \(candidate) to be implausible"
      )
    }
  }

  func testOverlongNameIsRejected() {
    let long = String(repeating: "a", count: OnboardingValidator.maximumNameLength + 1)
    let result = validator.validate(profile: profile(name: long), safetyPlan: plan())
    XCTAssertTrue(result.flags.contains(.nameImplausible))
  }

  func testHyphenatedAndAccentedNamesAreAccepted() {
    for candidate in ["Jean-Luc", "Zoë", "O'Brien", "Ana María"] {
      let result = validator.validate(profile: profile(name: candidate), safetyPlan: plan())
      XCTAssertFalse(
        result.flags.contains(.nameImplausible),
        "expected \(candidate) to be accepted"
      )
    }
  }

  // MARK: - Age

  func testMissingAgeBlocks() {
    let result = validator.validate(profile: profile(age: nil), safetyPlan: plan())
    XCTAssertTrue(result.flags.contains(.ageMissing))
    XCTAssertTrue(result.isBlocked)
  }

  func testAgeBelowMinimumBlocks() {
    let result = validator.validate(profile: profile(age: 12), safetyPlan: plan())
    XCTAssertTrue(result.flags.contains(.ageBelowMinimum))
    XCTAssertTrue(result.isBlocked)
  }

  func testImplausibleAgesBlock() {
    for age in [0, -4, 121, 900] {
      let result = validator.validate(profile: profile(age: age), safetyPlan: plan())
      XCTAssertTrue(result.flags.contains(.ageImplausible), "age \(age) should be implausible")
      XCTAssertTrue(result.isBlocked)
    }
  }

  func testMinimumAgeItselfIsAccepted() {
    let result = validator.validate(
      profile: profile(age: OnboardingValidator.minimumAgeYears),
      safetyPlan: plan()
    )
    XCTAssertFalse(result.flags.contains(.ageBelowMinimum))
    XCTAssertFalse(result.flags.contains(.ageImplausible))
  }

  // MARK: - Minors

  func testMinorWithoutReachableGuardianIsFlaggedButNotBlocked() {
    let result = validator.validate(
      profile: profile(age: 15),
      safetyPlan: plan(automatic: false, consent: false)
    )
    XCTAssertTrue(result.flags.contains(.minorRequiresGuardianContact))
    // Never blocking: stranding a teenager mid-setup is worse than proceeding
    // with the gap named on screen.
    XCTAssertFalse(result.isBlocked)
  }

  func testMinorWithReachableGuardianIsNotFlagged() {
    let result = validator.validate(profile: profile(age: 15), safetyPlan: plan())
    XCTAssertFalse(result.flags.contains(.minorRequiresGuardianContact))
    XCTAssertFalse(result.isOutOfOrdinary)
  }

  func testAdultWithoutGuardianIsNotFlaggedAsMinor() {
    let result = validator.validate(
      profile: profile(age: 30),
      safetyPlan: plan(automatic: false, consent: false)
    )
    XCTAssertFalse(result.flags.contains(.minorRequiresGuardianContact))
  }

  // MARK: - Family code

  func testFamilyCodeNormalizationIgnoresCaseAndSeparators() {
    let canonical = FamilyReferralCode.normalized("A1B2C3D4")
    XCTAssertEqual(validator.normalizeFamilyCode("a1b2-c3d4"), canonical)
    XCTAssertEqual(validator.normalizeFamilyCode(" A1B2 C3D4 "), canonical)
    XCTAssertEqual(validator.normalizeFamilyCode("a1b2c3d4"), canonical)
  }

  func testFamilyCodeRejectsAmbiguousLettersAndWrongLength() {
    // I, L, O, U are excluded from the alphabet, so a code containing them
    // cannot reach the required length.
    XCTAssertNil(validator.normalizeFamilyCode("AIBOCLDU"))
    XCTAssertNil(validator.normalizeFamilyCode("A1B2C3D"))
    XCTAssertNil(validator.normalizeFamilyCode("A1B2C3D4E"))
    XCTAssertNil(validator.normalizeFamilyCode(""))
  }

  func testMalformedFamilyCodeBlocks() {
    let result = validator.validate(
      profile: profile(code: FamilyReferralCode(rawValue: "nope")),
      safetyPlan: plan()
    )
    XCTAssertTrue(result.flags.contains(.familyCodeMalformed))
    XCTAssertTrue(result.isBlocked)
  }

  func testRedeemingYourOwnFamilyCodeBlocks() {
    let mine = FamilyReferralCode.normalized("A1B2C3D4")!
    let result = validator.validate(
      profile: profile(code: mine),
      safetyPlan: plan(),
      issuedFamilyCode: mine
    )
    XCTAssertTrue(result.flags.contains(.familyCodeIsSelfIssued))
    XCTAssertTrue(result.isBlocked)
  }

  func testAlreadyJoinedFamilyIsFlaggedButNotBlocked() {
    let code = FamilyReferralCode.normalized("A1B2C3D4")!
    let result = validator.validate(
      profile: profile(code: code),
      safetyPlan: plan(),
      joinedFamilyCodes: [code]
    )
    XCTAssertTrue(result.flags.contains(.familyAlreadyJoined))
    XCTAssertFalse(result.isBlocked)
  }

  func testOmittingTheFamilyCodeIsNotAnAnomaly() {
    let result = validator.validate(profile: profile(code: nil), safetyPlan: plan())
    XCTAssertFalse(result.isOutOfOrdinary)
  }

  // MARK: - Guardian numbers

  func testGuardianNumberEqualToUserNumberBlocks() {
    let result = validator.validate(
      profile: profile(),
      safetyPlan: plan(contactPhone: "312-555-0142", selfPhone: "(312) 555 0142")
    )
    XCTAssertTrue(result.flags.contains(.guardianPhoneMatchesUser))
    XCTAssertTrue(result.isBlocked)
  }

  func testDifferentlyFormattedButDistinctNumbersAreAccepted() {
    let result = validator.validate(
      profile: profile(),
      safetyPlan: plan(contactPhone: "312-555-0142", selfPhone: "(312) 555-0199")
    )
    XCTAssertFalse(result.flags.contains(.guardianPhoneMatchesUser))
  }

  func testTooShortGuardianNumberIsFlagged() {
    let result = validator.validate(profile: profile(), safetyPlan: plan(contactPhone: "5550142"))
    XCTAssertTrue(result.flags.contains(.guardianPhoneMalformed))
  }

  func testDuplicateFamilyNumbersAreFlagged() {
    let result = validator.validate(
      profile: profile(),
      safetyPlan: plan(contactPhone: "3125550142", additional: ["(312) 555-0142"])
    )
    XCTAssertTrue(result.flags.contains(.duplicateGuardianPhones))
  }

  func testDistinctFamilyNumbersAreNotFlagged() {
    let result = validator.validate(
      profile: profile(),
      safetyPlan: plan(contactPhone: "3125550142", additional: ["3125550188"])
    )
    XCTAssertFalse(result.flags.contains(.duplicateGuardianPhones))
  }

  // MARK: - Boundaries this feature must not cross

  func testOnboardingIdentityNeverReachesResearchExport() throws {
    let profileWithIdentity = UserProfile(
      displayName: "Vinay",
      ageYears: 17,
      familyCode: FamilyReferralCode.normalized("A1B2C3D4")
    )

    let envelope = ResearchSessionEnvelope(
      participantID: .generate(),
      sessionID: ResearchSessionID(rawValue: "session_identity_check"),
      startedAt: Date(),
      completedAt: Date(),
      metadata: ResearchSessionMetadata(
        device: ResearchDeviceMetadata(
          platform: "iOS",
          deviceModel: "iPhone",
          systemName: "iOS",
          systemVersion: "17.0",
          localeIdentifier: "en_US"
        ),
        app: ResearchAppMetadata(
          bundleIdentifier: "com.soberprototype.tests",
          version: "0.3.0",
          build: "1"
        ),
        protocolMetadata: ResearchProtocolMetadata(
          name: "Sober Research Battery",
          version: "0.3"
        )
      ),
      context: ResearchSessionContext(
        sessionKind: .soberBaseline,
        soberAtStartAttested: true,
        reportedAlcoholUse: false,
        reportedCannabisUse: false,
        sleepHours: 8,
        visionCorrection: .none,
        ambientLighting: .moderate
      ),
      metrics: ResearchScreeningMetrics(
        reactionTimeMilliseconds: 320,
        reactionMisses: 0,
        trackingError: 0.18,
        timeEstimateError: 0.08,
        gazeSmoothness: 0.16,
        qualityScore: 0.9,
        completedAllTasks: true
      )
    )

    let json = String(
      data: try JSONEncoder().encode(envelope),
      encoding: .utf8
    ) ?? ""

    XCTAssertFalse(json.contains(profileWithIdentity.trimmedName))
    XCTAssertFalse(json.contains("A1B2C3D4"))
    XCTAssertFalse(json.lowercased().contains("displayname"))
    XCTAssertFalse(json.lowercased().contains("ageyears"))
    XCTAssertFalse(json.lowercased().contains("familycode"))
  }

  func testProfileSurvivesJSONRoundTripAndLegacyRecordsDecode() throws {
    let original = UserProfile(
      displayName: "Vinay",
      ageYears: 22,
      familyCode: FamilyReferralCode.normalized("A1B2C3D4")
    )
    let restored = try JSONDecoder().decode(
      UserProfile.self,
      from: try JSONEncoder().encode(original)
    )
    XCTAssertEqual(restored, original)

    // A profile written before this feature existed decodes to empty rather
    // than failing and wiping the user's setup.
    let legacy = try JSONDecoder().decode(UserProfile.self, from: Data("{}".utf8))
    XCTAssertEqual(legacy.displayName, "")
    XCTAssertNil(legacy.ageYears)
    XCTAssertNil(legacy.familyCode)
  }

  func testLegacySafetyPlanWithoutNewPhoneFieldsStillDecodes() throws {
    let legacy = """
      {"isActive":true,"userName":"Vinay","contactName":"Parent",
       "contactPhone":"3125550142","automaticParentAlerts":true,
       "parentAlertConsent":true,"homeLabel":"Home","preferredRide":"Uber"}
      """
    let plan = try JSONDecoder().decode(SafetyPlan.self, from: Data(legacy.utf8))
    XCTAssertEqual(plan.selfPhone, "")
    XCTAssertEqual(plan.additionalContactPhones, [])
    XCTAssertEqual(plan.homeLabel, "")
    XCTAssertEqual(plan.homeAddress, "")
    XCTAssertTrue(plan.canAutomaticallyAlertParent)
    XCTAssertFalse(plan.hasDuplicateContactPhones)
  }

  func testSafetyPlanPersistsEditableDestinationNameAndAddress() throws {
    let original = SafetyPlan(
      homeLabel: "Campus apartment",
      homeAddress: "1234 West Main Street, Austin, TX 78701"
    )

    let restored = try JSONDecoder().decode(
      SafetyPlan.self,
      from: try JSONEncoder().encode(original)
    )

    XCTAssertEqual(restored.homeLabel, "Campus apartment")
    XCTAssertEqual(restored.homeAddress, "1234 West Main Street, Austin, TX 78701")
    XCTAssertEqual(restored.destinationDisplayName, "Campus apartment")
    XCTAssertTrue(restored.hasRideDestination)
  }

  func testLegacyAddressLikeHomeLabelMigratesToAddressField() throws {
    let legacy = """
      {"homeLabel":"850 West Jackson Boulevard, Chicago, IL 60607"}
      """

    let plan = try JSONDecoder().decode(SafetyPlan.self, from: Data(legacy.utf8))

    XCTAssertEqual(plan.homeLabel, "")
    XCTAssertEqual(plan.homeAddress, "850 West Jackson Boulevard, Chicago, IL 60607")
    XCTAssertTrue(plan.hasRideDestination)
  }
}
