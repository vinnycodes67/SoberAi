import SwiftUI

/// Shown when a task was interrupted mid-measurement.
///
/// Every timed task measures against the wall clock: reaction latency is the
/// gap between the target appearing and the tap, and the timing and gaze tasks
/// run on elapsed time. If the app leaves the foreground in the middle of one —
/// a call, a notification pulled into, the screen locking — that dead time lands
/// inside the measurement.
///
/// The recorded number would then be the interruption, not the person. Scored
/// against their own baseline it reads as a large slowdown, which is the
/// product's worst failure: a false signal produced by a phone call.
///
/// So the reading is discarded rather than salvaged, and the person is told
/// plainly why. There is no "resume": a partially measured task cannot be
/// completed honestly from where it left off.
struct InterruptedTaskView: View {
  let taskName: String
  let onRestartTask: () -> Void
  let onEndCheck: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: DSSpace.lg) {
      Spacer(minLength: 0)

      VStack(alignment: .leading, spacing: DSSpace.sm) {
        DSEyebrow("Interrupted")
        Text("That task was interrupted.")
          .font(DSFont.hero)
          .dsHeroTracking()
          .foregroundStyle(DSPalette.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
        Text(
          "Sober left the screen partway through \(taskName), so that reading was thrown away. Timing measured across an interruption would look like a change in you rather than a pause in the app."
        )
        .font(DSFont.callout)
        .foregroundStyle(DSPalette.textSecondary)
        .dsReadingLine()
      }

      DSCard {
        Text("Nothing from that task was saved, and it will not count toward a result.")
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
          .dsReadingLine()
      }

      Spacer(minLength: 0)

      VStack(spacing: DSSpace.sm) {
        Button("Redo this task", action: onRestartTask)
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
