import SwiftUI

/// The result, rebuilt on DesignKit.
///
/// Ordering is the whole design here: **what happened, what to do, then why.**
/// The way home sits above the evidence, because someone who has just read
/// "don't drive" needs an exit before they need data.
///
/// Additive: this does not replace `ResultView`. It takes the same
/// `ScreeningOutcome` and `SafetyPlan`, so it can be swapped in behind a flag
/// and compared side by side.
struct DSResultScreen: View {
  let outcome: ScreeningOutcome
  let safetyPlan: SafetyPlan
  var isSample: Bool = false

  /// Per-measure positions, if the engine's risks are being surfaced. When
  /// nil the portrait is omitted rather than drawn with invented values.
  var signalRisks: [String: Double]?

  var onOpenRide: () -> Void = {}
  var onCallContact: () -> Void = {}
  var onMessageContact: () -> Void = {}

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DSSpace.xl) {
        verdict.dsAppear(0)
        movedCount.dsAppear(1)
        getHome.dsAppear(2)
        if signalRisks != nil { evidence.dsAppear(3) }
        limits.dsAppear(4)
      }
      .padding(.horizontal, DSSpace.margin)
      .padding(.top, DSSpace.xxl)
      .padding(.bottom, DSSpace.xl)
    }
    .scrollIndicators(.hidden)
    .dsPageBackground()
  }

  // MARK: - Verdict
  //
  // A coloured rule carries the state rather than a badge or a glyph, so the
  // sentence itself stays the loudest thing on the screen.

  private var verdict: some View {
    VStack(alignment: .leading, spacing: 0) {
      if isSample {
        DSBadge(text: "Sample result", tint: DSPalette.unmeasured)
          .padding(.bottom, DSSpace.md)
      }
      HStack(alignment: .top, spacing: DSSpace.md) {
        Rectangle()
          .fill(stateTint)
          .frame(width: 3)
          .frame(maxHeight: .infinity)
        VStack(alignment: .leading, spacing: DSSpace.sm) {
          Text(outcome.state.title)
            .font(DSFont.hero)
            .dsHeroTracking()
            .foregroundStyle(DSPalette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
          Text(outcome.state.message)
            .font(DSFont.body)
            .foregroundStyle(DSPalette.textSecondary)
            .dsReadingLine()
        }
      }
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Orange marks concern. "No signals" stays neutral grey: there is no
  /// success colour, because the app never signals that anyone is clear to
  /// drive.
  private var stateTint: Color {
    switch outcome.state {
    case .signalsDetected: DSPalette.accent
    case .inconclusive: DSPalette.unmeasured
    case .noSignalsDetected: DSPalette.withinRange
    }
  }

  // MARK: - The count
  //
  // A count, not a score. It says how many of five readings fell outside this
  // person's own range and nothing about the person, which is why the
  // denominator is always shown.

  private var movedCount: some View {
    let moved = outcome.details.filter(\.concern).count
    let total = outcome.details.count

    return HStack(alignment: .firstTextBaseline, spacing: DSSpace.xs) {
      Text("\(moved)")
        .font(DSFont.figureLarge)
        .dsHeroTracking()
        .foregroundStyle(moved > 0 ? DSPalette.accent : DSPalette.textPrimary)
      VStack(alignment: .leading, spacing: 2) {
        Text("of \(total)")
          .font(DSFont.title)
          .foregroundStyle(DSPalette.textMuted)
        Text(moved == 1 ? "measure outside\nyour usual range" : "measures outside\nyour usual range")
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(moved) of \(total) measures outside your usual range")
  }

  // MARK: - Way home
  //
  // Above the evidence on purpose.

  private var getHome: some View {
    VStack(alignment: .leading, spacing: DSSpace.sm) {
      Text("Get home without driving")
        .font(DSFont.headline)
        .foregroundStyle(DSPalette.textPrimary)
      Text("Nothing sends automatically. Every action here needs your tap.")
        .font(DSFont.footnote)
        .foregroundStyle(DSPalette.textSecondary)
        .dsReadingLine()

      Button("Open \(safetyPlan.preferredRide)", action: onOpenRide)
        .buttonStyle(DSPrimaryButtonStyle())
        .padding(.top, DSSpace.xs)

      if safetyPlan.hasContact {
        HStack(spacing: DSSpace.sm) {
          Button("Call \(safetyPlan.contactName)", action: onCallContact)
            .buttonStyle(DSSecondaryButtonStyle())
          Button("Message", action: onMessageContact)
            .buttonStyle(DSSecondaryButtonStyle())
        }
      } else {
        Text("Add a contact in your Safety Circle to call or message from here.")
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
          .dsReadingLine()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DSSpace.lg)
    .background(
      RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
        .fill(DSPalette.accentWash))
  }

  // MARK: - Evidence

  private var evidence: some View {
    DSSection("Against your baseline") {
      VStack(alignment: .leading, spacing: DSSpace.md) {
        DSBaselinePortrait(
          tracks: DSBaselinePortrait.tracks(fromRisks: signalRisks),
          isEstablished: true,
          animatesOnAppear: false)
        DSPortraitLegend()
      }
    }
  }

  private var limits: some View {
    Text("Prototype measures. They show what contributed, and are not clinical readings.")
      .font(DSFont.footnote)
      .foregroundStyle(DSPalette.textMuted)
      .dsReadingLine()
  }
}

#if DEBUG
#Preview("Signals detected") {
  DSResultScreen(
    outcome: ScreeningOutcome(
      state: .signalsDetected,
      qualityScore: 0.88,
      riskScore: 0.71,
      details: [
        SignalDetail(id: "reaction", label: "Reaction", value: "612 ms", concern: true),
        SignalDetail(id: "tracking", label: "Motor tracking", value: "81% steady", concern: false),
        SignalDetail(id: "timing", label: "Time estimate", value: "7% off", concern: false),
        SignalDetail(id: "gaze", label: "Guided gaze", value: "41% smooth", concern: true),
        SignalDetail(id: "pupil", label: "Light reflex", value: "28% reactive", concern: false),
      ]),
    safetyPlan: SafetyPlan(contactName: "Jordan", contactPhone: "4155550148"),
    signalRisks: [
      "reaction": 0.78, "tracking": 0.31, "timing": 0.18, "gaze": 0.88, "pupil": 0.35,
    ]
  )
}
#endif
