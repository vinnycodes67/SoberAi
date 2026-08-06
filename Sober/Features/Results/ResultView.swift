import SwiftUI
import UIKit

// There is intentionally no green, checkmark, "pass", "clear", or dismiss X.
// The screen's primary content is the safety message plus a route home.
// 0.5s: the verdict in words, then the way home.
// User: someone who just received a concerning result and needs a fast way to get help.
// Emotional intent: protected and accountable, never punished or surveilled.
struct ResultView: View {
  let outcome: ScreeningOutcome
  let safetyPlan: SafetyPlan
  let isSample: Bool
  /// What the person declared about tonight, echoed read-only so a signal
  /// can be read in context. Never used in scoring — only shown.
  var context: ResearchPreferences? = nil
  let onDone: () -> Void

  @Environment(\.openURL) private var openURL
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var acknowledged = false
  @State private var secondsRemaining = 4

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.xl) {
        verdict
          .appear(0)
        InterventionCard(safetyPlan: safetyPlan)
          .appear(1)
        signalBreakdown
          .appear(2)
        contextSection
          .appear(3)
        acknowledgementCard
          .appear(4)

        Button("Return home", action: onDone)
          .buttonStyle(SecondaryActionButtonStyle(tint: Palette.textSecondary))
          .disabled(!canLeave)
          .opacity(canLeave ? 1 : 0.4)
          .accessibilityValue(returnHomeAccessibilityValue)
          .accessibilityHint(
            canLeave ? "Closes this result" : "Read and acknowledge the safety message first")
          .appear(5)
      }
      .padding(.horizontal, Space.margin)
      .padding(.top, Space.xxl)
      .padding(.bottom, Space.xl)
    }
    .pageBackground()
    .task {
      while secondsRemaining > 0 {
        try? await Task.sleep(for: .seconds(1))
        secondsRemaining -= 1
      }
      UIAccessibility.post(
        notification: .announcement,
        argument: "Safety hold complete. Acknowledge the message to enable Return home."
      )
    }
  }

  private var canLeave: Bool { acknowledged && secondsRemaining == 0 }

  private var returnHomeAccessibilityValue: String {
    if secondsRemaining > 0 {
      return "Available in \(secondsRemaining) second\(secondsRemaining == 1 ? "" : "s")"
    }
    return acknowledged ? "Available" : "Waiting for safety acknowledgement"
  }

  private var stateColor: Color {
    switch outcome.state {
    case .signalsDetected: Palette.error
    case .inconclusive: Palette.warning
    case .noSignalsDetected: Palette.textSecondary
    }
  }


  /// The verdict, stated in words. A colored rule carries the state rather
  /// than a badge or a glyph, so the sentence itself stays the loudest thing
  /// on the screen.
  private var verdict: some View {
    VStack(alignment: .leading, spacing: 0) {
      if isSample {
        PrototypeBadge()
          .padding(.bottom, Space.sm)
      }

      HStack(alignment: .top, spacing: Space.md) {
        Rectangle()
          .fill(stateColor)
          .frame(width: 3)
          .frame(maxHeight: .infinity)

        VStack(alignment: .leading, spacing: Space.sm) {
          Text(outcome.state.title)
            .font(SoberType.hero)
            .heroTracking()
            .foregroundStyle(Palette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
          Text(outcome.state.message)
            .font(SoberType.body)
            .foregroundStyle(Palette.textSecondary)
            .readingLine()
        }
      }
      .fixedSize(horizontal: false, vertical: true)

      movedCount
        .padding(.top, Space.xl)

      if isSample {
        Text("Sample result. No live measurement was used.")
          .font(SoberType.footnote)
          .foregroundStyle(Palette.textTertiary)
          .padding(.top, Space.md)
      }
    }
  }

  /// Self-reported context, shown read-only. This is why a signal might be
  /// present for reasons other than alcohol — the app states them rather
  /// than quietly folding them into a number.
  @ViewBuilder
  private var contextSection: some View {
    if let context, !contextChips(context).isEmpty {
      SoberSection("What you flagged tonight") {
        VStack(alignment: .leading, spacing: Space.xs) {
          FlowChips(items: contextChips(context))
          Text("Declared by you before this check. Not measured, and not used in scoring.")
            .font(SoberType.footnote)
            .foregroundStyle(Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func contextChips(_ context: ResearchPreferences) -> [ContextChipItem] {
    var items: [ContextChipItem] = []
    if context.sleepHours < 6 {
      items.append(.init(icon: "bed.double", label: "\(Int(context.sleepHours))h sleep"))
    }
    if context.caffeineWithinSixHours {
      items.append(.init(icon: "cup.and.saucer", label: "Caffeine"))
    }
    if context.medicationMayAffectPerformance {
      items.append(.init(icon: "pills", label: "Medication"))
    }
    if context.illnessOrInjuryMayAffectPerformance {
      items.append(.init(icon: "cross.case", label: "Illness or injury"))
    }
    if context.strenuousExerciseWithinTwoHours {
      items.append(.init(icon: "figure.run", label: "Exercise"))
    }
    switch context.visionCorrection {
    case .glasses: items.append(.init(icon: "eyeglasses", label: "Glasses"))
    case .contactLenses: items.append(.init(icon: "eye", label: "Contacts"))
    case .none, .unknown: break
    }
    return items
  }

  /// Each measure plotted against the person's own usual range. This is the
  /// product's central claim drawn rather than asserted: every row compares
  /// them only to themselves, and no row is a summary of the others.
  /// The evidence, drawn as the portrait rather than as a fresh chart. A
  /// person has been looking at this shape every time they opened the app, so
  /// the comparison needs no introduction at the worst possible moment.
  /// How many measures moved, set large.
  ///
  /// This is a count, not a score: it says how many of five readings fell
  /// outside this person's own range, and nothing about the person. The
  /// distinction matters, and it is why the denominator is always shown.
  private var movedCount: some View {
    let moved = outcome.details.filter(\.concern).count
    let total = outcome.details.count

    return HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
      Text("\(moved)")
        .font(SoberType.figureLarge)
        .heroTracking()
        .foregroundStyle(moved > 0 ? Palette.accent : Palette.textPrimary)
        .contentTransition(.numericText())
      VStack(alignment: .leading, spacing: 2) {
        Text("of \(total)")
          .font(SoberType.title)
          .foregroundStyle(Palette.textMuted)
        Text(moved == 1 ? "measure outside\nyour usual range" : "measures outside\nyour usual range")
          .font(SoberType.footnote)
          .foregroundStyle(Palette.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(moved) of \(total) measures outside your usual range")
  }

  private var signalBreakdown: some View {
    Section_("Against your baseline") {
      VStack(alignment: .leading, spacing: Space.md) {
        BaselinePortrait(
          tracks: BaselinePortrait.tracks(from: outcome.details),
          isEstablished: true,
          animatesOnAppear: false
        )
        PortraitLegend()
        Text("Prototype measures. They show what contributed, and are not clinical readings.")
          .font(SoberType.footnote)
          .foregroundStyle(Palette.textMuted)
          .readingLine()
      }
    }
  }

  private var acknowledgementCard: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: Space.sm) {
        Toggle(isOn: $acknowledged) {
          Text("I understand this result does not mean I’m sober or safe to drive.")
            .font(SoberType.body)
            .fixedSize(horizontal: false, vertical: true)
        }
        .tint(Palette.accent)

        if secondsRemaining > 0 {
          Text(
            "Safety message remains on screen for \(secondsRemaining) more second\(secondsRemaining == 1 ? "" : "s")."
          )
          .font(SoberType.footnote)
          .foregroundStyle(Palette.textSecondary)
          .contentTransition(.numericText())
          .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: secondsRemaining)
        }
      }
    }
  }

}

struct InterventionCard: View {
  let safetyPlan: SafetyPlan

  @Environment(\.openURL) private var openURL

  var body: some View {
    AccentCard {
      VStack(alignment: .leading, spacing: Space.sm) {
        VStack(alignment: .leading, spacing: Space.xxs) {
          Text("Get home without driving")
            .font(SoberType.headline)
            .foregroundStyle(Palette.textPrimary)
          Text("Nothing sends automatically. Every action here needs your tap.")
            .font(SoberType.footnote)
            .foregroundStyle(Palette.textSecondary)
            .readingLine()
        }

        Button {
          openRide()
        } label: {
          Label("Open \(safetyPlan.preferredRide)", systemImage: "car.fill")
        }
        .buttonStyle(OnAccentButtonStyle())

        if safetyPlan.hasContact {
          HStack(spacing: Space.xs) {
            Button {
              callContact()
            } label: {
              Label("Call \(safetyPlan.contactName)", systemImage: "phone.fill")
            }
            .buttonStyle(OnAccentButtonStyle(filled: false))

            Button {
              messageContact()
            } label: {
              Label("Message", systemImage: "message.fill")
            }
            .buttonStyle(OnAccentButtonStyle(filled: false))
          }
        } else {
          Text("Add a contact in your Safety Circle to call or message from here.")
            .font(SoberType.footnote)
            .foregroundStyle(Palette.textSecondary)
            .readingLine()
        }
      }
    }
  }

  private func openRide() {
    let destination =
      safetyPlan.homeLabel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Home"
    let rawURL: String
    if safetyPlan.preferredRide == "Lyft" {
      rawURL = "https://www.lyft.com/rider?id=lyft&destination%5Bnickname%5D=\(destination)"
    } else {
      rawURL =
        "https://m.uber.com/ul/?action=setPickup&pickup=my_location&dropoff%5Bformatted_address%5D=\(destination)"
    }
    if let url = URL(string: rawURL) { openURL(url) }
  }

  private func callContact() {
    let digits = safetyPlan.contactPhone.filter(\.isNumber)
    if let url = URL(string: "tel:\(digits)") { openURL(url) }
  }

  private func messageContact() {
    let digits = safetyPlan.contactPhone.filter(\.isNumber)
    let message = Self.messageBody(homeLabel: safetyPlan.homeLabel)
    let body = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message
    if let url = URL(string: "sms:\(digits)?body=\(body)") { openURL(url) }
  }

  /// Kept as a pure function so a regression test can assert this manual
  /// message — the only text this app ever puts in front of a contact —
  /// never leaks quality scores, camera details, or a BAC estimate.
  static func messageBody(homeLabel: String) -> String {
    "Can you help me get to \(homeLabel)? I’m choosing not to drive."
  }
}

/// Buttons that sit on the accent card. `filled` is the solid white primary;
/// unfilled is an outlined secondary that still clears contrast on purple.
/// Buttons inside the intervention block. The filled one is matte
/// turquoise; the others are plain panels. Nothing glows.
private struct OnAccentButtonStyle: ButtonStyle {
  var filled = true

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
    return configuration.label
      .font(SoberType.headline)
      .lineLimit(1)
      .minimumScaleFactor(0.78)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 50)
      .foregroundStyle(filled ? Palette.ink : Palette.textPrimary)
      .background(shape.fill(filled ? Palette.accent : Palette.panelHigh))
      .contentShape(shape)
      .opacity(configuration.isPressed ? 0.82 : 1)
      .animation(reduceMotion ? nil : SoberMotion.press, value: configuration.isPressed)
  }
}
