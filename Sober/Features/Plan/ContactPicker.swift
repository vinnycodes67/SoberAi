import Contacts
import ContactsUI
import SwiftUI

/// A name and number chosen with the system contact picker.
struct PickedContact: Equatable, Sendable {
  let name: String
  let phone: String

  /// Full name if the card has one, otherwise organisation, otherwise blank so
  /// the contact shows its number.
  static func make(
    givenName: String, familyName: String, organization: String, phone: String
  ) -> PickedContact {
    let person = [givenName, familyName]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    let name = person.isEmpty ? organization.trimmingCharacters(in: .whitespacesAndNewlines) : person
    return PickedContact(name: name, phone: phone.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}

/// Presents `CNContactPickerViewController` when `isPresented` turns true.
///
/// The picker runs in its own process and hands back only the one contact the
/// person taps, so Sober never reads the address book and needs no Contacts
/// permission. What comes back is saved like a typed contact: on this iPhone
/// only.
///
/// Presented from UIKit rather than wrapped in a SwiftUI sheet: as a sheet's
/// root the picker dismisses itself the moment it appears.
struct ContactPickerPresenter: UIViewControllerRepresentable {
  @Binding var isPresented: Bool
  let onPick: (PickedContact) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

  func updateUIViewController(_ host: UIViewController, context: Context) {
    context.coordinator.parent = self
    guard isPresented, host.presentedViewController == nil else { return }
    let picker = CNContactPickerViewController()
    picker.delegate = context.coordinator
    picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
    // Only people with a number can be chosen. One number selects the person
    // straight away; several open their card so the right one is tapped.
    picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
    picker.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count == 1")
    picker.predicateForSelectionOfProperty = NSPredicate(format: "key == 'phoneNumbers'")
    DispatchQueue.main.async { host.present(picker, animated: true) }
  }

  final class Coordinator: NSObject, CNContactPickerDelegate {
    var parent: ContactPickerPresenter

    init(_ parent: ContactPickerPresenter) { self.parent = parent }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
      finish(contact, phone: contact.phoneNumbers.first?.value.stringValue)
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
      finish(property.contact, phone: (property.value as? CNPhoneNumber)?.stringValue)
    }

    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
      parent.isPresented = false
    }

    private func finish(_ contact: CNContact, phone: String?) {
      parent.isPresented = false
      guard let phone, !phone.isEmpty else { return }
      parent.onPick(
        PickedContact.make(
          givenName: contact.givenName, familyName: contact.familyName,
          organization: contact.organizationName, phone: phone))
    }
  }
}
