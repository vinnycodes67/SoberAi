import SwiftUI
import UIKit

struct CameraCalibrationView: View {
  @ObservedObject var service: FaceTrackingService
  let onContinue: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasHeldReady = false
  @State private var readyTask: Task<Void, Never>?

  var body: some View {
    FlowContainer(progress: 0) {
      ScreenHeader(
        eyebrow: "Camera calibration",
        title: "Put your face in the signal.",
        detail:
          "This live preview checks position, light, distance, and stability. Frames stay on this iPhone and are not saved by Sober."
      )

      ZStack(alignment: .bottom) {
        if service.isSupported {
          FaceCameraPreview(service: service)
          FaceGuideOverlay(isReady: service.quality.isUsable)
        } else {
          unsupportedPreview
        }

        HStack(spacing: 8) {
          Circle()
            .fill(service.quality.isUsable ? Palette.primary : Palette.warning)
            .frame(width: 8, height: 8)
          Text(service.status.label)
            .font(DSFont.footnoteStrong)
          Spacer()
          Text(service.quality.isUsable ? "READY" : "ADJUST")
            .font(DSFont.caption2.monospaced())
            .tracking(1)
        }
        .foregroundStyle(Palette.textPrimary)
        .padding(12)
        .soberGlassCapsule(
          tint: service.quality.isUsable ? Palette.primary : Palette.warning
        )
        .padding(14)
      }
      .frame(height: 360)
      .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
          .stroke(
            service.quality.isUsable ? Palette.primary.opacity(0.8) : Palette.secondary.opacity(0.28),
            lineWidth: service.quality.isUsable ? 2 : 1
          )
      }
      .animation(reduceMotion ? nil : SoberMotion.progress, value: service.quality.isUsable)

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        qualityTile("Face", icon: "faceid", ready: service.quality.facePresent)
        qualityTile("Centered", icon: "viewfinder", ready: service.quality.centered)
        qualityTile("Distance", icon: "arrow.up.left.and.arrow.down.right", ready: service.quality.distanceAcceptable)
        qualityTile("Lighting", icon: "sun.max.fill", ready: service.quality.lightingAcceptable)
        qualityTile("Still", icon: "gyroscope", ready: service.quality.headStable)
        qualityTile(
          "Signal",
          icon: "waveform.path.ecg",
          ready: service.quality.frameRate >= 20 && service.quality.sampleCount >= 20
        )
      }

      if !service.quality.isUsable {
        Label(service.quality.primaryGuidance, systemImage: "exclamationmark.triangle.fill")
          .font(DSFont.footnoteStrong)
          .foregroundStyle(Palette.warning)
          .fixedSize(horizontal: false, vertical: true)
      }

      Button(buttonTitle) {
        service.pause()
        onContinue()
      }
      .buttonStyle(
        PrimaryActionButtonStyle(tint: hasHeldReady ? Palette.primary : Palette.warning)
      )
      .disabled(isBlocked)
      .opacity(isBlocked ? 0.42 : 1)

      if isPermissionDenied, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
        Link("Open Settings to allow camera access", destination: settingsURL)
          .font(DSFont.subheadlineStrong)
          .foregroundStyle(Palette.primary)
          .frame(maxWidth: .infinity, alignment: .center)
      }

      if canOnlyContinueWithLimitedCapture {
        Text("A live check can continue, but its result will be inconclusive without usable camera capture.")
          .font(DSFont.footnote)
          .foregroundStyle(Palette.textSecondary)
          .multilineTextAlignment(.center)
      }
    }
    .task { service.startCalibration() }
    .onChange(of: service.quality.isUsable) { _, isUsable in
      readyTask?.cancel()
      guard isUsable else {
        hasHeldReady = false
        return
      }
      readyTask = Task {
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled, service.quality.isUsable else { return }
        hasHeldReady = true
      }
    }
    .onDisappear {
      readyTask?.cancel()
      service.pause()
    }
  }

  private var isPermissionDenied: Bool { service.status == .permissionDenied }

  /// Denied permission is as unrecoverable in-flow as an unsupported device.
  /// Without this the continue button stays disabled forever and the
  /// participant is stranded on this screen.
  private var canOnlyContinueWithLimitedCapture: Bool {
    !service.isSupported || isPermissionDenied
  }

  private var isBlocked: Bool {
    !canOnlyContinueWithLimitedCapture && !hasHeldReady
  }

  private var buttonTitle: String {
    if canOnlyContinueWithLimitedCapture { return "Continue with limited capture" }
    return hasHeldReady ? "Camera ready" : "Hold steady…"
  }

  /// Public builds have no founder previews, so pointing at them would send a
  /// user on unsupported hardware looking for a screen that isn't in their app.
  ///
  /// The branch is on the string rather than the `Text` so the trailing view
  /// modifiers stay attached to a concrete view.
  private var unsupportedDetail: String {
    #if INTERNAL_BUILD
    return "Founder result previews remain available from the home screen."
    #else
    return "This check needs a working front camera."
    #endif
  }

  private var unsupportedPreview: some View {
    ZStack {
      Palette.cardBackground
      VStack(spacing: 16) {
        Image(systemName: "camera.fill")
          .font(.system(size: 42))
          .foregroundStyle(Palette.textSecondary)
        Text("Live face preview unavailable")
          .font(DSFont.headline)
        Text(unsupportedDetail)
          .font(DSFont.footnote)
          .foregroundStyle(Palette.textSecondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 30)
      }
    }
  }

  private func qualityTile(_ title: String, icon: String, ready: Bool) -> some View {
    HStack(spacing: 9) {
      Image(systemName: ready ? "checkmark.circle.fill" : icon)
        .foregroundStyle(ready ? Palette.primary : Palette.textSecondary)
        .frame(width: 20)
        .contentTransition(.symbolEffect(.replace))
      Text(title)
        .font(DSFont.footnoteStrong)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 44)
    .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 13, style: .continuous)
        .stroke((ready ? Palette.primary : Palette.secondary).opacity(0.3), lineWidth: 1)
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: ready)
  }
}
