import SwiftUI
import UIKit

/// Settings and the Privacy Center.
///
/// One screen rather than a tree, because almost everything here is something a
/// person checks once and needs to find again under stress. The order is what
/// they are most likely to want: the way home first, then what the app knows
/// about them, then how to get rid of it.
struct SettingsView: View {
  @EnvironmentObject private var model: AppModel

  @State private var showingPlan = false
  @State private var showingAbout = false
  @State private var showingPrivacy = false
  @State private var showingPrivacyPolicy = false
  @State private var showingHowResultsWork = false
  @State private var showingReset = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DSSpace.xl) {
        header
        safety
        privacy
        about
        danger
      }
      .padding(.horizontal, DSSpace.margin)
      .padding(.bottom, DSSpace.xxl)
    }
    .background(DSPalette.background.ignoresSafeArea())
    .sheet(isPresented: $showingPlan) {
      SafetyPlanView(plan: $model.safetyPlan)
        .preferredColorScheme(.dark)
    }
    .sheet(isPresented: $showingAbout) {
      AboutSoberView()
        .environmentObject(model)
        .preferredColorScheme(.dark)
    }
    .sheet(isPresented: $showingPrivacy) {
      PrivacyCenterView()
        .environmentObject(model)
        .preferredColorScheme(.dark)
    }
    .sheet(isPresented: $showingPrivacyPolicy) {
      PrivacyPolicyView()
        .preferredColorScheme(.dark)
    }
    .sheet(isPresented: $showingHowResultsWork) {
      HowResultsWorkView()
        .preferredColorScheme(.dark)
    }
    .alert("Delete everything on this iPhone?", isPresented: $showingReset) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) { model.resetPrototype() }
    } message: {
      Text(
        "This removes your Safety Plan, recorded sessions, and measured baseline from this installation. "
          + "You would start a new baseline from zero. Older device backups are managed separately "
          + "in Apple settings."
      )
    }
    .onChange(of: model.privacyShieldIsVisible) { _, isShielded in
      // Sheets are separate presentation layers. Close every Settings sheet
      // before iOS captures the app-switcher snapshot.
      guard isShielded else { return }
      showingPlan = false
      showingAbout = false
      showingPrivacy = false
      showingPrivacyPolicy = false
      showingReset = false
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: DSSpace.sm) {
      DSEyebrow("Settings")
      Text("Sober")
        .font(DSFont.hero)
        .dsHeroTracking()
        .foregroundStyle(DSPalette.textPrimary)
        .accessibilityAddTraits(.isHeader)
    }
    .padding(.top, DSSpace.lg)
  }

  private var safety: some View {
    DSSection("Getting home") {
      DSRows {
        DSRow(
          "Safety Plan",
          detail: safetyPlanDetail,
          action: { showingPlan = true }
        )
      }
    }
  }

  private var safetyPlanDetail: String {
    if model.safetyPlan.hasRideDestination {
      return "\(model.safetyPlan.preferredRide) to \(model.safetyPlan.destinationDisplayName)"
    }
    return "Add a destination, a ride app, and someone to contact"
  }

  private var privacy: some View {
    DSSection("Privacy") {
      DSRows {
        DSRow(
          "Privacy Lock",
          detail: model.privacyLockEnabled
            ? "On · protects History, Your Steady, and Settings"
            : "Off · optional device-owner protection",
          action: { showingPrivacy = true }
        )
        DSSeparator()
        DSRow(
          "What Sober stores",
          detail: "Every kind of data, where it lives, and when it goes",
          action: { showingPrivacy = true }
        )
        DSSeparator()
        DSRow(
          "Privacy policy",
          detail: "How the public app handles camera processing and local data",
          action: { showingPrivacyPolicy = true }
        )
        .accessibilityIdentifier("privacy-policy-row")
      }
    }
  }

  private var about: some View {
    DSSection("About") {
      DSRows {
        DSRow(
          "How results work",
          detail: "The three answers a check can give, with examples",
          action: { showingHowResultsWork = true }
        )
        DSSeparator()
        DSRow(
          "What this app can and cannot tell you",
          detail: "The limits of a check",
          action: { showingAbout = true }
        )
        DSSeparator()
        DSValueRow(label: "Version", value: versionString)
      }
    }
  }

  private var danger: some View {
    DSSection("Data") {
      DSCard {
        VStack(alignment: .leading, spacing: DSSpace.sm) {
          Text("Delete all local data")
            .font(DSFont.headline)
            .foregroundStyle(DSPalette.textPrimary)
          Text(
            "This removes Sober's data from this installation. Sober has no account or server copy, "
              + "but an older iCloud or computer backup may retain app data until that backup is "
              + "replaced or deleted in Apple settings."
          )
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textSecondary)
          .dsReadingLine()
          Button("Delete all local data") { showingReset = true }
            .buttonStyle(DSTertiaryButtonStyle())
            .padding(.top, DSSpace.xxs)
        }
      }
    }
  }

  private var versionString: String {
    let bundle = Bundle.main
    let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    return "\(short) (\(build))"
  }
}

