import SwiftUI

struct ReactionTaskView: View {
  let onComplete: (Double, Int) -> Void

  private enum Phase {
    case intro
    case waiting
    case target
    case feedback
  }

  @State private var phase: Phase = .intro
  @State private var reactions: [Double] = []
  @State private var falseStarts = 0
  @State private var targetX = 0.5
  @State private var targetY = 0.5
  @State private var targetAppearedAt = Date()
  @State private var waitTask: Task<Void, Never>?
  @State private var finished = false

  var body: some View {
    FlowContainer(progress: 1) {
      ScreenHeader(
        eyebrow: "Reaction",
        title: "Tap when the signal appears.",
        detail: "Wait for the blue target. Tapping early counts as a miss."
      )

      GeometryReader { proxy in
        ZStack {
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Palette.cardBackground)
            .overlay {
              RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Palette.secondary.opacity(0.2), lineWidth: 1)
            }

          if phase == .target {
            Button {
              targetTapped()
            } label: {
              Circle()
                .fill(Palette.primary)
                .frame(width: 76, height: 76)
                .overlay {
                  Circle().stroke(Palette.textPrimary.opacity(0.52), lineWidth: 2)
                }
                .shadow(color: Palette.primary.opacity(0.34), radius: 18)
            }
            .buttonStyle(.plain)
            .position(
              x: proxy.size.width * targetX,
              y: proxy.size.height * targetY
            )
            .accessibilityLabel("Reaction target")
          } else {
            VStack(spacing: 12) {
              if phase == .intro {
                Text("4 rounds")
                  .font(.system(.title, design: .rounded, weight: .semibold))
                Text("Keep your thumb ready")
                  .font(.subheadline)
                  .foregroundStyle(Palette.textSecondary)
              } else if phase == .waiting {
                Circle()
                  .fill(Palette.secondary.opacity(0.25))
                  .frame(width: 12, height: 12)
                Text("Wait…")
                  .font(.subheadline)
                  .foregroundStyle(Palette.textSecondary)
              } else {
                Image(systemName: "checkmark")
                  .font(.title2.weight(.bold))
                  .foregroundStyle(Palette.primary)
              }
            }
          }
        }
        .contentShape(Rectangle())
        .onTapGesture {
          if phase == .waiting {
            falseStarts += 1
            waitTask?.cancel()
            beginRound(afterFeedback: true)
          }
        }
      }
      .frame(height: 330)

      HStack {
        Label("\(reactions.count) of 4", systemImage: "scope")
        Spacer()
        if falseStarts > 0 {
          Text("\(falseStarts) early")
            .foregroundStyle(Palette.warning)
        }
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(Palette.textSecondary)

      if phase == .intro {
        Button("Begin reaction task") {
          beginRound()
        }
        .buttonStyle(PrimaryActionButtonStyle())
      }
    }
    .onDisappear { waitTask?.cancel() }
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
      targetX = Double.random(in: 0.23...0.77)
      targetY = Double.random(in: 0.24...0.76)
      targetAppearedAt = Date()
      phase = .target
    }
  }

  private func targetTapped() {
    guard !finished else { return }
    reactions.append(Date().timeIntervalSince(targetAppearedAt) * 1_000)
    phase = .feedback

    if reactions.count == 4 {
      finished = true
      let average = reactions.reduce(0, +) / Double(reactions.count)
      Task {
        try? await Task.sleep(for: .milliseconds(320))
        onComplete(average, falseStarts)
      }
    } else {
      beginRound(afterFeedback: true)
    }
  }
}

struct MotorTrackingTaskView: View {
  let onComplete: (Double) -> Void

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
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Palette.cardBackground)

          Canvas { context, _ in
            var path = Path()
            for x in stride(from: 28.0, through: max(size.width - 28, 28), by: 3) {
              let point = CGPoint(x: x, y: idealY(for: x, in: size))
              if x == 28 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(
              path,
              with: .color(Palette.secondary.opacity(0.42)),
              style: StrokeStyle(lineWidth: 18, lineCap: .round)
            )
            context.stroke(
              path,
              with: .color(Palette.primary.opacity(0.74)),
              style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 8])
            )
          }

          Circle()
            .fill(Palette.primary)
            .frame(width: 54, height: 54)
            .overlay { Circle().stroke(Palette.textPrimary.opacity(0.5), lineWidth: 2) }
            .shadow(color: Palette.primary.opacity(0.32), radius: 16)
            .position(displayPosition)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(Palette.secondary.opacity(0.2), lineWidth: 1)
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
                onComplete(error)
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
        .accessibilityAction(named: "Use prototype alternative") {
          guard !finished else { return }
          finished = true
          onComplete(0.22)
        }
      }
      .frame(height: 330)

      HStack(spacing: 9) {
        Image(systemName: "arrow.right")
          .foregroundStyle(Palette.primary)
        Text("If you lift early, the path resets. That is expected.")
          .font(.caption)
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
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .fill(Palette.cardBackground)

        if startedAt == nil {
          SignalHalo(size: 220, isActive: false)
        } else {
          TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt ?? timeline.date)
            ZStack {
              Circle()
                .stroke(Palette.primary.opacity(0.12), lineWidth: 2)
                .frame(width: 150 + sin(elapsed * 1.4) * 12)
              Circle()
                .fill(Palette.primary)
                .frame(width: 12, height: 12)
            }
          }
        }
      }
      .frame(height: 300)
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .stroke(Palette.secondary.opacity(0.2), lineWidth: 1)
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
        .font(.caption)
        .foregroundStyle(Palette.textSecondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
  }
}

