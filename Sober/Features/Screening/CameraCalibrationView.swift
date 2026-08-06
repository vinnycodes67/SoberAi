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

        HStack(spacing: Space.xs) {
          Circle()
            .fill(service.quality.isUsable ? Palette.textPrimary : Palette.accent)
            .frame(width: 8, height: 8)
          Text(service.status.label)
            .font(SoberType.footnoteStrong)
          Spacer()
          Text(service.quality.isUsable ? "READY" : "ADJUST")
            .font(SoberType.caption)
            .tracking(1)
        }
        .foregroundStyle(Palette.textPrimary)
        .padding(Space.sm)
        .soberGlassCapsule(
          tint: service.quality.isUsable ? Palette.textPrimary : Palette.accent
        )
        .padding(Space.sm)
      }
      .frame(height: 360)
      .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
          .stroke(
            service.quality.isUsable ? Palette.textMuted : Palette.line,
            lineWidth: service.quality.isUsable ? 2 : 1
          )
      }
      .animation(reduceMotion ? nil : SoberMotion.progress, value: service.quality.isUsable)

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.xs) {
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
          .font(SoberType.footnoteStrong)
          .foregroundStyle(Palette.warning)
          .fixedSize(horizontal: false, vertical: true)
      }

      Button(buttonTitle) {
        service.pause()
        onContinue()
      }
      .buttonStyle(
        PrimaryActionButtonStyle(tint: Palette.accent)
      )
      .disabled(isBlocked)
      .opacity(isBlocked ? 0.42 : 1)

      if isPermissionDenied, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
        Link("Open Settings to allow camera access", destination: settingsURL)
          .font(SoberType.body)
          .foregroundStyle(Palette.accent)
          .frame(maxWidth: .infinity, alignment: .center)
      }

      if canOnlyContinueWithLimitedCapture {
        Text("A live check can continue, but its result will be inconclusive without usable camera capture.")
          .font(SoberType.footnote)
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

  private var unsupportedPreview: some View {
    ZStack {
      Palette.raised
      VStack(spacing: Space.md) {
        Image(systemName: "camera.fill")
          .font(.system(size: 42))
          .foregroundStyle(Palette.textSecondary)
        Text("Live face preview unavailable")
          .font(SoberType.body)
        Text("Founder result previews remain available from the home screen.")
          .font(SoberType.footnote)
          .foregroundStyle(Palette.textSecondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, Space.xl)
      }
    }
  }

  private func qualityTile(_ title: String, icon: String, ready: Bool) -> some View {
    HStack(spacing: Space.xs) {
      Image(systemName: ready ? "checkmark.circle.fill" : icon)
        .foregroundStyle(ready ? Palette.textPrimary : Palette.textMuted)
        .frame(width: 20)
        .contentTransition(.symbolEffect(.replace))
      Text(title)
        .font(SoberType.footnoteStrong)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Space.sm)
    .frame(minHeight: 44)
    .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
        .stroke(Palette.separator, lineWidth: 1)
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: ready)
  }
}
