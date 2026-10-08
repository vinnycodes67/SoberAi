import XCTest

@testable import Sober

/// Several contacts replaced one. The risks are a saved plan that loses its
/// contact on update, a list with no one leading it, and a result screen that
/// offers an action the user turned off.
final class GuardianContactTests: XCTestCase {

  private func decode(_ json: String) throws -> SafetyPlan {
    try JSONDecoder().decode(SafetyPlan.self, from: Data(json.utf8))
  }

  private func contact(_ name: String, _ phone: String, call: Bool = true, text: Bool = true)
    -> GuardianContact
  {
    GuardianContact(name: name, phone: phone, canCall: call, canText: text)
  }

  // MARK: - Legacy migration

  func testLegacyPlanWithOneContactBecomesThePrimary() throws {
    let plan = try decode(
      """
      {"isActive":true,"userName":"Alex","contactName":"Jordan","contactPhone":"312-555-0100",
       "selfPhone":"","additionalContactPhones":[],"automaticParentAlerts":false,
       "parentAlertConsent":false,"homeLabel":"Home","homeAddress":"1 Main St","preferredRide":"Uber"}
      """)
    XCTAssertEqual(plan.contacts.count, 1)
    let primary = try XCTUnwrap(plan.primaryContact)
    XCTAssertEqual(primary.name, "Jordan")
    XCTAssertEqual(primary.phone, "312-555-0100")
    XCTAssertTrue(primary.canCall)
    XCTAssertTrue(primary.canText)
    XCTAssertEqual(plan.homeAddress, "1 Main St")
  }

  func testLegacyExtraNumbersFollowThePrimaryAsNamelessContacts() throws {
    let plan = try decode(
      """
      {"contactName":"Jordan","contactPhone":"3125550100",
       "additionalContactPhones":["(312) 555-0111"," 3125550122 "]}
      """)
    XCTAssertEqual(plan.contacts.map(\.name), ["Jordan", "", ""])
    XCTAssertEqual(plan.contacts.map(\.phoneDigits), ["3125550100", "3125550111", "3125550122"])
    XCTAssertEqual(plan.primaryContact?.name, "Jordan")
    // No name: the number is what the user sees.
    XCTAssertEqual(plan.contacts[1].displayName, "(312) 555-0111")
    XCTAssertEqual(plan.contacts[2].displayName, "3125550122")
  }

