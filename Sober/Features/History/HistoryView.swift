import SwiftUI

/// A log of every session this phone has recorded.
///
/// Deliberately a list and nothing more. There is no trend line, no average,
/// and no streak: any of those would compose individual checks into a
/// running figure, which is the score this product refuses to produce. Each
/// row states what happened once, at one time, and stops there.
struct HistoryView: View {
  @EnvironmentObject private var model: AppModel

  private var sessions: [ResearchSessionEnvelope] {
    model.researchSessions.sorted { $0.startedAt > $1.startedAt }
  }

  private var checkCount: Int {
    sessions.filter { $0.context.sessionKind == .screeningCheck }.count
  }

  private var baselineCount: Int {
    sessions.filter { $0.context.sessionKind == .soberBaseline }.count
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.xl) {
        if sessions.isEmpty {
          emptyState
        } else {
          counts
          log
          retentionNote
        }
      }
      .padding(.horizontal, Space.lg)
      .padding(.bottom, Space.xl)
    }
    .scrollIndicators(.hidden)
    .soberBackground()
    .safeAreaInset(edge: .top) {
      HStack {
        Text("History")
          .font(SoberType.title)
          .titleTracking()
          .foregroundStyle(Palette.textPrimary)
          .accessibilityAddTraits(.isHeader)
        Spacer()
      }
      .padding(.horizontal, Space.lg)
      .padding(.top, Space.xxs)
      .padding(.bottom, Space.sm)
      .soberHeaderScrim()
    }
  }

  private var counts: some View {
    MetricStrip(items: [
      .init(label: "Checks", value: "\(checkCount)"),
      .init(label: "Baseline", value: "\(baselineCount)"),
      .init(label: "Total", value: "\(sessions.count)"),
    ])
  }

  private var log: some View {
    SoberSection("All sessions") {
      SoberList {
        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
          if index > 0 { SoberDivider() }
          row(for: session)
        }
      }
    }
  }

  private func row(for session: ResearchSessionEnvelope) -> some View {
    let isBaseline = session.context.sessionKind == .soberBaseline
    let quality = session.metrics.qualityScore

    return HStack(spacing: Space.sm) {
      Circle()
        .fill(dotColor(for: session))
        .frame(width: 8, height: 8)
        .frame(width: 12)

      VStack(alignment: .leading, spacing: Space.xxs) {
        Text(title(for: session))
          .font(SoberType.body)
          .foregroundStyle(Palette.textPrimary)
        Text(
          session.startedAt.formatted(
            .dateTime.weekday(.abbreviated).month().day().hour().minute())
        )
        .font(SoberType.subheadline)
        .foregroundStyle(Palette.textTertiary)
      }

      Spacer(minLength: 10)

      Text("\(Int((quality * 100).rounded()))%")
        .font(SoberType.footnoteStrong)
        .monospacedDigit()
        .foregroundStyle(quality >= 0.72 ? Palette.textTertiary : Palette.warning)

      if isBaseline {
        Image(systemName: "target")
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(Palette.textTertiary.opacity(0.7))
      }
    }
    .padding(.vertical, Space.md)
    .accessibilityElement(children: .combine)
  }

  /// Sessions recorded before the History view existed carry no stored
  /// result, so they say so rather than being labelled by inference.
  private func title(for session: ResearchSessionEnvelope) -> String {
    if session.context.sessionKind == .soberBaseline { return "Baseline session" }
    guard let state = session.resultState else { return "Check, result not recorded" }
    return state.title
  }

  private func dotColor(for session: ResearchSessionEnvelope) -> Color {
    if session.context.sessionKind == .soberBaseline { return Palette.textTertiary }
    switch session.resultState {
    case .signalsDetected: return Palette.error
    case .inconclusive: return Palette.warning
    case .noSignalsDetected: return Palette.textSecondary
    case nil: return Palette.textTertiary
    }
  }

  private var retentionNote: some View {
    Text(
      "Stored only on this iPhone. Manage or delete everything from the Research Center."
    )
    .font(SoberType.footnote)
    .foregroundStyle(Palette.textTertiary)
    .readingLine()
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: Space.sm) {
      Text("No sessions yet")
        .font(SoberType.title)
        .titleTracking()
        .foregroundStyle(Palette.textPrimary)
      Text(
        "Completed baseline sessions and checks appear here, newest first. Nothing is uploaded."
      )
      .font(SoberType.body)
      .foregroundStyle(Palette.textSecondary)
      .readingLine()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, Space.xxxl)
  }
}
