import SwiftUI

struct SafetyPlanView: View {
  @Binding var plan: SafetyPlan
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          ScreenHeader(
            eyebrow: "Safety Circle",
            title: "Put a parent in your corner.",
            detail:
              "Set this up while clear-headed. A concerning result can alert them immediately without waiting for you to compose a message."
          )

          SoberCard {
            Toggle(isOn: $plan.isActive) {
              VStack(alignment: .leading, spacing: 3) {
                Text("Safety Circle").font(.headline)
                Text(plan.isActive ? "Ride and parent plan active" : "Safety Circle paused")
                  .font(.caption)
                  .foregroundStyle(Palette.textSecondary)
              }
            }
            .tint(Palette.primary)
          }

          SoberCard {
            VStack(alignment: .leading, spacing: 16) {
              fieldLabel("Who is taking the check?")
              TextField("Your first name", text: $plan.userName)
                .textContentType(.name)
                .textFieldStyle(SoberTextFieldStyle())

              fieldLabel("Parent or guardian")
              TextField("Parent name", text: $plan.contactName)
                .textContentType(.name)
                .textFieldStyle(SoberTextFieldStyle())
              TextField("Phone number", text: $plan.contactPhone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .textFieldStyle(SoberTextFieldStyle())
            }
          }

          SoberCard {
            VStack(alignment: .leading, spacing: 16) {
              Toggle(isOn: $plan.automaticParentAlerts) {
                VStack(alignment: .leading, spacing: 4) {
                  Text("Automatic parent alert")
                    .font(.headline)
                  Text("Send immediately when Sober detects concerning signals")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                }
              }
              .tint(Palette.primary)

              Divider().overlay(Palette.secondary.opacity(0.2))

              Toggle(isOn: $plan.parentAlertConsent) {
                Text(
                  "I authorize Sober to send this safety result to the parent or guardian above."
                )
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
              }
              .tint(Palette.primary)
              .disabled(!plan.automaticParentAlerts)
              .opacity(plan.automaticParentAlerts ? 1 : 0.45)

              Label(
                "Only the safety message is shared—never camera footage, face landmarks, task scores, or an estimated substance level.",
                systemImage: "hand.raised.fill"
              )
              .font(.caption)
              .foregroundStyle(Palette.textSecondary)
            }
          }

          SoberCard {
            VStack(alignment: .leading, spacing: 16) {
              fieldLabel("Ride home")
              Picker("Preferred ride", selection: $plan.preferredRide) {
                Text("Uber").tag("Uber")
                Text("Lyft").tag("Lyft")
              }
              .pickerStyle(.segmented)

              TextField("Destination label", text: $plan.homeLabel)
                .textContentType(.fullStreetAddress)
                .textFieldStyle(SoberTextFieldStyle())
            }
          }

          Text(
            "Automatic delivery requires the parent-alert service configured for this build. Ride booking still requires your tap."
          )
          .font(.caption)
          .foregroundStyle(Palette.textSecondary)
          .padding(.horizontal, 4)
        }
        .soberEntrance()
        .padding(22)
      }
      .soberBackground()
      .navigationTitle("Safety Circle")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .onChange(of: plan.automaticParentAlerts) { _, isEnabled in
        if !isEnabled {
          plan.parentAlertConsent = false
        }
      }
    }
  }

  private func fieldLabel(_ text: String) -> some View {
    Text(text.uppercased())
      .font(.caption.weight(.semibold))
      .tracking(1.1)
      .foregroundStyle(Palette.primary)
  }
}

struct SoberTextFieldStyle: TextFieldStyle {
  func _body(configuration: TextField<Self._Label>) -> some View {
    configuration
      .padding(.horizontal, 14)
      .frame(minHeight: 48)
      .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Palette.secondary.opacity(0.25), lineWidth: 1)
      }
  }
}
