import SwiftUI

// DesignKit screens
// =================
//
// Redesigned screens built entirely on DesignKit. They are additive: nothing
// here replaces `HomeView`, `ResultView`, or anything else that ships today.
// The existing app is untouched and still boots into `RootView` exactly as
// before.
//
// To try one, present it from anywhere:
//
//     .sheet(isPresented: $preview) { DSHomeScreen() }
//
// To adopt one, point `RootView` at it instead of the current screen and
// delete the old file once you are happy.
//
// These read real `AppModel` state, so they show real data rather than
// placeholders. Anything they cannot get from the model yet is noted inline.

/// Home, rebuilt on DesignKit.
///
/// Reads top to bottom as: where you stand, the thing to do, the way out if
/// you need it, what your normal looks like, and what happened lately. Every
/// block is either a fact about this person or an action they can take.
struct DSHomeScreen: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.openURL) private var openURL

  /// Provided by the host so the screen does not own navigation.
  var onStartCheck: () -> Void = {}
  var onOpenBaseline: () -> Void = {}
  var onOpenHistory: () -> Void = {}
  var onOpenCircle: () -> Void = {}

  private var checks: [ResearchSessionEnvelope] {
    model.researchSessions
      .filter { $0.context.sessionKind == .screeningCheck }
      .sorted { $0.startedAt > $1.startedAt }
  }

  private var lastCheck: ResearchSessionEnvelope? { checks.first }

  private var checksThisMonth: Int {
    let cutoff = Date().addingTimeInterval(-30 * 86_400)
    return checks.filter { $0.startedAt > cutoff }.count
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DSSpace.xl) {
        statusCard.dsAppear(0)
        startButton.dsAppear(1)
        if isCircleReady { getHome.dsAppear(2) }
        baselineStrip.dsAppear(3)
        if !checks.isEmpty { recent.dsAppear(4) }
      }
      .padding(.horizontal, DSSpace.margin)
      .padding(.top, DSSpace.xs)
      .padding(.bottom, DSSpace.tabBarClearance)
    }
    .scrollIndicators(.hidden)
    .dsPageBackground()
    .safeAreaInset(edge: .top) {
      HStack {
        Text("Sober")
          .font(DSFont.headline)
          .foregroundStyle(DSPalette.textPrimary)
        Spacer()
        if checksThisMonth > 0 {
          Text("\(checksThisMonth) this month")
            .font(DSFont.footnote)
            .foregroundStyle(DSPalette.textMuted)
        }
      }
      .padding(.horizontal, DSSpace.margin)
      .padding(.bottom, DSSpace.xs)
      .dsHeaderScrim()
    }
  }

  // MARK: - Status

  private var statusCard: some View {
    DSCard(highlighted: true) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: DSSpace.xs) {
          Circle().fill(statusTint).frame(width: 7, height: 7)
          Text(kicker)
            .font(DSFont.footnoteStrong)
            .foregroundStyle(statusTint)
        }
        Text(headline)
          .font(DSFont.hero)
          .dsHeroTracking()
          .foregroundStyle(DSPalette.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, DSSpace.xs)
        Text(supporting)
          .font(DSFont.callout)
          .foregroundStyle(DSPalette.textSecondary)
          .dsReadingLine()
          .padding(.top, DSSpace.sm)

        if !model.baselineReady {
          VStack(alignment: .leading, spacing: DSSpace.xs) {
            DSStepMeter(filled: model.baselineSessions, total: 5)
            Text("\(model.baselineSessions) of 5 baseline sessions recorded")
              .font(DSFont.footnote)
              .foregroundStyle(DSPalette.textMuted)
          }
          .padding(.top, DSSpace.lg)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(model.baselineSessions) of 5 baseline sessions recorded")
        }
      }
    }
  }

  private var isCircleReady: Bool {
    model.safetyPlan.isActive && model.safetyPlan.hasContact
  }

  private var kicker: String {
    if !model.baselineReady { return "Getting set up" }
    if !isCircleReady { return "One thing left" }
    return lastCheck == nil ? "Ready" : "Last check"
  }

  private var statusTint: Color {
    guard model.baselineReady, isCircleReady else { return DSPalette.accent }
    return lastCheckState == .signalsDetected ? DSPalette.accent : DSPalette.textMuted
  }

  /// The stored result state, if the engine's outcome is being persisted with
  /// the session. See the note on `recent` below.
  private var lastCheckState: ScreeningResultState? { nil }

  private var headline: String {
    if !model.baselineReady { return "Learn your steady." }
    if !isCircleReady { return "Name someone to call." }
    guard let lastCheck else { return "Ready when you are." }
    return "Checked \(relativeTime(lastCheck.startedAt))."
  }

  private var supporting: String {
    if !model.baselineReady {
      return
        "A few short sessions while you're sober teach the app what your normal looks like. Every check after that is compared against it."
    }
    if !isCircleReady {
      return "A check only starts once there's somewhere to turn if it comes back concerning."
    }
    return "A check takes about two minutes and stays on this iPhone."
  }

  private func relativeTime(_ date: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 3600 { return "\(max(seconds / 60, 1)) minutes ago" }
    if seconds < 86_400 {
      let hours = seconds / 3600
      return hours == 1 ? "an hour ago" : "\(hours) hours ago"
    }
    let days = seconds / 86_400
    return days == 1 ? "yesterday" : "\(days) days ago"
  }

  // MARK: - Action

  private var startButton: some View {
    Button(actionTitle) {
      if model.baselineReady && !isCircleReady {
        onOpenCircle()
      } else {
        onStartCheck()
      }
    }
    .buttonStyle(DSPrimaryButtonStyle())
  }

  private var actionTitle: String {
    if !model.baselineReady { return "Record a baseline session" }
    if !isCircleReady { return "Set up Safety Circle" }
    return "Start check"
  }

  // MARK: - Get home
  //
  // The safety net, reachable without running a check first. Someone who has
  // already decided not to drive should not have to take a test to get a car.

  private var getHome: some View {
    DSSection("Get home") {
      HStack(spacing: DSSpace.sm) {
        quickAction(
          title: model.safetyPlan.contactName,
          subtitle: "Call",
          symbol: "phone.fill",
          url: URL(string: "tel://\(model.safetyPlan.normalizedContactPhone)"))
        quickAction(
          title: model.safetyPlan.preferredRide,
          subtitle: "Ride",
          symbol: "car.fill",
          url: rideURL)
      }
    }
  }

  private var rideURL: URL? {
    model.safetyPlan.preferredRide.lowercased().contains("lyft")
      ? URL(string: "https://www.lyft.com/rider")
      : URL(string: "https://m.uber.com/ul/")
  }

  private func quickAction(
    title: String, subtitle: String, symbol: String, url: URL?
  ) -> some View {
    Button {
      if let url { openURL(url) }
    } label: {
      VStack(alignment: .leading, spacing: DSSpace.sm) {
        Image(systemName: symbol)
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(DSPalette.textSecondary)
        VStack(alignment: .leading, spacing: 1) {
          Text(subtitle)
            .font(DSFont.footnote)
            .foregroundStyle(DSPalette.textMuted)
          Text(title)
            .font(DSFont.headline)
            .foregroundStyle(DSPalette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(DSSpace.md)
      .background(
        RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
          .fill(DSPalette.surface))
    }
    .buttonStyle(DSPressStyle())
    .accessibilityElement(children: .combine)
  }

  // MARK: - Baseline

  private var baselineStrip: some View {
    DSSection("Your steady", action: ("Details", onOpenBaseline)) {
      Button(action: onOpenBaseline) {
        VStack(alignment: .leading, spacing: DSSpace.sm) {
          HStack(spacing: 5) {
            ForEach(DSPortraitTrack.all) { _ in
              Capsule()
                .fill(
                  model.baselineReady
                    ? DSPalette.withinRange.opacity(0.55) : DSPalette.surfaceRaised
                )
                .frame(height: 6)
            }
          }
          Text(
            model.baselineReady
              ? "Five measures, each with your own usual range."
              : "Five sober sessions build your range. Tap to see how it works."
          )
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
          .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpace.md)
        .background(
          RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
            .fill(DSPalette.surface))
      }
      .buttonStyle(DSPressStyle())
    }
  }

  // MARK: - Recent
  //
  // Sessions are listed by date and capture quality. To show the *result*
  // here, `ScreeningResultState` needs persisting alongside the session, which
  // it is not today: the outcome is computed, shown, and discarded. See the
  // README's note on `signalRisks` for the same reason.

  private var recent: some View {
    DSSection("Recent", action: ("All", onOpenHistory)) {
      DSRows {
        ForEach(Array(checks.prefix(3).enumerated()), id: \.element.id) { index, session in
          if index > 0 { DSSeparator() }
          HStack(spacing: DSSpace.sm) {
            Circle()
              .fill(
                session.metrics.qualityScore >= 0.72
                  ? DSPalette.withinRange : DSPalette.unmeasured
              )
              .frame(width: 7, height: 7)
            Text("Check")
              .font(DSFont.body)
              .foregroundStyle(DSPalette.textPrimary)
            Spacer(minLength: DSSpace.xs)
            Text(shortTime(session.startedAt))
              .font(DSFont.footnote)
              .foregroundStyle(DSPalette.textMuted)
          }
          .frame(minHeight: DSHit.minimum)
          .padding(.vertical, DSSpace.xs)
          .accessibilityElement(children: .combine)
        }
      }
    }
  }

  private func shortTime(_ date: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 86_400 { return date.formatted(date: .omitted, time: .shortened) }
    if seconds < 604_800 { return date.formatted(.dateTime.weekday(.abbreviated)) }
    return date.formatted(.dateTime.month(.abbreviated).day())
  }
}
