import SwiftUI
import UIKit

// 0.5s: Guardian Mode in large type on black, followed by one orange next action.
// User: a person pairing someone they trust, or a Guardian responding to a request.
// Emotional intent: protected and in control, never silently watched or accused.
struct GuardianCenterView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @FocusState private var inviteFieldIsFocused: Bool

  @State private var inviteCode = ""
  @State private var senderConsent = false
  @State private var guardianConsent = false
  @State private var showingRevokeConfirmation = false
  @State private var copiedInviteCode = false
  @State private var copyFeedbackCount = 0
  @State private var checkInTime = Calendar.current.date(
    bySettingHour: 22, minute: 0, second: 0, of: Date()
  ) ?? Date()
  @State private var checkInCondition: GuardianCheckInCondition = .awayFromHome

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DSSpace.xl) {
          hero.dsAppear(0)

          if let session = model.guardianSession {
            relationshipContent(session)
          } else {
            setupContent
          }

          if let error = model.guardianError {
            errorCard(error).dsAppear(5)
          }
        }
        .padding(.horizontal, DSSpace.margin)
        .padding(.top, DSSpace.sm)
        .padding(.bottom, DSSpace.xxl)
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.interactively)
      .dsPageBackground()
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(DSPalette.background, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .font(DSFont.headline)
            .foregroundStyle(DSPalette.accent)
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
    .preferredColorScheme(.dark)
    .tint(DSPalette.accent)
    .sensoryFeedback(.success, trigger: copyFeedbackCount)
    .sensoryFeedback(.success, trigger: model.guardianRelationshipIsActive) { oldValue, newValue in
      !oldValue && newValue
    }
    .sensoryFeedback(
      .warning,
      trigger: model.guardianActiveAlert?.canonicalEventId
    ) { oldValue, newValue in
      oldValue != newValue && newValue != nil
    }
  }

  private var hero: some View {
    HStack(alignment: .top, spacing: DSSpace.md) {
      VStack(alignment: .leading, spacing: DSSpace.sm) {
        DSEyebrow(heroEyebrow, tint: heroNeedsAttention ? DSPalette.accent : DSPalette.textMuted)

        Text("Guardian Mode")
          .font(DSFont.hero)
          .dsHeroTracking()
          .foregroundStyle(DSPalette.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)

        Text("Help requests say only that help is needed—never camera data, scores, location, or a substance guess. Circle location sharing is separate and opt-in.")
          .font(DSFont.callout)
          .foregroundStyle(DSPalette.textSecondary)
          .dsReadingLine()
      }

      Spacer(minLength: 0)

      ZStack {
        Circle()
          .fill(heroNeedsAttention ? DSPalette.accentWash : DSPalette.surface)
        Image(systemName: heroSymbol)
          .font(.system(size: 27, weight: .semibold))
          .foregroundStyle(heroNeedsAttention ? DSPalette.accent : DSPalette.textSecondary)
          .contentTransition(.symbolEffect(.replace))
          .symbolEffect(
            .pulse,
            options: reduceMotion || !hasActiveHelpRequest ? .nonRepeating : .repeating
          )
      }
      .frame(width: 64, height: 64)
      .accessibilityHidden(true)
    }
  }

  private var heroEyebrow: String {
    if hasActiveHelpRequest { return "Help requested" }
    if model.guardianRelationshipIsActive { return "Connected" }
    if model.guardianSession != nil { return "Invite pending" }
    return "Guardian setup"
  }

  private var heroSymbol: String {
    if hasActiveHelpRequest { return "exclamationmark.bubble.fill" }
    if model.guardianRelationshipIsActive { return "checkmark.shield.fill" }
    return "person.badge.shield.checkmark"
  }

  private var heroNeedsAttention: Bool {
    hasActiveHelpRequest || !model.guardianRelationshipIsActive
  }

  private var hasActiveHelpRequest: Bool {
    model.guardianActiveAlert?.personActionState == .requestingHelp
  }

  @ViewBuilder
  private var setupContent: some View {
    DSSection("Choose your Guardian") {
      DSCard(highlighted: true) {
        VStack(alignment: .leading, spacing: DSSpace.md) {
          setupHeading(
            "Ask someone you trust",
            detail: "Create a single-use invite, then share it directly with one person.",
            symbol: "link.badge.plus"
          )

          Toggle(
            "I consent to sending minimal help requests to my Guardian.",
            isOn: $senderConsent
          )
          .font(DSFont.subheadline)
          .foregroundStyle(DSPalette.textSecondary)
          .tint(DSPalette.accent)

          Button("Create Guardian invite") {
            inviteFieldIsFocused = false
            Task { await model.createGuardianRelationship() }
          }
          .buttonStyle(DSPrimaryButtonStyle())
          .disabled(!senderConsent || model.guardianIsWorking)
        }
      }
    }
    .dsAppear(1)

    DSSection("Have an invite?") {
      DSCard {
        VStack(alignment: .leading, spacing: DSSpace.md) {
          setupHeading(
            "Join as their Guardian",
            detail: "Use the private code they sent you. You can receive help requests and check-in status. Circle location sharing stays off unless they enable it.",
            symbol: "person.2.fill"
          )

          TextField("Paste invite code", text: $inviteCode)
            .font(DSFont.footnote)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .padding(DSSpace.md)
            .foregroundStyle(DSPalette.textPrimary)
            .background(
              RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
                .fill(DSPalette.surfaceRaised)
            )
            .overlay {
              RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
                .strokeBorder(
                  inviteFieldIsFocused ? DSPalette.accent : Color.clear,
                  lineWidth: 1
                )
            }
            .focused($inviteFieldIsFocused)
            .onSubmit(joinGuardian)
            .accessibilityLabel("Guardian invite code")

          Toggle(
            "I’m a different person and agree to respond as this Guardian.",
            isOn: $guardianConsent
          )
          .font(DSFont.subheadline)
          .foregroundStyle(DSPalette.textSecondary)
          .tint(DSPalette.accent)

          Button("Join as Guardian", action: joinGuardian)
            .buttonStyle(DSSecondaryButtonStyle())
            .disabled(!canJoinGuardian)
        }
      }
    }
    .dsAppear(2)
  }

  private func setupHeading(_ title: String, detail: String, symbol: String) -> some View {
    HStack(alignment: .top, spacing: DSSpace.sm) {
      Image(systemName: symbol)
        .font(.system(size: 19, weight: .semibold))
        .foregroundStyle(DSPalette.textSecondary)
        .frame(width: 26)
      VStack(alignment: .leading, spacing: DSSpace.xxs) {
        Text(title)
          .font(DSFont.headline)
          .foregroundStyle(DSPalette.textPrimary)
        Text(detail)
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var canJoinGuardian: Bool {
    !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && guardianConsent
      && !model.guardianIsWorking
  }

  private func joinGuardian() {
    guard canJoinGuardian else { return }
    inviteFieldIsFocused = false
    Task { await model.joinGuardianRelationship(inviteCode: inviteCode) }
  }

  @ViewBuilder
  private func relationshipContent(_ session: GuardianSession) -> some View {
    if session.role == .guardian,
      model.guardianActiveAlert?.personActionState == .requestingHelp
    {
      urgentGuardianCard.dsAppear(1)
    }

    relationshipCard(session).dsAppear(hasActiveHelpRequest ? 2 : 1)

    if let warning = model.guardianRelationship?.expiryWarning {
      expiryWarningCard(warning)
        .dsAppear(hasActiveHelpRequest ? 3 : 2)
    }

    if model.guardianRelationshipIsActive {
      checkInSection(session)
        .dsAppear(hasActiveHelpRequest ? 4 : 3)
    }

    if session.role == .guardian,
      model.guardianActiveAlert?.personActionState == .guardianConfirmed
    {
      acknowledgementCard(
        "You confirmed that you’re helping.",
        symbol: "hand.raised.fill"
      )
      .dsAppear(3)
    }

    if session.role == .person, let alert = model.guardianActiveAlert {
      acknowledgementCard(personAlertText(alert), symbol: personAlertIcon(alert))
        .dsAppear(3)
    }
  }

  private func relationshipCard(_ session: GuardianSession) -> some View {
    DSSection("Relationship") {
      DSCard(highlighted: true) {
        VStack(alignment: .leading, spacing: DSSpace.md) {
          HStack(alignment: .top, spacing: DSSpace.sm) {
            Image(systemName: model.guardianRelationshipIsActive
              ? "checkmark.shield.fill" : "clock.badge.checkmark")
              .font(.system(size: 21, weight: .semibold))
              .foregroundStyle(
                model.guardianRelationshipIsActive ? DSPalette.textSecondary : DSPalette.accent
              )
              .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: DSSpace.xxs) {
              Text(relationshipTitle(session))
                .font(DSFont.title)
                .dsTitleTracking()
                .foregroundStyle(DSPalette.textPrimary)
              Text(relationshipDetail(session))
                .font(DSFont.subheadline)
                .foregroundStyle(DSPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            DSBadge(
              text: session.role == .person ? "Person" : "Guardian",
              tint: DSPalette.textSecondary
            )
          }

          if session.role == .person, let code = session.inviteCode,
            model.guardianRelationship?.state != .active
          {
            inviteCodeBlock(code)
            inviteActions(code)
          }

          HStack(spacing: DSSpace.lg) {
            Button("Refresh") { Task { await model.refreshGuardian() } }
              .buttonStyle(DSTertiaryButtonStyle())

            Button("Disconnect") { showingRevokeConfirmation = true }
              .buttonStyle(DSTertiaryButtonStyle(tint: DSPalette.textSecondary))
          }
        }
      }
    }
  }

  private func inviteCodeBlock(_ code: String) -> some View {
    VStack(alignment: .leading, spacing: DSSpace.xs) {
      DSEyebrow("Private invite code")
      Text(code)
        .font(DSFont.footnote)
        .monospaced()
        .foregroundStyle(DSPalette.textPrimary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DSSpace.md)
    .background(
      RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
        .fill(DSPalette.surfaceRaised)
    )
  }

  private func inviteActions(_ code: String) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: DSSpace.sm) {
        copyButton(code)
        shareButton(code)
      }
      VStack(spacing: DSSpace.sm) {
        shareButton(code)
        copyButton(code)
      }
    }
  }

  private func copyButton(_ code: String) -> some View {
    Button {
      copyInvite(code)
    } label: {
      Label(
        copiedInviteCode ? "Copied" : "Copy",
        systemImage: copiedInviteCode ? "checkmark" : "doc.on.doc"
      )
      .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(DSSecondaryButtonStyle())
  }

  private func shareButton(_ code: String) -> some View {
    ShareLink(item: code) {
      Label("Share invite", systemImage: "square.and.arrow.up")
    }
    .buttonStyle(DSPrimaryButtonStyle())
  }

  private func copyInvite(_ code: String) {
    UIPasteboard.general.string = code
    copyFeedbackCount += 1
    let feedbackID = copyFeedbackCount
    withAnimation(reduceMotion ? nil : DSMotion.standard) {
      copiedInviteCode = true
    }
    Task {
      try? await Task.sleep(for: .seconds(1.6))
      guard feedbackID == copyFeedbackCount else { return }
      withAnimation(reduceMotion ? nil : DSMotion.standard) {
        copiedInviteCode = false
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
      DSSection("Daily check-in") {
        DSEmptyState(
          title: "No check-in planned",
          message: "Your Guardian can propose a time. Nothing starts until you review and accept it."
        )
      }
    }
  }

  private var guardianCheckInComposer: some View {
    DSSection("Daily check-in") {
      DSCard {
        VStack(alignment: .leading, spacing: DSSpace.md) {
          setupHeading(
            "Propose a check-in",
            detail: "Choose a time and condition. The other person must accept before reminders begin.",
            symbol: "calendar.badge.clock"
          )

          DSRows {
            DatePicker(
              "Check-in time",
              selection: $checkInTime,
              displayedComponents: .hourAndMinute
            )
            .font(DSFont.body)
            .foregroundStyle(DSPalette.textPrimary)
            .frame(minHeight: DSHit.minimum)
            .padding(.vertical, DSSpace.xs)

            DSSeparator()

            HStack {
              Text("When it applies")
                .font(DSFont.body)
                .foregroundStyle(DSPalette.textPrimary)
              Spacer()
              Picker("When it applies", selection: $checkInCondition) {
                ForEach(GuardianCheckInCondition.allCases, id: \.self) { condition in
                  Text(condition.title).tag(condition)
                }
              }
              .labelsHidden()
              .pickerStyle(.menu)
              .tint(DSPalette.accent)
            }
            .frame(minHeight: DSHit.minimum)
            .padding(.vertical, DSSpace.xs)
          }

          if checkInCondition == .awayFromHome {
            privacyNote(
              "Sober asks them for a one-time location check. You never see their location or distance.",
              symbol: "location.fill.viewfinder"
            )
          }

          if let plan = model.guardianCheckInPlan {
            DSSeparator()
            checkInStatus(plan)
          }

          Button(
            model.guardianCheckInPlan == nil ? "Send for approval" : "Propose updated plan"
          ) {
            Task {
              await model.proposeGuardianCheckIn(at: checkInTime, condition: checkInCondition)
            }
          }
          .buttonStyle(DSPrimaryButtonStyle())
          .disabled(model.guardianIsWorking)

          Text("A missed check-in means only “not completed.” It never means impaired.")
            .font(DSFont.footnote)
            .foregroundStyle(DSPalette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func personCheckInCard(_ plan: GuardianCheckInPlanSnapshot) -> some View {
    DSSection("Daily check-in") {
      DSCard {
        VStack(alignment: .leading, spacing: DSSpace.md) {
          HStack(alignment: .top, spacing: DSSpace.sm) {
            Image(systemName: personCheckInIcon(plan))
              .font(.system(size: 20, weight: .semibold))
              .foregroundStyle(
                plan.state == .pendingPersonConsent ? DSPalette.accent : DSPalette.textSecondary
              )
            Text(personCheckInTitle(plan))
              .font(DSFont.title)
              .dsTitleTracking()
              .foregroundStyle(DSPalette.textPrimary)
          }

          checkInPlanSummary(plan)

          if plan.state == .pendingPersonConsent {
            Text("This is a request, not an active rule. Review it and choose for yourself.")
              .font(DSFont.subheadline)
              .foregroundStyle(DSPalette.textSecondary)

            if plan.condition == .awayFromHome {
              privacyNote(
                "Your Home coordinate stays encrypted on this iPhone. Your Guardian receives no location or distance.",
                symbol: "hand.raised.fill"
              )

              Button(
                model.guardianHomeIsConfigured
                  ? "Replace Home with this location" : "Save this location as Home"
              ) {
                Task { await model.updateGuardianHome() }
              }
              .buttonStyle(DSSecondaryButtonStyle())

              Text("Only tap this while you are physically at the place you call Home.")
                .font(DSFont.footnote)
                .foregroundStyle(DSPalette.accent)
            }

            Button("Accept check-in plan") {
              Task { await model.acceptGuardianCheckInPlan() }
            }
            .buttonStyle(DSPrimaryButtonStyle())
            .disabled(
              model.guardianIsWorking
                || (plan.condition == .awayFromHome && !model.guardianHomeIsConfigured)
            )

            Button("Decline") {
              Task { await model.declineGuardianCheckInPlan() }
            }
            .buttonStyle(DSTertiaryButtonStyle(tint: DSPalette.textSecondary))
          } else if plan.state == .active {
            checkInStatus(plan)

            if plan.condition == .awayFromHome {
              Button("Update private Home location") {
                Task { await model.updateGuardianHome() }
              }
              .buttonStyle(DSSecondaryButtonStyle())
            }

            Button("Turn off scheduled check-ins") {
              Task { await model.declineGuardianCheckInPlan() }
            }
            .buttonStyle(DSTertiaryButtonStyle(tint: DSPalette.textSecondary))
          } else {
            Text("Scheduled check-ins are off. Your Guardian can propose a new plan for you to review.")
              .font(DSFont.subheadline)
              .foregroundStyle(DSPalette.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }

  private func checkInPlanSummary(_ plan: GuardianCheckInPlanSnapshot) -> some View {
    DSRows {
      DSValueRow(label: "Time", value: "Daily at \(plan.displayTime)")
      DSSeparator()
      DSValueRow(label: "Applies", value: plan.condition.title)
      DSSeparator()
      DSValueRow(label: "Grace period", value: "\(plan.graceMinutes) minutes")
    }
  }

  private func checkInStatus(_ plan: GuardianCheckInPlanSnapshot) -> some View {
    VStack(alignment: .leading, spacing: DSSpace.xxs) {
      Text(checkInStateText(plan))
        .font(DSFont.headline)
        .foregroundStyle(DSPalette.textPrimary)
      if plan.lastCompletion != nil {
        Text("The latest scheduled check-in was completed. Its result was not shared.")
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func privacyNote(_ text: String, symbol: String) -> some View {
    HStack(alignment: .top, spacing: DSSpace.sm) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(DSPalette.textSecondary)
        .frame(width: 20)
      Text(text)
        .font(DSFont.footnote)
        .foregroundStyle(DSPalette.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DSSpace.md)
    .background(
      RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
        .fill(DSPalette.surfaceRaised)
    )
  }

  private var urgentGuardianCard: some View {
    VStack(alignment: .leading, spacing: DSSpace.md) {
      HStack(alignment: .top, spacing: DSSpace.sm) {
        Image(systemName: "exclamationmark.bubble.fill")
          .font(.system(size: 23, weight: .semibold))
          .foregroundStyle(DSPalette.accent)
          .symbolEffect(
            .pulse,
            options: reduceMotion ? .nonRepeating : .repeating
          )
        VStack(alignment: .leading, spacing: DSSpace.xxs) {
          Text("Help requested now")
            .font(DSFont.title)
            .dsTitleTracking()
            .foregroundStyle(DSPalette.textPrimary)
          Text("\(model.guardianRelationship?.personDisplayName ?? "Your person") received a concerning check result and asked for help getting safe. No test details were shared.")
            .font(DSFont.body)
            .foregroundStyle(DSPalette.textSecondary)
            .dsReadingLine()
        }
      }

      Button("I’m helping") {
        Task { await model.acknowledgeGuardianAlert() }
      }
      .buttonStyle(DSPrimaryButtonStyle())
      .disabled(model.guardianIsWorking)
      .accessibilityHint("Confirms to the person that you are responding")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DSSpace.lg)
    .background(
      RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
        .fill(DSPalette.accentWash)
    )
  }

  private func acknowledgementCard(_ text: String, symbol: String) -> some View {
    HStack(alignment: .top, spacing: DSSpace.sm) {
      Image(systemName: symbol)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(DSPalette.textSecondary)
      Text(text)
        .font(DSFont.headline)
        .foregroundStyle(DSPalette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DSSpace.lg)
    .background(
      RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
        .fill(DSPalette.surface)
    )
  }

  private func errorCard(_ error: String) -> some View {
    HStack(alignment: .top, spacing: DSSpace.sm) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(DSPalette.accent)
      VStack(alignment: .leading, spacing: DSSpace.xxs) {
        Text("Guardian needs attention")
          .font(DSFont.headline)
          .foregroundStyle(DSPalette.textPrimary)
        Text(error)
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DSSpace.md)
    .background(
      RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
        .fill(DSPalette.accentWash)
    )
  }

  private func relationshipTitle(_ session: GuardianSession) -> String {
    if model.guardianRelationshipIsActive { return "Guardian connected" }
    return session.role == .person ? "Invite ready" : "Connecting"
  }

  private func relationshipDetail(_ session: GuardianSession) -> String {
    if model.guardianRelationshipIsActive {
      return session.role == .person
        ? "Your Guardian can receive an in-app help request after a concerning live result."
        : "Keep Sober available. Pull to refresh or leave this screen open during founder testing."
    }
    return session.role == .person
      ? "This invite can be used once. It expires after 24 hours."
      : "Checking the relationship status."
  }

  private func expiryWarningCard(_ warning: GuardianRelationshipExpiryWarning) -> some View {
    DSSection("Connection expiry") {
      DSCard {
        HStack(alignment: .top, spacing: DSSpace.sm) {
          Image(systemName: "calendar.badge.exclamationmark")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(DSPalette.accent)

          VStack(alignment: .leading, spacing: DSSpace.xxs) {
            Text("Guardian connection expires soon")
              .font(DSFont.headline)
              .foregroundStyle(DSPalette.textPrimary)
            Text(expiryWarningDetail(warning))
              .font(DSFont.footnote)
              .foregroundStyle(DSPalette.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
    .accessibilityElement(children: .combine)
  }

  private func expiryWarningDetail(_ warning: GuardianRelationshipExpiryWarning) -> String {
    let expiration = warning.expirationDate?.formatted(
      date: .abbreviated,
      time: .shortened
    ) ?? "the date shown in relationship status"
    return "This connection expires \(expiration). Both people will need a new invite; it will not renew automatically."
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

  private func personAlertText(_ alert: GuardianAlertSnapshot) -> String {
    switch alert.personActionState {
    case .guardianConfirmed:
      "Your Guardian confirmed they’re helping."
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
