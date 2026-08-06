import SwiftUI

// 0.5s: one sentence on black, and room around it.
// User: someone pausing before a consequential decision, likely at night.
// Emotional intent: calm, protected, and never judged.
struct OnboardingView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var page = 0
  @State private var biometricConsent = false
  @State private var retentionConsent = false
  @State private var showingRetentionPolicy = false

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        SoberWordmark()
        Spacer()
        Text("\(page + 1) / 3")
          .font(SoberType.caption)
          .monospacedDigit()
          .tracking(0.9)
          .foregroundStyle(Palette.textTertiary)
          .contentTransition(.numericText())
          .animation(reduceMotion ? nil : SoberMotion.progress, value: page)
      }
      .padding(.horizontal, Space.lg)
      .padding(.top, Space.xs)
      .padding(.bottom, Space.xxs)

      TabView(selection: $page) {
        introduction.tag(0)
        boundaries.tag(1)
        consent.tag(2)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .animation(reduceMotion ? nil : SoberMotion.screen, value: page)

      VStack(spacing: Space.sm) {
        StepProgress(current: page, total: 3)

        if page < 2 {
          Button("Continue") {
            page += 1
          }
          .buttonStyle(PrimaryActionButtonStyle())
        } else {
          #if DEBUG
          Button("Explore founder demo") {
            model.completeOnboarding(founderPreview: true)
          }
          .buttonStyle(PrimaryActionButtonStyle())
          .disabled(!canConsent)
          .opacity(canConsent ? 1 : 0.42)
          #endif

          Button("Start with a real baseline") {
            model.completeOnboarding(founderPreview: false)
          }
          #if DEBUG
          .font(SoberType.subheadline)
          .foregroundStyle(canConsent ? Palette.textSecondary : Palette.textTertiary)
          .disabled(!canConsent)
          #else
          // With the founder demo compiled out, this is the only CTA on the
          // screen and needs to read as the primary action, not a footnote.
          .buttonStyle(PrimaryActionButtonStyle())
          .disabled(!canConsent)
          .opacity(canConsent ? 1 : 0.42)
          #endif
        }
      }
      .padding(.horizontal, Space.lg)
      .padding(.bottom, Space.md)
    }
    .soberBackground()
    .sheet(isPresented: $showingRetentionPolicy) {
      RetentionPolicyView()
    }
  }

  private var canConsent: Bool { biometricConsent && retentionConsent }

  private var introduction: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer(minLength: 0)

      Eyebrow("Impairment awareness", tint: Palette.accentBright)
        .soberEntrance(order: 0)

      Text("Take a beat\nbefore you move.")
        .font(SoberType.hero)
        .displayTracking()
        .foregroundStyle(Palette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, Space.sm)
        .soberEntrance(order: 1)

      Text(
        "A short, private check for changes in reaction, coordination, and guided gaze, followed by a way home."
      )
      .font(SoberType.body)
      .foregroundStyle(Palette.textSecondary)
      .lineSpacing(3)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, Space.sm)
      .soberEntrance(order: 2)

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Space.lg)
  }

  private var boundaries: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.lg) {
        ScreenHeader(
          eyebrow: "What Sober is",
          title: "A signal, never a green light.",
          detail:
            "This prototype screens for changes from your own baseline. It cannot measure BAC, diagnose impairment, or tell you it’s safe to drive."
        )
        .soberEntrance(order: 0)

        SoberCard(padding: 0) {
          VStack(spacing: 0) {
            boundaryRow(
              icon: "hand.raised", title: "No pass state",
              detail: "Every result keeps the safest choice visible.")
            SoberDivider().padding(.leading, Space.xxl)
            boundaryRow(
              icon: "person.2", title: "A Safety Circle you control",
              detail:
                "Name someone to call or message from a result with one tap. No employer or law-enforcement mode.")
            SoberDivider().padding(.leading, Space.xxl)
            boundaryRow(
              icon: "arrow.up.forward.app", title: "Action built in",
              detail: "Call a ride or your person from every result.")
            SoberDivider().padding(.leading, Space.xxl)
            boundaryRow(
              icon: "sun.max", title: "One step brightens the screen",
              detail:
                "A guided light check briefly flashes the screen three times. It's always skippable, and skipped for anyone with photosensitive epilepsy.")
          }
        }
        .soberEntrance(order: 1)
      }
      .padding(Space.lg)
    }
  }

  private var consent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.lg) {
        ScreenHeader(
          eyebrow: "Your biometric data",
          title: "Processed here. Gone right after.",
          detail:
            "Eye and face landmarks are sensitive. They stay on this iPhone. Calling or messaging your Safety Circle contact, and Guardian Mode's completed/missed check-in, never carry biometric data with them."
        )
        .soberEntrance(order: 0)

        SoberCard(padding: 0) {
          VStack(spacing: 0) {
            consentToggle(
              title: "Camera processing",
              detail: "I consent to on-device eye and face landmark processing during a check.",
              isOn: $biometricConsent
            )
            .padding(Space.md)
            SoberDivider()
            consentToggle(
              title: "Retention and deletion",
              detail:
                "I understand raw frames are discarded after feature extraction and are never uploaded, and nothing derived from them ever leaves this iPhone.",
              isOn: $retentionConsent
            )
            .padding(Space.md)
          }
        }
        .soberEntrance(order: 1)

        Button("Read the retention policy") {
          showingRetentionPolicy = true
        }
        .font(SoberType.subheadline)
        .foregroundStyle(Palette.accentBright)
        .soberEntrance(order: 2)

        Text("Prototype consent only. Not legal advice or a production privacy policy.")
          .font(SoberType.footnote)
          .foregroundStyle(Palette.textTertiary)
          .soberEntrance(order: 3)
      }
      .padding(Space.lg)
    }
  }

  private func boundaryRow(icon: String, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: Space.sm) {
      Image(systemName: icon)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Palette.accentBright)
        .frame(width: 22, height: 22)
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text(title)
          .font(SoberType.body)
          .foregroundStyle(Palette.textPrimary)
        Text(detail)
          .font(SoberType.subheadline)
          .foregroundStyle(Palette.textSecondary)
          .lineSpacing(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(Space.md)
  }

  private func consentToggle(
    title: String,
    detail: String,
    isOn: Binding<Bool>
  ) -> some View {
    Toggle(isOn: isOn) {
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text(title)
          .font(SoberType.body)
          .foregroundStyle(Palette.textPrimary)
        Text(detail)
          .font(SoberType.subheadline)
          .foregroundStyle(Palette.textSecondary)
          .lineSpacing(2)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .toggleStyle(.switch)
    .tint(Palette.accent)
  }
}

