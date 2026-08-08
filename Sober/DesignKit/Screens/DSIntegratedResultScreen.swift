import SwiftUI
import UIKit

// The safety verdict and get-home actions dominate the page. Guardian delivery
// appears only in the internal build.
// User: someone who has just finished a check and needs a safe next action,
// not a score or a false clearance signal.
// Emotional intent: protected, informed, and able to get help immediately.
struct DSIntegratedResultScreen: View {
  let outcome: ScreeningOutcome
  let safetyPlan: SafetyPlan
  let isSample: Bool
  let guardianAlertState: GuardianAlertPresentationState
  let onRetryGuardianAlert: () -> Void
  let onDone: () -> Void

  @Environment(\.openURL) private var openURL
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var acknowledged = false
  @State private var secondsRemaining = 4

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DSSpace.xl) {
        verdict.dsAppear(0)

        if outcome.state == .signalsDetected {
          #if INTERNAL_BUILD
          guardianAlertCard.dsAppear(1)
          #endif
          movedCount.dsAppear(2)
        }

        getHome.dsAppear(outcome.state == .signalsDetected ? 3 : 1)
        measurements.dsAppear(outcome.state == .signalsDetected ? 4 : 2)
        acknowledgement.dsAppear(outcome.state == .signalsDetected ? 5 : 3)

        Button("Return home", action: onDone)
          .buttonStyle(DSSecondaryButtonStyle())
          .disabled(!canLeave)
          .opacity(canLeave ? 1 : 0.42)
          .accessibilityValue(returnHomeAccessibilityValue)
          .accessibilityHint(
            canLeave ? "Closes this result" : "Read and acknowledge the safety message first"
          )
          .dsAppear(outcome.state == .signalsDetected ? 6 : 4)
      }
      .padding(.horizontal, DSSpace.margin)
      .padding(.top, DSSpace.xl)
      .padding(.bottom, DSSpace.xl)
    }
    .scrollIndicators(.hidden)
    .dsPageBackground()
    .task {
      while secondsRemaining > 0 {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        secondsRemaining -= 1
      }
      UIAccessibility.post(
        notification: .announcement,
        argument: "Safety hold complete. Acknowledge the message to enable Return home."
      )
    }
  }

  private var verdict: some View {
    VStack(alignment: .leading, spacing: DSSpace.md) {
      if isSample {
        DSBadge(text: "Sample result", tint: DSPalette.textSecondary)
      }

      HStack(alignment: .top, spacing: DSSpace.md) {
        Rectangle()
          .fill(stateTint)
          .frame(width: 3)
        VStack(alignment: .leading, spacing: DSSpace.sm) {
          Text(outcome.state.title)
            .font(DSFont.hero)
            .dsHeroTracking()
            .foregroundStyle(DSPalette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
          Text(outcome.state.message)
            .font(DSFont.body)
            .foregroundStyle(DSPalette.textSecondary)
            .dsReadingLine()
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .fixedSize(horizontal: false, vertical: true)

      if isSample {
        Text(sampleDisclosure)
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
      }
    }
  }

  private var stateTint: Color {
    outcome.state == .signalsDetected ? DSPalette.accent : DSPalette.textMuted
  }

  private var sampleDisclosure: String {
    #if INTERNAL_BUILD
    "No live measurement or Guardian request was used."
    #else
    "No live measurement was used."
    #endif
  }

  private var movedCount: some View {
    let moved = measuredDetails.filter(\.concern).count
    let total = measuredDetails.count

    return Group {
      if total == 0 {
        VStack(alignment: .leading, spacing: DSSpace.xxs) {
          Text("No tasks measured")
            .font(DSFont.title)
            .foregroundStyle(DSPalette.textSecondary)
          Text("Your report determined this result.")
            .font(DSFont.footnote)
            .foregroundStyle(DSPalette.textMuted)
        }
        .accessibilityElement(children: .combine)
      } else {
        HStack(alignment: .firstTextBaseline, spacing: DSSpace.xs) {
          Text("\(moved)")
            .font(DSFont.figureLarge)
            .monospacedDigit()
            .dsHeroTracking()
            .foregroundStyle(DSPalette.accent)
          VStack(alignment: .leading, spacing: DSSpace.xxs) {
            Text("of \(total) measured")
              .font(DSFont.title)
              .foregroundStyle(DSPalette.textSecondary)
            Text(moved == 1 ? "reading outside your usual range" : "readings outside your usual range")
              .font(DSFont.footnote)
              .foregroundStyle(DSPalette.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(moved) of \(total) measured readings outside your usual range")
      }
    }
  }

  #if INTERNAL_BUILD
  private var guardianAlertCard: some View {
    VStack(alignment: .leading, spacing: DSSpace.md) {
      HStack(alignment: .top, spacing: DSSpace.sm) {
        Image(systemName: guardianAlertSystemImage)
          .font(.system(size: 21, weight: .semibold))
          .foregroundStyle(guardianNeedsAttention ? DSPalette.accent : DSPalette.textSecondary)
          .symbolEffect(
            .pulse,
            options: reduceMotion || guardianAlertState != .requestingHelp ? .nonRepeating : .repeating
          )
          .frame(width: 28)

        VStack(alignment: .leading, spacing: DSSpace.xxs) {
          Text(guardianAlertTitle)
            .font(DSFont.headline)
            .foregroundStyle(DSPalette.textPrimary)
          Text(guardianAlertMessage)
            .font(DSFont.footnote)
            .foregroundStyle(DSPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      if guardianAlertState == .actNow || guardianAlertState == .notConfigured {
        Button("Try Guardian request again", action: onRetryGuardianAlert)
          .buttonStyle(DSSecondaryButtonStyle())
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DSSpace.lg)
    .background(
      RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
        .fill(guardianNeedsAttention ? DSPalette.accentWash : DSPalette.surface)
    )
  }

  private var guardianNeedsAttention: Bool {
    switch guardianAlertState {
    case .actNow, .notConfigured, .requestingHelp: true
    case .guardianConfirmed, .preview, .notRequired: false
    }
  }

  private var guardianAlertSystemImage: String {
    switch guardianAlertState {
    case .guardianConfirmed: "hand.raised.fill"
    case .actNow, .notConfigured: "exclamationmark.message.fill"
    case .preview: "eye.fill"
    case .requestingHelp: "paperplane.fill"
    case .notRequired: "message"
    }
  }

  private var guardianAlertTitle: String {
    switch guardianAlertState {
    case .requestingHelp: "Requesting help"
    case .guardianConfirmed: "Your Guardian is helping"
    case .actNow: "Contact someone now"
    case .notConfigured: "Guardian Mode isn’t connected"
    case .preview: "Guardian request preview"
    case .notRequired: "Guardian request"
    }
  }

  private var guardianAlertMessage: String {
    switch guardianAlertState {
    case .requestingHelp:
      "A minimal in-app help request is active. Camera data, measurements, and scores stay on this iPhone."
    case .guardianConfirmed:
      "A signed response confirms your Guardian is helping. Camera data, measurements, and scores were not shared."
    case .actNow:
      "Automatic delivery could not be confirmed. Call or message someone now and arrange a ride without driving."
    case .notConfigured:
      "No Guardian relationship is active. Call or message someone below now."
    case .preview:
      "Sample only. A live concerning result would create a minimal in-app help request."
    case .notRequired:
      "No Guardian request was required for this result."
    }
  }
  #endif

  private var getHome: some View {
    DSSection("Get home without driving") {
      VStack(alignment: .leading, spacing: DSSpace.md) {
        Text(interventionDisclosure)
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textSecondary)
          .dsReadingLine()
          .fixedSize(horizontal: false, vertical: true)

        if safetyPlan.hasRideDestination {
          HStack(alignment: .top, spacing: DSSpace.sm) {
            Image(systemName: "mappin.and.ellipse")
              .foregroundStyle(DSPalette.accent)
            VStack(alignment: .leading, spacing: DSSpace.xxs) {
              Text(safetyPlan.destinationDisplayName)
                .font(DSFont.headline)
                .foregroundStyle(DSPalette.textPrimary)
              Text(safetyPlan.trimmedHomeAddress)
                .font(DSFont.footnote)
                .foregroundStyle(DSPalette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }

        Button("Open \(safetyPlan.preferredRide)", action: openRide)
          .buttonStyle(DSPrimaryButtonStyle())

        if safetyPlan.hasContact {
          Group {
            if dynamicTypeSize.isAccessibilitySize {
              VStack(spacing: DSSpace.sm) { contactActions }
            } else {
              HStack(spacing: DSSpace.sm) { contactActions }
            }
          }
        } else {
          Text("Add a trusted contact in your Safety Plan to call or message from here.")
            .font(DSFont.footnote)
            .foregroundStyle(DSPalette.textMuted)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(DSSpace.lg)
      .background(
        RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
          .fill(DSPalette.accentWash)
      )
    }
  }

  @ViewBuilder
  private var contactActions: some View {
    Button("Call \(safetyPlan.contactName)", action: callContact)
      .buttonStyle(DSSecondaryButtonStyle())
    Button("Message", action: messageContact)
      .buttonStyle(DSSecondaryButtonStyle())
  }

  private var interventionDisclosure: String {
    #if INTERNAL_BUILD
    if outcome.state == .signalsDetected && !isSample {
      return "The Guardian request starts automatically. Your ride, call, and message actions remain under your control."
    }
    #endif
    return "Ride, call, and message actions only happen when you tap them."
  }

  private var measurements: some View {
    DSSection("Measurements") {
      DSRows {
        DSValueRow(
          label: "Capture quality",
          value: "\(Int(outcome.qualityScore * 100))%"
        )
        .padding(.vertical, DSSpace.sm)

        ForEach(outcome.details) { detail in
          DSSeparator()
          measurementRow(detail)
        }
      }

      Text("Prototype measurements explain what contributed. They are not clinical readings.")
        .font(DSFont.footnote)
        .foregroundStyle(DSPalette.textMuted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, DSSpace.sm)
    }
  }

  private var acknowledgement: some View {
    DSCard {
      VStack(alignment: .leading, spacing: DSSpace.sm) {
        Toggle(isOn: $acknowledged) {
          Text("I understand this result does not mean I’m sober or safe to drive.")
            .font(DSFont.body)
            .foregroundStyle(DSPalette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .tint(DSPalette.accent)

        if secondsRemaining > 0 {
          Text("Safety message remains on screen for \(secondsRemaining) more second\(secondsRemaining == 1 ? "" : "s").")
            .font(DSFont.footnote)
            .monospacedDigit()
            .foregroundStyle(DSPalette.textMuted)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : DSMotion.standard, value: secondsRemaining)
        }
      }
    }
  }

  private var canLeave: Bool { acknowledged && secondsRemaining == 0 }

  private var returnHomeAccessibilityValue: String {
    if secondsRemaining > 0 {
      return "Available in \(secondsRemaining) second\(secondsRemaining == 1 ? "" : "s")"
    }
    return acknowledged ? "Available" : "Waiting for safety acknowledgement"
  }

  private var measuredDetails: [SignalDetail] {
    outcome.details.filter(\.wasMeasured)
  }

  private func readingStatus(_ detail: SignalDetail) -> String {
    if !detail.wasMeasured { return "Not measured" }
    return detail.concern ? "Outside usual range" : "Within usual range"
  }

  private func readingTint(_ detail: SignalDetail) -> Color {
    detail.wasMeasured && detail.concern ? DSPalette.accent : DSPalette.textMuted
  }

  private func measurementRow(_ detail: SignalDetail) -> some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: DSSpace.xxs) {
          measurementLabel(detail)
          measurementValue(detail)
        }
      } else {
        HStack(alignment: .firstTextBaseline, spacing: DSSpace.sm) {
          measurementLabel(detail)
          Spacer(minLength: DSSpace.sm)
          measurementValue(detail)
        }
      }
    }
    .frame(minHeight: DSHit.minimum)
    .padding(.vertical, DSSpace.sm)
    .accessibilityElement(children: .combine)
  }

  private func measurementLabel(_ detail: SignalDetail) -> some View {
    VStack(alignment: .leading, spacing: DSSpace.xxs) {
      Text(detail.label)
        .font(DSFont.body)
        .foregroundStyle(DSPalette.textPrimary)
      Text(readingStatus(detail))
        .font(DSFont.caption)
        .foregroundStyle(readingTint(detail))
    }
  }

  private func measurementValue(_ detail: SignalDetail) -> some View {
    Text(detail.value)
      .font(DSFont.subheadline)
      .monospacedDigit()
      .foregroundStyle(DSPalette.textSecondary)
      .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func openRide() {
    let destination = safetyPlan.trimmedHomeAddress.addingPercentEncoding(
      withAllowedCharacters: .urlQueryAllowed
    )
    let rawURL: String
    if safetyPlan.preferredRide == "Lyft" {
      rawURL = "https://www.lyft.com/rider"
    } else if let destination, !destination.isEmpty {
      rawURL = "https://m.uber.com/ul/?action=setPickup&pickup=my_location&dropoff[formatted_address]=\(destination)"
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
    let message = SafeRideMessage.body(destinationName: safetyPlan.destinationDisplayName)
    let body = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message
    if let url = URL(string: "sms:\(digits)?body=\(body)") { openURL(url) }
  }
}
