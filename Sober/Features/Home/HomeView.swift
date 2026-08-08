import SwiftUI

// 0.5s: one calm readiness card, one orange action, then Map, Guardian, and Plans.
// The feature implementations remain in their existing focused screens; this view
// is the DesignKit navigation shell that makes every one of them reachable.
struct HomeView: View {
  @EnvironmentObject private var model: AppModel
  @State private var launch: ScreeningLaunch?
  @State private var showingPlan = false
  @State private var showingGuardian = false
  @State private var showingCircleMap = false
  @State private var showingAbout = false
  @State private var showingResearch = false

  var body: some View {
    DSIntegratedHomeScreen(
      onStartBaseline: {
        launch = ScreeningLaunch(mode: .baseline, scenario: .live)
      },
      onStartCheck: {
        launch = ScreeningLaunch(mode: .check, scenario: .live)
      },
      onStartScheduledCheckIn: {
        guard case let .due(occurrence) = model.guardianCheckInEvaluation else { return }
        launch = ScreeningLaunch(
          mode: .check,
          scenario: .live,
          guardianCheckInOccurrenceID: occurrence.id
        )
      },
      onEvaluateCheckInLocation: {
        Task { await model.evaluateGuardianCheckInLocation() }
      },
      onOpenMap: { showingCircleMap = true },
      onOpenGuardian: { showingGuardian = true },
      onOpenPlan: { showingPlan = true },
      onOpenAbout: { showingAbout = true },
      onOpenResearch: { showingResearch = true },
      onOpenFounderScenario: { scenario in
        launch = ScreeningLaunch(mode: .check, scenario: scenario)
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
              aboutRow("Signed Guardian help request after concerning results", "message.badge.fill")
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
