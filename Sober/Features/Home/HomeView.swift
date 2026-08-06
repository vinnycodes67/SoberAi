import SwiftUI

/// The app shell: four sections under a floating glass bar.
struct HomeView: View {
  @EnvironmentObject private var model: AppModel
  @State private var tab: SoberTab = .home

  var body: some View {
    ZStack(alignment: .bottom) {
      Group {
        switch tab {
        case .home:
          HomeDashboardView(selectTab: { tab = $0 })
        case .history:
          NavigationStack { HistoryView() }
        case .circle:
          NavigationStack { SafetyPlanView(plan: $model.safetyPlan, showsDoneButton: false) }
        case .settings:
          SettingsTabView()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      SoberTabBar(selection: $tab)
        .padding(.bottom, Space.xs)
    }
    .background(Palette.background.ignoresSafeArea())
  }
}

/// Home.
///
/// Reads top to bottom as: where you stand, the thing to do, the way out if
/// you need it, what your normal looks like, and what happened lately.
/// Everything on the screen is either a fact about this person or an action
/// they can take. Nothing is filler.
struct HomeDashboardView: View {
  var selectTab: (SoberTab) -> Void = { _ in }

  @EnvironmentObject private var model: AppModel
  @Environment(\.openURL) private var openURL
  @State private var launch: ScreeningLaunch?
  @State private var selectedSession: ResearchSessionEnvelope?
  @State private var showingBaseline = false

  private var checks: [ResearchSessionEnvelope] {
    model.researchSessions
      .filter { $0.context.sessionKind == .screeningCheck }
      .sorted { $0.startedAt > $1.startedAt }
  }

  private var lastCheck: ResearchSessionEnvelope? { checks.first }
  private var recentChecks: [ResearchSessionEnvelope] { Array(checks.prefix(3)) }

  /// Checks taken in the last 30 days. A count, never a trend.
  private var checksThisMonth: Int {
    let cutoff = Date().addingTimeInterval(-30 * 86_400)
    return checks.filter { $0.startedAt > cutoff }.count
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.xl) {
        statusCard.appear(0)
        startButton.appear(1)

        if isSafetyCircleReady {
          getHome.appear(2)
        }

        baselineStrip.appear(3)

        if !recentChecks.isEmpty {
          recent.appear(4)
        }
      }
      .padding(.horizontal, Space.margin)
      .padding(.top, Space.xs)
      // Matches the top inset plus the floating bar, so the page is evenly
      // framed rather than sitting high in the screen.
      .padding(.bottom, 116)
    }
    .scrollIndicators(.hidden)
    .pageBackground()
    .safeAreaInset(edge: .top) {
      HStack {
        Text("Sober")
          .font(SoberType.headline)
          .foregroundStyle(Palette.textPrimary)
        Spacer()
        if checksThisMonth > 0 {
          Text("\(checksThisMonth) this month")
            .font(SoberType.footnote)
            .foregroundStyle(Palette.textMuted)
        }
      }
      .padding(.horizontal, Space.margin)
      .padding(.bottom, Space.xs)
      .headerScrim()
    }
    .fullScreenCover(item: $launch) { configuration in
      ScreeningFlowView(configuration: configuration).environmentObject(model)
    }
    .sheet(item: $selectedSession) { session in
      PastResultView(session: session, safetyPlan: model.safetyPlan)
    }
    .sheet(isPresented: $showingBaseline) {
      BaselineDetailView().environmentObject(model)
    }
  }

  // MARK: - Status
  //
  // The one card that answers "where do I stand" without interpretation.

