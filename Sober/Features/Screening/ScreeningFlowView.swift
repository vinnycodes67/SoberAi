import SwiftUI

private enum ScreeningStep: Int {
  case attestation
  case environment
  case reaction
  case tracking
  case timing
  case gaze
  case analyzing
  case result
  case baselineComplete
}

struct ScreeningFlowView: View {
  let configuration: ScreeningLaunch

  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @StateObject private var faceTracking = FaceTrackingService()
  @State private var step: ScreeningStep
  @State private var selfReport: SelfReport = .no
  @State private var reactionTime = 0.0
  @State private var reactionMisses = 0
  @State private var trackingError = 0.0
  @State private var timingError = 0.0
  @State private var gazeSmoothness = 0.0
  @State private var qualityScore = 1.0
  @State private var outcome: ScreeningOutcome?
  @State private var showingExitAlert = false

  private let engine = ScreeningEngine()

  init(configuration: ScreeningLaunch) {
    self.configuration = configuration
    if configuration.scenario == .live {
      _step = State(initialValue: .attestation)
    } else {
      _step = State(initialValue: .result)
      _outcome = State(
        initialValue: ScreeningEngine().evaluate(
          selfReport: .no,
          metrics: .demoClear,
          founderScenario: configuration.scenario
        ))
    }
  }

  var body: some View {
    ZStack(alignment: .top) {
      Group {
        switch step {
        case .attestation:
          if configuration.mode == .baseline {
            BaselineAttestationView { step = .environment }
          } else {
            SelfReportView { answer in
              handleSelfReport(answer)
            }
          }
        case .environment:
          EnvironmentCheckView(faceTrackingSupported: faceTracking.isSupported) {
            step = .reaction
          }
        case .reaction:
          ReactionTaskView { average, misses in
            reactionTime = average
            reactionMisses = misses
            step = .tracking
          }
        case .tracking:
          MotorTrackingTaskView { error in
            trackingError = error
            step = .timing
          }
        case .timing:
          TimeEstimateTaskView { error in
            timingError = error
            step = .gaze
          }
        case .gaze:
          GuidedGazeTaskView(service: faceTracking) { summary in
            gazeSmoothness = summary.smoothnessRisk
            qualityScore = summary.qualityScore
            step = .analyzing
          }
        case .analyzing:
          AnalyzingView {
            finishScoring()
          }
        case .result:
          if let outcome {
            ResultView(
              outcome: outcome,
              safetyPlan: model.safetyPlan,
              isSample: configuration.scenario != .live
            ) {
              dismiss()
            }
          }
        case .baselineComplete:
          BaselineCompleteView(
            sessions: model.baselineSessions,
            onDone: { dismiss() }
          )
        }
      }

      if canExit {
        HStack {
          Spacer()
          Button {
            showingExitAlert = true
          } label: {
            Image(systemName: "xmark")
              .font(.subheadline.weight(.bold))
              .foregroundStyle(Palette.textSecondary)
              .frame(width: 44, height: 44)
              .background(.ultraThinMaterial, in: Circle())
          }
          .accessibilityLabel("Exit check")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
      }
    }
    .preferredColorScheme(.dark)
    .interactiveDismissDisabled()
    .alert("Leave this check?", isPresented: $showingExitAlert) {
      Button("Keep going", role: .cancel) {}
      Button("Leave check", role: .destructive) { dismiss() }
    } message: {
      Text("Progress from this check won’t be saved.")
    }
  }

  private var canExit: Bool {
    step != .result && step != .baselineComplete && configuration.scenario == .live
  }

  private func handleSelfReport(_ answer: SelfReport) {
    selfReport = answer
    guard answer == .no else {
      outcome = engine.evaluate(
        selfReport: answer,
        metrics: ScreeningMetrics(
          reactionTimeMilliseconds: 0,
          reactionMisses: 0,
          trackingError: 0,
          timeEstimateError: 0,
          gazeSmoothness: 0,
          qualityScore: 1,
          completedAllTasks: false
        )
      )
      step = .result
      return
    }
    step = .environment
  }

  private func finishScoring() {
    if configuration.mode == .baseline {
      model.recordBaseline()
      step = .baselineComplete
      return
    }

    let metrics = ScreeningMetrics(
      reactionTimeMilliseconds: reactionTime,
      reactionMisses: reactionMisses,
      trackingError: trackingError,
      timeEstimateError: timingError,
      gazeSmoothness: gazeSmoothness,
      qualityScore: qualityScore,
      completedAllTasks: true
    )
    outcome = engine.evaluate(selfReport: selfReport, metrics: metrics)
    step = .result
  }
}

struct FlowContainer<Content: View>: View {
  let progress: Int?
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let progress {
          StepProgress(current: progress, total: 5)
            .padding(.trailing, 54)
        }
        content
      }
      .padding(.horizontal, 22)
      .padding(.top, 58)
      .padding(.bottom, 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .soberBackground()
  }
}

private struct BaselineAttestationView: View {
  let onContinue: () -> Void
  @State private var attested = false

