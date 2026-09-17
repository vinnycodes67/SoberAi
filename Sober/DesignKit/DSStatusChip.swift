import SwiftUI

/// A short state label: Home · Checked in 11:42 · Asked for a ride · No check-in yet.
///
/// Deliberately generic — it takes a label and a tone, not a Curfew type, so
/// DesignKit stays independent of the feature that happens to need it first.
///
/// There is no success tone and no green. On a guardian's screen a green chip
/// would be read as "they're fine", which is the one thing no state in this
/// product is allowed to claim. A settled state is quiet grey; only something
/// needing attention takes the accent.
struct DSStatusChip: View {
  enum Tone {
    /// Nothing to do. Quiet, never celebratory.
    case settled
    /// Needs a person to look. The only tone that spends the accent.
    case attention
  }

  let text: String
  var tone: Tone = .settled

  private var foreground: Color {
    switch tone {
    case .settled: DSPalette.textSecondary
    case .attention: DSPalette.accent
    }
  }

  private var background: Color {
    switch tone {
    case .settled: DSPalette.surface
    case .attention: DSPalette.accentWash
    }
  }

  var body: some View {
    Text(text)
      .font(DSFont.footnoteStrong)
      .monospacedDigit()
      .foregroundStyle(foreground)
      .padding(.horizontal, DSSpace.sm)
      .padding(.vertical, DSSpace.xxs)
      .background(Capsule(style: .continuous).fill(background))
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel(text)
  }
}
