import SwiftUI

/// Time remaining until a deadline, as a ring with the figure inside.
///
/// Used for the curfew countdown. The ring drains rather than fills: this
/// measures time being spent, not progress being earned, and a filling ring
/// reads as an achievement.
///
/// The ring turns to the accent only once `remaining` is inside
/// `attentionThreshold`, so the colour means "soon", not "running".
struct DSCountdownRing: View {
  /// 0 through 1, where 1 is the full window still ahead.
  let fraction: Double
  /// The large figure, e.g. "42 min".
  let figure: String
  /// The line under it, e.g. "Home by 11:00".
  let caption: String
  var attentionThreshold: Double = 0.25

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var clamped: Double { min(max(fraction, 0), 1) }
  private var needsAttention: Bool { clamped <= attentionThreshold }
  private var tint: Color { needsAttention ? DSPalette.accent : DSPalette.textMuted }

  var body: some View {
    ZStack {
      Circle()
        .stroke(DSPalette.separator, lineWidth: 3)
      Circle()
        .trim(from: 0, to: clamped)
        .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .animation(reduceMotion ? nil : DSMotion.standard, value: clamped)

      VStack(spacing: DSSpace.xxs) {
        Text(figure)
          .font(DSFont.title)
          .monospacedDigit()
          .dsTitleTracking()
          .foregroundStyle(DSPalette.textPrimary)
        Text(caption)
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
          .multilineTextAlignment(.center)
      }
      .padding(DSSpace.md)
    }
    .frame(maxWidth: .infinity)
    .aspectRatio(1, contentMode: .fit)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(figure) remaining. \(caption)")
  }
}
