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
            title: "Line up your way home.",
            detail:
              "Set this up while clear-headed. A concerning result puts a ride and a direct call or message to this contact one tap away."
          )

          SoberCard {
            Toggle(isOn: $plan.isActive) {
              VStack(alignment: .leading, spacing: 3) {
                Text("Safety Circle").font(.headline)
                Text(plan.isActive ? "Ride and contact plan active" : "Safety Circle paused")
                  .font(.caption)
                  .foregroundStyle(Palette.textSecondary)
              }
            }
            .tint(Palette.primary)
          }

          SoberCard {
            VStack(alignment: .leading, spacing: 16) {
              fieldLabel("Contact")
              TextField("Name", text: $plan.contactName)
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
            "Ride booking, calling, and messaging all require your tap — nothing here happens automatically."
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