  private var statusCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: Space.xs) {
        Circle()
          .fill(statusTint)
          .frame(width: 7, height: 7)
        Text(kicker)
          .font(SoberType.footnoteStrong)
          .foregroundStyle(statusTint)
      }

      Text(headline)
        .font(SoberType.hero)
        .heroTracking()
        .foregroundStyle(Palette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, Space.xs)

      Text(supporting)
        .font(SoberType.callout)
        .foregroundStyle(Palette.textSecondary)
        .readingLine()
        .padding(.top, Space.sm)

      if !model.baselineReady {
        baselineProgress.padding(.top, Space.lg)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Space.lg)
    .background(
      RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
        .fill(Palette.surface)
    )
    .overlay(
      // The one specular edge in the app. It sits on the hero card only,
      // which is what keeps it reading as emphasis rather than texture.
      RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
        .strokeBorder(
          LinearGradient(
            colors: [Color.white.opacity(0.10), Color.white.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
          ),
          lineWidth: 0.5
        )
    )
  }

  private var baselineProgress: some View {
    VStack(alignment: .leading, spacing: Space.xs) {
      HStack(spacing: Space.xxs + 1) {
        ForEach(0..<5, id: \.self) { index in
          Capsule()
            .fill(index < model.baselineSessions ? Palette.accent : Palette.surfaceRaised)
            .frame(height: 4)
        }
      }
      Text("\(model.baselineSessions) of 5 baseline sessions recorded")
        .font(SoberType.footnote)
        .foregroundStyle(Palette.textMuted)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(model.baselineSessions) of 5 baseline sessions recorded")
  }

  private var isSafetyCircleReady: Bool {
    model.safetyPlan.isActive && model.safetyPlan.hasContact
  }

  private var kicker: String {
    if !model.baselineReady { return "Getting set up" }
    if !isSafetyCircleReady { return "One thing left" }
    return lastCheck == nil ? "Ready" : "Last check"
  }

  private var statusTint: Color {
    guard model.baselineReady, isSafetyCircleReady else { return Palette.accent }
    return lastCheck?.resultState == .signalsDetected ? Palette.accent : Palette.textMuted
  }

  private var headline: String {
    if !model.baselineReady { return "Learn your steady." }
    if !isSafetyCircleReady { return "Name someone to call." }
    guard let state = lastCheck?.resultState else { return "Ready when you are." }
    switch state {
    case .signalsDetected: return "Signals detected."
    case .inconclusive: return "No clear read."
    case .noSignalsDetected: return "Nothing unusual."
    }
  }

  private var supporting: String {
    if !model.baselineReady {
      return
        "A few short sessions while you're sober teach the app what your normal looks like. Every check after that is compared against it."
    }
    if !isSafetyCircleReady {
      return "A check only starts once there's somewhere to turn if it comes back concerning."
    }
    guard let lastCheck else {
      return "A check takes about two minutes and stays on this iPhone."
    }
    return "\(relativeTime(lastCheck.startedAt).capitalizedFirst). A check takes about two minutes."
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
      if model.baselineReady && !isSafetyCircleReady {
        selectTab(.circle)
      } else {
        launch = ScreeningLaunch(
          mode: model.baselineReady ? .check : .baseline, scenario: .live)
      }
    }
    .buttonStyle(PrimaryButtonStyle())
  }

  private var actionTitle: String {
    if !model.baselineReady { return "Record a baseline session" }
    if !isSafetyCircleReady { return "Set up Safety Circle" }
    return "Start check"
  }

  // MARK: - Get home
  //
  // The safety net, reachable without running a check first. Someone who has
  // already decided not to drive should not have to take a test to get a car.

  private var getHome: some View {
    Section_("Get home") {
      HStack(spacing: Space.sm) {
        quickAction(
          title: model.safetyPlan.contactName,
          subtitle: "Call",
          symbol: "phone.fill",
          url: URL(string: "tel://\(model.safetyPlan.normalizedContactPhone)")
        )
        quickAction(
          title: model.safetyPlan.preferredRide,
          subtitle: "Ride",
          symbol: "car.fill",
          url: rideURL
        )
      }
    }
  }

  /// Opens the provider. Destination and location handling remain
  /// unimplemented; see the prototype limits in the README.
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
      VStack(alignment: .leading, spacing: Space.sm) {
        Image(systemName: symbol)
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(Palette.textSecondary)
        VStack(alignment: .leading, spacing: 1) {
          Text(subtitle)
            .font(SoberType.footnote)
            .foregroundStyle(Palette.textMuted)
          Text(title)
            .font(SoberType.headline)
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Space.md)
      .background(
        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
          .fill(Palette.surface)
      )
    }
    .buttonStyle(PlainPressStyle())
    .accessibilityElement(children: .combine)
  }

  // MARK: - Baseline
  //
  // A compact read of the portrait, captioned. The full graphic lives on its
  // own screen; here it is a summary with a way in.

  private var baselineStrip: some View {
    Section_("Your steady", action: ("Details", { showingBaseline = true })) {
      Button {
        showingBaseline = true
      } label: {
        VStack(alignment: .leading, spacing: Space.sm) {
          HStack(spacing: 5) {
            ForEach(PortraitTrack.all) { track in
              trackPip(for: track)
            }
          }
          Text(baselineCaption)
            .font(SoberType.footnote)
            .foregroundStyle(Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .background(
          RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
            .fill(Palette.surface)
        )
      }
      .buttonStyle(PlainPressStyle())
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Your steady")
      .accessibilityValue(baselineCaption)
    }
  }

  private func trackPip(for track: PortraitTrack) -> some View {
    let risk = lastCheck?.signalRisks?[track.id]
    let outside = (risk ?? 0) >= SignalDetail.concernThreshold
    return Capsule()
      .fill(
        !model.baselineReady
          ? Palette.surfaceRaised
          : (outside ? Palette.accent : Palette.withinRange.opacity(0.55))
      )
      .frame(height: 6)
  }

  private var baselineCaption: String {
    guard model.baselineReady else {
      return "Five sober sessions build your range. Tap to see how it works."
    }
    guard let risks = lastCheck?.signalRisks else {
      return "Five measures, each with your own usual range."
    }
    let outside = risks.values.filter { $0 >= SignalDetail.concernThreshold }.count
    if outside == 0 { return "All five measures sat inside your usual range." }
    return outside == 1
      ? "One measure sat outside your usual range."
      : "\(outside) measures sat outside your usual range."
  }

  // MARK: - Recent

  private var recent: some View {
    Section_("Recent", action: ("All", { selectTab(.history) })) {
      Rows {
        ForEach(Array(recentChecks.enumerated()), id: \.element.id) { index, session in
          if index > 0 { Separator() }
          Button {
            selectedSession = session
          } label: {
            HStack(spacing: Space.sm) {
              Circle()
                .fill(color(for: session.resultState))
                .frame(width: 7, height: 7)
              Text(session.resultState?.title ?? "Result not recorded")
                .font(SoberType.body)
                .foregroundStyle(Palette.textPrimary)
              Spacer(minLength: Space.xs)
              Text(shortTime(session.startedAt))
                .font(SoberType.footnote)
                .foregroundStyle(Palette.textMuted)
            }
            .frame(minHeight: Hit.minimum)
            .padding(.vertical, Space.xs)
            .contentShape(Rectangle())
          }
          .buttonStyle(PlainPressStyle())
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

  private func color(for state: ScreeningResultState?) -> Color {
    switch state {
    case .signalsDetected: Palette.accent
    case .inconclusive: Palette.unmeasured
    case .noSignalsDetected: Palette.withinRange
    case nil: Palette.textMuted
    }
  }
}

extension String {
  fileprivate var capitalizedFirst: String {
    guard let first else { return self }
    return first.uppercased() + dropFirst()
  }
}
