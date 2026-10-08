import SwiftUI

// 0.5s: A calm stack of dark setup cards with one unmistakable destination form.
// User: someone configuring their safety plan before going out, who needs to save the exact place
// they want a ride to without confusing a nickname for an address.
// Emotional intent: calm and confident.
struct SafetyPlanView: View {
  @Binding var plan: SafetyPlan
  @Environment(\.dismiss) private var dismiss
  @State private var editing: ContactEditTarget?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DSSpace.md) {
          ScreenHeader(
            eyebrow: "Safety Circle",
            title: "Plan your way home.",
            detail:
              "Set the exact ride destination and the people you can call or message while clear-headed."
          )

          // Internal only. `isActive` feeds `canAutomaticallyAlertParent`, which
          // also needs `automaticParentAlerts` -- and nothing in the public app
          // can set that. So in the build we ship this toggle changed nothing
          // either way: a working-looking control wired to nothing, which is
          // exactly what an App Completeness review flags.
          #if INTERNAL_BUILD
          SoberCard {
            Toggle(isOn: $plan.isActive) {
              VStack(alignment: .leading, spacing: DSSpace.xxs) {
                Text("Safety Circle").font(DSFont.headline)
                Text(
                  plan.isActive
                    ? "Ride and contact plan active"
                    : "Paused. Ride and contact stay available; automatic alerts do not."
                )
                  .font(DSFont.footnote)
                  .foregroundStyle(Palette.textSecondary)
              }
            }
            .tint(Palette.primary)
          }
          #endif

          SoberCard {
            VStack(alignment: .leading, spacing: DSSpace.md) {
              fieldLabel("Who is taking the check?")
              TextField("Your first name", text: $plan.userName)
                .textContentType(.name)
                .textFieldStyle(SoberTextFieldStyle())

            }
          }

          SoberCard {
            VStack(alignment: .leading, spacing: DSSpace.sm) {
              fieldLabel("Trusted contacts")
              if plan.contacts.isEmpty {
                Text("Add someone you can call or message from a result.")
                  .font(DSFont.footnote)
                  .foregroundStyle(DSPalette.textSecondary)
                  .fixedSize(horizontal: false, vertical: true)
              } else {
                DSRows {
                  ForEach(Array(plan.contacts.enumerated()), id: \.element.id) { index, contact in
                    if index > 0 { DSSeparator() }
                    contactRow(contact, isPrimary: index == 0)
                  }
                }
              }

              if plan.canAddContact {
                Button {
                  editing = ContactEditTarget(contact: GuardianContact(), isNew: true)
                } label: {
                  Label("Add contact", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSTertiaryButtonStyle())
              } else {
                Text("You can save up to \(SafetyPlan.maximumContacts) contacts.")
                  .font(DSFont.footnote)
                  .foregroundStyle(DSPalette.textMuted)
              }
            }
          }

          SoberCard {
            VStack(alignment: .leading, spacing: DSSpace.md) {
              fieldLabel("Ride destination")
              Picker("Preferred ride", selection: $plan.preferredRide) {
                Text("Uber").tag("Uber")
                Text("Lyft").tag("Lyft")
              }
              .pickerStyle(.segmented)

              TextField("Place name, such as Home or Campus", text: $plan.homeLabel)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .textFieldStyle(SoberTextFieldStyle())

              // Most people name this one of four things. The address still has
              // to be typed -- or filled from the Contacts card by iOS AutoFill,
              // since the public build has no network to look addresses up with.
              HStack(spacing: DSSpace.xs) {
                ForEach(["Home", "Dorm", "Campus", "Work"], id: \.self) { suggestion in
                  Button(suggestion) { plan.homeLabel = suggestion }
                    .font(DSFont.footnoteStrong)
                    .foregroundStyle(
                      plan.trimmedHomeLabel == suggestion
                        ? DSPalette.onAccent : DSPalette.textSecondary
                    )
                    .padding(.horizontal, DSSpace.sm)
                    .frame(minHeight: DSHit.minimum)
                    .background(
                      Capsule(style: .continuous)
                        .fill(
                          plan.trimmedHomeLabel == suggestion
                            ? DSPalette.accent : DSPalette.surface
                        )
                    )
                    .contentShape(Capsule(style: .continuous))
                    .accessibilityAddTraits(
                      plan.trimmedHomeLabel == suggestion ? [.isButton, .isSelected] : .isButton
                    )
                }
                Spacer(minLength: 0)
              }

              TextField("Full street address", text: $plan.homeAddress)
                .textContentType(.fullStreetAddress)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .textFieldStyle(SoberTextFieldStyle())

              Label(
                plan.hasRideDestination
                  ? "Ride drop-off: \(plan.destinationDisplayName)"
                  : "Add the exact drop-off address before you need a ride.",
                systemImage: plan.hasRideDestination ? "mappin.and.ellipse" : "location.slash"
              )
              .font(DSFont.footnote)
              .foregroundStyle(plan.hasRideDestination ? Palette.textSecondary : Palette.warning)
            }
          }

          Text(
            "Guardian Mode is configured separately and uses a two-device invite. Ride booking and direct contact always require your tap."
          )
          .font(DSFont.footnote)
          .foregroundStyle(Palette.textSecondary)
          .padding(.horizontal, DSSpace.xxs)
        }
        .soberEntrance()
        .padding(DSSpace.margin)
      }
      .soberBackground()
      .navigationTitle("Safety Circle")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: $editing) { target in
        GuardianContactEditor(plan: $plan, target: target)
      }
    }
  }

  private func contactRow(_ contact: GuardianContact, isPrimary: Bool) -> some View {
    DSRow(
      contact.displayName,
      detail: contactDetail(contact),
      trailing: {
        if isPrimary {
          DSBadge(text: "Primary", tint: DSPalette.textSecondary)
        }
      },
      action: { editing = ContactEditTarget(contact: contact, isNew: false) }
    )
    .accessibilityHint("Edits this contact")
  }

  private func contactDetail(_ contact: GuardianContact) -> String {
    var parts: [String] = []
    // A migrated contact already shows its number as the title.
    if !contact.trimmedName.isEmpty, !contact.phoneDigits.isEmpty {
      parts.append(contact.phone.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    if contact.phoneDigits.isEmpty {
      parts.append("No number yet")
    } else if !plan.issues(for: contact).isEmpty {
      parts.append("Check this number")
    } else {
      parts.append(GuardianContactEditor.permissionSummary(contact))
    }
    return parts.joined(separator: " · ")
  }

  private func fieldLabel(_ text: String) -> some View {
    Text(text.uppercased())
      .font(DSFont.footnoteStrong)
      .tracking(1.1)
      .foregroundStyle(Palette.primary)
  }
}

struct ContactEditTarget: Identifiable {
  var contact: GuardianContact
  let isNew: Bool
  var id: GuardianContact.ID { contact.id }
}

/// Adds or edits one contact. Changes reach the plan only on Save, so a
/// half-typed number never becomes the person a result screen dials.
struct GuardianContactEditor: View {
  @Binding var plan: SafetyPlan
  let target: ContactEditTarget

  @Environment(\.dismiss) private var dismiss
  @State private var draft: GuardianContact
  @State private var confirmingDelete = false
  @State private var makesPrimary: Bool

  init(plan: Binding<SafetyPlan>, target: ContactEditTarget) {
    _plan = plan
    self.target = target
    _draft = State(initialValue: target.contact)
    let leads =
      target.isNew
      ? plan.wrappedValue.contacts.isEmpty
      : plan.wrappedValue.primaryContact?.id == target.contact.id
    _makesPrimary = State(initialValue: leads)
  }

  static func permissionSummary(_ contact: GuardianContact) -> String {
    switch (contact.canCall, contact.canText) {
    case (true, true): return "Call or message"
    case (true, false): return "Call only"
    case (false, true): return "Message only"
    case (false, false): return "Hidden from results"
    }
  }

  private var issues: [GuardianContactIssue] { plan.issues(for: draft) }

  /// The first contact added, or the one already leading. Either way there is
  /// no one else to lead instead.
  private var isAlreadyPrimary: Bool {
    target.isNew ? plan.contacts.isEmpty : plan.primaryContact?.id == draft.id
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DSSpace.md) {
          SoberCard {
            VStack(alignment: .leading, spacing: DSSpace.md) {
              TextField("Name", text: $draft.name)
                .textContentType(.name)
                .textFieldStyle(SoberTextFieldStyle())
              TextField("Phone number", text: $draft.phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .textFieldStyle(SoberTextFieldStyle())

              // A blank number is not an error while someone is still typing;
              // Save stays off until there is one.
              ForEach(issues.filter { $0 != .phoneMissing }, id: \.self) { issue in
                Label(issue.message, systemImage: "exclamationmark.circle")
                  .font(DSFont.footnote)
                  .foregroundStyle(DSPalette.accent)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }

          SoberCard {
            VStack(alignment: .leading, spacing: DSSpace.sm) {
              // One of the two always stays on. A contact with neither would
              // sit in the list looking like a safety net and never appear
              // on a result.
              Toggle("Call from a result", isOn: $draft.canCall)
                .disabled(draft.canCall && !draft.canText)
                .frame(minHeight: DSHit.minimum)
              Toggle("Message from a result", isOn: $draft.canText)
                .disabled(draft.canText && !draft.canCall)
                .frame(minHeight: DSHit.minimum)
              Text("Calls and messages only start when you tap them.")
                .font(DSFont.footnote)
                .foregroundStyle(DSPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(DSFont.body)
            .tint(DSPalette.accent)
          }

          SoberCard {
            VStack(alignment: .leading, spacing: DSSpace.sm) {
              // Not switchable off: someone always leads, so the way to change
              // it is to make another contact primary.
              Toggle("Primary contact", isOn: $makesPrimary)
                .disabled(isAlreadyPrimary)
                .frame(minHeight: DSHit.minimum)
              Text("The primary contact gets the main call and message buttons on a result. Everyone else is one tap away under More contacts.")
                .font(DSFont.footnote)
                .foregroundStyle(DSPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(DSFont.body)
            .tint(DSPalette.accent)
          }

          if !target.isNew {
            Button("Delete contact", role: .destructive) { confirmingDelete = true }
              .buttonStyle(DSTertiaryButtonStyle(tint: DSPalette.textSecondary))
              .padding(.horizontal, DSSpace.xxs)
          }
        }
        .padding(DSSpace.margin)
      }
      .soberBackground()
      .navigationTitle(target.isNew ? "Add contact" : "Edit contact")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save)
            .disabled(!issues.isEmpty)
        }
      }
      .confirmationDialog(
        "Delete \(target.contact.displayName)?",
        isPresented: $confirmingDelete,
        titleVisibility: .visible
      ) {
        Button("Delete contact", role: .destructive) {
          plan.removeContact(id: draft.id)
          dismiss()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          isAlreadyPrimary && plan.contacts.count > 1
            ? "They won't appear on results. The next contact becomes primary."
            : "They won't appear on results."
        )
      }
    }
    .preferredColorScheme(.dark)
    .tint(DSPalette.accent)
  }

  private func save() {
    var contact = draft
    contact.name = contact.trimmedName
    contact.phone = contact.phone.trimmingCharacters(in: .whitespacesAndNewlines)
    if target.isNew {
      plan.addContact(contact)
    } else {
      plan.updateContact(contact)
    }
    if makesPrimary { plan.makePrimary(id: contact.id) }
    dismiss()
  }
}

struct SoberTextFieldStyle: TextFieldStyle {
  func _body(configuration: TextField<Self._Label>) -> some View {
    configuration
      .padding(.horizontal, DSSpace.sm)
      .frame(minHeight: 48)
      .background(Palette.surface, in: RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
          .stroke(Palette.secondary.opacity(0.25), lineWidth: 1)
      }
  }
}
