import SwiftUI

struct ReactionTaskView: View {
  let onComplete: (ChoiceReactionSummary) -> Void

  private enum Phase {
    case intro
    case waiting
    case target
    case feedback
  }

  @State private var phase: Phase = .intro
  @State private var trials: [ChoiceReactionTrial] = []
  @State private var target: ChoiceReactionSymbol = .blueCircle
  @State private var targetAppearedAt = Date()
  @State private var waitTask: Task<Void, Never>?
  @State private var timeoutTask: Task<Void, Never>?
  @State private var finished = false

  private let roundCount = 6

  var body: some View {
    FlowContainer(progress: 1) {
      ScreenHeader(
        eyebrow: "Divided attention",
        title: "Match the color and shape.",
        detail: "Wait for the cue, then choose its exact match. Early, incorrect, and missed responses are recorded."
      )

      VStack(spacing: DSSpace.sm) {
        ZStack {
          RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
            .fill(StimulusPalette.field)
            .overlay {
              RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
                .stroke(StimulusPalette.guide.opacity(0.2), lineWidth: 1)
            }

          if phase == .target {
            reactionSymbol(target, size: 94)
              .shadow(color: symbolColor(target).opacity(0.42), radius: 22)
              .accessibilityLabel("Target: \(target.accessibilityLabel)")
          } else {
            VStack(spacing: DSSpace.sm) {
              if phase == .intro {
                Text("6 choices")
                  .font(DSFont.title)
                Text("Color + shape + timing")
                  .font(DSFont.subheadline)
                  .foregroundStyle(Palette.textSecondary)
              } else if phase == .waiting {
                Circle()
                  .fill(StimulusPalette.guide.opacity(0.25))
                  .frame(width: 12, height: 12)
                Text("Wait…")
                  .font(DSFont.subheadline)
                  .foregroundStyle(Palette.textSecondary)
              } else {
                Image(systemName: "checkmark")
                  .font(DSFont.title)
                  .foregroundStyle(Palette.primary)
              }
            }
          }
        }
        .frame(height: 200)

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpace.xs) {
          ForEach(ChoiceReactionSymbol.allCases, id: \.rawValue) { choice in
            Button {
              choiceTapped(choice)
            } label: {
              HStack(spacing: DSSpace.xs) {
                reactionSymbol(choice, size: 28)
                Text(choice.accessibilityLabel)
                  .font(DSFont.footnoteStrong)
                  .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
              }
              .padding(.horizontal, DSSpace.sm)
              .frame(minHeight: 54)
              .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
                  .stroke(symbolColor(choice).opacity(0.4), lineWidth: 1)
              }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(choice.accessibilityLabel)
          }
        }
      }

      HStack {
        Label("\(trials.count) of \(roundCount)", systemImage: "scope")
        Spacer()
        let errors = trials.filter { !$0.isCorrect }.count
        if errors > 0 {
          Text("\(errors) error\(errors == 1 ? "" : "s")")
            .foregroundStyle(Palette.warning)
        }
      }
      .font(DSFont.footnote.monospacedDigit())
      .foregroundStyle(Palette.textSecondary)

      if phase == .intro {
        Button("Begin reaction task") {
          beginRound()
        }
        .buttonStyle(PrimaryActionButtonStyle())
      }
    }
    .onDisappear {
      waitTask?.cancel()
      timeoutTask?.cancel()
    }
  }

  private func beginRound(afterFeedback: Bool = false) {
    phase = afterFeedback ? .feedback : .waiting
    waitTask?.cancel()
    waitTask = Task {
      if afterFeedback {
        try? await Task.sleep(for: .milliseconds(300))
      }
      phase = .waiting
      try? await Task.sleep(for: .milliseconds(Int.random(in: 650...1350)))
      guard !Task.isCancelled else { return }
      target = ChoiceReactionSymbol.allCases.randomElement() ?? .blueCircle
      targetAppearedAt = Date()
      phase = .target
      timeoutTask?.cancel()
      timeoutTask = Task {
        try? await Task.sleep(for: .milliseconds(1_500))
        guard !Task.isCancelled, phase == .target else { return }
        record(ChoiceReactionTrial(
          expected: target,
          selected: nil,
          latencyMilliseconds: nil,
          wasAnticipation: false,
          wasMiss: true
        ))
      }
    }
  }

  private func choiceTapped(_ choice: ChoiceReactionSymbol) {
    guard !finished else { return }
    if phase == .waiting {
      waitTask?.cancel()
      record(ChoiceReactionTrial(
        expected: nil,
        selected: choice,
        latencyMilliseconds: nil,
        wasAnticipation: true,
        wasMiss: false
      ))
      return
    }
    guard phase == .target else { return }
    timeoutTask?.cancel()
    record(ChoiceReactionTrial(
      expected: target,
      selected: choice,
      latencyMilliseconds: Date().timeIntervalSince(targetAppearedAt) * 1_000,
      wasAnticipation: false,
      wasMiss: false
    ))
  }

  private func record(_ trial: ChoiceReactionTrial) {
    trials.append(trial)
    phase = .feedback

    if trials.count == roundCount {
      finished = true
      Task {
        try? await Task.sleep(for: .milliseconds(320))
        onComplete(ChoiceReactionSummary(trials: trials))
      }
    } else {
      beginRound(afterFeedback: true)
    }
  }

  @ViewBuilder
  private func reactionSymbol(_ symbol: ChoiceReactionSymbol, size: CGFloat) -> some View {
    let shape = symbol.shapeName
    if shape == "circle" {
      Circle()
        .fill(symbolColor(symbol))
        .frame(width: size, height: size)
    } else {
      RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
        .fill(symbolColor(symbol))
        .frame(width: size * 0.76, height: size * 0.76)
        .rotationEffect(.degrees(45))
        .frame(width: size, height: size)
    }
  }

  /// The two choice colours the task asks a person to tell apart.
  ///
  /// These must come from `StimulusPalette`, not the theme. Both once resolved
  /// through `Palette`, and repointing `Palette` at DesignKit — where `primary`
  /// and `accent` are the same orange — collapsed them into one colour and left
  /// a colour-discrimination task with nothing to discriminate.
  private func symbolColor(_ symbol: ChoiceReactionSymbol) -> Color {
    symbol.colorName == "Blue" ? StimulusPalette.targetPrimary : StimulusPalette.targetContrast
  }
}

