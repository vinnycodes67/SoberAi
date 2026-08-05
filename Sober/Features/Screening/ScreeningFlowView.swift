import SwiftUI

private enum ScreeningStep: Int {
  case attestation
  case environment
  case reaction
  case tracking
  case timing
  case gaze
  case pupil
  case analyzing
  case result
  case baselineComplete
}

struct ScreeningFlowView: View {
  let configuration: ScreeningLaunch

  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @StateObject private var faceTracking = FaceTrackingService()
  @StateObject private var pupilCapture = PupilCaptureService()
  @State private var step: ScreeningStep
  @State private var selfReport: SelfReport = .no
  @State private var reactionTime = 0.0
  @State private var reactionMisses = 0
  @State private var reactionSummary: ChoiceReactionSummary?
  @State private var trackingError: Double?
  @State private var trackingWasMeasured = true
  @State private var timingError = 0.0
  @State private var gazeSmoothness: Double?
  @State private var pupilSample: PupillometrySample?
  // Defaults to failing so an unset value can never pass the quality gate.
  @State private var qualityScore = 0.0
  @State private var ocularSummary: GazeCaptureSummary?
  @State private var outcome: ScreeningOutcome?
  @StateObject private var parentAlert: ParentAlertCoordinator
  @State private var showingExitAlert = false
  @State private var sessionStartedAt = Date()
  @State private var baselineAccepted = false
  @State private var baselineCompletionState = BaselineCompletionState(reason: .ready)

  private let engine = ScreeningEngine()

  init(configuration: ScreeningLaunch) {
    self.configuration = configuration
    if configuration.scenario == .live {
      _step = State(initialValue: .attestation)
      _parentAlert = StateObject(wrappedValue: ParentAlertCoordinator())
    } else {
      _step = State(initialValue: .result)
      _parentAlert = StateObject(
        wrappedValue: ParentAlertCoordinator(
          state: configuration.scenario == .signals ? .preview : .notRequired
        )
      )
      _outcome = State(
        initialValue: ScreeningEngine().evaluate(
          selfReport: .no,
          metrics: .demoClear,
          founderScenario: configuration.scenario
        ))
    }
  }

  private var parentAlertState: ParentAlertDeliveryState { parentAlert.state }

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
            } onAccessibilityRoute: { answer in
              handleAccessibilityUnavailableRoute(answer)
            }
          }
        case .environment:
          CameraCalibrationView(service: faceTracking) {
            step = .reaction
          }
        case .reaction:
          ReactionTaskView { summary in
            reactionSummary = summary
            reactionTime = summary.averageMilliseconds
            reactionMisses = summary.totalErrors
            step = .tracking
          }
        case .tracking:
          MotorTrackingTaskView { result in
            trackingError = result.wasMeasured ? result.error : nil
            trackingWasMeasured = result.wasMeasured
            step = .timing
          }
        case .timing:
          TimeEstimateTaskView { error in
            timingError = error
            step = .gaze
          }
        case .gaze:
          OcularTaskView(service: faceTracking) { summary in
            ocularSummary = summary
            gazeSmoothness = summary.smoothnessRisk
            qualityScore = summary.qualityScore
            step = .pupil
          }
        case .pupil:
          PupillometryTaskView(service: pupilCapture) { sample in
            pupilSample = sample
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
              isSample: configuration.scenario != .live,
              parentAlertState: parentAlertState,
              onRetryParentAlert: { beginParentAlert(for: outcome) }
            ) {
              dismiss()
            }
          }
        case .baselineComplete:
          BaselineCompleteView(
            sessions: model.baselineSessions,
            accepted: baselineAccepted,
            completionState: baselineCompletionState,
            onDone: { dismiss() }
          )
        }
      }
      .id(step)
      .transition(
        reduceMotion
          ? .opacity
          : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 10)),
            removal: .opacity.combined(with: .offset(x: -8))
          )
      )
      .animation(reduceMotion ? nil : SoberMotion.screen, value: step)

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
              .soberGlassCircle()
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
      let metrics = ScreeningMetrics(
        reactionTimeMilliseconds: 0,
        reactionMisses: 0,
        trackingError: 0,
        timeEstimateError: 0,
        gazeSmoothness: 0,
        qualityScore: 0,
        completedAllTasks: false
      )
      presentOutcome(engine.evaluate(selfReport: answer, metrics: metrics))
      Task {
        await model.recordCompletedSession(
          mode: .check,
          selfReport: answer,
          metrics: metrics,
          reactionSummary: nil,
          ocularSummary: nil,
          startedAt: sessionStartedAt
        )
      }
      return
    }
    step = .environment
  }

  private func handleAccessibilityUnavailableRoute(_ answer: SelfReport) {
    selfReport = answer
    let metrics = ScreeningMetrics(
      reactionTimeMilliseconds: 0,
      reactionMisses: 0,
      trackingError: nil,
      timeEstimateError: 0,
      gazeSmoothness: nil,
      qualityScore: 0,
      completedAllTasks: false
    )
    presentOutcome(engine.evaluate(selfReport: answer, metrics: metrics))
    Task {
      await model.recordCompletedSession(
        mode: .check,
        selfReport: answer,
        metrics: metrics,
        reactionSummary: nil,
        ocularSummary: nil,
        startedAt: sessionStartedAt
      )
    }
  }

  private func finishScoring() {
    let metrics = ScreeningMetrics(
      reactionTimeMilliseconds: reactionTime,
      reactionMisses: reactionMisses,
      trackingError: trackingError,
      timeEstimateError: timingError,
      gazeSmoothness: gazeSmoothness,
      pupillometry: pupilSample,
      qualityScore: qualityScore,
      // A task the participant could not perform is not a completed task.
      completedAllTasks: trackingWasMeasured
    )

    if configuration.mode == .baseline {
      baselineAccepted = metrics.completedAllTasks && metrics.qualityScore >= 0.72
      baselineCompletionState = BaselineCompletionState(
        reason: baselineAccepted ? .ready : (trackingWasMeasured ? .captureQualityTooLow : .taskUnavailable)
      )
      // A low-quality capture would poison every future comparison against
      // this baseline, so it's held to the same quality bar as a real check
      // rather than being recorded unconditionally. Independent of the
      // research baseline recorded below.
      if baselineAccepted {
        model.recordBaseline(
          BaselineSample(
            reactionTimeMilliseconds: reactionTime,
            reactionMisses: reactionMisses,
            trackingError: trackingError,
            timeEstimateError: timingError,
            gazeSmoothness: gazeSmoothness,
            pupillometry: pupilSample
          )
        )
      }
      Task {
        await model.recordCompletedSession(
          mode: .baseline,
          selfReport: .no,
          metrics: metrics,
          reactionSummary: reactionSummary,
          ocularSummary: ocularSummary,
          startedAt: sessionStartedAt
        )
        step = .baselineComplete
      }
      return
    }

    presentOutcome(
      engine.evaluate(selfReport: selfReport, metrics: metrics, personalBaseline: model.baseline))
    Task {
      await model.recordCompletedSession(
        mode: .check,
        selfReport: selfReport,
        metrics: metrics,
        reactionSummary: reactionSummary,
        ocularSummary: ocularSummary,
        startedAt: sessionStartedAt
      )
    }
  }

  private func presentOutcome(_ newOutcome: ScreeningOutcome) {
    outcome = newOutcome
    step = .result
    beginParentAlert(for: newOutcome)
  }

  private func beginParentAlert(for outcome: ScreeningOutcome) {
    guard configuration.scenario == .live else {
      parentAlert.presentSample(for: outcome)
      return
    }
    parentAlert.send(outcome: outcome, safetyPlan: model.safetyPlan)
  }
}

