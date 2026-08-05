import SwiftUI

// 0.5s: one steady signal halo suspended over a dark field.
// User: someone pausing before a consequential decision, likely at night.
// Emotional intent: calm, protected, and never judged.
struct OnboardingView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var page = 0
  @State private var biometricConsent = false
  @State private var retentionConsent = false
  @State private var showingRetentionPolicy = false
  @State private var nameField = ""
  @State private var ageField = ""

  private let validator = OnboardingValidator()
  private static let pageCount = 4

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        SoberWordmark()
        Spacer()
        Text("\(page + 1) / \(Self.pageCount)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(Palette.textSecondary)
          .contentTransition(.numericText())
          .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: page)
      }
      .padding(.horizontal, 22)
      .padding(.top, 12)

      TabView(selection: $page) {
        introduction.tag(0)
        boundaries.tag(1)
        profile.tag(2)
        consent.tag(3)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .animation(reduceMotion ? nil : SoberMotion.screen, value: page)

      VStack(spacing: 14) {
        StepProgress(current: page, total: Self.pageCount)

        if page < Self.pageCount - 1 {
          Button("Continue") {
            if page == 2 { commitProfile() }
            page += 1
          }
          .buttonStyle(PrimaryActionButtonStyle())
          .disabled(page == 2 && profileValidation.isBlocked)
          .opacity(page == 2 && profileValidation.isBlocked ? 0.42 : 1)
        } else {
          Button("Explore founder demo") {
            model.completeOnboarding(founderPreview: true)
          }
          .buttonStyle(PrimaryActionButtonStyle())
          .disabled(!canConsent)
          .opacity(canConsent ? 1 : 0.42)

          Button("Start with a real baseline") {
            model.completeOnboarding(founderPreview: false)
          }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(canConsent ? Palette.textSecondary : Palette.textSecondary.opacity(0.45))
          .disabled(!canConsent)
        }
      }
      .padding(.horizontal, 22)
      .padding(.bottom, 18)
    }
    .soberBackground()
    .sheet(isPresented: $showingRetentionPolicy) {
      RetentionPolicyView()
        .preferredColorScheme(.dark)
    }
  }

  private var canConsent: Bool { biometricConsent && retentionConsent }

  private var introduction: some View {
    ScrollView {
      VStack(spacing: 30) {
        SignalHalo(size: 244)
          .padding(.top, 28)
          .soberEntrance(order: 0)

        VStack(spacing: 12) {
          Text("Take a beat before you move.")
            .font(.system(.largeTitle, design: .serif, weight: .semibold))
            .tracking(-1.2)
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.textPrimary)
          Text(
            "A short, private check for changes in reaction, coordination, and guided gaze, followed by a way home."
          )
          .font(.body)
          .multilineTextAlignment(.center)
          .foregroundStyle(Palette.textSecondary)
          .padding(.horizontal, 14)
        }
        .soberEntrance(order: 1)
      }
      .padding(.horizontal, 22)
    }
  }

  private var boundaries: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        ScreenHeader(
          eyebrow: "What Sober is",
          title: "A signal, never a green light.",
          detail:
            "This prototype screens for changes from your own baseline. It cannot measure BAC, diagnose impairment, or tell you it’s safe to drive."
        )
        .soberEntrance(order: 0)

        VStack(spacing: 10) {
          boundaryRow(
            icon: "hand.raised.fill", title: "No pass state",
            detail: "Every result keeps the safest choice visible.")
          boundaryRow(
            icon: "person.2.badge.gearshape", title: "A Safety Circle you control",
            detail:
              "You can invite one trusted guardian to receive a minimal help request. No employer or law-enforcement mode.")
          boundaryRow(
            icon: "iphone.and.arrow.forward", title: "Action built in",
            detail: "Call a ride or your person from every result.")
        }
        .soberEntrance(order: 1)
      }
      .padding(22)
    }
  }

  /// The draft the profile page is validating on every keystroke.
  private var profileDraft: UserProfile {
    UserProfile(
      displayName: nameField,
      ageYears: Int(ageField.trimmingCharacters(in: .whitespaces)),
      familyCode: nil
    )
  }

  private var profileValidation: OnboardingValidation {
    validator.validate(profile: profileDraft, safetyPlan: model.safetyPlan)
  }

  private func commitProfile() {
    model.userProfile = profileDraft
    // Keep the Safety Circle's display name in step with onboarding so the
    // alert copy and the family roster agree.
    model.safetyPlan.userName = profileDraft.trimmedName
  }

  private var profile: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        ScreenHeader(
          eyebrow: "Your details",
          title: "Who should your family see?",
          detail:
            "Your age stays on this iPhone. Your first name may appear in a help request to the guardian you choose. Neither is attached to research data."
        )
        .soberEntrance(order: 0)

        SoberCard {
          VStack(alignment: .leading, spacing: 18) {
            field(
              title: "Name",
              prompt: "First name",
              text: $nameField,
              contentType: .givenName
            )
            Divider().overlay(Palette.secondary.opacity(0.2))
            field(
              title: "Age",
              prompt: "\(OnboardingValidator.minimumAgeYears) or older",
              text: $ageField,
              keyboard: .numberPad
            )
          }
        }
        .soberEntrance(order: 1)

        if profileValidation.isOutOfOrdinary {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(profileValidation.flags, id: \.self) { flag in
              HStack(alignment: .top, spacing: 9) {
                Image(systemName: flag.isBlocking ? "exclamationmark.circle.fill" : "info.circle")
                  .foregroundStyle(flag.isBlocking ? Palette.accent : Palette.textSecondary)
                Text(flag.message)
                  .font(.footnote)
                  .foregroundStyle(flag.isBlocking ? Palette.textPrimary : Palette.textSecondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
              .accessibilityElement(children: .combine)
            }
          }
          .soberEntrance(order: 2)
        }
      }
      .padding(22)
    }
  }

  private func field(
    title: String,
    prompt: String,
    text: Binding<String>,
    keyboard: UIKeyboardType = .default,
    contentType: UITextContentType? = nil,
    autocapitalize: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.headline)
      TextField(prompt, text: text)
        .keyboardType(keyboard)
        .textContentType(contentType)
        .textInputAutocapitalization(autocapitalize ? .characters : .words)
        .autocorrectionDisabled(autocapitalize)
        .font(.body)
        .foregroundStyle(Palette.textPrimary)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
          Rectangle()
            .fill(Palette.secondary.opacity(0.28))
            .frame(height: 1)
        }
        .accessibilityLabel(title)
    }
  }

  private var consent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        ScreenHeader(
          eyebrow: "Your biometric data",
          title: "Processed here. Gone right after.",
          detail:
            "Eye and face landmarks are sensitive. They stay on this iPhone. If you enable Safety Circle, only a short safety alert leaves the device."
        )
        .soberEntrance(order: 0)

        SoberCard {
          VStack(spacing: 18) {
            consentToggle(
              title: "Camera processing",
              detail: "I consent to on-device eye and face landmark processing during a check.",
              isOn: $biometricConsent
            )
            Divider().overlay(Palette.secondary.opacity(0.2))
            consentToggle(
              title: "Retention and deletion",
              detail:
                "I understand raw frames are discarded after feature extraction and are never uploaded. Safety alerts never contain biometric data.",
              isOn: $retentionConsent
            )
          }
        }
        .soberEntrance(order: 1)

        Button("Read the retention policy") {
          showingRetentionPolicy = true
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Palette.primary)
        .soberEntrance(order: 2)

        Text("Prototype consent only, not legal advice or a production privacy policy.")
          .font(.caption)
          .foregroundStyle(Palette.textSecondary)
          .soberEntrance(order: 3)
      }
      .padding(22)
    }
  }

  private func boundaryRow(icon: String, title: String, detail: String) -> some View {
    SoberCard {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: icon)
          .font(.title3)
          .foregroundStyle(Palette.primary)
          .frame(width: 32, height: 32)
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.headline)
          Text(detail)
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
        }
      }
    }
  }

  private func consentToggle(
    title: String,
    detail: String,
    isOn: Binding<Bool>
  ) -> some View {
    Toggle(isOn: isOn) {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.headline)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(Palette.textSecondary)
      }
    }
    .toggleStyle(.switch)
    .tint(Palette.primary)
  }
}

struct RetentionPolicyView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          ScreenHeader(
            eyebrow: "Prototype policy",
            title: "Short memory by design.",
            detail: "The MVP is designed around data minimization."
          )

          policySection(
            "During a check",
            "Camera frames stay in memory long enough to derive landmarks and quality measures. They are not written to the photo library or a server."
          )
          policySection(
            "After a check",
            "Raw frames and face landmarks are discarded. The app may retain task summaries such as reaction time, quality score, and your own baseline."
          )
          policySection(
            "Sharing",
            "The MVP contains no advertising, analytics, biometric export, employer portal, or law-enforcement mode. If you explicitly enable Safety Circle, a concerning-result message is sent to the parent or guardian you provide."
          )
          policySection(
            "Your control",
            "Research Mode can export or delete the local session archive at any time. Resetting the prototype clears onboarding, Safety Circle, and consent state, and permanently deletes every stored research session, your measured baseline, and any export file this build wrote."
          )
        }
        .padding(22)
      }
      .soberBackground()
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private func policySection(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title).font(.headline)
      Text(detail)
        .foregroundStyle(Palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
