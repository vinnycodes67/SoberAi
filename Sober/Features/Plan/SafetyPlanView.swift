import SwiftUI

// 0.5s: A calm stack of dark setup cards with one unmistakable destination form.
// User: someone configuring their safety plan before going out, who needs to save the exact place
// they want a ride to without confusing a nickname for an address.
// Emotional intent: calm and confident.
struct SafetyPlanView: View {
  @Binding var plan: SafetyPlan
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DSSpace.md) {
          ScreenHeader(
            eyebrow: "Safety Circle",
            title: "Plan your way home.",
            detail:
              "Set the exact ride destination and a person you can call or message while clear-headed."
          )

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

          SoberCard {
            VStack(alignment: .leading, spacing: DSSpace.md) {
              fieldLabel("Who is taking the check?")
              TextField("Your first name", text: $plan.userName)
                .textContentType(.name)
                .textFieldStyle(SoberTextFieldStyle())

              fieldLabel("Trusted contact")
              TextField("Contact name", text: $plan.contactName)
                .textContentType(.name)
                .textFieldStyle(SoberTextFieldStyle())
              TextField("Phone number", text: $plan.contactPhone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .textFieldStyle(SoberTextFieldStyle())
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
    }
  }

  private func fieldLabel(_ text: String) -> some View {
    Text(text.uppercased())
      .font(DSFont.footnoteStrong)
      .tracking(1.1)
      .foregroundStyle(Palette.primary)
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
