import SwiftUI

/// Public, read-only education for the three result states.
///
/// This view deliberately has no `AppModel`, `ScreeningEngine`, persistence,
/// camera, or task dependency. Opening it cannot create a session, change
/// baseline readiness, or present sample measurements as a real result.
struct HowResultsWorkView: View {
  @Environment(\.dismiss) private var dismiss

  private let examples: [ResultEducationExample] = [
    .init(
      state: .signalsDetected,
      nextStep: "Choose not to drive. Use a ride or contact someone you trust."
    ),
    .init(
      state: .inconclusive,
      nextStep: "The check could not support a conclusion. Treat uncertainty as a reason not to drive."
    ),
    .init(
      state: .noSignalsDetected,
      nextStep: "A phone check cannot establish sobriety or driving safety, even when it finds no change."
    ),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DSSpace.xl) {
          header

          ForEach(Array(examples.enumerated()), id: \.element.state.rawValue) { index, example in
            exampleCard(example, number: index + 1)
          }

          DSCard {
            VStack(alignment: .leading, spacing: DSSpace.xs) {
              Text("Examples only. No data is recorded.")
                .font(DSFont.headline)
                .foregroundStyle(DSPalette.textPrimary)
              Text(
                "Opening this page does not use the camera, run the scorer, add to History, or count toward your baseline."
              )
              .font(DSFont.footnote)
              .foregroundStyle(DSPalette.textSecondary)
              .dsReadingLine()
            }
          }
        }
        .padding(.horizontal, DSSpace.margin)
        .padding(.top, DSSpace.lg)
        .padding(.bottom, DSSpace.xxl)
      }
      .scrollIndicators(.hidden)
      .background(DSPalette.background.ignoresSafeArea())
      .navigationTitle("How results work")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .preferredColorScheme(.dark)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: DSSpace.sm) {
      DSEyebrow("Three possible results")
      Text("No result is a green light.")
        .font(DSFont.hero)
        .dsHeroTracking()
        .foregroundStyle(DSPalette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      Text(
        "Sober compares a live check with your measured personal baseline. It can point out changes or uncertainty, but it cannot tell whether you are sober or safe to drive."
      )
      .font(DSFont.callout)
      .foregroundStyle(DSPalette.textSecondary)
      .dsReadingLine()
    }
  }

  private func exampleCard(_ example: ResultEducationExample, number: Int) -> some View {
    DSCard {
      VStack(alignment: .leading, spacing: DSSpace.md) {
        DSBadge(text: "Example \(number) of \(examples.count)", tint: example.tint)

        HStack(alignment: .top, spacing: DSSpace.md) {
          Rectangle()
            .fill(example.tint)
            .frame(width: 3)

          VStack(alignment: .leading, spacing: DSSpace.sm) {
            Text(example.state.title)
              .font(DSFont.title)
              .dsTitleTracking()
              .foregroundStyle(DSPalette.textPrimary)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityAddTraits(.isHeader)
            Text(example.state.message)
              .font(DSFont.body)
              .foregroundStyle(DSPalette.textSecondary)
              .dsReadingLine()
          }
        }

        DSSeparator()

        Text(example.nextStep)
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textSecondary)
          .dsReadingLine()
      }
    }
  }
}

private struct ResultEducationExample {
  let state: ScreeningResultState
  let nextStep: String

  var tint: Color {
    state == .signalsDetected ? DSPalette.accent : DSPalette.textMuted
  }
}
