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
  @EnvironmentObject private var guardianCoordinator: GuardianCoordinator
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
  @State private var showingExitAlert = false
  @State private var sessionStartedAt = Date()
  @State private var baselineAccepted = false
  @State private var baselineCompletionState = BaselineCompletionState(reason: .ready)

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
              context: configuration.scenario == .live ? model.researchPreferences : nil
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
      .padding(.top, canExit ? 56 : 0)
      .animation(reduceMotion ? nil : Motion.standard, value: step)

      if canExit {
        closeControl
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Space.sm)
          .padding(.top, Space.xxs)
      }

      if let index = taskIndex {
        taskDots(current: index)
          .frame(maxHeight: .infinity, alignment: .bottom)
          .padding(.bottom, Space.lg)
      }
    }
    // The check stays dark regardless of system appearance: the ocular and
    // light-reflex tasks control screen luminance as part of the protocol, so
    // a light page would corrupt the capture.
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

  /// The only chrome during a task. Low contrast, out of the way, and never
  /// competing with the target.
  private var closeControl: some View {
    Button {
      showingExitAlert = true
    } label: {
      Image(systemName: "xmark")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Palette.textMuted)
        .frame(width: Hit.minimum, height: Hit.minimum)
        .contentShape(Rectangle())
    }
    .accessibilityLabel("Leave check")
  }

  /// Progress, stated as quietly as it can be. Five dots at the very bottom
  /// of the screen: glanceable, peripheral, and ignorable.
  ///
  /// A step counter tells someone how much longer they must endure, which is
  /// the wrong frame for a task that asks for attention.
  private func taskDots(current: Int) -> some View {
    HStack(spacing: Space.xs) {
      ForEach(1...Self.taskCount, id: \.self) { index in
        Circle()
          .fill(index <= current ? Palette.accent : Palette.textMuted.opacity(0.35))
          .frame(width: 4, height: 4)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Task \(current) of \(Self.taskCount)")
  }

  private static let taskCount = 5

  /// 1-based position among the five measured tasks, or `nil` for the setup
  /// and scoring steps that bracket them.
  private var taskIndex: Int? {
    switch step {
    case .reaction: 1
    case .tracking: 2
    case .timing: 3
    case .gaze: 4
    case .pupil: 5
    case .attestation, .environment, .analyzing, .result, .baselineComplete: nil
    }
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
      let gateOutcome = engine.evaluate(selfReport: answer, metrics: metrics)
      presentOutcome(gateOutcome)
      Task {
        await model.recordCompletedSession(
          mode: .check,
          selfReport: answer,
          metrics: metrics,
          reactionSummary: nil,
          ocularSummary: nil,
          startedAt: sessionStartedAt,
          resultState: gateOutcome.state,
          signalRisks: gateOutcome.signalRisks
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
    let routeOutcome = engine.evaluate(selfReport: answer, metrics: metrics)
    presentOutcome(routeOutcome)
    Task {
      await model.recordCompletedSession(
        mode: .check,
        selfReport: answer,
        metrics: metrics,
        reactionSummary: nil,
        ocularSummary: nil,
        startedAt: sessionStartedAt,
        resultState: routeOutcome.state,
        signalRisks: routeOutcome.signalRisks
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

    let checkOutcome = engine.evaluate(
      selfReport: selfReport, metrics: metrics, personalBaseline: model.baseline)
    presentOutcome(checkOutcome)
    Task {
      await model.recordCompletedSession(
        mode: .check,
        selfReport: selfReport,
        metrics: metrics,
        reactionSummary: reactionSummary,
        ocularSummary: ocularSummary,
        startedAt: sessionStartedAt,
        resultState: checkOutcome.state,
        signalRisks: checkOutcome.signalRisks
      )
    }
  }

  private func presentOutcome(_ newOutcome: ScreeningOutcome) {
    outcome = newOutcome
    step = .result
    if configuration.scenario == .live {
      Task {
        await guardianCoordinator.recordScreeningResult(
          isValid: newOutcome.state != .inconclusive)
      }
    }
  }
}

/// The container every step of the check sits in.
///
/// It draws no progress of its own: the flow header above already states the
/// task and its position, and two indicators saying the same thing is exactly
/// the noise this screen cannot afford. Content is given generous vertical
/// room so a task reads as one thing to do rather than a page to work down.
struct FlowContainer<Content: View>: View {
  let progress: Int?
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.xl) {
        content
      }
      .appear()
      .padding(.horizontal, Space.lg)
      .padding(.top, Space.xl)
      .padding(.bottom, Space.xl)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollIndicators(.hidden)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .pageBackground()
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
          .font(SoberType.body)
          .fixedSize(horizontal: false, vertical: true)
        }
        .tint(Palette.accent)
      }

      Button("Begin baseline session", action: onContinue)
        .buttonStyle(PrimaryActionButtonStyle())
        .disabled(!attested)
        .opacity(attested ? 1 : 0.42)

      Text("Don’t use a baseline session to decide whether to drive.")
        .font(SoberType.footnote)
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

      VStack(spacing: Space.xs) {
        answerButton("Yes", value: .yes)
        answerButton("I’m not sure", value: .unsure)
        answerButton("No", value: .no)
      }

      if let selection, selection != .no {
        SoberCard {
          HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: "hand.raised.fill")
              .foregroundStyle(Palette.warning)
            Text(
              "We won’t run tasks to talk you out of what you already know. Safer options come next."
            )
            .font(SoberType.body)
            .fixedSize(horizontal: false, vertical: true)
          }
        }
      }

      if isVoiceOverEnabled {
        SoberCard {
          VStack(alignment: .leading, spacing: Space.xs) {
            Text("I can’t do the visual tasks")
              .font(SoberType.body)
            Text("The visual tasks need sight and a steady drag. You can skip them and still get to the safer next step.")
              .font(SoberType.subheadline)
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
        PrimaryActionButtonStyle()
      )
      .disabled(selection == nil)
      .opacity(selection == nil ? 0.42 : 1)

      Text("Sober never returns a no-signals result after reported use.")
        .font(SoberType.footnote)
        .foregroundStyle(Palette.textSecondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
  }

  private func answerButton(_ title: String, value: SelfReport) -> some View {
    Button {
      selection = value
    } label: {
      HStack {
        Text(title).font(SoberType.body)
        Spacer()
        Image(systemName: selection == value ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(selection == value ? Palette.accent : Palette.textSecondary)
      }
      .foregroundStyle(Palette.textPrimary)
      .padding(.horizontal, Space.md)
      .frame(minHeight: 58)
      .background(
        Palette.raised, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
          .stroke(
            selection == value ? Palette.accent : Palette.line, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }
}

private struct AnalyzingView: View {
  let onComplete: () -> Void

  private static let tasks = [
    "Reaction", "Tracking", "Timing", "Guided gaze", "Light reflex",
  ]

  var body: some View {
    VStack(spacing: Space.lg) {
      ProgressRing(completed: 5, total: 5, size: 148)

      VStack(spacing: Space.xs) {
        Text("Comparing your signals")
          .font(SoberType.title)
          .titleTracking()
        Text("Against your own baseline, not against anyone else's.")
          .font(SoberType.subheadline)
          .foregroundStyle(Palette.textSecondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(spacing: 0) {
        ForEach(Array(Self.tasks.enumerated()), id: \.offset) { index, task in
          if index > 0 { SoberDivider() }
          HStack(spacing: Space.sm) {
            Image(systemName: "checkmark")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(Palette.accentBright)
              .frame(width: 16)
            Text(task)
              .font(SoberType.subheadline)
              .foregroundStyle(Palette.textSecondary)
            Spacer()
          }
          .padding(.horizontal, Space.md)
          .padding(.vertical, Space.sm)
        }
      }
      .background(
        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Palette.raised)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(Palette.line, lineWidth: 1)
      )
      .padding(.horizontal, Space.md)
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
    VStack(spacing: Space.lg) {
      Spacer()
      StateMark(symbol: accepted ? "checkmark" : "minus", size: 104)
        .soberEntrance(order: 0)
      VStack(spacing: Space.xs) {
        Text(accepted ? "Baseline recorded" : completionState.title)
          .font(SoberType.hero)
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
          "This was calibration, not a driving result. It does not mean you’re sober or safe to drive."
        )
        .font(SoberType.body)
        .fixedSize(horizontal: false, vertical: true)
      }
      .soberEntrance(order: 2)
      Spacer()
      Button("Return home", action: onDone)
        .buttonStyle(PrimaryActionButtonStyle())
        .soberEntrance(order: 3)
    }
    .padding(Space.lg)
    .soberBackground()
  }
}
