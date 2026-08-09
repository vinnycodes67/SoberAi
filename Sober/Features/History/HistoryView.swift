import SwiftUI

/// Past sessions, and the way into Your Steady.
///
/// Each row says what the session was, when, how well it captured, and — for a
/// check — which of the three states came out. What it deliberately does not do
/// is aggregate: no streak, no count of concerning results, no chart. A handful
/// of sessions is not a time series, and a running tally would invite reading a
/// trend the measurement cannot support.
///
/// Entries age out. `CheckHistoryStore` bounds them by both age and count,
/// because a permanent record of when someone checked themselves is the thing
/// another person would ask to see.
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

        if let error = model.localDataError {
          loadFailure(error)
        }

        if model.checkHistory.isEmpty, model.localDataError == nil {
          emptyState
        } else if !model.checkHistory.isEmpty {
          filterControl
          sessionList
        }
      }
      .padding(.horizontal, DSSpace.margin)
      .padding(.bottom, DSSpace.xxl)
    }
    .background(DSPalette.background.ignoresSafeArea())
    .task {
      await model.reloadCheckHistory()
      await model.reloadResearchData()
    }
    .sheet(isPresented: $showingSteady) {
      NavigationStack {
        YourSteadyView()
          .environmentObject(model)
          .navigationTitle("Your steady")
          .navigationBarTitleDisplayMode(.inline)
      }
      .preferredColorScheme(.dark)
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
              showsChevron: false,
              trailing: {
                if session.outcome == .signalsDetected {
                  Circle().fill(tint(for: session)).frame(width: 7, height: 7)
                }
              }
            )
          }
        }
      }
    }
  }

  /// A read failure is not an empty history. Saying so keeps someone from
  /// concluding the app deleted their sessions and starting over.
  private func loadFailure(_ error: AppModel.LocalDataError) -> some View {
    DSCard {
      VStack(alignment: .leading, spacing: DSSpace.xs) {
        Text("Could not load")
          .font(DSFont.headline)
          .foregroundStyle(DSPalette.accent)
        Text(error.message)
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textSecondary)
          .dsReadingLine()
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var emptyState: some View {
    DSEmptyState(
      title: "Nothing recorded yet",
      message:
        "Baseline sessions and checks you complete on this iPhone will appear here. Nothing is uploaded, and entries older than \(CheckHistoryStore.retentionDays) days are removed automatically."
    )
  }

  // MARK: - Data

  private var visibleSessions: [CheckHistoryEntry] {
    switch filter {
    case .all: model.checkHistory
    case .baseline: model.checkHistory.filter { $0.kind == .baseline }
    case .check: model.checkHistory.filter { $0.kind == .check }
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

  private func title(for entry: CheckHistoryEntry) -> String {
    guard entry.kind == .check else { return "Baseline session" }
    switch entry.outcome {
    case .signalsDetected: return "Signals detected"
    case .inconclusive: return "Inconclusive"
    case .noSignalsDetected: return "No signals detected"
    case nil: return "Check"
    }
  }

  /// Only a concerning result is coloured, matching the palette's single rule:
  /// orange means attention. "No signals detected" gets no colour, because it is
  /// not a pass and must not read as one.
  private func tint(for entry: CheckHistoryEntry) -> Color {
    entry.outcome == .signalsDetected ? DSPalette.accent : DSPalette.textPrimary
  }

  /// Date, then how well the capture went. Capture quality is the honest thing
  /// to show about a past session: it says whether the numbers were worth
  /// anything, without restating a verdict out of context.
  private func detail(for entry: CheckHistoryEntry) -> String {
    let when = entry.startedAt.formatted(date: .abbreviated, time: .shortened)
    guard entry.completedAllTasks else { return "\(when) · not completed" }
    return "\(when) · \(qualityLabel(entry.qualityScore)) capture"
  }

  private func qualityLabel(_ score: Double) -> String {
    switch score {
    case 0.85...: "strong"
    case 0.72..<0.85: "usable"
    default: "low"
    }
  }
}
