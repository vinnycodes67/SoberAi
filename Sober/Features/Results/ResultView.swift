import SwiftUI
import UIKit

// There is intentionally no green, checkmark, "pass", "clear", or dismiss X.
// The screen's primary content is the safety message plus a route home.
// 0.5s: the result halo and a protected-parent alert card dominate the screen.
// User: someone who just received a concerning result and needs proof that help was contacted.
// Emotional intent: protected and accountable, never punished or surveilled.
struct ResultView: View {
  let outcome: ScreeningOutcome
  let safetyPlan: SafetyPlan
  let isSample: Bool
  let parentAlertState: ParentAlertDeliveryState
  let onRetryParentAlert: () -> Void
  let onDone: () -> Void

  @Environment(\.openURL) private var openURL
  @State private var acknowledged = false
  @State private var secondsRemaining = 4

  var body: some View {
    ScrollView {
      VStack(spacing: 18) {
        if isSample {
          PrototypeBadge()
          Text("Sample result—no live measurement was used")
            .font(.caption)
            .foregroundStyle(Palette.textSecondary)
        }

        SignalHalo(tone: stateColor, size: 164, isActive: outcome.state != .noSignalsDetected)

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

        if outcome.state == .signalsDetected {
          parentAlertCard
        }
        signalBreakdown
        InterventionCard(safetyPlan: safetyPlan)
        acknowledgementCard

        Button("Return home", action: onDone)
          .buttonStyle(SecondaryActionButtonStyle(tint: Palette.textSecondary))
          .disabled(!canLeave)
          .opacity(canLeave ? 1 : 0.4)
          .accessibilityValue(returnHomeAccessibilityValue)
          .accessibilityHint(
            canLeave ? "Closes this result" : "Read and acknowledge the safety message first")
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
    case .noSignalsDetected: Palette.primary
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

  private var parentAlertCard: some View {
    SoberCard {
      HStack(alignment: .top, spacing: 14) {
        ZStack {
          Circle()
            .fill(parentAlertTint.opacity(0.14))
          parentAlertIcon
            .font(.title3.weight(.semibold))
            .foregroundStyle(parentAlertTint)
        }
        .frame(width: 48, height: 48)

        VStack(alignment: .leading, spacing: 5) {
          Text(parentAlertTitle)
            .font(.headline)
          Text(parentAlertMessage)
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

          if parentAlertState == .failed || parentAlertState == .notConfigured {
            Button("Try automatic alert again", action: onRetryParentAlert)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Palette.primary)
              .padding(.top, 3)
          }
        }

        Spacer(minLength: 0)
      }
    }
  }

  @ViewBuilder
  private var parentAlertIcon: some View {
    if parentAlertState == .sending {
      ProgressView()
        .tint(parentAlertTint)
    } else {
      Image(systemName: parentAlertSystemImage)
    }
  }

  private var parentAlertTint: Color {
    switch parentAlertState {
    case .failed, .notConfigured: Palette.warning
    default: Palette.primary
    }
  }

  private var parentAlertSystemImage: String {
    switch parentAlertState {
    case .sent: "paperplane.fill"
    case .failed, .notConfigured: "exclamationmark.message.fill"
    case .preview: "eye.fill"
    case .sending: "paperplane"
    case .notRequired: "message"
    }
  }

  private var parentAlertTitle: String {
    switch parentAlertState {
    case .sending: "Alerting \(safetyPlan.contactName)…"
    case .sent: "Alert accepted for sending"
    case .failed: "Automatic alert didn’t go through"
    case .notConfigured: "Automatic parent alert needs setup"
    case .preview: "Parent alert preview"
    case .notRequired: "Parent alert"
    }
  }

  private var parentAlertMessage: String {
    switch parentAlertState {
    case .sending:
      "Sober is sending the concerning result now. You don’t need to compose the message."
    case .sent:
      "The messaging service accepted the alert for \(safetyPlan.contactName). Carrier delivery is not yet confirmed. No camera data or scores were shared."
    case .failed:
      "Call or message them below now. Sober will not hide a delivery failure."
    case .notConfigured:
      "Add consent, a valid parent number, and the alert-service configuration. Call or message them below now."
    case .preview:
      "Sample only. A live concerning result would alert \(safetyPlan.contactName) immediately."
    case .notRequired:
      "No automatic alert was required for this result."
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
          Text("Your ride and direct contact options stay available while the alert is sent.")
            .font(.caption)
            .foregroundStyle(Palette.textSecondary)
        }

        Button {
          openRide()
        } label: {
          Label("Open \(safetyPlan.preferredRide)", systemImage: "car.side.fill")
        }
        .buttonStyle(PrimaryActionButtonStyle())

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
  }

  private func openRide() {
    let destination =
      safetyPlan.homeLabel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Home"
    let rawURL: String
    if safetyPlan.preferredRide == "Lyft" {
      rawURL = "https://www.lyft.com/rider"
    } else {
      rawURL =
        "https://m.uber.com/ul/?action=setPickup&pickup=my_location&dropoff[formatted_address]=\(destination)"
    }
    if let url = URL(string: rawURL) { openURL(url) }
  }

  private func callContact() {
    let digits = safetyPlan.contactPhone.filter(\.isNumber)
    if let url = URL(string: "tel:\(digits)") { openURL(url) }
  }

  private func messageContact() {
    let digits = safetyPlan.contactPhone.filter(\.isNumber)
    let message = "Can you help me get home? I’m choosing not to drive."
    let body = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message
    if let url = URL(string: "sms:\(digits)&body=\(body)") { openURL(url) }
  }
}

private struct CompactActionButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.subheadline.weight(.semibold))
      .lineLimit(1)
      .minimumScaleFactor(0.78)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 50)
      .foregroundStyle(Palette.primary)
      .background(
        Palette.primary.opacity(configuration.isPressed ? 0.16 : 0.08),
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(Palette.primary.opacity(0.34), lineWidth: 1)
      }
  }
}
