import SwiftUI

// 0.5s: the signal halo floats above one decisive action.
// User: about to leave a social setting and wants a low-friction pause.
// Primary goal: begin a private check or get home without driving.
struct HomeView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var launch: ScreeningLaunch?
  @State private var showingPlan = false
  @State private var showingGuardian = false
  @State private var showingCircleMap = false
  @State private var showingAbout = false
  @State private var showingResearch = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          hero
            .soberEntrance(order: 0)
          if showsScheduledCheckIn {
            scheduledCheckInCard
              .soberEntrance(order: 1)
          }
          baselineCard
            .soberEntrance(order: showsScheduledCheckIn ? 2 : 1)
          nightOutCard
            .soberEntrance(order: 2)
          guardianCard
            .soberEntrance(order: 3)
          circleMapCard
            .soberEntrance(order: 4)

          if model.isFounderPreview {
            founderPreviewCard
              .soberEntrance(order: 5)
            researchCenterCard
              .soberEntrance(order: 6)
          }

          evidenceNote
            .soberEntrance(order: model.isFounderPreview ? 7 : 5)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 30)
      }
      .soberBackground()
      .toolbar {
        ToolbarItem(placement: .principal) {
          SoberWordmark()
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showingAbout = true
          } label: {
            Image(systemName: "info.circle")
          }
          .accessibilityLabel("About this prototype")
        }
      }
    }
    .fullScreenCover(item: $launch) { configuration in
      ScreeningFlowView(configuration: configuration)
        .environmentObject(model)
    }
    .sheet(isPresented: $showingPlan) {
      SafetyPlanView(plan: $model.safetyPlan)
        .preferredColorScheme(.dark)
    }
    .sheet(isPresented: $showingGuardian) {
      GuardianCenterView()
        .environmentObject(model)
        .preferredColorScheme(.dark)
    }
    .fullScreenCover(isPresented: $showingCircleMap) {
      CircleMapView()
        .environmentObject(model)
        .preferredColorScheme(.dark)
    }
    .sheet(isPresented: $showingAbout) {
      AboutPrototypeView()
        .environmentObject(model)
        .preferredColorScheme(.dark)
    }
    .sheet(isPresented: $showingResearch) {
      ResearchModeView()
        .environmentObject(model)
        .preferredColorScheme(.dark)
    }
    .task(id: model.guardianSession?.relationshipID) {
      if model.guardianSession != nil { await model.refreshGuardian() }
      while !Task.isCancelled {
        model.refreshGuardianCheckInEvaluation()
        try? await Task.sleep(for: .seconds(30))
      }
    }
  }

  private var showsScheduledCheckIn: Bool {
    model.guardianSession?.role == .person && model.guardianCheckInPlan?.state == .active
  }

  private var scheduledCheckInCard: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: 13) {
        HStack(alignment: .top, spacing: 12) {
          ZStack {
            Circle().fill(checkInTint.opacity(0.15))
            Image(systemName: checkInIcon)
              .foregroundStyle(checkInTint)
          }
          .frame(width: 46, height: 46)

          VStack(alignment: .leading, spacing: 4) {
            Text(checkInTitle)
              .font(.headline)
            Text(checkInDetail)
              .font(.subheadline)
              .foregroundStyle(Palette.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        switch model.guardianCheckInEvaluation {
        case let .due(occurrence):
          Button {
            launch = ScreeningLaunch(
              mode: .check,
              scenario: .live,
              guardianCheckInOccurrenceID: occurrence.id
            )
          } label: {
            Label("Take scheduled Sober test", systemImage: "play.fill")
          }
          .buttonStyle(PrimaryActionButtonStyle(tint: Palette.warning))

        case .needsLocation, .locationUncertain:
          Button {
            Task { await model.evaluateGuardianCheckInLocation() }
          } label: {
            Label("Check whether I’m at Home", systemImage: "location.fill.viewfinder")
          }
          .buttonStyle(PrimaryActionButtonStyle())
          .disabled(model.guardianIsWorking)

        case .needsHome:
          Button {
            showingGuardian = true
          } label: {
            Label("Save private Home location", systemImage: "house.and.flag.fill")
          }
          .buttonStyle(PrimaryActionButtonStyle())

        case .upcoming, .completed, .waivedAtHome, .inactive:
          EmptyView()
        }

        if model.guardianCheckInPlan?.condition == .awayFromHome {
          Text("Sober checks location once, only after your tap. Your guardian never receives it.")
            .font(.caption)
            .foregroundStyle(Palette.textSecondary)
        }
      }
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
    case .upcoming:
      "You accepted this daily reminder in Guardian Mode."
    case .due:
      "Complete the same private live test. Only completion—not the result—is shown to your guardian."
    case .needsHome:
      "Stand at Home and save that location before Sober can evaluate this condition."
    case .needsLocation:
      "Tap below for a one-time on-device distance check."
    case .locationUncertain:
      "The last location was too close to the 200-meter boundary to decide. Move into open sky and retry."
    case .completed:
      "Your guardian can see that it was completed, but not the outcome or any test data."
    case .waivedAtHome:
      "The on-device check placed you within 200 meters of your saved Home."
    case .inactive:
      "Open Guardian Mode to review the plan."
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

  private var checkInTint: Color {
    switch model.guardianCheckInEvaluation {
    case .due, .needsHome: Palette.warning
    case .completed, .waivedAtHome: Palette.primary
    case .needsLocation, .locationUncertain, .upcoming, .inactive: Palette.item0
    }
  }

  private var hero: some View {
    VStack(spacing: 14) {
      if model.isFounderPreview {
        PrototypeBadge()
          .padding(.top, 10)
      }

      SignalHalo(size: 226)
        .padding(.top, model.isFounderPreview ? 0 : 22)

      VStack(spacing: 7) {
        Text(heroTitle)
          .font(.system(.largeTitle, design: .serif, weight: .semibold))
          .tracking(-1.1)
          .multilineTextAlignment(.center)
        Text(heroDetail)
        .font(.subheadline)
        .foregroundStyle(Palette.textSecondary)
        .multilineTextAlignment(.center)
      }

      Button(heroButtonTitle) {
        if model.baselineReady && !model.guardianRelationshipIsActive {
          showingGuardian = true
        } else {
          launch = ScreeningLaunch(
            mode: model.baselineReady ? .check : .baseline,
            scenario: .live
          )
        }
      }
      .buttonStyle(PrimaryActionButtonStyle())
      .padding(.top, 6)
    }
  }

  private var heroTitle: String {
    if !model.baselineReady { return "Learn your steady." }
    if !model.guardianRelationshipIsActive { return "Connect your Guardian." }
    return "Pause. Check in."
  }

  private var heroDetail: String {
    if !model.baselineReady { return "Five high-quality sober sessions create your research baseline." }
    if !model.guardianRelationshipIsActive {
      return "A live check starts after one trusted person accepts your invite."
    }
    return "About two minutes. Concerning results alert your parent immediately."
  }

  private var heroButtonTitle: String {
    if !model.baselineReady { return "Record sober baseline" }
    if !model.guardianRelationshipIsActive { return "Set up Guardian Mode" }
    return "Start a check"
  }

  private var baselineCard: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Personal baseline")
              .font(.headline)
            Text(
              model.baselineReady
                ? "Starter baseline ready" : "Complete only while sober and rested"
            )
            .font(.caption)
            .foregroundStyle(Palette.textSecondary)
          }
          Spacer()
          Text("\(model.baselineSessions)/5")
            .font(.title2.monospacedDigit().weight(.semibold))
            .foregroundStyle(Palette.primary)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : SoberMotion.progress, value: model.baselineSessions)
        }

        HStack(spacing: 8) {
          ForEach(0..<5, id: \.self) { index in
            Capsule()
              .fill(
                index < model.baselineSessions ? Palette.primary : Palette.secondary.opacity(0.22)
              )
              .frame(height: 8)
              .scaleEffect(x: index < model.baselineSessions ? 1 : 0.84, anchor: .leading)
              .animation(
                reduceMotion ? nil : SoberMotion.progress.delay(Double(index) * 0.035),
                value: model.baselineSessions
              )
          }
        }

        Text(
          "Five sessions unlock this research build. A defensible production baseline still needs a larger validated protocol, likely 10 to 20 sessions."
        )
        .font(.caption)
        .foregroundStyle(Palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var nightOutCard: some View {
    Button {
      showingPlan = true
    } label: {
      SoberCard {
        HStack(spacing: 14) {
          ZStack {
            Circle()
              .fill(Palette.item0.opacity(0.16))
            Image(systemName: model.safetyPlan.isActive ? "moon.stars.fill" : "moon.stars")
              .foregroundStyle(Palette.item0)
          }
          .frame(width: 50, height: 50)

          VStack(alignment: .leading, spacing: 4) {
            Text("Safety Circle")
              .font(.headline)
              .foregroundStyle(Palette.textPrimary)
            Text(
              model.safetyPlan.isActive
                ? safetyCircleSummary
                : "Choose your ride and parent while clear-headed"
            )
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.leading)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(Palette.textSecondary)
        }
      }
    }
    .buttonStyle(SoberCardButtonStyle())
    .accessibilityHint("Configure your ride and designated contact")
  }

  private var guardianCard: some View {
    Button {
      showingGuardian = true
    } label: {
      SoberCard {
        HStack(spacing: 14) {
          ZStack {
            Circle().fill(Palette.primary.opacity(0.14))
            Image(systemName: model.guardianRelationshipIsActive
              ? "checkmark.shield.fill" : "person.badge.shield.checkmark")
              .foregroundStyle(Palette.primary)
          }
          .frame(width: 50, height: 50)

          VStack(alignment: .leading, spacing: 4) {
            Text("Guardian Mode")
              .font(.headline)
              .foregroundStyle(Palette.textPrimary)
            Text(guardianSummary)
              .font(.subheadline)
              .foregroundStyle(Palette.textSecondary)
              .multilineTextAlignment(.leading)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(Palette.textSecondary)
        }
      }
    }
    .buttonStyle(SoberCardButtonStyle())
    .accessibilityHint("Set up or review the trusted guardian relationship")
  }

  private var circleMapCard: some View {
    Button {
      showingCircleMap = true
    } label: {
      SoberCard {
        HStack(spacing: 14) {
          ZStack {
            Circle().fill(Palette.item2.opacity(0.17))
            Image(systemName: model.guardianLocationSharingIsEnabled
              ? "location.fill" : "map.fill")
              .foregroundStyle(Palette.item2)
          }
          .frame(width: 50, height: 50)

          VStack(alignment: .leading, spacing: 4) {
            Text("Circle Map")
              .font(.headline)
              .foregroundStyle(Palette.textPrimary)
            Text(circleMapSummary)
              .font(.subheadline)
              .foregroundStyle(Palette.textSecondary)
              .multilineTextAlignment(.leading)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(Palette.textSecondary)
        }
      }
    }
    .buttonStyle(SoberCardButtonStyle())
    .accessibilityHint("Open the private family location map")
  }

  private var circleMapSummary: String {
    guard model.guardianRelationshipIsActive else {
      return "Connect your Guardian to start a private map"
    }
    if model.guardianLocationSharing?.enabled == true {
      if let captured = model.guardianLocationSharing?.latestLocation?.capturedDate {
        return "Latest location \(captured.formatted(.relative(presentation: .named)))"
      }
      return "Sharing is on · waiting for the first update"
    }
    return model.guardianSession?.role == .person
      ? "Choose when your guardian can see your location"
      : "Location sharing is currently off"
  }

  private var guardianSummary: String {
    if model.guardianRelationshipIsActive {
      return model.guardianSession?.role == .guardian
        ? "Ready to respond to a help request"
        : "Connected for minimal in-app help requests"
    }
    if model.guardianInviteCode != nil { return "Invite ready to share" }
    return "Connect one trusted person before a live check"
  }

  private var safetyCircleSummary: String {
    if model.safetyPlan.hasRideDestination {
      return "\(model.safetyPlan.preferredRide) to \(model.safetyPlan.destinationDisplayName)"
    }
    return "Choose and name the address you’ll ride to"
  }

  private var founderPreviewCard: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: 13) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Review every safety state")
            .font(.headline)
          Text(
            "These paths use clearly labeled sample data so the team can inspect copy and intervention behavior."
          )
          .font(.subheadline)
          .foregroundStyle(Palette.textSecondary)
        }

        ForEach([FounderScenario.signals, .inconclusive, .noSignals]) { scenario in
          Button {
            launch = ScreeningLaunch(mode: .check, scenario: scenario)
          } label: {
            HStack {
              Circle()
                .fill(scenarioColor(scenario))
                .frame(width: 8, height: 8)
              Text(scenario.rawValue)
                .font(.subheadline.weight(.semibold))
              Spacer()
              Image(systemName: "arrow.up.right")
                .font(.caption.weight(.bold))
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(.vertical, 3)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var researchCenterCard: some View {
    Button {
      showingResearch = true
    } label: {
      SoberCard {
        HStack(spacing: 14) {
          ZStack {
            Circle().fill(Palette.item2.opacity(0.16))
            Image(systemName: "waveform.path.ecg.rectangle.fill")
              .foregroundStyle(Palette.item2)
          }
          .frame(width: 50, height: 50)

          VStack(alignment: .leading, spacing: 4) {
            Text("Research Center")
              .font(.headline)
              .foregroundStyle(Palette.textPrimary)
            Text("Consent, context, \(model.researchSessions.count) sessions, export, and deletion")
              .font(.subheadline)
              .foregroundStyle(Palette.textSecondary)
              .multilineTextAlignment(.leading)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(Palette.textSecondary)
        }
      }
    }
    .buttonStyle(SoberCardButtonStyle())
    .accessibilityHint("Open local research data controls")
  }

  private var evidenceNote: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.shield")
        .foregroundStyle(Palette.warning)
      Text(
        "This MVP demonstrates product behavior. It has not been clinically validated and must not be used to decide whether to drive."
      )
      .font(.caption)
      .foregroundStyle(Palette.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 8)
    .padding(.top, 4)
  }

  private func scenarioColor(_ scenario: FounderScenario) -> Color {
    switch scenario {
    case .signals: Palette.error
    case .inconclusive: Palette.warning
    case .noSignals, .live: Palette.primary
    }
  }
}

struct AboutPrototypeView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var showingReset = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          SignalHalo(size: 130, isActive: false)
            .frame(maxWidth: .infinity)

          ScreenHeader(
            eyebrow: "Sober 0.2",
            title: "A founder-review build.",
            detail:
              "The app demonstrates an ethically constrained screening and intervention flow, not a validated impairment detector."
          )

          SoberCard {
            VStack(alignment: .leading, spacing: 14) {
              aboutRow("No safe-to-drive state", "checkmark.shield")
              aboutRow("Self-report hard gate", "hand.raised")
              aboutRow("Quality-gated results", "waveform.badge.magnifyingglass")
              aboutRow("Ride and contact on every result", "car.side")
              aboutRow("Automatic parent alert after concerning results", "message.badge.fill")
              aboutRow("No raw biometric uploads", "network.slash")
            }
          }

          Button("Reset prototype") {
            showingReset = true
          }
          .foregroundStyle(Palette.textSecondary)
          .frame(maxWidth: .infinity)
        }
        .padding(22)
      }
      .soberBackground()
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .alert("Reset the prototype and delete research data?", isPresented: $showingReset) {
        Button("Cancel", role: .cancel) {}
        Button("Reset and delete", role: .destructive) {
          dismiss()
          model.resetPrototype()
        }
      } message: {
        Text(
          "This clears onboarding, your Safety Circle, and consent, and permanently deletes all \(model.researchSessions.count) stored research session\(model.researchSessions.count == 1 ? "" : "s") and your measured baseline. Export first if you need the data. This cannot be undone."
        )
      }
    }
  }

  private func aboutRow(_ title: String, _ icon: String) -> some View {
    Label(title, systemImage: icon)
      .font(.subheadline.weight(.medium))
      .foregroundStyle(Palette.textPrimary)
  }
}