  func testLegacyPlanWithNoContactDecodesEmpty() throws {
    let plan = try decode(#"{"contactName":"","contactPhone":"","additionalContactPhones":[]}"#)
    XCTAssertTrue(plan.contacts.isEmpty)
    XCTAssertFalse(plan.hasContact)
  }

  func testEmptyObjectDecodesToADefaultPlan() throws {
    let plan = try decode("{}")
    XCTAssertTrue(plan.contacts.isEmpty)
    XCTAssertEqual(plan.preferredRide, "Uber")
  }

  func testLegacyExtrasWithoutAPrimaryStillMigrate() throws {
    let plan = try decode(#"{"additionalContactPhones":["3125550111"]}"#)
    XCTAssertEqual(plan.contacts.map(\.phoneDigits), ["3125550111"])
    XCTAssertEqual(plan.primaryContact?.phoneDigits, "3125550111")
  }

  func testLegacyNameWithoutANumberIsKeptForTheUserToFinish() throws {
    let plan = try decode(#"{"contactName":"Jordan","contactPhone":""}"#)
    XCTAssertEqual(plan.contacts.map(\.name), ["Jordan"])
    XCTAssertFalse(plan.hasContact, "no number means nothing to offer on a result")
    XCTAssertEqual(plan.issues(for: plan.contacts[0]), [.phoneMissing])
  }

  func testLegacyBlankAndRepeatedExtrasAreDropped() throws {
    let plan = try decode(
      """
      {"contactName":"Jordan","contactPhone":"3125550100",
       "additionalContactPhones":["", "  ", "312.555.0100", "3125550111", "(312) 555-0111"]}
      """)
    XCTAssertEqual(plan.contacts.map(\.phoneDigits), ["3125550100", "3125550111"])
    XCTAssertFalse(plan.hasDuplicateContactPhones)
  }

  func testLegacyMigrationRespectsTheCap() throws {
    let extras = (1...8).map { "\"31255501\(10 + $0)\"" }.joined(separator: ",")
    let plan = try decode(
      #"{"contactName":"Jordan","contactPhone":"3125550100","additionalContactPhones":[\#(extras)]}"#
    )
    XCTAssertEqual(plan.contacts.count, SafetyPlan.maximumContacts)
    XCTAssertEqual(plan.primaryContact?.name, "Jordan")
  }

  // MARK: - Round trip

  func testEncodingWritesOnlyTheNewShapeAndRoundTrips() throws {
    let original = SafetyPlan(
      userName: "Alex",
      contacts: [contact("Jordan", "3125550100"), contact("Sam", "3125550111", call: false)],
      selfPhone: "3125550199",
      homeLabel: "Home",
      homeAddress: "1 Main St",
      preferredRide: "Lyft"
    )
    let data = try JSONEncoder().encode(original)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertNotNil(object["contacts"])
    XCTAssertNil(object["contactName"])
    XCTAssertNil(object["contactPhone"])
    XCTAssertNil(object["additionalContactPhones"])

    let decoded = try JSONDecoder().decode(SafetyPlan.self, from: data)
    XCTAssertEqual(decoded, original)
    XCTAssertFalse(decoded.contacts[1].canCall)
  }

  func testNewShapeWinsOverLeftoverLegacyKeys() throws {
    let plan = try decode(
      """
      {"contacts":[{"id":"6F1C1E0A-8C1D-4D3B-9C55-2B0B7A2E0001","name":"Sam","phone":"3125550111",
                    "canCall":true,"canText":false}],
       "contactName":"Jordan","contactPhone":"3125550100"}
      """)
    XCTAssertEqual(plan.contacts.map(\.name), ["Sam"])
    XCTAssertFalse(plan.contacts[0].canText)
  }

  // MARK: - Primary and cap

  func testFirstContactAddedIsPrimary() {
    var plan = SafetyPlan()
    XCTAssertNil(plan.primaryContact)
    let jordan = contact("Jordan", "3125550100")
    XCTAssertTrue(plan.addContact(jordan))
    plan.addContact(contact("Sam", "3125550111"))
    XCTAssertEqual(plan.primaryContact?.id, jordan.id)
  }

  func testDeletingThePrimaryPromotesTheNextContact() {
    let jordan = contact("Jordan", "3125550100")
    let sam = contact("Sam", "3125550111")
    var plan = SafetyPlan(contacts: [jordan, sam])
    plan.removeContact(id: jordan.id)
    XCTAssertEqual(plan.primaryContact?.id, sam.id)
    plan.removeContact(id: sam.id)
    XCTAssertNil(plan.primaryContact)
    XCTAssertTrue(plan.contacts.isEmpty)
  }

  func testMakePrimaryMovesOnlyThatContact() {
    let a = contact("A", "3125550100")
    let b = contact("B", "3125550111")
    let c = contact("C", "3125550122")
    var plan = SafetyPlan(contacts: [a, b, c])
    plan.makePrimary(id: c.id)
    XCTAssertEqual(plan.contacts.map(\.id), [c.id, a.id, b.id])
    plan.makePrimary(id: UUID())
    XCTAssertEqual(plan.contacts.map(\.id), [c.id, a.id, b.id], "unknown id changes nothing")
  }

  func testUpdateKeepsPosition() {
    let a = contact("A", "3125550100")
    var b = contact("B", "3125550111")
    var plan = SafetyPlan(contacts: [a, b])
    b.name = "Bea"
    b.canText = false
    plan.updateContact(b)
    XCTAssertEqual(plan.contacts.map(\.name), ["A", "Bea"])
    XCTAssertFalse(plan.contacts[1].canText)
  }

  func testCapIsEnforcedByAddAndInit() {
    let many = (0..<8).map { contact("P\($0)", "31255501\(10 + $0)") }
    var plan = SafetyPlan(contacts: many)
    XCTAssertEqual(plan.contacts.count, SafetyPlan.maximumContacts)
    XCTAssertFalse(plan.canAddContact)
    XCTAssertFalse(plan.addContact(contact("Late", "3125550199")))
    XCTAssertEqual(plan.contacts.count, SafetyPlan.maximumContacts)
  }

  func testAddingTheSameContactTwiceIsIgnored() {
    let jordan = contact("Jordan", "3125550100")
    var plan = SafetyPlan(contacts: [jordan])
    XCTAssertFalse(plan.addContact(jordan))
    XCTAssertEqual(plan.contacts.count, 1)
  }

  // MARK: - Validation

  func testValidContactHasNoIssues() {
    let plan = SafetyPlan(contacts: [contact("Jordan", "3125550100")])
    XCTAssertEqual(plan.issues(for: contact("Sam", "+1 (312) 555-0111")), [])
  }

  func testInvalidNumbersAreFlagged() {
    let plan = SafetyPlan()
    XCTAssertEqual(plan.issues(for: contact("Sam", "")), [.phoneMissing])
    XCTAssertEqual(plan.issues(for: contact("Sam", "call me")), [.phoneMissing])
    XCTAssertEqual(plan.issues(for: contact("Sam", "555-0111")), [.phoneMalformed])
    XCTAssertEqual(plan.issues(for: contact("Sam", "1234567890123456")), [.phoneMalformed])
  }

  func testOwnNumberIsRejectedForAnyContact() {
    let plan = SafetyPlan(contacts: [contact("Jordan", "3125550100")], selfPhone: "(312) 555-0199")
    XCTAssertEqual(plan.issues(for: contact("Me", "312.555.0199")), [.phoneMatchesUser])
  }

  func testDuplicateNumberIsRejectedButEditingYourselfIsNot() {
    let jordan = contact("Jordan", "3125550100")
    let plan = SafetyPlan(contacts: [jordan])
    XCTAssertEqual(plan.issues(for: contact("Sam", "(312) 555-0100")), [.duplicatePhone])
    var renamed = jordan
    renamed.name = "Jordan B"
    XCTAssertEqual(plan.issues(for: renamed), [], "a contact never duplicates its own stored copy")
  }

  func testOnboardingFlagsASecondaryContactMatchingTheUser() {
    let plan = SafetyPlan(
      userName: "Alex",
      contacts: [contact("Jordan", "3125550100"), contact("", "3125550199")],
      selfPhone: "3125550199"
    )
    let result = OnboardingValidator().validate(
      profile: UserProfile(displayName: "Alex", ageYears: 22), safetyPlan: plan)
    XCTAssertTrue(result.flags.contains(.guardianPhoneMatchesUser))
    XCTAssertTrue(result.isBlocked)
  }

  // MARK: - Result-screen selection

  func testPrimaryLeadsAndOthersFollowInOrder() {
    let a = contact("A", "3125550100")
    let b = contact("B", "3125550111")
    let c = contact("C", "3125550122")
    let plan = SafetyPlan(contacts: [a, b, c])
    XCTAssertEqual(plan.leadContact?.id, a.id)
    XCTAssertEqual(plan.otherReachableContacts.map(\.id), [b.id, c.id])
  }

  func testUnreachablePrimaryHandsTheLeadToTheNextContact() {
    let noNumber = contact("A", "")
    let silenced = contact("B", "3125550111", call: false, text: false)
    let c = contact("C", "3125550122")
    let plan = SafetyPlan(contacts: [noNumber, silenced, c])
    XCTAssertEqual(plan.leadContact?.id, c.id)
    XCTAssertTrue(plan.otherReachableContacts.isEmpty)
    XCTAssertTrue(plan.hasContact)
  }

  func testNoReachableContactMeansNoContactActions() {
    let plan = SafetyPlan(contacts: [contact("A", "", call: true, text: true)])
    XCTAssertNil(plan.leadContact)
    XCTAssertFalse(plan.hasContact)
  }

  func testCallAndMessageLinksRespectPermissions() throws {
    let callOnly = contact("A", "(312) 555-0100", call: true, text: false)
    XCTAssertEqual(callOnly.callURL?.absoluteString, "tel:3125550100")
    XCTAssertNil(callOnly.messageURL(body: "hi"))

    let textOnly = contact("B", "312-555-0111", call: false, text: true)
    XCTAssertNil(textOnly.callURL)
    let sms = try XCTUnwrap(textOnly.messageURL(body: "Can you pick me up?"))
    XCTAssertTrue(sms.absoluteString.hasPrefix("sms:3125550111?body=Can%20you%20pick%20me%20up?"))
  }

  func testAutomaticAlertsStillRequireANamedPrimaryWithAValidNumber() {
    var plan = SafetyPlan(
      userName: "Alex",
      contacts: [contact("", "3125550100"), contact("Sam", "3125550111")],
      automaticParentAlerts: true,
      parentAlertConsent: true
    )
    XCTAssertFalse(plan.canAutomaticallyAlertParent, "the primary has no name")
    plan.makePrimary(id: plan.contacts[1].id)
    XCTAssertTrue(plan.canAutomaticallyAlertParent)
  }
}
