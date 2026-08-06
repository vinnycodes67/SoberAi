import SwiftUI

/// How someone's steady was built, and what it is made of.
///
/// This is where the app's honesty lives. Showing which sessions were
/// excluded, and saying plainly why, does more for trust than any amount of
/// visual polish. It is also the one place raw numbers are appropriate,
/// because a person has deliberately navigated here to see them.
struct BaselineDetailContent: View {
  @EnvironmentObject private var model: AppModel

  private var baselineSessions: [ResearchSessionEnvelope] {
    model.researchSessions
      .filter { $0.context.sessionKind == .soberBaseline }
      .sorted { $0.startedAt > $1.startedAt }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.xl) {
        VStack(alignment: .leading, spacing: Space.sm) {
          BaselinePortrait(isEstablished: model.baselineReady, animatesOnAppear: false)
          if model.baselineReady {
            PortraitLegend()
          }
        }

        if model.baselineReady {
          Section_("Your usual ranges") {
            Rows {
              ForEach(Array(ranges.enumerated()), id: \.element.label) { index, range in
                if index > 0 { Separator() }
                ValueRow(label: range.label, value: range.value)
              }
            }
          }
        } else {
          Text(
            "Your ranges appear once five sober sessions have been recorded. Sessions with poor capture are not counted, because a weak reading would widen every range it entered."
          )
          .font(SoberType.body)
          .foregroundStyle(Palette.textSecondary)
          .readingLine()
        }

        Section_("Sessions") {
          if baselineSessions.isEmpty {
            Text("No baseline sessions recorded yet.")
              .font(SoberType.subheadline)
              .foregroundStyle(Palette.textMuted)
          } else {
            Rows {
              ForEach(Array(baselineSessions.enumerated()), id: \.element.id) { index, session in
                if index > 0 { Separator() }
                sessionRow(session)
              }
            }
          }
        }

        Text(
          "A range is the spread of your own sober sessions for one measure. It is not a clinical reference range, it says nothing about anyone else, and it is not a threshold for whether you can drive."
        )
        .font(SoberType.footnote)
        .foregroundStyle(Palette.textMuted)
        .readingLine()
      }
      .padding(.horizontal, Space.margin)
      .padding(.bottom, Space.xl)
    }
    .scrollIndicators(.hidden)
    .pageBackground()
    .navigationTitle("Your steady")
    .navigationBarTitleDisplayMode(.large)
  }

  private func sessionRow(_ session: ResearchSessionEnvelope) -> some View {
    let quality = session.metrics.qualityScore
    let counted = quality >= 0.72

    return HStack(spacing: Space.sm) {
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text(session.startedAt.formatted(.dateTime.weekday(.wide).month().day()))
          .font(SoberType.body)
          .foregroundStyle(Palette.textPrimary)
        Text(
          counted
            ? session.startedAt.formatted(date: .omitted, time: .shortened)
            : "Not counted, capture was too weak"
        )
        .font(SoberType.footnote)
        .foregroundStyle(counted ? Palette.textMuted : Palette.unmeasured)
      }
      Spacer(minLength: Space.xs)
      if !counted {
        Image(systemName: "minus.circle")
          .font(.system(size: 15))
          .foregroundStyle(Palette.unmeasured)
      }
    }
    .frame(minHeight: Hit.minimum)
    .padding(.vertical, Space.xs)
    .accessibilityElement(children: .combine)
  }

  /// Ranges are the observed spread of the person's own counted sessions.
  private var ranges: [(label: String, value: String)] {
    let samples = model.baseline.samples
    guard !samples.isEmpty else { return [] }

    func span(_ values: [Double], unit: String, decimals: Int = 0) -> String {
      guard let lo = values.min(), let hi = values.max() else { return "Not measured" }
      let f = "%.\(decimals)f"
      return "\(String(format: f, lo)) to \(String(format: f, hi))\(unit)"
    }

    var out: [(String, String)] = [
      ("Reaction", span(samples.map(\.reactionTimeMilliseconds), unit: " ms")),
      ("Timing", span(samples.map { $0.timeEstimateError * 100 }, unit: "% off")),
    ]
    let tracking = samples.compactMap(\.trackingError)
    if !tracking.isEmpty {
      out.append(("Tracking", span(tracking.map { (1 - $0) * 100 }, unit: "% steady")))
    }
    let gaze = samples.compactMap(\.gazeSmoothness)
    if !gaze.isEmpty {
      out.append(("Guided gaze", span(gaze.map { (1 - $0) * 100 }, unit: "% smooth")))
    }
    return out
  }
}

/// Sheet wrapper.
struct BaselineDetailView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      BaselineDetailContent()
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
          }
        }
    }
  }
}

/// A stored check, reopened from Home or History.
struct PastResultView: View {
  let session: ResearchSessionEnvelope
  let safetyPlan: SafetyPlan

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Space.xl) {
          HStack(alignment: .top, spacing: Space.md) {
            Rectangle()
              .fill(stateColor)
              .frame(width: 3)
              .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: Space.xs) {
              Text(session.resultState?.title ?? "Result not recorded")
                .font(SoberType.hero)
                .heroTracking()
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
              Text(session.startedAt.formatted(date: .complete, time: .shortened))
                .font(SoberType.subheadline)
                .foregroundStyle(Palette.textMuted)
            }
          }
          .fixedSize(horizontal: false, vertical: true)

          Section_("Against your baseline") {
            VStack(alignment: .leading, spacing: Space.sm) {
              BaselinePortrait(
                tracks: BaselinePortrait.tracks(from: session.signalRisks),
                isEstablished: true,
                animatesOnAppear: false
              )
              PortraitLegend()
            }
          }

          Text(
            "Recorded on this iPhone. Measures shown are prototype readings, not clinical values."
          )
          .font(SoberType.footnote)
          .foregroundStyle(Palette.textMuted)
          .readingLine()
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.md)
        .padding(.bottom, Space.xl)
      }
      .scrollIndicators(.hidden)
      .pageBackground()
      .navigationTitle("Past check")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private var stateColor: Color {
    switch session.resultState {
    case .signalsDetected: Palette.outsideRange
    case .inconclusive: Palette.unmeasured
    case .noSignalsDetected: Palette.withinRange
    case nil: Palette.textMuted
    }
  }
}

/// Sheet wrapper for History.
struct HistorySheet: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      HistoryView()
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
          }
        }
    }
  }
}
