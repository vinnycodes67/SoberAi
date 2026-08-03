import SwiftUI

// 0.5s: the signal halo floats above one decisive action.
// User: about to leave a social setting and wants a low-friction pause.
// Primary goal: begin a private check or get home without driving.
struct HomeView: View {
  @EnvironmentObject private var model: AppModel
  @State private var launch: ScreeningLaunch?
  @State private var showingPlan = false
  @State private var showingAbout = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          hero
          baselineCard
          nightOutCard

          if model.isFounderPreview {
            founderPreviewCard
          }

          evidenceNote
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
    .sheet(isPresented: $showingAbout) {
      AboutPrototypeView()
        .environmentObject(model)
        .preferredColorScheme(.dark)
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
        Text(model.baselineReady ? "Pause. Check in." : "Learn your steady.")
          .font(.system(.largeTitle, design: .serif, weight: .semibold))
          .tracking(-1.1)
          .multilineTextAlignment(.center)
        Text(
          model.baselineReady
            ? "About two minutes. Private on this iPhone."
            : "Three sober sessions create your starter baseline."
        )
        .font(.subheadline)
        .foregroundStyle(Palette.textSecondary)
        .multilineTextAlignment(.center)
      }

      Button(model.baselineReady ? "Start a check" : "Record sober baseline") {
        launch = ScreeningLaunch(
          mode: model.baselineReady ? .check : .baseline,
          scenario: .live
        )
      }
      .buttonStyle(PrimaryActionButtonStyle())
      .padding(.top, 6)
    }
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
          Text("\(model.baselineSessions)/3")
            .font(.title2.monospacedDigit().weight(.semibold))
            .foregroundStyle(Palette.primary)
        }

        HStack(spacing: 8) {
          ForEach(0..<3, id: \.self) { index in
            Capsule()
              .fill(
                index < model.baselineSessions ? Palette.primary : Palette.secondary.opacity(0.22)
              )
              .frame(height: 8)
          }
        }

        Text(
          "A production model will require a larger validated baseline. Three sessions keep this MVP reviewable; the research handoff suggests 10–20."
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
            Text("Night Out Mode")
              .font(.headline)
              .foregroundStyle(Palette.textPrimary)
            Text(
              model.safetyPlan.isActive
                ? "\(model.safetyPlan.preferredRide) + \(model.safetyPlan.contactName) are ready"
                : "Choose your ride and person while clear-headed"
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
    .buttonStyle(.plain)
    .accessibilityHint("Configure your ride and designated contact")
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
            eyebrow: "Sober 0.1",
            title: "A founder-review build.",
            detail:
              "The app demonstrates an ethically constrained screening and intervention flow—not a validated impairment detector."
          )

          SoberCard {
            VStack(alignment: .leading, spacing: 14) {
              aboutRow("No safe-to-drive state", "checkmark.shield")
              aboutRow("Self-report hard gate", "hand.raised")
              aboutRow("Quality-gated results", "waveform.badge.magnifyingglass")
              aboutRow("Ride and contact on every result", "car.side")
              aboutRow("No measurement-path networking", "network.slash")
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
      .alert("Reset onboarding and baseline?", isPresented: $showingReset) {
        Button("Cancel", role: .cancel) {}
        Button("Reset", role: .destructive) {
          dismiss()
          model.resetPrototype()
        }
      } message: {
        Text("This removes locally stored prototype setup state.")
      }
    }
  }

  private func aboutRow(_ title: String, _ icon: String) -> some View {
    Label(title, systemImage: icon)
      .font(.subheadline.weight(.medium))
      .foregroundStyle(Palette.textPrimary)
  }
}
