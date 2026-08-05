import SwiftUI
import UIKit

// 0.5s: relationship status first; then one calm, consent-gated check-in plan.
// User: a guardian proposing a daily time, or the screened person deciding whether to accept it.
// Emotional intent: supported and in control, never silently watched or accused.
struct GuardianCenterView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var inviteCode = ""
  @State private var senderConsent = false
  @State private var guardianConsent = false
  @State private var showingRevokeConfirmation = false
  @State private var checkInTime = Calendar.current.date(
    bySettingHour: 22, minute: 0, second: 0, of: Date()
  ) ?? Date()
  @State private var checkInCondition: GuardianCheckInCondition = .awayFromHome

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
  private func checkInSection(_ session: GuardianSession) -> some View {
    if session.role == .guardian {
      guardianCheckInComposer
    } else if let plan = model.guardianCheckInPlan {
      personCheckInCard(plan)
    } else {
      SoberCard {
        VStack(alignment: .leading, spacing: 8) {
          Label("No scheduled check-in", systemImage: "calendar.badge.clock")
            .font(.headline)
          Text("Your guardian can propose a time. Nothing starts until you review and accept it.")
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
        }
      }
    }
  }

  private var guardianCheckInComposer: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: 15) {
        Label("Propose a daily check-in", systemImage: "calendar.badge.clock")
          .font(.headline)
          .foregroundStyle(Palette.item0)

        Text("Choose a time and condition. The other person must accept before reminders begin.")
          .font(.subheadline)
          .foregroundStyle(Palette.textSecondary)

        DatePicker("Check-in time", selection: $checkInTime, displayedComponents: .hourAndMinute)
          .font(.subheadline.weight(.medium))

        Picker("When it applies", selection: $checkInCondition) {
          ForEach(GuardianCheckInCondition.allCases, id: \.self) { condition in
            Text(condition.title).tag(condition)
          }
        }
        .pickerStyle(.menu)
        .tint(Palette.primary)

        if checkInCondition == .awayFromHome {
          Label(
            "Sober asks for a one-time location check when they open the app. You never see their location.",
            systemImage: "location.fill.viewfinder"
          )
          .font(.caption)
          .foregroundStyle(Palette.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        }

        if let plan = model.guardianCheckInPlan {
          Divider().overlay(Palette.secondary.opacity(0.2))
          checkInStatus(plan)
        }

        Button {
          Task {
            await model.proposeGuardianCheckIn(at: checkInTime, condition: checkInCondition)
          }
        } label: {
          Label(
            model.guardianCheckInPlan == nil ? "Send for approval" : "Propose updated plan",
            systemImage: "paperplane.fill"
          )
        }
        .buttonStyle(PrimaryActionButtonStyle())
        .disabled(model.guardianIsWorking)

        Text("A missed check-in means only ‘not completed.’ It never means impaired.")
          .font(.caption)
          .foregroundStyle(Palette.textSecondary)
      }
    }
  }

  private func personCheckInCard(_ plan: GuardianCheckInPlanSnapshot) -> some View {
    SoberCard {
      VStack(alignment: .leading, spacing: 14) {
        Label(personCheckInTitle(plan), systemImage: personCheckInIcon(plan))
          .font(.headline)
          .foregroundStyle(plan.state == .pendingPersonConsent ? Palette.warning : Palette.primary)

        checkInPlanSummary(plan)

        if plan.state == .pendingPersonConsent {
          Text("This is a request, not an active rule. Review it and choose for yourself.")
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)

          if plan.condition == .awayFromHome {
            Label(
              "Your Home coordinate stays encrypted on this iPhone. Your guardian receives no location or distance.",
              systemImage: "hand.raised.fill"
            )
            .font(.caption)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Button {
              Task { await model.updateGuardianHome() }
            } label: {
              Label(
                model.guardianHomeIsConfigured ? "Replace Home with this location" : "Save this location as Home",
                systemImage: "house.and.flag.fill"
              )
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: Palette.item0))

            Text("Only tap this while you are physically at the place you call Home.")
              .font(.caption)
              .foregroundStyle(Palette.warning)
          }

          Button {
            Task { await model.acceptGuardianCheckInPlan() }
          } label: {
            Label("Accept check-in plan", systemImage: "checkmark.circle.fill")
          }
          .buttonStyle(PrimaryActionButtonStyle())
          .disabled(
            model.guardianIsWorking
              || (plan.condition == .awayFromHome && !model.guardianHomeIsConfigured)
          )

          Button("Decline", role: .destructive) {
            Task { await model.declineGuardianCheckInPlan() }
          }
          .font(.subheadline.weight(.semibold))
        } else if plan.state == .active {
          checkInStatus(plan)

          if plan.condition == .awayFromHome {
            Button {
              Task { await model.updateGuardianHome() }
            } label: {
              Label("Update private Home location", systemImage: "house.and.flag")
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: Palette.item0))
          }

          Button("Turn off scheduled check-ins", role: .destructive) {
            Task { await model.declineGuardianCheckInPlan() }
          }
          .font(.subheadline.weight(.semibold))
        } else {
          Text("Scheduled check-ins are off. Your guardian can propose a new plan, which you can review again.")
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
        }
      }
    }
  }

  private func checkInPlanSummary(_ plan: GuardianCheckInPlanSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label("Daily at \(plan.displayTime)", systemImage: "clock.fill")
      Label(plan.condition.title, systemImage: plan.condition == .always ? "calendar" : "house.fill")
      Text("\(plan.timeZoneIdentifier) · \(plan.graceMinutes)-minute grace period")
        .font(.caption)
        .foregroundStyle(Palette.textSecondary)
    }
    .font(.subheadline.weight(.medium))
  }

  private func checkInStatus(_ plan: GuardianCheckInPlanSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(checkInStateText(plan))
        .font(.subheadline.weight(.semibold))
      if plan.lastCompletion != nil {
        Text("The latest scheduled check-in was completed. Its result was not shared.")
          .font(.caption)
          .foregroundStyle(Palette.textSecondary)
      }
    }
  }

  private func personCheckInTitle(_ plan: GuardianCheckInPlanSnapshot) -> String {
    switch plan.state {
    case .pendingPersonConsent: "Check-in plan awaiting your choice"
    case .active: "Scheduled check-in active"
    case .declined: "Scheduled check-ins are off"
    case .unknown: "Check-in status unavailable"
    }
  }

  private func personCheckInIcon(_ plan: GuardianCheckInPlanSnapshot) -> String {
    switch plan.state {
    case .pendingPersonConsent: "person.crop.circle.badge.questionmark"
    case .active: "calendar.badge.checkmark"
    case .declined, .unknown: "calendar.badge.minus"
    }
  }

  private func checkInStateText(_ plan: GuardianCheckInPlanSnapshot) -> String {
    switch plan.state {
    case .pendingPersonConsent: "Waiting for the screened person to approve"
    case .active: "Accepted and active"
    case .declined: "Declined or turned off by the screened person"
    case .unknown: "Status unavailable"
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

    if model.guardianRelationshipIsActive {
      checkInSection(session)
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
