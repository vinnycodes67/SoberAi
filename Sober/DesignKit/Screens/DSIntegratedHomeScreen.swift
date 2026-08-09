import SwiftUI

// 0.5s: one calm readiness card, one orange action, then the get-home plan.
// User: someone leaving a social setting who needs to check in, find their circle,
// or arrange a ride in under ten seconds.
// Emotional intent: protected and in control, never watched or judged.
struct DSIntegratedHomeScreen: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var onStartBaseline: () -> Void
  var onStartCheck: () -> Void
  var onStartScheduledCheckIn: () -> Void
  var onEvaluateCheckInLocation: () -> Void
  var onOpenMap: () -> Void
  var onOpenGuardian: () -> Void
  var onOpenPlan: () -> Void
  var onOpenAbout: () -> Void
  var onOpenResearch: () -> Void
  var onOpenFounderScenario: (FounderScenario) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DSSpace.xl) {
        header.dsAppear(0)
        readinessCard.dsAppear(1)

        #if INTERNAL_BUILD
        if showsScheduledCheckIn {
          scheduledCheckInCard.dsAppear(2)
        }
        #endif

        // At accessibility sizes the readiness card alone fills the screen, so
        // the action moves to a pinned inset instead of sitting below the fold.
        if !dynamicTypeSize.isAccessibilitySize {
          primaryAction.dsAppear(2)
        }
        #if INTERNAL_BUILD
        connectedFeatures.dsAppear(4)
        #endif
        safetyPlanRow.dsAppear(3)
        baselineStrip.dsAppear(4)

        #if INTERNAL_BUILD
        if model.isFounderPreview {
          founderTools.dsAppear(5)
        }
        #endif

        evidenceNote.dsAppear(6)
      }
      .padding(.horizontal, DSSpace.margin)
      .padding(.top, DSSpace.sm)
      .padding(.bottom, DSSpace.xxl)
    }
    .scrollIndicators(.hidden)
    // The one thing this screen exists to do has to be reachable without
    // scrolling at every text size. At AX5 the readiness card is taller than the
    // display, which put "Record a baseline session" out of reach for exactly
    // the people most likely to need large text.
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if dynamicTypeSize.isAccessibilitySize {
        primaryAction
          .padding(.horizontal, DSSpace.margin)
          .padding(.vertical, DSSpace.sm)
          .background(DSPalette.background)
      }
    }
    .dsPageBackground()
  }

  private var header: some View {
    HStack(alignment: .center) {
      Text("Sober")
        .font(DSFont.headline)
        .foregroundStyle(DSPalette.textPrimary)
        .accessibilityAddTraits(.isHeader)
      Spacer()
      #if INTERNAL_BUILD
      if model.isFounderPreview {
        DSBadge(text: "Founder build", tint: DSPalette.accent)
      }
      #endif
      Button(action: onOpenAbout) {
        Image(systemName: "info.circle")
          .font(.system(size: 19, weight: .medium))
          .foregroundStyle(DSPalette.textSecondary)
          .frame(width: DSHit.minimum, height: DSHit.minimum)
      }
      .buttonStyle(DSPressStyle())
      .accessibilityLabel("About Sober")
    }
  }

  private var readinessCard: some View {
    DSCard(highlighted: true) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: DSSpace.xs) {
          Circle()
            .fill(readinessNeedsAttention ? DSPalette.accent : DSPalette.textMuted)
            .frame(width: 7, height: 7)
          Text(readinessKicker)
            .font(DSFont.footnoteStrong)
            .foregroundStyle(readinessNeedsAttention ? DSPalette.accent : DSPalette.textMuted)
        }

        Text(readinessTitle)
          .font(DSFont.hero)
          .dsHeroTracking()
          .foregroundStyle(DSPalette.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, DSSpace.xs)
          .accessibilityAddTraits(.isHeader)

        Text(readinessDetail)
          .font(DSFont.callout)
          .foregroundStyle(DSPalette.textSecondary)
          .dsReadingLine()
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, DSSpace.sm)

        if !model.baselineReady {
          VStack(alignment: .leading, spacing: DSSpace.xs) {
            DSStepMeter(filled: model.baselineSessions, total: 5)
            Text("\(model.baselineSessions) of 5 baseline sessions recorded")
              .font(DSFont.footnote)
              .foregroundStyle(DSPalette.textMuted)
          }
          .padding(.top, DSSpace.lg)
        }
      }
    }
  }

  private var readinessNeedsAttention: Bool {
    !model.baselineReady
  }

  private var readinessKicker: String {
    if !model.baselineReady { return "Getting set up" }
    return "Ready"
  }

  private var readinessTitle: String {
    if !model.baselineReady { return "Learn your steady." }
    return "Ready when you are."
  }

  private var readinessDetail: String {
    if !model.baselineReady {
      return "Five high-quality sessions while sober build your personal comparison range."
    }
    #if INTERNAL_BUILD
    if model.guardianRelationshipIsActive {
      return "A check takes about two minutes. A concerning result can send your Guardian a minimal help request, never camera data or scores."
    }
    #endif
    return "A private check takes about two minutes and works without a Guardian, network, location, or notifications."
  }

  private var primaryAction: some View {
    Button(primaryActionTitle, action: performPrimaryAction)
      .buttonStyle(DSPrimaryButtonStyle())
      .accessibilityHint(primaryActionHint)
  }

  private var primaryActionTitle: String {
    if !model.baselineReady { return "Record a baseline session" }
    return "Start Sober check"
  }

  private var primaryActionHint: String {
    if !model.baselineReady { return "Starts a sober baseline session" }
    return "Starts the private impairment screening flow"
  }

  private func performPrimaryAction() {
    if !model.baselineReady {
      onStartBaseline()
    } else {
      onStartCheck()
    }
  }

  private var connectedFeatures: some View {
    DSSection("Stay connected") {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(spacing: DSSpace.sm) {
            mapFeature
            guardianFeature
          }
        } else {
          HStack(alignment: .top, spacing: DSSpace.sm) {
            mapFeature
            guardianFeature
          }
        }
      }
    }
  }

  private var mapFeature: some View {
    featureButton(
      title: "Circle Map",
      detail: mapSummary,
      symbol: model.guardianLocationSharingIsEnabled ? "location.fill" : "map.fill",
      needsAttention: model.guardianRelationshipIsActive && !model.guardianLocationSharingIsEnabled,
      action: onOpenMap
    )
  }

  private var guardianFeature: some View {
    featureButton(
      title: "Guardian",
      detail: guardianSummary,
      symbol: model.guardianRelationshipIsActive
        ? "checkmark.shield.fill" : "person.badge.shield.checkmark",
      needsAttention: !model.guardianRelationshipIsActive,
      action: onOpenGuardian
    )
  }

  private func featureButton(
    title: String,
    detail: String,
    symbol: String,
    needsAttention: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: DSSpace.sm) {
        HStack {
          Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(needsAttention ? DSPalette.accent : DSPalette.textSecondary)
          Spacer()
          Image(systemName: "arrow.up.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DSPalette.textMuted)
            .accessibilityHidden(true)
        }
        Text(title)
          .font(DSFont.headline)
          .foregroundStyle(DSPalette.textPrimary)
        Text(detail)
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
      .padding(DSSpace.md)
      .background(
        RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
          .fill(needsAttention ? DSPalette.accentWash : DSPalette.surface)
      )
    }
    .buttonStyle(DSPressStyle())
    .accessibilityElement(children: .combine)
    .accessibilityHint("Opens \(title)")
  }

  private var safetyPlanRow: some View {
    DSSection("Get home") {
      DSRows {
        DSRow(
          "Safety Circle",
          detail: safetyPlanSummary,
          trailing: {
            if model.safetyPlan.hasContact {
              DSBadge(text: model.safetyPlan.contactName, tint: DSPalette.textSecondary)
            }
          },
          action: onOpenPlan
        )
      }
    }
  }

  private var baselineStrip: some View {
    DSSection("Your steady", action: ("Record", onStartBaseline)) {
      Button(action: onStartBaseline) {
        VStack(alignment: .leading, spacing: DSSpace.sm) {
          DSStepMeter(filled: min(model.baselineSessions, 5), total: 5)
          Text(
            model.baselineReady
              ? "Your starter baseline is ready. Record only while sober and rested."
              : "Five sober sessions build the comparison range used by every check."
          )
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
          .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpace.md)
        .background(
          RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
            .fill(DSPalette.surface)
        )
      }
      .buttonStyle(DSPressStyle())
    }
  }

  @ViewBuilder
  private var scheduledCheckInCard: some View {
    DSSection("Scheduled Sober test") {
      DSCard {
        VStack(alignment: .leading, spacing: DSSpace.md) {
          HStack(alignment: .top, spacing: DSSpace.sm) {
            Image(systemName: checkInIcon)
              .font(.system(size: 20, weight: .semibold))
              .foregroundStyle(checkInNeedsAttention ? DSPalette.accent : DSPalette.textSecondary)
              .frame(width: 28)
            VStack(alignment: .leading, spacing: DSSpace.xxs) {
              Text(checkInTitle)
                .font(DSFont.headline)
                .foregroundStyle(DSPalette.textPrimary)
              Text(checkInDetail)
                .font(DSFont.footnote)
                .foregroundStyle(DSPalette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
          }

          switch model.guardianCheckInEvaluation {
          case .due:
            Button("Take scheduled Sober test", action: onStartScheduledCheckIn)
              .buttonStyle(DSPrimaryButtonStyle())
          case .needsLocation, .locationUncertain:
            Button("Check whether I’m at Home", action: onEvaluateCheckInLocation)
              .buttonStyle(DSSecondaryButtonStyle())
              .disabled(model.guardianIsWorking)
          case .needsHome:
            Button("Save private Home location", action: onOpenGuardian)
              .buttonStyle(DSSecondaryButtonStyle())
          case .upcoming, .completed, .waivedAtHome, .inactive:
            Button("Manage schedule", action: onOpenGuardian)
              .buttonStyle(DSTertiaryButtonStyle())
          }

          if model.guardianCheckInPlan?.condition == .awayFromHome {
            Text("Location is checked once on this iPhone after your tap. Your Guardian never receives the coordinate or distance."
            )
            .font(DSFont.footnote)
            .foregroundStyle(DSPalette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }

  private var showsScheduledCheckIn: Bool {
    model.guardianSession?.role == .person && model.guardianCheckInPlan?.state == .active
  }

  private var checkInNeedsAttention: Bool {
    switch model.guardianCheckInEvaluation {
    case .due, .needsHome, .needsLocation, .locationUncertain: true
    case .upcoming, .completed, .waivedAtHome, .inactive: false
    }
  }

  private var checkInTitle: String {
    switch model.guardianCheckInEvaluation {
    case let .upcoming(occurrence):
      "Scheduled for \(occurrence.dueAt.formatted(date: .omitted, time: .shortened))"
    case let .due(occurrence):
      Date() > occurrence.graceEndsAt ? "Scheduled check-in overdue" : "Scheduled check-in ready"
    case .needsHome: "Home location needed"
    case .needsLocation: "Is tonight’s check-in required?"
    case .locationUncertain: "Location needs another look"
    case .completed: "Today’s check-in completed"
    case .waivedAtHome: "No check-in needed at Home"
    case .inactive: "Scheduled check-in"
    }
  }

  private var checkInDetail: String {
    switch model.guardianCheckInEvaluation {
    case .upcoming: "You accepted this daily reminder in Guardian Mode."
    case .due: "Complete the same private live test. Only completion, never the result, is shown to your Guardian."
    case .needsHome: "Stand at Home and save that location before Sober can evaluate this condition."
    case .needsLocation: "Tap below for a one-time, on-device distance check."
    case .locationUncertain: "The previous reading was too close to the 200-meter boundary. Move into open sky and retry."
    case .completed: "Your Guardian can see completion, but not the result or measurements."
    case .waivedAtHome: "The on-device check placed you within 200 meters of your saved Home."
    case .inactive: "Open Guardian Mode to review the plan."
    }
  }

  private var checkInIcon: String {
    switch model.guardianCheckInEvaluation {
    case .completed: "checkmark.circle.fill"
    case .waivedAtHome: "house.fill"
    case .due: "exclamationmark.circle.fill"
    case .needsHome, .needsLocation, .locationUncertain: "location.circle.fill"
    case .upcoming, .inactive: "calendar.badge.clock"
    }
  }

  private var mapSummary: String {
    guard model.guardianRelationshipIsActive else { return "Connect a Guardian to begin" }
    if model.guardianLocationSharingIsEnabled {
      if let captured = model.guardianLocationSharing?.latestLocation?.capturedDate {
        return "Updated \(captured.formatted(.relative(presentation: .named)))"
      }
      return "Sharing on, waiting for an update"
    }
    return "Open the private family map"
  }

  private var guardianSummary: String {
    if model.guardianRelationshipIsActive {
      return model.guardianSession?.role == .guardian
        ? "Ready to respond to help" : "Connected for help requests"
    }
    if model.guardianInviteCode != nil { return "Invite ready to share" }
    return "Pair a parent or trusted person"
  }

  private var safetyPlanSummary: String {
    if model.safetyPlan.hasRideDestination {
      return "\(model.safetyPlan.preferredRide) to \(model.safetyPlan.destinationDisplayName)"
    }
    return "Add a named destination, ride, and direct contact"
  }

  private var founderTools: some View {
    DSSection("Founder tools") {
      DSRows {
        DSRow(
          "Research Center",
          detail: "Consent, local sessions, export, and deletion",
          action: onOpenResearch
        )
        DSSeparator()
        DSRow(
          "Preview concerning result",
          detail: "Uses labeled sample data and never sends an alert",
          action: { onOpenFounderScenario(.signals) }
        )
        DSSeparator()
        DSRow(
          "Preview inconclusive result",
          detail: "Shows the capture-quality refusal path",
          action: { onOpenFounderScenario(.inconclusive) }
        )
        DSSeparator()
        DSRow(
          "Preview no-signals result",
          detail: "Still does not say safe to drive",
          action: { onOpenFounderScenario(.noSignals) }
        )
      }
    }
  }

  private var evidenceNote: some View {
    HStack(alignment: .top, spacing: DSSpace.sm) {
      Image(systemName: "exclamationmark.shield")
        .foregroundStyle(DSPalette.accent)
      Text("This MVP is not clinically validated and must not be used to decide whether to drive.")
        .font(DSFont.footnote)
        .foregroundStyle(DSPalette.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
