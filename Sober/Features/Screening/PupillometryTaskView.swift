import SwiftUI
import UIKit

/// Drives the 3-trial pupillary light reflex protocol: dark-adapt, flash,
/// capture, repeat. Screen brightness itself is the light stimulus — the
/// only light source available for a self-administered front-facing test.
struct PupillometryTaskView: View {
  @ObservedObject var service: PupilCaptureService
  let onComplete: (PupillometrySample?) -> Void

  @State private var phase: Phase = .intro
  @State private var trialIndex = 0
  @State private var trials: [PupilLightReflexTrial] = []
  @State private var countdown = 0

  private static let brightnessLevels: [CGFloat] = [0.4, 0.7, 1.0]
  private static let darkAdaptSeconds = 20
  private static let captureSeconds = 10

  private enum Phase: Equatable {
    case intro
    case darkAdapting
    case flashing
    case transition
    case finishing
  }

  var body: some View {
    Group {
      if phase == .intro {
        FlowContainer(progress: 5) {
          introContent
        }
      } else {
        trialContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(phase == .flashing ? Color.white : Color.black)
      }
    }
    .onDisappear {
      UIScreen.main.brightness = 1.0
      service.stop()
    }
  }

  private var introContent: some View {
    VStack(alignment: .leading, spacing: Space.md) {
      ScreenHeader(
        eyebrow: "Guided light check",
        title: "Watch the screen brighten three times.",
        detail:
          "The screen dims, then flashes three times while the camera watches your pupil. Keep your eyes open and look at the dot each time."
      )

      SoberCard {
        HStack(alignment: .top, spacing: Space.sm) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(Palette.warning)
          Text(
            "This step briefly brightens the screen three times. Skip it if you have photosensitive epilepsy or a seizure disorder."
          )
          .font(SoberType.body)
          .fixedSize(horizontal: false, vertical: true)
        }
      }

      Button("Begin light check") {
        beginSession()
      }
      .buttonStyle(PrimaryActionButtonStyle())

      Button("Skip this step") {
        onComplete(nil)
      }
      .font(SoberType.body)
      .foregroundStyle(Palette.textSecondary)
      .frame(maxWidth: .infinity, alignment: .center)
    }
  }

  private var trialContent: some View {
    VStack(spacing: Space.lg) {
      Spacer()

      ZStack {
        if phase == .flashing {
          Circle()
            .fill(Color.black)
            .frame(width: 16, height: 16)
        }
      }
      .frame(height: 120)

      VStack(spacing: Space.xs) {
        Text("Trial \(min(trialIndex + 1, Self.brightnessLevels.count)) of \(Self.brightnessLevels.count)")
          .font(SoberType.footnoteStrong)
          .foregroundStyle(phase == .flashing ? .black.opacity(0.55) : Palette.textSecondary)
        Text(phaseLabel)
          .font(SoberType.footnoteStrong)
          .foregroundStyle(phase == .flashing ? .black : Palette.textPrimary)
          .multilineTextAlignment(.center)
        if phase == .darkAdapting {
          Text("\(countdown)s")
            .font(SoberType.figure(28))
            .foregroundStyle(Palette.textPrimary)
        }
      }
      .padding(.horizontal, Space.xl)

      Spacer()
    }
  }

  private var phaseLabel: String {
    switch phase {
    case .darkAdapting: "Let your eyes adjust to the dark"
    case .flashing: "Keep looking at the dot"
    case .transition: "Nice. One moment…"
    case .finishing: "Wrapping up"
    case .intro: ""
    }
  }

  private func beginSession() {
    service.start()
    service.beginSession()
    trialIndex = 0
    trials = []
    runTrial()
  }

  private func runTrial() {
    guard trialIndex < Self.brightnessLevels.count else {
      finishSession()
      return
    }

    phase = .darkAdapting
    UIScreen.main.brightness = 0.02
    service.beginTrial()
    countdown = Self.darkAdaptSeconds

    Task {
      while countdown > 0 {
        try? await Task.sleep(for: .seconds(1))
        countdown -= 1
      }
      guard phase == .darkAdapting else { return }
      flash()
    }
  }

  private func flash() {
    phase = .flashing
    UIScreen.main.brightness = Self.brightnessLevels[trialIndex]
    service.markFlashOnset()

    Task {
      try? await Task.sleep(for: .seconds(Self.captureSeconds))
      guard phase == .flashing else { return }
      completeTrial()
    }
  }

  private func completeTrial() {
    phase = .transition
    if let trial = service.endTrial() {
      trials.append(trial)
    }
    UIScreen.main.brightness = 0.5
    trialIndex += 1

    Task {
      try? await Task.sleep(for: .milliseconds(600))
      runTrial()
    }
  }

  private func finishSession() {
    phase = .finishing
    let quality = service.finishSession()
    service.stop()
    UIScreen.main.brightness = 1.0
    let sample = trials.isEmpty ? nil : PupillometrySample(trials: trials, qualityScore: quality)
    onComplete(sample)
  }
}