struct GuidedGazeTaskView: View {
  @ObservedObject var service: FaceTrackingService
  let onComplete: (GazeCaptureSummary) -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var startedAt: Date?
  @State private var guideTask: Task<Void, Never>?
  @State private var finished = false

  var body: some View {
    FlowContainer(progress: 4) {
      ScreenHeader(
        eyebrow: "Guided gaze",
        title: "Follow with your eyes, not your head.",
        detail:
          "Keep facing forward while the signal moves side to side. This prototype records a head-relative gaze trace on supported iPhones."
      )

      GeometryReader { proxy in
        ZStack {
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Palette.cardBackground)

          Path { path in
            path.move(to: CGPoint(x: 36, y: proxy.size.height / 2))
            path.addLine(to: CGPoint(x: proxy.size.width - 36, y: proxy.size.height / 2))
          }
          .stroke(Palette.secondary.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 8]))

          if let startedAt {
            TimelineView(.animation) { timeline in
              let elapsed = timeline.date.timeIntervalSince(startedAt)
              let travel = (sin((elapsed / 4.0) * .pi * 2 - (.pi / 2)) + 1) / 2
              Circle()
                .fill(Palette.primary)
                .frame(width: 26, height: 26)
                .shadow(color: Palette.primary.opacity(0.5), radius: 18)
                .position(
                  x: 36 + (proxy.size.width - 72) * travel,
                  y: proxy.size.height / 2
                )
            }
          } else {
            SignalHalo(size: 190, isActive: false)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(Palette.secondary.opacity(0.2), lineWidth: 1)
        }
      }
      .frame(height: 300)

      HStack(spacing: 8) {
        Circle()
          .fill(statusColor)
          .frame(width: 8, height: 8)
        Text(service.status.label)
          .font(.caption.weight(.medium))
          .foregroundStyle(Palette.textSecondary)
        Spacer()
        if service.sampleCount > 0 {
          Text("\(service.sampleCount) samples")
            .font(.caption.monospacedDigit())
            .foregroundStyle(Palette.textSecondary)
        }
      }

      if reduceMotion {
        Button("Use reduced-motion prototype path") {
          finish(with: GazeCaptureSummary(smoothnessRisk: 0.18, qualityScore: 0.93, sampleCount: 0))
        }
        .buttonStyle(PrimaryActionButtonStyle())
        Text(
          "This accommodation uses sample data in the MVP and is never presented as a live measurement."
        )
        .font(.caption)
        .foregroundStyle(Palette.textSecondary)
      } else {
        Button(startedAt == nil ? "Begin 8-second trace" : "Keep following…") {
          start()
        }
        .buttonStyle(PrimaryActionButtonStyle())
        .disabled(startedAt != nil)
        .opacity(startedAt == nil ? 1 : 0.55)
      }
    }
    .onDisappear {
      guideTask?.cancel()
      if startedAt != nil, !finished { _ = service.stop() }
    }
  }

  private var statusColor: Color {
    switch service.status {
    case .tracking: Palette.primary
    case .limited: Palette.warning
    case .unsupported: Palette.item2
    case .idle: Palette.textSecondary
    }
  }

  private func start() {
    guard startedAt == nil else { return }
    service.start()
    startedAt = Date()
    guideTask = Task {
      try? await Task.sleep(for: .seconds(8))
      guard !Task.isCancelled else { return }
      finish(with: service.stop())
    }
  }

  private func finish(with summary: GazeCaptureSummary) {
    guard !finished else { return }
    finished = true
    onComplete(summary)
  }
}
