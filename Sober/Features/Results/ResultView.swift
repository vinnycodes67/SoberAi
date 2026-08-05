import SwiftUI
import UIKit

// There is intentionally no green, checkmark, "pass", "clear", or dismiss X.
// The screen's primary content is the safety message plus a route home.
// 0.5s: the result halo and a ride/contact card dominate the screen.
// User: someone who just received a concerning result and needs a fast way to get help.
// Emotional intent: protected and accountable, never punished or surveilled.
struct ResultView: View {
  let outcome: ScreeningOutcome
  let safetyPlan: SafetyPlan
  let isSample: Bool
  let onDone: () -> Void

  @Environment(\.openURL) private var openURL
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var acknowledged = false
  @State private var secondsRemaining = 4

  var body: some View {
    ScrollView {
      VStack(spacing: 18) {
        if isSample {
          PrototypeBadge()
          Text("Sample result. No live measurement was used")
            .font(.caption)
            .foregroundStyle(Palette.textSecondary)
        }

        SignalHalo(tone: stateColor, size: 164, isActive: outcome.state != .noSignalsDetected)
          .soberEntrance(order: 0)

        VStack(spacing: 9) {
          Text(outcome.state.rawValue.replacingOccurrences(of: "_", with: " "))
            .font(.caption.weight(.bold))
            .tracking(1.3)
            .foregroundStyle(stateColor)
          Text(outcome.state.title)
            .font(.system(.largeTitle, design: .serif, weight: .semibold))
            .tracking(-1.0)
            .multilineTextAlignment(.center)
          Text(outcome.state.message)
            .font(.title3.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .soberEntrance(order: 1)

        signalBreakdown
          .soberEntrance(order: 2)
        InterventionCard(safetyPlan: safetyPlan)
          .soberEntrance(order: 3)
        acknowledgementCard
          .soberEntrance(order: 4)

        Button("Return home", action: onDone)
          .buttonStyle(SecondaryActionButtonStyle(tint: Palette.textSecondary))
          .disabled(!canLeave)
          .opacity(canLeave ? 1 : 0.4)
          .accessibilityValue(returnHomeAccessibilityValue)
          .accessibilityHint(
            canLeave ? "Closes this result" : "Read and acknowledge the safety message first")
          .soberEntrance(order: 5)
      }
      .padding(.horizontal, 18)
      .padding(.top, 16)
      .padding(.bottom, 30)
    }
    .soberBackground()
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

  private var signalBreakdown: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text("Signal summary")
            .font(.headline)
          Spacer()
          Text("QUALITY \(Int(outcome.qualityScore * 100))%")
            .font(.caption2.monospacedDigit().weight(.bold))
            .tracking(0.8)
            .foregroundStyle(outcome.qualityScore >= 0.72 ? Palette.primary : Palette.warning)
        }

        ForEach(outcome.details) { detail in
          HStack {
            Circle()
              .fill(detail.concern ? stateColor : Palette.secondary.opacity(0.55))
              .frame(width: 7, height: 7)
            Text(detail.label)
              .font(.subheadline)
            Spacer()
            Text(detail.value)
              .font(.subheadline.monospacedDigit().weight(.medium))
              .foregroundStyle(Palette.textSecondary)
          }
        }

        Text("Prototype scores show what contributed; they are not clinical measurements.")
          .font(.caption)
          .foregroundStyle(Palette.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var acknowledgementCard: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: 12) {
        Toggle(isOn: $acknowledged) {
          Text("I understand this result does not mean I’m sober or safe to drive.")
            .font(.subheadline.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
        }
        .tint(Palette.primary)

        if secondsRemaining > 0 {
          Text(
            "Safety message remains on screen for \(secondsRemaining) more second\(secondsRemaining == 1 ? "" : "s")."
          )
          .font(.caption.monospacedDigit())
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
    SoberCard {
      VStack(alignment: .leading, spacing: 13) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Get home without driving")
            .font(.title3.weight(.semibold))
          Text("Open a ride, or call or message your Safety Circle contact directly.")
            .font(.caption)
            .foregroundStyle(Palette.textSecondary)
        }

        SoberGlassControlGroup(spacing: 10) {
          Button {
            openRide()
          } label: {
            Label("Open \(safetyPlan.preferredRide)", systemImage: "car.side.fill")
          }
          .buttonStyle(PrimaryActionButtonStyle())

          if safetyPlan.hasContact {
            HStack(spacing: 10) {
              Button {
                callContact()
              } label: {
                Label("Call \(safetyPlan.contactName)", systemImage: "phone.fill")
              }
              .buttonStyle(CompactActionButtonStyle())

              Button {
                messageContact()
              } label: {
                Label("Message", systemImage: "message.fill")
              }
              .buttonStyle(CompactActionButtonStyle())
            }
          }
        }

        if !safetyPlan.hasContact {
          Text("Add a contact in your Safety Circle to call or message them from here.")
            .font(.caption)
            .foregroundStyle(Palette.textSecondary)
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

private struct CompactActionButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  @ViewBuilder
  func makeBody(configuration: Configuration) -> some View {
    if #available(iOS 26.0, *) {
      label(configuration)
        .glassEffect(
          .regular.interactive(),
          in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    } else {
      label(configuration)
        .background(
          reduceTransparency
            ? Palette.cardBackground
            : Palette.primary.opacity(configuration.isPressed ? 0.16 : 0.08),
          in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Palette.primary.opacity(0.34), lineWidth: 1)
        }
        .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.978)
        .animation(reduceMotion ? nil : SoberMotion.press, value: configuration.isPressed)
    }
  }

  private func label(_ configuration: Configuration) -> some View {
    configuration.label
      .font(.subheadline.weight(.semibold))
      .lineLimit(1)
      .minimumScaleFactor(0.78)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 50)
      .foregroundStyle(Palette.primary)
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}
