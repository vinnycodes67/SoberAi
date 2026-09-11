import SwiftUI

// The ten-second check-in. Two answers, both of which lift the pause; an
// optional private check that does nothing to it.
// User: a teen out past curfew, with paused apps and a phone in one hand.
// Emotional intent: quick, plain, and never accusatory.
//
// This view never learns how a Sober check turned out. It launches the flow
// and forgets it; there is no onDismiss, no history read, nothing to observe.
struct CurfewCheckInView: View {
  @EnvironmentObject private var coordinator: CurfewCoordinator
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL

  @State private var isWorking = false
  @State private var rideRequested = false
  @State private var screeningLaunch: ScreeningLaunch?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DSSpace.xl) {
        heading.dsAppear(0)
        if rideRequested {
          rideConfirmation.dsAppear(1)
        } else {
          actions.dsAppear(1)
        }
        DSSeparator()
        optionalCheck.dsAppear(2)
        if let error = coordinator.lastError {
          Text(error)
            .font(DSFont.footnote)
            .foregroundStyle(DSPalette.textSecondary)
            .dsReadingLine()
        }
      }
      .padding(.horizontal, DSSpace.margin)
      .padding(.top, DSSpace.xl)
      .padding(.bottom, DSSpace.xxl)
    }
    .scrollIndicators(.hidden)
    .dsPageBackground()
    .fullScreenCover(item: $screeningLaunch) { configuration in
      ScreeningFlowView(configuration: configuration)
        .environmentObject(model)
    }
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: DSSpace.sm) {
      DSEyebrow("Curfew")
      Text(coordinator.decision.shouldPause ? CurfewCopy.pausedTitle : "Check in")
        .font(DSFont.hero)
        .dsHeroTracking()
        .foregroundStyle(DSPalette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      Text(CurfewCopy.stillWorks)
        .font(DSFont.body)
        .foregroundStyle(DSPalette.textSecondary)
        .dsReadingLine()
      if let night = coordinator.decision.night {
        Text("\(CurfewCopy.countdownPrefix) \(night.curfewAt.formatted(date: .omitted, time: .shortened))")
          .font(DSFont.footnote)
          .monospacedDigit()
          .foregroundStyle(DSPalette.textMuted)
      }
    }
  }

  private var actions: some View {
    VStack(spacing: DSSpace.sm) {
      Button(CurfewCopy.checkInOK) { submit(.checkedIn) }
        .buttonStyle(DSPrimaryButtonStyle())
        .disabled(isWorking)

      Button(CurfewCopy.checkInRide) { submit(.askedForRide) }
        .buttonStyle(DSSecondaryButtonStyle())
        .disabled(isWorking)

      Button("Not now") { dismiss() }
        .buttonStyle(DSTertiaryButtonStyle(tint: DSPalette.textSecondary))
        .disabled(isWorking)
        .accessibilityHint("Closes this screen. Apps stay paused until you check in.")
    }
  }

  private var rideConfirmation: some View {
    VStack(alignment: .leading, spacing: DSSpace.md) {
      Text(CurfewCopy.safeRidePromise(guardianName: coordinator.state.guardianDisplayName))
        .font(DSFont.title)
        .dsTitleTracking()
        .foregroundStyle(DSPalette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
      Text("Your ride is opening. Nothing more is asked of you tonight.")
        .font(DSFont.body)
        .foregroundStyle(DSPalette.textSecondary)
        .dsReadingLine()
      Button("Open \(model.safetyPlan.preferredRide) again", action: openRide)
        .buttonStyle(DSSecondaryButtonStyle())
      Button("Done") { dismiss() }
        .buttonStyle(DSTertiaryButtonStyle(tint: DSPalette.textSecondary))
    }
  }

  private var optionalCheck: some View {
    VStack(alignment: .leading, spacing: DSSpace.xs) {
      Button(CurfewCopy.optionalCheck) {
        screeningLaunch = ScreeningLaunch(mode: .check, scenario: .live)
      }
      .buttonStyle(DSTertiaryButtonStyle(tint: DSPalette.textSecondary))
      Text(CurfewCopy.optionalCheckDetail)
        .font(DSFont.footnote)
        .foregroundStyle(DSPalette.textMuted)
        .dsReadingLine()
    }
  }

  private func submit(_ status: CurfewStatus) {
    guard !isWorking else { return }
    isWorking = true
    Task {
      defer { isWorking = false }
      switch status {
      case .askedForRide:
        await coordinator.checkIn(.askedForRide, dismissingCheckIn: false)
        openRide()
        rideRequested = true
      case .checkedIn:
        await coordinator.checkIn(.checkedIn)
        dismiss()
      case .home, .noCheckInYet:
        return
      }
    }
  }

  /// Same link the result screen opens; see `CurfewRideLink`.
  private func openRide() {
    guard let url = CurfewRideLink.url(for: model.safetyPlan) else { return }
    openURL(url)
  }
}
