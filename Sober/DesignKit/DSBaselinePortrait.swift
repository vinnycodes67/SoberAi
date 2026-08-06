import SwiftUI

/// One measure in the portrait.
struct DSPortraitTrack: Identifiable, Equatable {
  let id: String
  let label: String
  /// Where this check landed, on a 0...1 scale where 0 is at or below the
  /// person's usual and 1 is roughly three of their own standard deviations
  /// above it. `nil` when no check exists, or the measure could not be read.
  var marker: Double?
  /// False when a reading was attempted and failed, which is a different
  /// thing from never having been attempted.
  var attempted: Bool = true

  /// The point on that scale where a measure starts being called out. Matches
  /// the threshold `ScreeningEngine` already uses for `SignalDetail.concern`.
  static let concernThreshold = 0.55

  static let all: [DSPortraitTrack] = [
    .init(id: "reaction", label: "Reaction"),
    .init(id: "tracking", label: "Tracking"),
    .init(id: "timing", label: "Timing"),
    .init(id: "gaze", label: "Guided gaze"),
    .init(id: "pupil", label: "Light reflex"),
  ]
}

/// The portrait of someone's own steady.
///
/// Five measures, each drawn as a band representing that person's usual
/// range, with a tick showing where a check landed. It is the product's
/// central claim made visible: every row compares someone only to themselves,
/// and no row is a summary of the others.
///
/// **Always caption it.** Shown bare it is a diagram with no legend, and
/// nobody can tell what the bar, the block, or the tick mean. Pair it with
/// `DSPortraitLegend` and a sentence, or put it behind a titled screen.
///
/// Before a baseline exists the bands draw as dashed outlines: the portrait
/// is then honestly incomplete, which is a better invitation than a progress
/// bar counting to five.
struct DSBaselinePortrait: View {
  var tracks: [DSPortraitTrack] = DSPortraitTrack.all
  /// False before enough sober sessions exist to define a range.
  var isEstablished: Bool
  /// Drives the one-time draw-in. Set false where the portrait is not the
  /// screen's entrance moment.
  var animatesOnAppear: Bool = true

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var drawn = false

  private let rowHeight: CGFloat = 34
  private let labelWidth: CGFloat = 76

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
        row(track, index: index).frame(height: rowHeight)
      }
    }
    .onAppear {
      guard animatesOnAppear, !drawn else { drawn = true; return }
      if reduceMotion {
        drawn = true
      } else {
        withAnimation(.easeOut(duration: 0.5)) { drawn = true }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(isEstablished ? "Your baseline" : "Baseline not yet established")
  }

  private func row(_ track: DSPortraitTrack, index: Int) -> some View {
    HStack(spacing: DSSpace.sm) {
      Text(track.label)
        .font(DSFont.caption2)
        .foregroundStyle(DSPalette.textMuted)
        .frame(width: labelWidth, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      GeometryReader { proxy in
        let width = proxy.size.width
        // The band spans everything the engine treats as usual for this
        // person. Its right edge is where a measure starts being called out.
        let bandWidth = width * DSPortraitTrack.concernThreshold

        ZStack(alignment: .leading) {
          Capsule().fill(DSPalette.separator).frame(height: 1)

          if isEstablished {
            Capsule()
              .fill(DSPalette.surfaceRaised)
              .frame(width: drawn ? bandWidth : 0, height: 8)
              .animation(
                reduceMotion ? nil : .easeOut(duration: 0.45).delay(Double(index) * 0.04),
                value: drawn)
          } else {
            Capsule()
              .strokeBorder(DSPalette.separator, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
              .frame(width: bandWidth, height: 8)
          }

          if let marker = track.marker {
            let x = min(max(marker, 0), 1) * (width - 3)
            // Orange only when the measure actually moved. A tick inside the
            // usual range is the common case and stays neutral, because the
            // absence of attention is itself the message.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
              .fill(
                marker >= DSPortraitTrack.concernThreshold
                  ? DSPalette.accent : DSPalette.textPrimary
              )
              .frame(width: 3, height: 18)
              .offset(x: x)
              .opacity(drawn ? 1 : 0)
              .animation(
                reduceMotion ? nil : .easeOut(duration: 0.3).delay(0.28 + Double(index) * 0.04),
                value: drawn)
          } else if !track.attempted {
            Text("not read")
              .font(DSFont.caption)
              .foregroundStyle(DSPalette.unmeasured)
              .offset(x: bandWidth + DSSpace.sm)
          }
        }
        .frame(height: rowHeight)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(track.label)
    .accessibilityValue(accessibilityValue(for: track))
  }

  private func accessibilityValue(for track: DSPortraitTrack) -> String {
    guard isEstablished else { return "Range not yet established" }
    guard let marker = track.marker else {
      return track.attempted ? "Within your usual range" : "Could not be read"
    }
    return marker >= DSPortraitTrack.concernThreshold
      ? "Outside your usual range" : "Within your usual range"
  }
}

extension DSBaselinePortrait {
  /// Builds tracks from a dictionary of signal id to risk, which is the shape
  /// `ScreeningOutcome` already produces. Signals absent from the dictionary
  /// draw as unread rather than as zero, so a missing reading is never
  /// mistaken for a reading of nothing.
  static func tracks(fromRisks risks: [String: Double]?) -> [DSPortraitTrack] {
    DSPortraitTrack.all.map { track in
      var copy = track
      if let risks {
        copy.marker = risks[track.id]
        copy.attempted = risks[track.id] != nil
      }
      return copy
    }
  }
}

/// Explains the portrait once, beneath it, never per row.
struct DSPortraitLegend: View {
  var body: some View {
    HStack(spacing: DSSpace.sm) {
      HStack(spacing: DSSpace.xs) {
        Capsule().fill(DSPalette.surfaceRaised).frame(width: 14, height: 8)
        Text("Usual range")
      }
      HStack(spacing: DSSpace.xs) {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
          .fill(DSPalette.textPrimary).frame(width: 3, height: 11)
        Text("This check")
      }
      HStack(spacing: DSSpace.xs) {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
          .fill(DSPalette.accent).frame(width: 3, height: 11)
        Text("Outside")
      }
      Spacer(minLength: 0)
    }
    .font(DSFont.footnote)
    .foregroundStyle(DSPalette.textMuted)
  }
}
