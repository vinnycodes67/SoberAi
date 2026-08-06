import SwiftUI

/// One measure in the portrait.
struct PortraitTrack: Identifiable, Equatable {
  let id: String
  let label: String
  /// Where tonight sat, on the same 0...1 scale the engine uses. `nil` when
  /// no check has been taken, or when this measure could not be read.
  var marker: Double?
  /// False when a reading was attempted and failed, which is a different
  /// thing from never having been attempted.
  var attempted: Bool = true

  static let all: [PortraitTrack] = [
    .init(id: "reaction", label: "Reaction"),
    .init(id: "tracking", label: "Tracking"),
    .init(id: "timing", label: "Timing"),
    .init(id: "gaze", label: "Guided gaze"),
    .init(id: "pupil", label: "Light reflex"),
  ]
}

/// Sober's object: the portrait of someone's own steady.
///
/// Five measures, each drawn as a band representing that person's usual
/// range. When a check exists, a marker sits on each band showing where
/// tonight fell. This is the only material in the app that belongs to the
/// person using it, and it is the literal basis of every claim the product
/// makes: a check is nothing more than the question *does tonight sit inside
/// this shape?*
///
/// Before a baseline exists the bands are drawn as faint outlines. The
/// portrait is then honestly incomplete, and that incompleteness is a better
/// invitation than a progress bar counting to five.
struct BaselinePortrait: View {
  var tracks: [PortraitTrack] = PortraitTrack.all
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
        row(track, index: index)
          .frame(height: rowHeight)
      }
    }
    .onAppear {
      guard animatesOnAppear, !drawn else {
        drawn = true
        return
      }
      if reduceMotion {
        drawn = true
      } else {
        withAnimation(.easeOut(duration: 0.5)) { drawn = true }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(isEstablished ? "Your baseline" : "Baseline not yet established")
  }

  private func row(_ track: PortraitTrack, index: Int) -> some View {
    HStack(spacing: Space.sm) {
      Text(track.label)
        .font(SoberType.caption2)
        .foregroundStyle(Palette.textMuted)
        .frame(width: labelWidth, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      GeometryReader { proxy in
        let width = proxy.size.width
        // The band spans everything the engine treats as usual for this
        // person. Its right edge is where a measure starts being called out.
        let bandWidth = width * SignalDetail.concernThreshold

        ZStack(alignment: .leading) {
          Capsule()
            .fill(Palette.separator)
            .frame(height: 1)

          if isEstablished {
            Capsule()
              .fill(Palette.surfaceRaised)
              .frame(width: drawn ? bandWidth : 0, height: 8)
              .animation(
                reduceMotion ? nil : .easeOut(duration: 0.45).delay(Double(index) * 0.04),
                value: drawn)
          } else {
            Capsule()
              .strokeBorder(Palette.separator, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
              .frame(width: bandWidth, height: 8)
          }

          if let marker = track.marker {
            let x = min(max(marker, 0), 1) * (width - 3)
            // Orange only when the measure actually moved. A marker sitting
            // inside the usual range is the common case and stays neutral,
            // because the absence of attention is itself the message.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
              .fill(marker >= SignalDetail.concernThreshold
                ? Palette.accent : Palette.textPrimary)
              .frame(width: 3, height: 18)
              .offset(x: x)
              .opacity(drawn ? 1 : 0)
              .animation(
                reduceMotion ? nil : .easeOut(duration: 0.3).delay(0.28 + Double(index) * 0.04),
                value: drawn)
          } else if !track.attempted {
            Text("not read")
              .font(SoberType.caption)
              .foregroundStyle(Palette.unmeasured)
              .offset(x: bandWidth + Space.sm)
          }
        }
        .frame(height: rowHeight)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(track.label)
    .accessibilityValue(accessibilityValue(for: track))
  }

  private func accessibilityValue(for track: PortraitTrack) -> String {
    guard isEstablished else { return "Range not yet established" }
    guard let marker = track.marker else {
      return track.attempted ? "Within your usual range" : "Could not be read"
    }
    return marker >= SignalDetail.concernThreshold
      ? "Outside your usual range" : "Within your usual range"
  }
}

extension BaselinePortrait {
  /// Builds the portrait's tracks from a stored session's per-signal
  /// positions. Signals absent from the record are drawn as unread rather
  /// than as zero.
  static func tracks(from risks: [String: Double]?) -> [PortraitTrack] {
    PortraitTrack.all.map { track in
      var copy = track
      if let risks {
        copy.marker = risks[track.id]
        copy.attempted = risks[track.id] != nil
      }
      return copy
    }
  }

  /// Builds the portrait's tracks from a live outcome.
  static func tracks(from details: [SignalDetail]) -> [PortraitTrack] {
    PortraitTrack.all.map { track in
      var copy = track
      if let detail = details.first(where: { $0.id == track.id }) {
        copy.marker = detail.risk
        copy.attempted = detail.risk != nil
      }
      return copy
    }
  }
}

/// Explains the portrait once, beneath it, never per row.
struct PortraitLegend: View {
  var body: some View {
    HStack(spacing: Space.sm) {
      HStack(spacing: Space.xs) {
        Capsule().fill(Palette.textMuted.opacity(0.45)).frame(width: 14, height: 3)
        Text("Your usual range")
      }
      HStack(spacing: Space.xs) {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
          .fill(Palette.textPrimary).frame(width: 3, height: 11)
        Text("This check")
      }
      HStack(spacing: Space.xs) {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
          .fill(Palette.accent).frame(width: 3, height: 11)
        Text("Outside")
      }
      Spacer(minLength: 0)
    }
    .font(SoberType.footnote)
    .foregroundStyle(Palette.textMuted)
  }
}
