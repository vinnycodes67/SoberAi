import SwiftUI

// The public target is local-only. Guardian, Circle, Research, and founder
// routes are constructed only in the internal target at compile time.
struct HomeView: View {
  @EnvironmentObject private var model: AppModel
  @State private var launch: ScreeningLaunch?
  @State private var showingPlan = false
  @State private var showingAbout = false
  #if INTERNAL_BUILD
  @State private var showingGuardian = false
  @State private var showingCircleMap = false
  @State private var showingResearch = false
  #endif

  var body: some View {
    #if INTERNAL_BUILD
    internalHome
    #else
    baseHome
    #endif
  }

  private var baseHome: some View {
    DSIntegratedHomeScreen(
      onStartBaseline: {
        launch = ScreeningLaunch(mode: .baseline, scenario: .live)
      },
      onStartCheck: {
        launch = ScreeningLaunch(mode: .check, scenario: .live)
      },
      onStartScheduledCheckIn: {
        #if INTERNAL_BUILD
        guard case let .due(occurrence) = model.guardianCheckInEvaluation else { return }
        launch = ScreeningLaunch(
          mode: .check,
          scenario: .live,
          guardianCheckInOccurrenceID: occurrence.id
        )
        #endif
      },
      onEvaluateCheckInLocation: {
        #if INTERNAL_BUILD
        Task { await model.evaluateGuardianCheckInLocation() }
        #endif
      },
      onOpenMap: {
        #if INTERNAL_BUILD
        showingCircleMap = true
        #endif
      },
      onOpenGuardian: {
        #if INTERNAL_BUILD
        showingGuardian = true
        #endif
      },
      onOpenPlan: { showingPlan = true },
      onOpenAbout: { showingAbout = true },
      onOpenResearch: {
        #if INTERNAL_BUILD
        showingResearch = true
        #endif
      },
      onOpenFounderScenario: { scenario in
        #if INTERNAL_BUILD
        launch = ScreeningLaunch(mode: .check, scenario: scenario)
        #endif
      }
    )
    .preferredColorScheme(.dark)
    .fullScreenCover(item: $launch) { configuration in
      ScreeningFlowView(configuration: configuration)
        .environmentObject(model)
    }
    .sheet(isPresented: $showingPlan) {
      SafetyPlanView(plan: $model.safetyPlan)
        .preferredColorScheme(.dark)
    }
    .sheet(isPresented: $showingAbout) {
      AboutPrototypeView()
        .environmentObject(model)
        .preferredColorScheme(.dark)
    }
  }

  #if INTERNAL_BUILD
  private var internalHome: some View {
    baseHome
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
  #endif
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
            title: aboutTitle,
            detail:
              "The app demonstrates an ethically constrained screening and intervention flow, not a validated impairment detector."
          )

          SoberCard {
            VStack(alignment: .leading, spacing: 14) {
              aboutRow("No safe-to-drive state", "checkmark.shield")
              aboutRow("Self-report hard gate", "hand.raised")
              aboutRow("Quality-gated results", "waveform.badge.magnifyingglass")
              aboutRow("Ride and contact on every result", "car.side")
              #if INTERNAL_BUILD
              aboutRow("Signed Guardian help request after concerning results", "message.badge.fill")
              #endif
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
      .alert(resetTitle, isPresented: $showingReset) {
        Button("Cancel", role: .cancel) {}
        Button("Reset and delete", role: .destructive) {
          dismiss()
          model.resetPrototype()
        }
      } message: {
        Text(resetMessage)
      }
    }
  }

  private func aboutRow(_ title: String, _ icon: String) -> some View {
    Label(title, systemImage: icon)
      .font(DSFont.subheadlineStrong)
      .foregroundStyle(Palette.textPrimary)
  }

  private var aboutTitle: String {
    #if INTERNAL_BUILD
    "A founder-review build."
    #else
    "Private checks and a safer way home."
    #endif
  }

  private var resetTitle: String {
    #if INTERNAL_BUILD
    "Reset the prototype and delete research data?"
    #else
    "Reset Sober and delete local data?"
    #endif
  }

  private var resetMessage: String {
    #if INTERNAL_BUILD
    "This clears onboarding, your Safety Circle, and consent, and permanently deletes all \(model.researchSessions.count) stored research session\(model.researchSessions.count == 1 ? "" : "s") and your measured baseline. Export first if you need the data. This cannot be undone."
    #else
    "This clears onboarding, your Safety Plan, stored sessions, and your measured baseline from this iPhone. This cannot be undone."
    #endif
  }
}