/// The plain-language data inventory.
///
/// Written to match the data classification table in the release plan, because
/// a privacy screen that disagrees with the App Privacy answers is worse than
/// no privacy screen. Anything added to one has to be added to the other.
struct PrivacyCenterView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var isChangingPrivacyLock = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DSSpace.xl) {
          VStack(alignment: .leading, spacing: DSSpace.sm) {
            Text("No Sober account or data server.")
              .font(DSFont.title)
              .dsTitleTracking()
              .foregroundStyle(DSPalette.textPrimary)
              .fixedSize(horizontal: false, vertical: true)
            Text(
              "Sober has no account or configured server connection. The list below explains what "
                + "the app stores locally and what removes it."
            )
            .font(DSFont.callout)
            .foregroundStyle(DSPalette.textSecondary)
            .dsReadingLine()
          }

          privacyLock

          DSSection("Never stored") {
            DSCard {
              VStack(alignment: .leading, spacing: DSSpace.xs) {
                item(
                  "Camera frames",
                  "Used for face and eye landmarks while a task runs, then gone. Never written "
                    + "to disk, never uploaded."
                )
                item("Video or audio", "Sober records neither.")
              }
            }
          }

          DSSection("Kept on this iPhone") {
            DSCard {
              VStack(alignment: .leading, spacing: DSSpace.xs) {
                item("Your steady", "The range your checks compare against. Removed by deleting all local data.")
                item(
                  "History",
                  "When you checked, how well the capture went, and which of the three results came "
                    + "out. Entries older than \(CheckHistoryStore.retentionDays) days are removed "
                    + "automatically, and only the most recent \(CheckHistoryStore.maximumEntries) are kept."
                )
                item("Session summaries", "Numbers only — no imagery. Removed by deleting all local data.")
                item("Safety Plan", "Your destination, ride app, and contact. Removed by deleting all local data.")
                item("Your optional name and age", "Used only to address you and to check you are old enough.")
                item(
                  "Device backups",
                  "Depending on your Apple settings, iOS may include Sober's app data in an iCloud "
                    + "or computer backup. Sober does not receive or control those backups."
                )
              }
            }
          }

          DSSection("Permissions") {
            DSRows {
              DSValueRow(label: "Camera", value: cameraPermissionLabel)
              DSSeparator()
              DSValueRow(label: "Location", value: "Not used", tint: DSPalette.textMuted)
              DSSeparator()
              DSValueRow(label: "Notifications", value: "Not used", tint: DSPalette.textMuted)
              DSSeparator()
              DSValueRow(label: "Contacts", value: "Not used", tint: DSPalette.textMuted)
            }

            if cameraPermissionNeedsSettings {
              Button("Open iPhone Settings", action: openSystemSettings)
                .buttonStyle(DSTertiaryButtonStyle())
                .padding(.top, DSSpace.xs)
            }
          }

          DSSection("Results are yours alone") {
            DSCard {
              Text(
                "A result is not proof of anything and cannot be shared from the app as though it "
                  + "were. If someone asks you to run a check and show them, you are under no "
                  + "obligation, and the result would not tell them what they think it does."
              )
              .font(DSFont.body)
              .foregroundStyle(DSPalette.textSecondary)
              .dsReadingLine()
            }
          }
        }
        .padding(DSSpace.margin)
      }
      .background(DSPalette.background.ignoresSafeArea())
      .navigationTitle("Privacy")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private var privacyLock: some View {
    DSSection("Privacy Lock") {
      DSCard(highlighted: model.privacyLockEnabled) {
        VStack(alignment: .leading, spacing: DSSpace.sm) {
          Toggle(isOn: privacyLockBinding) {
            VStack(alignment: .leading, spacing: DSSpace.xxs) {
              Text("Lock private screens")
                .font(DSFont.headline)
                .foregroundStyle(DSPalette.textPrimary)
              Text(model.privacyLockEnabled ? "On" : "Off")
                .font(DSFont.footnoteStrong)
                .foregroundStyle(DSPalette.textSecondary)
            }
          }
          .tint(DSPalette.accent)
          .disabled(
            isChangingPrivacyLock
              || (!model.privacyLockEnabled && !model.privacyLockIsAvailable)
          )

          Text(
            "After Sober has been away for 30 seconds, iOS protects History, Your Steady, and Settings with Face ID, Touch ID, or your device passcode. Home, Ride, Call, and Message stay available."
          )
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textSecondary)
          .dsReadingLine()

          if isChangingPrivacyLock {
            HStack(spacing: DSSpace.xs) {
              ProgressView().tint(DSPalette.textSecondary)
              Text("Waiting for iOS verification")
                .font(DSFont.footnote)
                .foregroundStyle(DSPalette.textMuted)
            }
            .accessibilityElement(children: .combine)
          } else if !model.privacyLockIsAvailable && !model.privacyLockEnabled {
            Text("Set up a device passcode, Face ID, or Touch ID in iPhone Settings to turn this on.")
              .font(DSFont.footnote)
              .foregroundStyle(DSPalette.textMuted)
              .dsReadingLine()
          }

          if let error = model.privacyLockError {
            Text(error)
              .font(DSFont.footnote)
              .foregroundStyle(DSPalette.textSecondary)
              .dsReadingLine()
          }
        }
      }
    }
  }

  private var privacyLockBinding: Binding<Bool> {
    Binding(
      get: { model.privacyLockEnabled },
      set: { isEnabled in
        guard !isChangingPrivacyLock else { return }
        isChangingPrivacyLock = true
        Task {
          _ = await model.setPrivacyLockEnabled(isEnabled)
          isChangingPrivacyLock = false
        }
      }
    )
  }

  private var cameraPermissionLabel: String {
    switch model.cameraPermissionState {
    case .notDetermined: "Asked when you start a check"
    case .restricted: "Restricted by iPhone settings"
    case .denied: "Off"
    case .authorized: "On · used only during a check"
    }
  }

  private var cameraPermissionNeedsSettings: Bool {
    switch model.cameraPermissionState {
    case .restricted, .denied: true
    case .notDetermined, .authorized: false
    }
  }

  private func openSystemSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    openURL(url)
  }

  private func item(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: DSSpace.xxs) {
      Text(title)
        .font(DSFont.subheadlineStrong)
        .foregroundStyle(DSPalette.textPrimary)
      Text(detail)
        .font(DSFont.footnote)
        .foregroundStyle(DSPalette.textSecondary)
        .dsReadingLine()
    }
    .padding(.vertical, DSSpace.xxs)
  }
}