  var body: some View {
    FlowContainer(progress: nil) {
      ScreenHeader(
        eyebrow: "Sober baseline",
        title: "Only record your normal.",
        detail:
          "A baseline is useful only when it reflects you sober, rested, and feeling like yourself."
      )

      SoberCard {
        Toggle(isOn: $attested) {
          Text(
            "I haven’t used alcohol, cannabis, stimulants, opioids, or other impairing substances in the last 4 hours, and I feel rested."
          )
          .font(.body.weight(.medium))
          .fixedSize(horizontal: false, vertical: true)
        }
        .tint(Palette.primary)
      }

      Button("Begin baseline session", action: onContinue)
        .buttonStyle(PrimaryActionButtonStyle())
        .disabled(!attested)
        .opacity(attested ? 1 : 0.42)

      Text("Don’t use a baseline session to decide whether to drive.")
        .font(.caption)
        .foregroundStyle(Palette.textSecondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
  }
}

private struct SelfReportView: View {
  let onContinue: (SelfReport) -> Void
  @State private var selection: SelfReport?

  var body: some View {
    FlowContainer(progress: nil) {
      ScreenHeader(
        eyebrow: "Before the check",
        title: "Have you had anything to drink or use in the last 4 hours?",
        detail:
          "Be honest with yourself. Your answer stays on this iPhone and overrides the task result."
      )

      VStack(spacing: 10) {
        answerButton("Yes", value: .yes)
        answerButton("I’m not sure", value: .unsure)
        answerButton("No", value: .no)
      }

      if let selection, selection != .no {
        SoberCard {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
              .foregroundStyle(Palette.warning)
            Text(
              "We won’t run tasks to talk you out of what you already know. Safer options come next."
            )
            .font(.subheadline.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
          }
        }
      }

      Button(selection == .no ? "Continue to setup" : "See safer options") {
        if let selection { onContinue(selection) }
      }
      .buttonStyle(
        PrimaryActionButtonStyle(tint: selection == .no ? Palette.primary : Palette.warning)
      )
      .disabled(selection == nil)
      .opacity(selection == nil ? 0.42 : 1)

      Text("Sober never returns a no-signals result after reported use.")
        .font(.caption)
        .foregroundStyle(Palette.textSecondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
  }

  private func answerButton(_ title: String, value: SelfReport) -> some View {
    Button {
      selection = value
    } label: {
      HStack {
        Text(title).font(.headline)
        Spacer()
        Image(systemName: selection == value ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(selection == value ? Palette.primary : Palette.textSecondary)
      }
      .foregroundStyle(Palette.textPrimary)
      .padding(.horizontal, 18)
      .frame(minHeight: 58)
      .background(
        Palette.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(
            selection == value ? Palette.primary : Palette.secondary.opacity(0.2), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }
}

private struct EnvironmentCheckView: View {
  let faceTrackingSupported: Bool
  let onContinue: () -> Void
  @State private var phoneStable = false
  @State private var evenLight = false
  @State private var glassesClear = false

  private var isReady: Bool { phoneStable && evenLight && glassesClear }

  var body: some View {
    FlowContainer(progress: 0) {
      ScreenHeader(
        eyebrow: "Set up",
        title: "Give the check a fair shot.",
        detail:
          "Bad capture quality returns inconclusive. It never guesses through motion, darkness, or glare."
      )

      SoberCard {
        VStack(spacing: 18) {
          setupToggle("Phone is propped or held still", icon: "iphone", isOn: $phoneStable)
          Divider().overlay(Palette.secondary.opacity(0.2))
          setupToggle("My face is evenly lit", icon: "sun.max", isOn: $evenLight)
          Divider().overlay(Palette.secondary.opacity(0.2))
          setupToggle("No glare covers my eyes", icon: "eyeglasses", isOn: $glassesClear)
        }
      }

      HStack(spacing: 10) {
        Image(systemName: faceTrackingSupported ? "faceid" : "desktopcomputer")
          .foregroundStyle(Palette.primary)
        Text(
          faceTrackingSupported
            ? "TrueDepth is available for the guided gaze step."
            : "Simulator mode will use a labeled demo trace for guided gaze."
        )
        .font(.caption)
        .foregroundStyle(Palette.textSecondary)
      }

      Button("I’m ready", action: onContinue)
        .buttonStyle(PrimaryActionButtonStyle())
        .disabled(!isReady)
        .opacity(isReady ? 1 : 0.42)
    }
  }

  private func setupToggle(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
      Label(title, systemImage: icon)
        .font(.subheadline.weight(.medium))
    }
    .tint(Palette.primary)
  }
}

private struct AnalyzingView: View {
  let onComplete: () -> Void

  var body: some View {
    VStack(spacing: 26) {
      SignalHalo(size: 238)
      VStack(spacing: 8) {
        Text("Comparing your signals")
          .font(.system(.title, design: .serif, weight: .semibold))
        Text("Reaction · tracking · timing · guided gaze")
          .font(.caption)
          .foregroundStyle(Palette.textSecondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .soberBackground()
    .task {
      try? await Task.sleep(for: .milliseconds(900))
      onComplete()
    }
  }
}

private struct BaselineCompleteView: View {
  let sessions: Int
  let onDone: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Spacer()
      SignalHalo(tone: Palette.item0, size: 210, isActive: false)
      VStack(spacing: 9) {
        Text("Baseline recorded")
          .font(.system(.largeTitle, design: .serif, weight: .semibold))
        Text(
          sessions >= 3
            ? "Your three-session starter baseline is ready."
            : "\(3 - sessions) sober session\(3 - sessions == 1 ? "" : "s") still needed."
        )
        .foregroundStyle(Palette.textSecondary)
        .multilineTextAlignment(.center)
      }
      SoberCard {
        Text(
          "This was calibration—not a driving result. It does not mean you’re sober or safe to drive."
        )
        .font(.subheadline.weight(.medium))
        .fixedSize(horizontal: false, vertical: true)
      }
      Spacer()
      Button("Return home", action: onDone)
        .buttonStyle(PrimaryActionButtonStyle())
    }
    .padding(22)
    .soberBackground()
  }
}
