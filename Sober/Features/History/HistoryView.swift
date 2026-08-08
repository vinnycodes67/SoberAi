import SwiftUI

/// Past sessions, and the way into Your Steady.
///
/// Sessions are listed as what they were and how well they captured — never as
/// a verdict. A past check's result is deliberately not restated as a headline
/// here: a list of outcomes invites reading a trend, and there is no trend to
/// read. Five measures over a handful of sessions is not a time series.
struct HistoryView: View {
  @EnvironmentObject private var model: AppModel

  @State private var filter: Filter = .all
  @State private var showingSteady = false

  enum Filter: String, CaseIterable, Identifiable {
    case all
    case baseline
    case check

    var id: String { rawValue }

    var title: String {
      switch self {
      case .all: "All"
      case .baseline: "Baseline"
      case .check: "Checks"
      }
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DSSpace.xl) {
        header
        steadyEntry

        if model.researchSessions.isEmpty {
          emptyState
        } else {
          filterControl
          sessionList
        }
      }
      .padding(.horizontal, DSSpace.margin)
      .padding(.bottom, DSSpace.xxl)
    }
    .background(DSPalette.background.ignoresSafeArea())
    .task { await model.reloadResearchData() }
    .sheet(isPresented: $showingSteady) {
      NavigationStack {
        YourSteadyView()
          .environmentObject(model)
          .navigationTitle("Your steady")
          .navigationBarTitleDisplayMode(.inline)
      }
      .preferredColorScheme(.dark)
    }
    .onChange(of: model.privacyShieldIsVisible) { _, isShielded in
      // A presented sheet sits above its parent. Dismiss it before the app
      // switcher snapshot so Your Steady cannot remain visible over the shield.
      if isShielded { showingSteady = false }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: DSSpace.sm) {
      DSEyebrow("History")
      Text("What you have recorded.")
        .font(DSFont.hero)
        .dsHeroTracking()
        .foregroundStyle(DSPalette.textPrimary)
        .accessibilityAddTraits(.isHeader)
    }
    .padding(.top, DSSpace.lg)
  }

  private var steadyEntry: some View {
    DSRows {
      DSRow(
        "Your steady",
        detail: model.baselineReady
          ? "The range your checks compare against"
          : "\(model.baselineSessions) of 5 baseline sessions recorded",
        action: { showingSteady = true }
      )
    }
  }

  private var filterControl: some View {
    Picker("Show", selection: $filter) {
      ForEach(Filter.allCases) { option in
        Text(option.title).tag(option)
      }
    }
    .pickerStyle(.segmented)
  }

  private var sessionList: some View {
    DSSection(sectionTitle) {
      if visibleSessions.isEmpty {
        DSCard {
          Text(emptyFilterMessage)
            .font(DSFont.body)
            .foregroundStyle(DSPalette.textSecondary)
            .dsReadingLine()
        }
      } else {
        DSRows {
          ForEach(Array(visibleSessions.enumerated()), id: \.element.id) { index, session in
            if index > 0 { DSSeparator() }
            DSRow(
              title(for: session),
              detail: detail(for: session),
              showsChevron: false
            )
          }
        }
      }
    }
  }

  private var emptyState: some View {
    DSEmptyState(
      title: "Nothing recorded yet",
      message:
        "Baseline sessions and checks you complete on this iPhone will appear here. Nothing is uploaded."
    )
  }

  // MARK: - Data

  private var visibleSessions: [ResearchSessionEnvelope] {
    let sorted = model.researchSessions.sorted { $0.startedAt > $1.startedAt }
    switch filter {
    case .all:
      return sorted
    case .baseline:
      return sorted.filter { $0.context.sessionKind == .soberBaseline }
    case .check:
      return sorted.filter { $0.context.sessionKind == .screeningCheck }
    }
  }

  private var sectionTitle: String {
    let count = visibleSessions.count
    return "\(count) session\(count == 1 ? "" : "s")"
  }

  private var emptyFilterMessage: String {
    switch filter {
    case .all:
      return "Nothing recorded yet."
    case .baseline:
      return "No baseline sessions recorded on this iPhone yet."
    case .check:
      return "No checks recorded on this iPhone yet."
    }
  }

  private func title(for session: ResearchSessionEnvelope) -> String {
    switch session.context.sessionKind {
    case .soberBaseline: "Baseline session"
    case .screeningCheck: "Check"
    case .controlledResearch: "Research session"
    }
  }

  /// Date, then how well the capture went. Capture quality is the honest thing
  /// to show about a past session: it says whether the numbers were worth
  /// anything, without restating a verdict out of context.
  private func detail(for session: ResearchSessionEnvelope) -> String {
    let when = session.startedAt.formatted(date: .abbreviated, time: .shortened)
    guard session.completedAt != nil, session.metrics.completedAllTasks else {
      return "\(when) · not completed"
    }
    return "\(when) · \(qualityLabel(session.metrics.qualityScore)) capture"
  }

  private func qualityLabel(_ score: Double) -> String {
    switch score {
    case 0.85...: "strong"
    case 0.72..<0.85: "usable"
    default: "low"
    }
  }
}