struct FlowContainer<Content: View>: View {
  let progress: Int?
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let progress {
          StepProgress(current: progress, total: 6)
            .padding(.trailing, 54)
        }
        content
      }
      .soberEntrance()
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
  let onAccessibilityRoute: (SelfReport) -> Void
  @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
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

      if isVoiceOverEnabled {
        SoberCard {
          VStack(alignment: .leading, spacing: 8) {
            Text("I can’t do the visual tasks")
              .font(.headline)
            Text("The visual tasks need sight and a steady drag. You can skip them and still get to the safer next step.")
              .font(.subheadline)
              .foregroundStyle(Palette.textSecondary)
          }
        }

        Button("Skip the visual battery") {
          onAccessibilityRoute(selection ?? .no)
        }
        .buttonStyle(SecondaryActionButtonStyle(tint: Palette.warning))
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

private struct AnalyzingView: View {
  let onComplete: () -> Void

  var body: some View {
    VStack(spacing: 26) {
      SignalHalo(size: 238)
      VStack(spacing: 8) {
        Text("Comparing your signals")
          .font(.system(.title, design: .serif, weight: .semibold))
        Text("Reaction · tracking · timing · guided gaze · light reflex")
          .font(.caption)
          .foregroundStyle(Palette.textSecondary)
      }
    }
    .soberEntrance()
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
  let accepted: Bool
  let completionState: BaselineCompletionState
  let onDone: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Spacer()
      SignalHalo(tone: Palette.item0, size: 210, isActive: false)
        .soberEntrance(order: 0)
      VStack(spacing: 9) {
        Text(accepted ? "Baseline recorded" : completionState.title)
          .font(.system(.largeTitle, design: .serif, weight: .semibold))
        Text(
          accepted
            ? (sessions >= 5
              ? "Your five-session research baseline is ready."
              : "\(5 - sessions) sober session\(5 - sessions == 1 ? "" : "s") still needed.")
            : completionState.message
        )
        .foregroundStyle(Palette.textSecondary)
        .multilineTextAlignment(.center)
      }
      .soberEntrance(order: 1)
      SoberCard {
        Text(
          "This was calibration—not a driving result. It does not mean you’re sober or safe to drive."
        )
        .font(.subheadline.weight(.medium))
        .fixedSize(horizontal: false, vertical: true)
      }
      .soberEntrance(order: 2)
      Spacer()
      Button("Return home", action: onDone)
        .buttonStyle(PrimaryActionButtonStyle())
        .soberEntrance(order: 3)
    }
    .padding(22)
    .soberBackground()
  }
}