struct RetentionPolicyView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Space.lg) {
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
            "The MVP contains no advertising, analytics, biometric export, employer portal, or law-enforcement mode. Nothing is ever sent automatically: calling or messaging your Safety Circle contact always requires your tap, and Guardian Mode only ever shares whether a check was completed, never a score or raw data."
          )
          policySection(
            "Your control",
            "Research Mode can export or delete the local session archive at any time. Resetting the prototype clears onboarding, Safety Circle, and consent state, and permanently deletes every stored research session, your measured baseline, and any export file this build wrote."
          )
        }
        .padding(Space.lg)
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
    VStack(alignment: .leading, spacing: Space.xs) {
      Text(title).font(SoberType.body)
      Text(detail)
        .foregroundStyle(Palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}


/// Push-shaped body of the retention policy, for `SetupView`.
struct RetentionPolicyContent: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.lg) {
        Text(
          "Camera frames stay in memory only long enough to derive landmarks and quality measures. They are never written to the photo library, and never uploaded."
        )
        Text(
          "After a check, raw frames and face landmarks are discarded. What remains is a set of task summaries and your own baseline, stored on this iPhone."
        )
        Text(
          "Nothing is ever sent automatically. Calling or messaging your Safety Circle contact always requires your tap, and Guardian Mode shares only whether a check happened, never a score or any raw data."
        )
        Text(
          "You can export or delete everything at any time from the Research Center. Resetting the prototype deletes all of it permanently."
        )
        Text("Prototype policy only. Not legal advice or a production privacy policy.")
          .font(SoberType.footnote)
          .foregroundStyle(Palette.textMuted)
      }
      .font(SoberType.body)
      .foregroundStyle(Palette.textSecondary)
      .padding(.horizontal, Space.margin)
      .padding(.bottom, Space.xl)
    }
    .scrollIndicators(.hidden)
    .pageBackground()
    .navigationTitle("Privacy")
    .navigationBarTitleDisplayMode(.large)
  }
}

/// Push-shaped body of About, for `SetupView`.
struct AboutContent: View {
  private static let commitments = [
    "There is no safe-to-drive state, and there never will be.",
    "Saying you have had a drink ends the check immediately.",
    "A poor capture returns no result rather than a guess.",
    "A ride and a contact appear on every result.",
    "Guardian Mode is mutual, visible, and opt-in.",
    "Nothing derived from the camera leaves this iPhone.",
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.xl) {
        Text(
          "Sober compares you against your own baseline so you can pause and think. It cannot measure alcohol, diagnose impairment, or tell anyone they are safe to drive."
        )
        .font(SoberType.body)
        .foregroundStyle(Palette.textSecondary)
        .readingLine()

        Section_("What it holds to") {
          VStack(alignment: .leading, spacing: Space.md) {
            ForEach(Self.commitments, id: \.self) { line in
              HStack(alignment: .top, spacing: Space.sm) {
                Circle()
                  .fill(Palette.accent)
                  .frame(width: 5, height: 5)
                  .padding(.top, Space.xs)
                Text(line)
                  .font(SoberType.callout)
                  .foregroundStyle(Palette.textSecondary)
                  .readingLine()
              }
            }
          }
        }
      }
      .padding(.horizontal, Space.margin)
      .padding(.bottom, Space.xl)
    }
    .scrollIndicators(.hidden)
    .pageBackground()
    .navigationTitle("About Sober")
    .navigationBarTitleDisplayMode(.large)
  }
}
