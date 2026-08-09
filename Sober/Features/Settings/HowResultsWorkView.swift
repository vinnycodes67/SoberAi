import SwiftUI

/// The three results, explained, with a labelled example of each.
///
/// Two audiences need this and neither can get it any other way.
///
/// A person deciding whether to trust the app wants to know what it can say
/// before they spend five sessions earning a comparison. And an App Reviewer
/// has no route to a result at all: a check needs five accepted sober sessions
/// first, which is not something anyone can produce on a review device. Without
/// this screen the reviewer's only options are to reject on "could not test the
/// core feature" or to guess.
///
/// The founder previews are not the answer to that. They are compiled out of
/// public builds deliberately, and they fabricate a ready baseline. These
/// examples are static text: nothing is measured, nothing is stored, and
/// readiness is untouched.
struct HowResultsWorkView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DSSpace.xl) {
          intro
          ForEach(Example.all) { example in
            card(for: example)
          }
          limits
        }
        .padding(DSSpace.margin)
      }
      .background(DSPalette.background.ignoresSafeArea())
      .navigationTitle("How results work")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private var intro: some View {
    VStack(alignment: .leading, spacing: DSSpace.sm) {
      Text("A check has three possible answers.")
        .font(DSFont.title)
        .dsTitleTracking()
        .foregroundStyle(DSPalette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
      Text(
        "Each one compares this check against your own earlier sober sessions. There is no fourth answer, and none of the three says you are safe to drive."
      )
      .font(DSFont.callout)
      .foregroundStyle(DSPalette.textSecondary)
      .dsReadingLine()
    }
  }

  private func card(for example: Example) -> some View {
    DSCard {
      VStack(alignment: .leading, spacing: DSSpace.sm) {
        // Labelled on every card, not once at the top of the screen. A
        // screenshot of one card has to carry its own disclaimer.
        DSBadge(text: "Example", tint: DSPalette.textMuted)

        Text(example.state.title)
          .font(DSFont.title)
          .dsTitleTracking()
          .foregroundStyle(example.needsAttention ? DSPalette.accent : DSPalette.textPrimary)
          .fixedSize(horizontal: false, vertical: true)

        Text(example.state.message)
          .font(DSFont.body)
          .foregroundStyle(DSPalette.textSecondary)
          .dsReadingLine()

        DSSeparator()

        Text(example.whenItHappens)
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
          .dsReadingLine()

        Text(example.whatToDo)
          .font(DSFont.footnoteStrong)
          .foregroundStyle(DSPalette.textSecondary)
          .dsReadingLine()
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Example result: \(example.state.title)")
  }

  private var limits: some View {
    DSSection("What no result can tell you") {
      DSCard {
        VStack(alignment: .leading, spacing: DSSpace.xs) {
          limit("Whether it is safe for you to drive.")
          limit("How much you have had, or your blood alcohol level.")
          limit("Whether you are impaired. Sober measures change, not cause.")
          limit(
            "Anything about anyone else. A result is not evidence, and nobody should ask you to produce one."
          )
        }
      }
    }
  }

  private func limit(_ text: String) -> some View {
    Text(text)
      .font(DSFont.footnote)
      .foregroundStyle(DSPalette.textSecondary)
      .dsReadingLine()
  }

  /// Static content. Deliberately not a `ScreeningOutcome`: building one here
  /// would mean running the scorer, and an example must never touch the thing
  /// that produces real results.
  private struct Example: Identifiable {
    let state: ScreeningResultState
    let whenItHappens: String
    let whatToDo: String

    var id: String { state.rawValue }

    var needsAttention: Bool { state == .signalsDetected }

    static let all: [Example] = [
      Example(
        state: .signalsDetected,
        whenItHappens:
          "Enough measures fell outside your usual range that the difference is unlikely to be noise.",
        whatToDo: "Take a ride or call someone. Both are one tap from the result."
      ),
      Example(
        state: .inconclusive,
        whenItHappens:
          "The capture was too poor to trust, a task could not be completed, or you said you had been drinking. Sober refuses to score rather than guess.",
        whatToDo: "Treat it as no information, not as a good sign."
      ),
      Example(
        state: .noSignalsDetected,
        whenItHappens:
          "Your measures were close to your usual range on this check.",
        whatToDo:
          "This is the absence of a signal, not evidence that you are fine. Plenty of impairment does not show up in two minutes."
      ),
    ]
  }
}
