import SwiftUI

/// Live recovery when capture quality collapses during the gaze task.
///
/// The gaze protocol runs on a fixed schedule. If the face is lost, the light
/// drops, or the person moves out of range partway through, the remaining
/// samples are not a worse reading — they are not a reading. Letting the timer
/// run out and reporting an inconclusive result two minutes later wastes the
/// person's time on a problem that was visible and fixable the moment it
/// started.
///
/// It escalates rather than interrupting instantly: brief losses are normal —
/// a blink, a hand passing the camera — and a modal that appears on every one
/// would be worse than the problem. Only a sustained loss stops the capture.
///
/// The instruction is the specific one the tracker produced, not a generic
/// "improve conditions". "Move somewhere brighter" is actionable at 1am on a
/// pavement; "capture quality too low" is not.
struct CaptureRecoveryOverlay: View {
  let guidance: String
  let onRetryCalibration: () -> Void
  let onEndCheck: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: DSSpace.lg) {
      Spacer(minLength: 0)

      VStack(alignment: .leading, spacing: DSSpace.sm) {
        DSEyebrow("Capture stopped")
        Text("Sober lost your face.")
          .font(DSFont.hero)
          .dsHeroTracking()
          .foregroundStyle(DSPalette.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
        Text(guidance)
          .font(DSFont.callout)
          .foregroundStyle(DSPalette.textSecondary)
          .dsReadingLine()
      }

      DSCard {
        Text(
          "The gaze step was stopped rather than finished on bad data. Nothing from it was saved."
        )
        .font(DSFont.footnote)
        .foregroundStyle(DSPalette.textMuted)
        .dsReadingLine()
      }

      Spacer(minLength: 0)

      VStack(spacing: DSSpace.sm) {
        Button("Set the camera up again", action: onRetryCalibration)
          .buttonStyle(DSPrimaryButtonStyle())
        Button("End check", action: onEndCheck)
          .buttonStyle(DSSecondaryButtonStyle())
      }
    }
    .padding(.horizontal, DSSpace.margin)
    .padding(.vertical, DSSpace.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(DSPalette.background.ignoresSafeArea())
  }
}
