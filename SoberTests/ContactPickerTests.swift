import XCTest

@testable import Sober

/// What a contact chosen from the system picker turns into. The picker itself
/// is system UI and runs out of process; this covers what Sober keeps.
final class ContactPickerTests: XCTestCase {

  func testAPersonIsNamedByTheirFullName() {
    let picked = PickedContact.make(
      givenName: " Jordan ", familyName: "Lee", organization: "Acme", phone: " (312) 555-0100 ")
    XCTAssertEqual(picked.name, "Jordan Lee")
    XCTAssertEqual(picked.phone, "(312) 555-0100")
  }

  func testACompanyCardFallsBackToTheOrganisation() {
    let picked = PickedContact.make(givenName: "", familyName: "", organization: "Campus Safety", phone: "3125550199")
    XCTAssertEqual(picked.name, "Campus Safety")
  }

  /// No name at all: blank, so the contact shows its number rather than a
  /// made-up label.
  func testAnUnnamedCardStaysUnnamed() {
    let picked = PickedContact.make(givenName: " ", familyName: "", organization: "", phone: "3125550199")
    XCTAssertEqual(picked.name, "")
  }

  /// The own-number field is what makes this rule fire; before it existed
  /// nothing in the app could set `selfPhone`.
  func testYourOwnNumberCannotBePickedAsAContact() {
    var plan = SafetyPlan()
    plan.selfPhone = "312-555-0100"
    let picked = PickedContact.make(givenName: "Me", familyName: "", organization: "", phone: "(312) 555-0100")
    let contact = GuardianContact(name: picked.name, phone: picked.phone)
    XCTAssertTrue(plan.issues(for: contact).contains(.phoneMatchesUser))
  }
}