/// The policy for the public, local-only App Store build. It intentionally
/// excludes Guardian and research tooling, which are reachable only in
/// SoberInternal.
struct PrivacyPolicyView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DSSpace.xl) {
          VStack(alignment: .leading, spacing: DSSpace.sm) {
            DSEyebrow("Effective August 13, 2026")
            Text("Privacy policy")
              .font(DSFont.hero)
              .dsHeroTracking()
              .foregroundStyle(DSPalette.textPrimary)
              .accessibilityAddTraits(.isHeader)
            Text(
              "This policy covers the public Sober app. Sober has no account, advertising, "
                + "analytics, or configured server connection."
            )
            .font(DSFont.callout)
            .foregroundStyle(DSPalette.textSecondary)
            .dsReadingLine()
          }

          policySection(
            "Camera processing",
            "When you start a check, Sober asks for camera access and processes face and eye "
              + "landmarks on this iPhone. Camera frames, video, and audio are not saved or uploaded. "
              + "You can deny access or turn it off later in iPhone Settings; the app then uses its "
              + "explicit no-camera path rather than inventing a reading."
          )
          policySection(
            "Data kept on this iPhone",
            "Sober keeps your optional name, age, Safety Plan, baseline session summaries, "
              + "preferences, and check History in the app’s private container. History is limited "
              + "to the newest 100 entries and entries are removed after 90 days. Baseline sessions "
              + "remain until you delete all local data. Depending on your Apple settings, iOS may "
              + "include this app data in an iCloud or computer backup. Sober does not receive or "
              + "control those backups."
          )
          policySection(
            "Data collection and sharing",
            "The public app does not upload personal data or measurements to Sober or a remote "
              + "result feed. It does not track you, sell data, show ads, or share results with a "
              + "parent, employer, insurer, school, law-enforcement agency, or other third party. "
              + "Ride, call, and message actions happen only after you tap them and open the relevant "
              + "system or third-party app, which operates under its own privacy policy. Sober does "
              + "not attach your check result."
          )
          policySection(
            "Your choices",
            "Camera processing and local retention require your agreement during onboarding. You "
              + "can review permissions in Privacy, remove camera access in iPhone Settings, or use "
              + "Delete all local data in Sober Settings. Deletion removes onboarding, the Safety "
              + "Plan, History, session summaries, and your measured baseline from the current "
              + "installation. It does not delete older device backups managed through Apple settings."
          )
          policySection(
            "Age and changes",
            "Sober is not available to children under 13. If this policy changes, the effective date and the in-app policy will be updated before new data practices take effect."
          )
          policySection(
            "Contact",
            "For privacy or support questions, email pulavarthyvinay@gmail.com. Do not send camera images, health information, or sensitive measurements."
          )
        }
        .padding(DSSpace.margin)
      }
      .background(DSPalette.background.ignoresSafeArea())
      .navigationTitle("Privacy policy")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private func policySection(_ title: String, _ detail: String) -> some View {
    DSSection(title) {
      DSCard {
        Text(detail)
          .font(DSFont.body)
          .foregroundStyle(DSPalette.textSecondary)
          .dsReadingLine()
      }
    }
  }
}
