import SwiftUI

// There is intentionally no green, checkmark, "pass", "clear", or dismiss X.
// The screen's primary content is the safety message plus a route home.
struct ResultView: View {
  let outcome: ScreeningOutcome
  let safetyPlan: SafetyPlan
  let isSample: Bool
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

        signalBreakdown
        interventionCard
        acknowledgementCard

        Button("Return home", action: onDone)
          .buttonStyle(SecondaryActionButtonStyle(tint: Palette.textSecondary))
          .disabled(!canLeave)
          .opacity(canLeave ? 1 : 0.4)
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
    }
  }

  private var canLeave: Bool { acknowledged && secondsRemaining == 0 }

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

  private var interventionCard: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: 13) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Get home without driving")
            .font(.title3.weight(.semibold))
          Text("Your Night Out plan is ready. Taking action does not share this result.")
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
