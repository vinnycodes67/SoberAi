import SwiftUI

struct SafetyPlanView: View {
  @Binding var plan: SafetyPlan
  /// False when this is a tab destination rather than a presented sheet —
  /// there is nothing to dismiss, so the Done button must not appear.
  var showsDoneButton = true
  @Environment(\.dismiss) private var dismiss

  var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: Space.md) {
          ScreenHeader(
            eyebrow: "Safety Circle",
            title: "Line up your way home.",
            detail:
              "Set this up while clear-headed. A concerning result puts a ride and a direct call or message to this contact one tap away."
          )

          SoberCard {
            Toggle(isOn: $plan.isActive) {
              VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Safety Circle").font(SoberType.body)
                Text(plan.isActive ? "Ride and contact plan active" : "Safety Circle paused")
                  .font(SoberType.footnote)
                  .foregroundStyle(Palette.textSecondary)
              }
            }
            .tint(Palette.accent)
          }

          SoberCard {
            VStack(alignment: .leading, spacing: Space.md) {
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
            VStack(alignment: .leading, spacing: Space.md) {
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
            "Ride booking, calling, and messaging all require your tap. Nothing here happens automatically."
          )
          .font(SoberType.footnote)
          .foregroundStyle(Palette.textSecondary)
          .padding(.horizontal, Space.xxs)
        }
        .soberEntrance()
        .padding(Space.lg)
      }
      .soberBackground()
      .navigationTitle("Safety Circle")
      .navigationBarTitleDisplayMode(.inline)
  }

  private func fieldLabel(_ text: String) -> some View {
    Text(text.uppercased())
      .font(SoberType.footnoteStrong)
      .tracking(1.1)
      .foregroundStyle(Palette.accent)
  }
}

struct SoberTextFieldStyle: TextFieldStyle {
  func _body(configuration: TextField<Self._Label>) -> some View {
    configuration
      .padding(.horizontal, Space.sm)
      .frame(minHeight: 48)
      .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
          .stroke(Palette.line, lineWidth: 1)
      }
  }
}
