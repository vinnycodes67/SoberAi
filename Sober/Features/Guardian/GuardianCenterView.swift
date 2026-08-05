import SwiftUI
import UIKit

// 0.5s: relationship status first; if help is pending, one dominant “I’m helping” action.
// User: either inviting one trusted person or responding to that person's request.
// Emotional intent: calm, immediate, and accountable without exposing test details.
struct GuardianCenterView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var inviteCode = ""
  @State private var senderConsent = false
  @State private var guardianConsent = false
  @State private var showingRevokeConfirmation = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          header

          if let session = model.guardianSession {
            relationshipContent(session)
          } else {
            setupContent
          }

          if let error = model.guardianError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .font(.subheadline)
              .foregroundStyle(Palette.warning)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 4)
          }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 28)
      }
      .soberBackground()
      .navigationTitle("Guardian Mode")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .refreshable { await model.refreshGuardian() }
      .task(id: model.guardianSession?.relationshipID) {
        while !Task.isCancelled, model.guardianSession != nil {
          await model.refreshGuardian()
          try? await Task.sleep(for: .seconds(3))
        }
      }
      .confirmationDialog(
        "Disconnect Guardian Mode?",
        isPresented: $showingRevokeConfirmation,
        titleVisibility: .visible
      ) {
        Button("Disconnect relationship", role: .destructive) {
          Task { await model.revokeGuardianRelationship() }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Both devices will need a new invite to reconnect.")
      }
    }
  }

  private var header: some View {
    VStack(spacing: 12) {
      SignalHalo(
        tone: model.guardianActiveAlert?.personActionState == .requestingHelp
          ? Palette.warning : Palette.primary,
        size: 122,
        isActive: true
      )
      Text("One trusted person. One clear response.")
        .font(.system(.title2, design: .serif, weight: .semibold))
        .multilineTextAlignment(.center)
      Text("Guardian Mode shares a minimal help request—never camera data, scores, or a substance guess.")
        .font(.subheadline)
        .foregroundStyle(Palette.textSecondary)
        .multilineTextAlignment(.center)
    }
    .padding(.top, 14)
  }

  @ViewBuilder
  private var setupContent: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: 14) {
        Label("Ask someone to be your guardian", systemImage: "person.badge.shield.checkmark.fill")
          .font(.headline)
          .foregroundStyle(Palette.primary)
        Text("Create a single-use invite, then share it directly with someone you trust.")
          .font(.subheadline)
          .foregroundStyle(Palette.textSecondary)
        Toggle("I consent to sending minimal help requests to my guardian.", isOn: $senderConsent)
          .font(.subheadline)
          .tint(Palette.primary)
        Button {
          Task { await model.createGuardianRelationship() }
        } label: {
          Label("Create guardian invite", systemImage: "link.badge.plus")
        }
        .buttonStyle(PrimaryActionButtonStyle())
        .disabled(!senderConsent || model.guardianIsWorking)
      }
    }

    SoberCard {
      VStack(alignment: .leading, spacing: 14) {
        Label("I received an invite", systemImage: "person.2.fill")
          .font(.headline)
          .foregroundStyle(Palette.item0)
        TextField("Paste invite code", text: $inviteCode, axis: .vertical)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .font(.footnote.monospaced())
          .padding(13)
          .background(Palette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
        Toggle("I’m a different person and agree to respond as this guardian.", isOn: $guardianConsent)
          .font(.subheadline)
          .tint(Palette.primary)
        Button {
          Task { await model.joinGuardianRelationship(inviteCode: inviteCode) }
        } label: {
          Label("Join as guardian", systemImage: "checkmark.shield.fill")
        }
        .buttonStyle(SecondaryActionButtonStyle(tint: Palette.item0))
        .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || !guardianConsent || model.guardianIsWorking)
      }
    }
  }

  @ViewBuilder
  private func relationshipContent(_ session: GuardianSession) -> some View {
    if session.role == .guardian,
      let alert = model.guardianActiveAlert,
      alert.personActionState == .requestingHelp
    {
      urgentGuardianCard(alert)
    }

    SoberCard {
      VStack(alignment: .leading, spacing: 13) {
        HStack {
          Label(
            relationshipTitle(session),
            systemImage: model.guardianRelationshipIsActive
              ? "checkmark.shield.fill" : "clock.badge.checkmark"
          )
          .font(.headline)
          .foregroundStyle(model.guardianRelationshipIsActive ? Palette.primary : Palette.warning)
          Spacer()
          Text(session.role == .person ? "PERSON" : "GUARDIAN")
            .font(.caption2.weight(.bold))
            .tracking(0.9)
            .foregroundStyle(Palette.textSecondary)
        }

        Text(relationshipDetail(session))
          .font(.subheadline)
          .foregroundStyle(Palette.textSecondary)

        if session.role == .person, let code = session.inviteCode,
          model.guardianRelationship?.state != .active
        {
          Text(code)
            .font(.caption.monospaced().weight(.semibold))
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 12))

          SoberGlassControlGroup(spacing: 10) {
            HStack(spacing: 10) {
              Button {
                UIPasteboard.general.string = code
              } label: {
                Label("Copy", systemImage: "doc.on.doc")
              }
              .buttonStyle(SecondaryActionButtonStyle())

              ShareLink(item: code) {
                Label("Share", systemImage: "square.and.arrow.up")
              }
              .buttonStyle(PrimaryActionButtonStyle())
            }
          }
        }

        Button("Refresh status") { Task { await model.refreshGuardian() } }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Palette.primary)

        Button("Disconnect", role: .destructive) { showingRevokeConfirmation = true }
          .font(.subheadline.weight(.semibold))
      }
    }

    if session.role == .guardian,
      model.guardianActiveAlert?.personActionState == .guardianConfirmed
    {
      SoberCard {
        Label("You confirmed that you’re helping.", systemImage: "hand.raised.fill")
          .font(.headline)
          .foregroundStyle(Palette.primary)
      }
    }

    if session.role == .person, let alert = model.guardianActiveAlert {
      SoberCard {
        Label(personAlertText(alert), systemImage: personAlertIcon(alert))
          .font(.headline)
          .foregroundStyle(
            alert.personActionState == .guardianConfirmed ? Palette.primary : Palette.warning
          )
      }
    }
  }

  private func urgentGuardianCard(_ alert: GuardianAlertSnapshot) -> some View {
    SoberCard {
      VStack(alignment: .leading, spacing: 15) {
        Label("Help requested now", systemImage: "exclamationmark.bubble.fill")
          .font(.title3.weight(.semibold))
          .foregroundStyle(Palette.warning)
        Text("\(model.guardianRelationship?.personDisplayName ?? "Your person") received a concerning check result and asked for help getting safe. No test details were shared.")
          .font(.body)
          .foregroundStyle(Palette.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        Button {
          Task { await model.acknowledgeGuardianAlert() }
        } label: {
          Label("I’m helping", systemImage: "hand.raised.fill")
        }
        .buttonStyle(PrimaryActionButtonStyle(tint: Palette.warning))
        .disabled(model.guardianIsWorking)
        .accessibilityHint("Confirms to the person that you are responding")
      }
    }
  }

  private func relationshipTitle(_ session: GuardianSession) -> String {
    if model.guardianRelationshipIsActive { return "Guardian connected" }
    return session.role == .person ? "Invite ready" : "Connecting"
  }

  private func relationshipDetail(_ session: GuardianSession) -> String {
    if model.guardianRelationshipIsActive {
      return session.role == .person
        ? "Your guardian can receive an in-app help request after a concerning live result."
        : "Keep Sober available. Pull to refresh or leave this screen open during founder testing."
    }
    return session.role == .person
      ? "This invite can be used once. It expires after 24 hours."
      : "Checking the relationship status."
  }

  private func personAlertText(_ alert: GuardianAlertSnapshot) -> String {
    switch alert.personActionState {
    case .guardianConfirmed:
      "Your guardian confirmed they’re helping."
    case .requestingHelp:
      "Your help request is still active."
    case .actNow, .unknown:
      "Automatic status could not be confirmed. Contact someone now."
    }
  }

  private func personAlertIcon(_ alert: GuardianAlertSnapshot) -> String {
    alert.personActionState == .guardianConfirmed
      ? "hand.raised.fill" : "exclamationmark.bubble.fill"
  }
}
