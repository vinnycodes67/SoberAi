import SwiftUI

struct OcularTaskView: View {
  @ObservedObject var service: FaceTrackingService
  let onComplete: (GazeCaptureSummary) -> Void
  /// Sends the person back to camera setup after a sustained capture failure.
  var onRetryCalibration: (() -> Void)?
  var onEndCheck: (() -> Void)?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var startedAt: Date?
  @State private var protocolTask: Task<Void, Never>?
  @State private var recoveryTask: Task<Void, Never>?
  @State private var finished = false
  @State private var needsRecovery = false

  var body: some View {
    ZStack {
      capture
      if needsRecovery {
        CaptureRecoveryOverlay(
          guidance: service.quality.primaryGuidance,
          onRetryCalibration: { onRetryCalibration?() },
          onEndCheck: { onEndCheck?() }
        )
        .transition(.opacity)
        .zIndex(2)
      }
    }
    // Escalation, not instant interruption: track how long quality has been
    // unusable and only stop the run once it stays that way.
    .onChange(of: service.quality.isUsable) { _, isUsable in
      if isUsable {
        recoveryTask?.cancel()
        recoveryTask = nil
      } else {
        scheduleCaptureRecovery()
      }
    }
  }

  private var capture: some View {
    FlowContainer(progress: 4) {
      ScreenHeader(
        eyebrow: "Visual motor",
        title: "Keep your head still. Follow the signal.",
        detail:
          "The signal will hold, glide horizontally and vertically, then jump. This is a guided eye-movement task, not an official clinical HGN test."
      )

      GeometryReader { proxy in
        ZStack {
          RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
            .fill(StimulusPalette.field)

          targetGuides(in: proxy.size)

          if let startedAt {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
              let elapsed = timeline.date.timeIntervalSince(startedAt)
              let target = OcularProtocolSchedule.target(at: elapsed, variant: activeVariant)
              Circle()
                .fill(StimulusPalette.targetPrimary)
                .frame(width: target.phase == .saccades ? 22 : 26, height: target.phase == .saccades ? 22 : 26)
                .overlay { Circle().stroke(.white.opacity(0.6), lineWidth: 2) }
                .shadow(color: StimulusPalette.targetPrimary.opacity(0.58), radius: 18)
                .position(
                  x: proxy.size.width * target.x,
                  y: proxy.size.height * target.y
                )
                .accessibilityLabel(target.phase.title)
            }
          } else {
            SignalHalo(size: 178, isActive: false)
          }

          VStack {
            HStack {
              Spacer()
              if service.isSupported {
                ZStack {
                  FaceCameraPreview(service: service)
                  Ellipse()
                    // Face lost is the state worth looking at; face present is
                    // the quiet default. Both previously mapped to colours that
                    // are now the same orange.
                    .stroke(
                      service.quality.facePresent ? DSPalette.textSecondary : DSPalette.accent,
                      lineWidth: 1.5)
                    .padding(DSSpace.xs)
                }
                .frame(width: 78, height: 102)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous))
                .overlay {
                  RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
                    .stroke(StimulusPalette.guide.opacity(0.35), lineWidth: 1)
                }
              }
            }
            Spacer()
          }
          .padding(DSSpace.sm)
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
            .stroke(StimulusPalette.guide.opacity(0.2), lineWidth: 1)
        }
      }
      .frame(height: 330)

      protocolProgress

      if reduceMotion {
        SoberCard {
          VStack(alignment: .leading, spacing: DSSpace.xs) {
            Label("Reduced Motion is enabled", systemImage: "figure.walk.motion")
              .font(DSFont.headline)
            Text("This variant uses a static hold and jump targets only. It still records a live visual sample when the camera is usable.")
              .font(DSFont.footnote)
              .foregroundStyle(Palette.textSecondary)
          }
        }

        Button("Begin reduced-motion eye task") {
          start()
        }
        .buttonStyle(PrimaryActionButtonStyle())
        .disabled(startedAt != nil || !canCapture)
        .opacity(startedAt == nil && canCapture ? 1 : 0.55)

        if !canCapture {
          Button("Continue with inconclusive capture") {
            finish(with: service.unusableSummary(
              issue: service.isSupported ? .permissionDenied : .unsupported
            ))
          }
          .buttonStyle(SecondaryActionButtonStyle(tint: Palette.warning))
        }

        Button("Skip eye task") {
          finish(with: service.unusableSummary(issue: .interrupted))
        }
        .buttonStyle(SecondaryActionButtonStyle(tint: Palette.warning))
      } else {
        Button(startedAt == nil ? "Begin 25-second eye task" : "Keep following…") {
          start()
        }
        .buttonStyle(PrimaryActionButtonStyle())
        .disabled(startedAt != nil || !canCapture)
        .opacity(startedAt == nil && canCapture ? 1 : 0.55)

        // Without a usable camera the 25-second protocol can only produce an
        // empty capture, so offer the inconclusive exit instead of the wait.
        if !canCapture {
          Button("Continue with inconclusive capture") {
            finish(with: service.unusableSummary(
              issue: service.isSupported ? .permissionDenied : .unsupported
            ))
          }
          .buttonStyle(SecondaryActionButtonStyle(tint: Palette.warning))
        }
      }
    }
    .onDisappear {
      protocolTask?.cancel()
      recoveryTask?.cancel()
      if startedAt != nil, !finished { service.pause() }
    }
  }

  @ViewBuilder
  private func targetGuides(in size: CGSize) -> some View {
    Path { path in
      path.move(to: CGPoint(x: size.width * 0.14, y: size.height * 0.5))
      path.addLine(to: CGPoint(x: size.width * 0.86, y: size.height * 0.5))
      path.move(to: CGPoint(x: size.width * 0.5, y: size.height * 0.18))
      path.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 0.82))
    }
    .stroke(StimulusPalette.guide.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 8]))
  }

  private var protocolProgress: some View {
    VStack(spacing: DSSpace.xs) {
      HStack(spacing: DSSpace.xs) {
        ForEach(progressPhases, id: \.self) { phase in
          Capsule()
            .fill(progressColor(for: phase))
            .frame(height: 5)
        }
      }
      HStack {
        Label(service.status.label, systemImage: "eye.fill")
        Spacer()
        if service.sampleCount > 0 {
          Text("\(service.sampleCount) samples")
            .monospacedDigit()
        }
      }
      .font(DSFont.footnoteStrong)
      .foregroundStyle(service.quality.facePresent ? Palette.textSecondary : Palette.warning)
    }
  }

  private var progressPhases: [OcularPhase] {
    switch activeVariant {
    case .full: return [.fixation, .horizontalPursuit, .verticalPursuit, .saccades]
    case .reducedMotion: return [.fixation, .saccades]
    }
  }

  private var activeVariant: OcularProtocolVariant { reduceMotion ? .reducedMotion : .full }

  private func progressColor(for phase: OcularPhase) -> Color {
    guard let startedAt else { return StimulusPalette.guide.opacity(0.22) }
    let current = OcularProtocolSchedule.target(at: Date().timeIntervalSince(startedAt), variant: activeVariant).phase
    let phases = progressPhases
    guard let currentIndex = phases.firstIndex(of: current),
      let phaseIndex = phases.firstIndex(of: phase)
    else { return StimulusPalette.guide.opacity(0.22) }
    return phaseIndex <= currentIndex ? StimulusPalette.targetPrimary : Palette.secondary.opacity(0.22)
  }

  private var canCapture: Bool {
    service.isSupported && service.status != .permissionDenied
  }

  private func start() {
    guard startedAt == nil, canCapture else { return }
    startedAt = Date()
    service.startOcularProtocol(variant: activeVariant)
    if !service.quality.isUsable { scheduleCaptureRecovery() }
    protocolTask = Task {
      try? await Task.sleep(for: .seconds(OcularProtocolSchedule.totalDuration(for: activeVariant)))
      guard !Task.isCancelled else { return }
      finish(with: service.stopOcularProtocol())
    }
  }

  private func finish(with summary: GazeCaptureSummary) {
    guard !finished else { return }
    finished = true
    protocolTask?.cancel()
    recoveryTask?.cancel()
    onComplete(summary)
  }

  /// This task is independent of sample delivery. When a face disappears,
  /// sample count may stop changing entirely; waiting for another sample would
  /// therefore leave recovery stuck forever.
  private func scheduleCaptureRecovery() {
    guard startedAt != nil, !finished, !needsRecovery, recoveryTask == nil else { return }
    recoveryTask = Task {
      try? await Task.sleep(for: .seconds(CaptureRecoveryPolicy.sustainedLossSeconds))
      guard !Task.isCancelled, startedAt != nil, !finished, !service.quality.isUsable else {
        return
      }
      protocolTask?.cancel()
      service.pause()
      needsRecovery = true
      recoveryTask = nil
    }
  }
}

enum CaptureRecoveryPolicy {
  /// Short losses such as a blink or a hand crossing the camera are normal.
  static let sustainedLossSeconds: TimeInterval = 3
}