struct MotorTrackingTaskView: View {
  let onComplete: (MotorTrackingOutcome) -> Void

  @State private var fingerPosition = CGPoint.zero
  @State private var cumulativeError = 0.0
  @State private var sampleCount = 0
  @State private var finished = false

  var body: some View {
    FlowContainer(progress: 2) {
      ScreenHeader(
        eyebrow: "Coordination",
        title: "Trace the current.",
        detail: "Press the circle and follow the path from left to right in one steady motion."
      )

      GeometryReader { proxy in
        let size = proxy.size
        let start = CGPoint(x: 28, y: idealY(for: 28, in: size))
        let displayPosition = fingerPosition == .zero ? start : fingerPosition

        ZStack {
          RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
            .fill(StimulusPalette.field)

          Canvas { context, _ in
            var path = Path()
            for x in stride(from: 28.0, through: max(size.width - 28, 28), by: 3) {
              let point = CGPoint(x: x, y: idealY(for: x, in: size))
              if x == 28 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(
              path,
              with: .color(StimulusPalette.guide.opacity(0.42)),
              style: StrokeStyle(lineWidth: 18, lineCap: .round)
            )
            context.stroke(
              path,
              with: .color(StimulusPalette.targetPrimary.opacity(0.74)),
              style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 8])
            )
          }

          Circle()
            .fill(StimulusPalette.targetPrimary)
            .frame(width: 54, height: 54)
            .overlay { Circle().stroke(Palette.textPrimary.opacity(0.5), lineWidth: 2) }
            .shadow(color: StimulusPalette.targetPrimary.opacity(0.32), radius: 16)
            .position(displayPosition)
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
            .stroke(StimulusPalette.guide.opacity(0.2), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              guard !finished else { return }
              let x = min(max(value.location.x, 28), size.width - 28)
              let y = min(max(value.location.y, 28), size.height - 28)
              fingerPosition = CGPoint(x: x, y: y)
              cumulativeError += abs(y - idealY(for: x, in: size)) / size.height
              sampleCount += 1
            }
            .onEnded { _ in
              guard !finished else { return }
              if fingerPosition.x >= size.width * 0.78, sampleCount >= 10 {
                finished = true
                let error = min((cumulativeError / Double(sampleCount)) * 2.4, 1)
                onComplete(MotorTrackingOutcome(error: error))
              } else {
                fingerPosition = .zero
                cumulativeError = 0
                sampleCount = 0
              }
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Motor tracking path")
        .accessibilityHint("Drag from the left edge to the right edge following the curved path")
        // This path cannot measure coordination, so it reports "not measured"
        // rather than a stand-in score. The check then ends as inconclusive.
        .accessibilityAction(named: "Skip tracing; result will be inconclusive") {
          guard !finished else { return }
          finished = true
          onComplete(.notMeasured)
        }
      }
      .frame(height: 330)

      HStack(spacing: DSSpace.xs) {
        Image(systemName: "arrow.right")
          .foregroundStyle(Palette.primary)
        Text("If you lift early, the path resets. That is expected.")
          .font(DSFont.footnote)
          .foregroundStyle(Palette.textSecondary)
      }
    }
  }

  private func idealY(for x: CGFloat, in size: CGSize) -> CGFloat {
    let usableWidth = max(size.width - 56, 1)
    let normalized = min(max((x - 28) / usableWidth, 0), 1)
    return (size.height / 2) + sin(normalized * .pi * 2.2) * (size.height * 0.22)
  }
}

struct TimeEstimateTaskView: View {
  let onComplete: (Double) -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var startedAt: Date?
  @State private var finished = false

  var body: some View {
    FlowContainer(progress: 3) {
      ScreenHeader(
        eyebrow: "Time sense",
        title: "Hold ten seconds in your head.",
        detail:
          "Start when ready. Count silently, then stop when you believe ten seconds have passed."
      )

      ZStack {
        RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
          .fill(StimulusPalette.field)

        if startedAt == nil {
          SignalHalo(size: 220, isActive: false)
        } else {
          TimelineView(.animation(paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt ?? timeline.date)
            ZStack {
              Circle()
                .stroke(StimulusPalette.targetPrimary.opacity(0.12), lineWidth: 2)
                .frame(width: reduceMotion ? 150 : 150 + sin(elapsed * 1.4) * 12)
              Circle()
                .fill(StimulusPalette.targetPrimary)
                .frame(width: 12, height: 12)
            }
          }
        }
      }
      .frame(height: 300)
      .overlay {
        RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
          .stroke(StimulusPalette.guide.opacity(0.2), lineWidth: 1)
      }

      Button(startedAt == nil ? "Start counting" : "Stop now") {
        if let startedAt {
          guard !finished else { return }
          finished = true
          let elapsed = Date().timeIntervalSince(startedAt)
          onComplete(min(abs(elapsed - 10) / 10, 1))
        } else {
          self.startedAt = Date()
        }
      }
      .buttonStyle(PrimaryActionButtonStyle())

      Text("The timer stays hidden on purpose.")
        .font(DSFont.footnote)
        .foregroundStyle(Palette.textSecondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
  }
}
