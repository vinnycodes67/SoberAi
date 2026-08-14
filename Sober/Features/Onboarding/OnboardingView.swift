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
    VStack(spacing: DSSpace.xxs) {
      HStack {
        SoberWordmark()
        Spacer()
        Text("\(page + 1) / \(Self.pageCount)")
          .font(DSFont.footnote.monospacedDigit())
          .foregroundStyle(Palette.textSecondary)
          .contentTransition(.numericText())
          .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: page)
      }
      .padding(.horizontal, DSSpace.margin)
      .padding(.top, DSSpace.sm)

      TabView(selection: $page) {
        introduction.tag(0)
        boundaries.tag(1)
        profile.tag(2)
        consent.tag(3)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .animation(reduceMotion ? nil : SoberMotion.screen, value: page)

      VStack(spacing: DSSpace.sm) {
        StepProgress(current: page, total: Self.pageCount)

        if page < Self.pageCount - 1 {
          Button("Continue") {
            if page == 2 { commitProfile() }
            page += 1
          }
          .buttonStyle(PrimaryActionButtonStyle())
          .disabled(page == 2 && profileValidation.isBlocked)
          .opacity(page == 2 && profileValidation.isBlocked ? 0.42 : 1)

          // The page-style TabView already supports a swipe-back gesture,
          // but nothing on screen says so — this is the only visible way
          // to go back and review or fix an earlier step (most usefully,
          // your name/age on the profile step) without relying on someone
          // discovering the swipe.
          if page > 0 {
            Button("Back") { page -= 1 }
              .font(DSFont.subheadlineStrong)
              .foregroundStyle(Palette.textSecondary)
          }
        } else {
          // The real baseline is the primary action. The founder demo fabricates
          // a ready baseline, so it is compiled out of public builds entirely
          // rather than hidden behind a runtime check.
          Button("Start with a real baseline") {
            model.completeOnboarding(founderPreview: false)
          }
          .buttonStyle(PrimaryActionButtonStyle())
          .disabled(!canConsent)
          .opacity(canConsent ? 1 : 0.42)

          #if INTERNAL_BUILD
          Button("Explore founder demo") {
            model.completeOnboarding(founderPreview: true)
          }
          .font(DSFont.subheadlineStrong)
          .foregroundStyle(canConsent ? Palette.textSecondary : Palette.textSecondary.opacity(0.45))
          .disabled(!canConsent)
          #endif
        }
      }
      .padding(.horizontal, DSSpace.margin)
      .padding(.bottom, DSSpace.md)
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
      VStack(spacing: DSSpace.xl) {
        SignalHalo(size: 244)
          .padding(.top, DSSpace.lg)
          .soberEntrance(order: 0)

        VStack(spacing: DSSpace.sm) {
          Text("Take a beat before you move.")
            .font(DSFont.hero)
            .dsHeroTracking()
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.textPrimary)
          Text(
            "A short, private check for changes in reaction, coordination, and guided gaze, followed by a way home."
          )
          .font(DSFont.body)
          .multilineTextAlignment(.center)
          .foregroundStyle(Palette.textSecondary)
          .padding(.horizontal, DSSpace.sm)
        }
        .soberEntrance(order: 1)
      }
      .padding(.horizontal, DSSpace.margin)
    }
  }

  private var boundaries: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DSSpace.lg) {
        ScreenHeader(
          eyebrow: "What Sober is",
          title: "A signal, never a green light.",
          detail:
            "Sober checks for changes from your own measured baseline. It cannot measure BAC, diagnose impairment, or tell you it’s safe to drive."
        )
        .soberEntrance(order: 0)

        VStack(spacing: DSSpace.xs) {
          boundaryRow(
            icon: "hand.raised.fill", title: "No pass state",
            detail: "Every result keeps the safest choice visible.")
          boundaryRow(
            icon: boundaryPrivacyIcon,
            title: boundaryPrivacyTitle,
            detail: boundaryPrivacyDetail)
          boundaryRow(
            icon: "iphone.and.arrow.forward", title: "Action built in",
            detail: "Call a ride or your person from every result.")
        }
        .soberEntrance(order: 1)
      }
      .padding(DSSpace.margin)
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
    validator.validate(
      profile: profileDraft,
      safetyPlan: model.safetyPlan,
      requiresName: BuildChannel.allowsInternalTools,
      validatesGuardian: BuildChannel.allowsInternalTools
    )
  }

  private func commitProfile() {
    model.userProfile = profileDraft
    // Keep the Safety Plan's contact message in step with onboarding.
    model.safetyPlan.userName = profileDraft.trimmedName
  }

  private var profile: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DSSpace.margin) {
        ScreenHeader(
          eyebrow: "Your details",
          title: profileTitle,
          detail: profileDetail
        )
        .soberEntrance(order: 0)

        SoberCard {
          VStack(alignment: .leading, spacing: DSSpace.md) {
            field(
              title: profileNameFieldTitle,
              prompt: profileNamePrompt,
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
          VStack(alignment: .leading, spacing: DSSpace.xs) {
            ForEach(profileValidation.flags, id: \.self) { flag in
              HStack(alignment: .top, spacing: DSSpace.xs) {
                Image(systemName: flag.isBlocking ? "exclamationmark.circle.fill" : "info.circle")
                  .foregroundStyle(flag.isBlocking ? Palette.accent : Palette.textSecondary)
                Text(flag.message)
                  .font(DSFont.footnote)
                  .foregroundStyle(flag.isBlocking ? Palette.textPrimary : Palette.textSecondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
              .accessibilityElement(children: .combine)
            }
          }
          .soberEntrance(order: 2)
        }
      }
      .padding(DSSpace.margin)
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
    VStack(alignment: .leading, spacing: DSSpace.xxs) {
      Text(title).font(DSFont.headline)
      TextField(prompt, text: text)
        .keyboardType(keyboard)
        .textContentType(contentType)
        .textInputAutocapitalization(autocapitalize ? .characters : .words)
        .autocorrectionDisabled(autocapitalize)
        .font(DSFont.body)
        .foregroundStyle(Palette.textPrimary)
        .padding(.vertical, DSSpace.xs)
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
      VStack(alignment: .leading, spacing: DSSpace.margin) {
        ScreenHeader(
          eyebrow: "Your biometric data",
          title: "Processed here. Gone right after.",
          detail: biometricDetail
        )
        .soberEntrance(order: 0)

        SoberCard {
          VStack(spacing: DSSpace.md) {
            consentToggle(
              title: "Camera processing",
              detail: "I consent to on-device eye and face landmark processing during a check.",
              isOn: $biometricConsent
            )
            Divider().overlay(Palette.secondary.opacity(0.2))
            consentToggle(
              title: "Retention and deletion",
              detail: retentionConsentDetail,
              isOn: $retentionConsent
            )
          }
        }
        .soberEntrance(order: 1)

        Button("Read the retention policy") {
          showingRetentionPolicy = true
        }
        .font(DSFont.subheadlineStrong)
        .foregroundStyle(Palette.primary)
        .soberEntrance(order: 2)

        Text("You can review what Sober stores and delete all local data at any time in Settings.")
          .font(DSFont.footnote)
          .foregroundStyle(Palette.textSecondary)
          .soberEntrance(order: 3)
      }
      .padding(DSSpace.margin)
    }
  }

  private func boundaryRow(icon: String, title: String, detail: String) -> some View {
    SoberCard {
      HStack(alignment: .top, spacing: DSSpace.sm) {
        Image(systemName: icon)
          .font(DSFont.title)
          .foregroundStyle(Palette.primary)
          .frame(width: 32, height: 32)
        VStack(alignment: .leading, spacing: DSSpace.xxs) {
          Text(title).font(DSFont.headline)
          Text(detail)
            .font(DSFont.subheadline)
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
      VStack(alignment: .leading, spacing: DSSpace.xxs) {
        Text(title).font(DSFont.headline)
        Text(detail)
          .font(DSFont.subheadline)
          .foregroundStyle(Palette.textSecondary)
      }
    }
    .toggleStyle(.switch)
    .tint(Palette.primary)
  }

  private var boundaryPrivacyIcon: String {
    #if INTERNAL_BUILD
    "person.2.badge.gearshape"
    #else
    "iphone.and.arrow.down"
    #endif
  }

  private var boundaryPrivacyTitle: String {
    #if INTERNAL_BUILD
    "A Safety Circle you control"
    #else
    "Private by default"
    #endif
  }

  private var boundaryPrivacyDetail: String {
    #if INTERNAL_BUILD
    "You can invite one trusted Guardian to receive a minimal help request. No employer or law-enforcement mode."
    #else
    "The public app has no Sober server connection, family tracking, or remote result feed."
    #endif
  }

  private var profileTitle: String {
    #if INTERNAL_BUILD
    "Who should your family see?"
    #else
    "Confirm your age."
    #endif
  }

  private var profileDetail: String {
    #if INTERNAL_BUILD
    "Your age stays on this iPhone. Your first name may appear in a help request to the Guardian you choose. Neither is attached to research data."
    #else
    "Sober is available to people 13 and older. A name is optional. Both are stored in the app "
      + "and are never attached to camera frames or sent to Sober."
    #endif
  }

  private var profileNameFieldTitle: String {
    #if INTERNAL_BUILD
    "Name"
    #else
    "Name (optional)"
    #endif
  }

  private var profileNamePrompt: String {
    #if INTERNAL_BUILD
    "First name"
    #else
    "What should Sober call you?"
    #endif
  }

  private var biometricDetail: String {
    #if INTERNAL_BUILD
    "Eye and face landmarks are sensitive. They stay on this iPhone. If you enable Safety Circle, only a short safety alert leaves the device."
    #else
    "Eye and face landmarks are sensitive. They are processed on this iPhone and are never uploaded."
    #endif
  }

  private var retentionConsentDetail: String {
    #if INTERNAL_BUILD
    "I understand raw frames are discarded after feature extraction and are never uploaded. Safety alerts never contain biometric data."
    #else
    "I understand raw frames are discarded after feature extraction and are never uploaded."
    #endif
  }
}

struct RetentionPolicyView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DSSpace.margin) {
          ScreenHeader(
            eyebrow: "Privacy & retention",
            title: "Short memory by design.",
            detail: "Sober keeps only the local data needed for your baseline, History, and Safety Plan."
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
            sharingPolicy
          )
          policySection(
            "Your control",
            controlPolicy
          )
        }
        .padding(DSSpace.margin)
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
    VStack(alignment: .leading, spacing: DSSpace.xs) {
      Text(title).font(DSFont.headline)
      Text(detail)
        .foregroundStyle(Palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var sharingPolicy: String {
    #if INTERNAL_BUILD
    "The internal build contains no advertising or biometric export. If you explicitly enable Safety Circle, a concerning-result message is sent to the Guardian you provide."
    #else
    "The public app contains no advertising, analytics, biometric export, employer portal, family tracking, or remote result feed."
    #endif
  }

  private var controlPolicy: String {
    #if INTERNAL_BUILD
    "Research Mode can export or delete the local session archive at any time. Resetting clears onboarding, Safety Circle, consent state, stored research sessions, the measured baseline, and any prepared export file."
    #else
    "Resetting Sober clears onboarding, the Safety Plan, stored sessions, and your measured baseline from this iPhone."
    #endif
  }
}
