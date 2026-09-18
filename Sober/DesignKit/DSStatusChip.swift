import SwiftUI

/// A short state label: Home · Checked in 11:42 · Asked for a ride · No check-in yet
/// · Not added to your steady.
///
/// Deliberately generic — it takes a label and a tone, not a Curfew type, so
/// DesignKit stays independent of the feature that happens to need it first.
/// Anything that needs to mark a state on a row uses this rather than a
/// feature-local copy, so the two cannot drift apart.
///
/// There is no success tone and no green. On a guardian's screen a green chip
/// would be read as "they're fine", which is the one thing no state in this
/// product is allowed to claim. A settled state is quiet grey; only something
/// needing attention takes the accent.
struct DSStatusChip: View {
  enum Tone: CaseIterable {
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

#Preview("Every tone") {
  VStack(alignment: .leading, spacing: DSSpace.lg) {
    ForEach(DSStatusChip.Tone.allCases, id: \.self) { tone in
      DSStatusChip(text: "\(tone)".capitalized, tone: tone)
    }

    // In place, as History marks a baseline session that did not count.
    DSRows {
      DSRow("Baseline session", detail: "12 Sep, 22:14 · low capture", showsChevron: false) {
        DSStatusChip(text: "Not added to your steady")
      }
      DSSeparator()
      DSRow("Baseline session", detail: "11 Sep, 21:50 · strong capture", showsChevron: false)
    }
  }
  .padding(DSSpace.margin)
  .frame(maxHeight: .infinity, alignment: .top)
  .dsPageBackground()
}

#Preview("Every tone · AX5") {
  VStack(alignment: .leading, spacing: DSSpace.lg) {
    ForEach(DSStatusChip.Tone.allCases, id: \.self) { tone in
      DSStatusChip(text: "\(tone)".capitalized, tone: tone)
    }
    DSRow("Baseline session", detail: "12 Sep, 22:14 · low capture", showsChevron: false) {
      DSStatusChip(text: "Not added to your steady")
    }
  }
  .padding(DSSpace.margin)
  .frame(maxHeight: .infinity, alignment: .top)
  .dsPageBackground()
  .environment(\.dynamicTypeSize, .accessibility5)
}
