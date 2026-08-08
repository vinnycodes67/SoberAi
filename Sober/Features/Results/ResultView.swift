import SwiftUI
import UIKit

// There is intentionally no green, checkmark, "pass", "clear", or dismiss X.
// The screen's primary content is the safety message plus a route home.
// 0.5s: the result halo and Guardian request state dominate the screen.
// User: someone who just received a concerning result and needs a direct route to help.
// Emotional intent: protected and accountable, never punished or surveilled.
struct ResultView: View {
  let outcome: ScreeningOutcome
  let safetyPlan: SafetyPlan
  let isSample: Bool
  let guardianAlertState: GuardianAlertPresentationState
  let onRetryGuardianAlert: () -> Void
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

        if outcome.state == .signalsDetected {
          guardianAlertCard
            .soberEntrance(order: 2)
        }
        signalBreakdown
          .soberEntrance(order: outcome.state == .signalsDetected ? 3 : 2)
        InterventionCard(safetyPlan: safetyPlan)
          .soberEntrance(order: outcome.state == .signalsDetected ? 4 : 3)
        acknowledgementCard
          .soberEntrance(order: outcome.state == .signalsDetected ? 5 : 4)

        Button("Return home", action: onDone)
          .buttonStyle(SecondaryActionButtonStyle(tint: Palette.textSecondary))
          .disabled(!canLeave)
          .opacity(canLeave ? 1 : 0.4)
          .accessibilityValue(returnHomeAccessibilityValue)
          .accessibilityHint(
            canLeave ? "Closes this result" : "Read and acknowledge the safety message first")
          .soberEntrance(order: outcome.state == .signalsDetected ? 6 : 5)
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

  private var guardianAlertCard: some View {
    SoberCard {
      HStack(alignment: .top, spacing: 14) {
        ZStack {
          Circle()
            .fill(guardianAlertTint.opacity(0.14))
          guardianAlertIcon
            .font(.title3.weight(.semibold))
            .foregroundStyle(guardianAlertTint)
        }
        .frame(width: 48, height: 48)

        VStack(alignment: .leading, spacing: 5) {
          Text(guardianAlertTitle)
            .font(.headline)
          Text(guardianAlertMessage)
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

          // Only .actNow is a retriable transient failure. .notConfigured
          // means there's no Guardian relationship to send to at all —
          // beginConcerningGuardianAlert's own guard clause would just set
          // .notConfigured again, so a "retry" button there is a dead end;
          // the message above already tells them to use the manual
          // options below instead.
          if guardianAlertState == .actNow {
            Button("Try Guardian request again", action: onRetryGuardianAlert)
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
  private var guardianAlertIcon: some View {
    GuardianRequestGlyph(
      state: guardianAlertState,
      systemImage: guardianAlertSystemImage,
      tint: guardianAlertTint
    )
    .accessibilityHidden(true)
  }

  private var guardianAlertTint: Color {
    switch guardianAlertState {
    case .actNow, .notConfigured: Palette.warning
    case .guardianConfirmed: Palette.primary
    default: Palette.item0
    }
  }

  private var guardianAlertSystemImage: String {
    switch guardianAlertState {
    case .guardianConfirmed: "hand.raised.fill"
    case .actNow, .notConfigured: "exclamationmark.message.fill"
    case .preview: "eye.fill"
    case .requestingHelp: "paperplane"
    case .notRequired: "message"
    }
  }

  private var guardianAlertTitle: String {
    switch guardianAlertState {
    case .requestingHelp: "Requesting help"
    case .guardianConfirmed: "Your guardian is helping"
    case .actNow: "Contact someone now"
    case .notConfigured: "Guardian Mode isn’t connected"
    case .preview: "Guardian request preview"
    case .notRequired: "Guardian request"
    }
  }

  private var guardianAlertMessage: String {
    switch guardianAlertState {
    case .requestingHelp:
      "Your request is active. Keep the direct call, message, and ride options below available until a person confirms."
    case .guardianConfirmed:
      "A signed response from your guardian confirms they’re helping. No camera data or scores were shared."
    case .actNow:
      "Automatic status could not be confirmed. Call or message someone now and arrange a ride without driving."
    case .notConfigured:
      "No guardian relationship is active. Call or message someone below now."
    case .preview:
      "Sample only. A live concerning result would create a minimal in-app help request."
    case .notRequired:
      "No Guardian request was required for this result."
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

/// A restrained adaptation of the phase-driven alert motion in
/// Amos Gyamfi's open-swiftui-animations collection (Unlicense).
private struct GuardianRequestGlyph: View {
  let state: GuardianAlertPresentationState
  let systemImage: String
  let tint: Color

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var phases: [GuardianRequestPhase] {
    state == .requestingHelp && !reduceMotion ? GuardianRequestPhase.sending : [.settled]
  }

  var body: some View {
    PhaseAnimator(phases) { phase in
      Image(systemName: systemImage)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(tint)
        .offset(x: phase.offset)
        .scaleEffect(phase.scale)
        .opacity(phase.opacity)
        .contentTransition(.symbolEffect(.replace))
    } animation: { phase in
      phase.animation
    }
    .animation(reduceMotion ? nil : SoberMotion.progress, value: state)
  }
}

private enum GuardianRequestPhase {
  case settled
  case takeoff
  case inFlight

  static let sending: [GuardianRequestPhase] = [.takeoff, .inFlight]

  var offset: CGFloat {
    switch self {
    case .settled: 0
    case .takeoff: -1.5
    case .inFlight: 2.5
    }
  }

  var scale: CGFloat {
    switch self {
    case .settled, .inFlight: 1
    case .takeoff: 0.96
    }
  }

  var opacity: Double {
    switch self {
    case .settled, .inFlight: 1
    case .takeoff: 0.68
    }
  }

  var animation: Animation {
    .easeInOut(duration: 0.72)
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

        if safetyPlan.hasRideDestination {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text(safetyPlan.destinationDisplayName)
                .font(.subheadline.weight(.semibold))
              Text(safetyPlan.trimmedHomeAddress)
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
            }
          } icon: {
            Image(systemName: "mappin.and.ellipse")
              .foregroundStyle(Palette.primary)
          }
          .fixedSize(horizontal: false, vertical: true)
        }

        SoberGlassControlGroup(spacing: 10) {
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
  }

  private func openRide() {
    let destination = safetyPlan.trimmedHomeAddress.addingPercentEncoding(
      withAllowedCharacters: .urlQueryAllowed
    )
    let rawURL: String
    if safetyPlan.preferredRide == "Lyft" {
      rawURL = "https://www.lyft.com/rider"
    } else if let destination, !destination.isEmpty {
      rawURL =
        "https://m.uber.com/ul/?action=setPickup&pickup=my_location&dropoff[formatted_address]=\(destination)"
    } else {
      rawURL = "https://m.uber.com/ul/?action=setPickup&pickup=my_location"
    }
    if let url = URL(string: rawURL) { openURL(url) }
  }

  private func callContact() {
    let digits = safetyPlan.contactPhone.filter(\.isNumber)
    if let url = URL(string: "tel:\(digits)") { openURL(url) }
  }

  private func messageContact() {
    let digits = safetyPlan.contactPhone.filter(\.isNumber)
    let message = Self.messageBody(homeLabel: safetyPlan.destinationDisplayName)
    let body = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message
    if let url = URL(string: "sms:\(digits)?body=\(body)") { openURL(url) }
  }

  nonisolated static func messageBody(homeLabel: String) -> String {
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
