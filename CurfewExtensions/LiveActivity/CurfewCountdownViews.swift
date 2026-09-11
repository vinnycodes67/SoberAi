import ActivityKit
import SwiftUI
import WidgetKit

// The countdown's views. System fonts, every one relative to a Dynamic Type
// style; Satoshi is not bundled in the extension. Times and timers use
// `monospacedDigit()` so nothing jitters as the seconds tick.

/// The Lock Screen banner. One or two lines of text, the countdown on the
/// trailing edge when there is one.
struct CurfewLockScreenView: View {
  let context: ActivityViewContext<CurfewCountdownAttributes>

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      CurfewCountdownText(context: context)
      Spacer(minLength: 0)
      if context.state.phase.showsTrailingTimer {
        CurfewCompactTrailing(state: context.state)
          .font(.title2.weight(.medium))
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
  }
}

/// The words for each phase. Shared by the Lock Screen and the expanded
/// Dynamic Island so the two never disagree.
struct CurfewCountdownText: View {
  let context: ActivityViewContext<CurfewCountdownAttributes>

  private var state: CurfewCountdownAttributes.ContentState { context.state }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      switch state.phase {
      case .beforeCurfew:
        // "Home by 11:00 PM"
        (Text("\(CurfewCountdownCopy.homeByPrefix) ") + Text(state.curfewAt, style: .time))
          .font(.headline)
          .foregroundStyle(CurfewCountdownPalette.textPrimary)

      case .grace:
        // "Curfew 11:00 PM · apps pause soon"
        (Text("\(CurfewCountdownCopy.gracePrefix) ")
          + Text(state.curfewAt, style: .time)
          + Text("\(CurfewCountdownCopy.separator)\(CurfewCountdownCopy.graceSuffix)"))
          .font(.headline)
          .foregroundStyle(CurfewCountdownPalette.textPrimary)
        Text(CurfewCopy.stillWorks)
          .font(.footnote)
          .foregroundStyle(CurfewCountdownPalette.textSecondary)

      case .checkInDue:
        Text(CurfewCopy.shieldTitle)
          .font(.headline)
          .foregroundStyle(CurfewCountdownPalette.textPrimary)
        // The one orange line in the whole countdown: the thing to do next.
        Text(CurfewCopy.shieldPrimaryButton)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(CurfewCountdownPalette.accent)
        Text(CurfewCopy.stillWorks)
          .font(.footnote)
          .foregroundStyle(CurfewCountdownPalette.textSecondary)

      case .checkedIn:
        // "Checked in · next check-in 12:42 AM" — grey, never green.
        if let next = state.nextCheckInAt {
          (Text("\(CurfewCountdownCopy.checkedInPrefix)\(CurfewCountdownCopy.separator)")
            + Text("\(CurfewCountdownCopy.nextCheckInPrefix) ")
            + Text(next, style: .time))
            .font(.headline)
            .foregroundStyle(CurfewCountdownPalette.textSecondary)
        } else {
          Text(CurfewCountdownCopy.checkedInPrefix)
            .font(.headline)
            .foregroundStyle(CurfewCountdownPalette.textSecondary)
        }

      case .ride:
        Text(CurfewCopy.safeRidePromise(guardianName: context.attributes.guardianName))
          .font(.headline)
          .foregroundStyle(CurfewCountdownPalette.textPrimary)
        Text(CurfewCountdownCopy.rideDetail)
          .font(.footnote)
          .foregroundStyle(CurfewCountdownPalette.textSecondary)
      }
    }
    .monospacedDigit()
    .multilineTextAlignment(.leading)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The trailing slot: a live timer where there is something to count down
/// to, otherwise a short word. Same view in the compact island, the expanded
/// island, and the banner; only the font changes.
struct CurfewCompactTrailing: View {
  let state: CurfewCountdownAttributes.ContentState

  var body: some View {
    Group {
      switch state.phase {
      case .beforeCurfew:
        CurfewTimerText(until: state.curfewAt)
          .foregroundStyle(CurfewCountdownPalette.textPrimary)
      case .grace:
        Text(state.curfewAt, style: .time)
          .foregroundStyle(CurfewCountdownPalette.textPrimary)
      case .checkInDue:
        Text(CurfewCountdownCopy.compactCheckIn)
          .foregroundStyle(CurfewCountdownPalette.accent)
      case .checkedIn:
        if let next = state.nextCheckInAt {
          CurfewTimerText(until: next)
            .foregroundStyle(CurfewCountdownPalette.textSecondary)
        } else {
          Text(CurfewCountdownCopy.checkedInPrefix)
            .foregroundStyle(CurfewCountdownPalette.textSecondary)
        }
      case .ride:
        Text(CurfewCountdownCopy.compactRide)
          .foregroundStyle(CurfewCountdownPalette.textPrimary)
      }
    }
    .monospacedDigit()
    .lineLimit(1)
  }
}

/// A countdown that stops at 0:00 instead of counting back up. The compact
/// island gives timers unbounded width, so this one is capped and
/// right-aligned (verify the width on a device with hours showing).
struct CurfewTimerText: View {
  let until: Date

  var body: some View {
    // A closed range must not run backwards; a target already behind us
    // simply shows 0:00.
    let start = min(Date(), until)
    Text(timerInterval: start...until, countsDown: true)
      .multilineTextAlignment(.trailing)
      .frame(maxWidth: 64, alignment: .trailing)
  }
}

/// One glyph per phase for the compact and minimal island. Orange only while
/// a check-in is due, matching the call to action.
struct CurfewPhaseGlyph: View {
  let phase: CurfewCountdownAttributes.Phase

  var body: some View {
    Image(systemName: symbolName)
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(
        phase == .checkInDue ? CurfewCountdownPalette.accent : CurfewCountdownPalette.textPrimary
      )
      .accessibilityLabel(accessibilityLabel)
  }

  private var symbolName: String {
    switch phase {
    case .beforeCurfew, .grace, .checkedIn: "house"
    case .checkInDue: "exclamationmark.circle.fill"
    case .ride: "car.fill"
    }
  }

  private var accessibilityLabel: String {
    switch phase {
    case .beforeCurfew, .grace: CurfewCountdownCopy.homeByPrefix
    case .checkInDue: CurfewCopy.shieldTitle
    case .checkedIn: CurfewCountdownCopy.checkedInPrefix
    case .ride: CurfewCountdownCopy.compactRide
    }
  }
}

extension CurfewCountdownAttributes.Phase {
  /// Whether the banner's trailing slot has a timer or time worth the room.
  var showsTrailingTimer: Bool {
    switch self {
    case .beforeCurfew, .grace, .checkedIn: true
    case .checkInDue, .ride: false
    }
  }
}

// MARK: - Previews

#if DEBUG
#Preview("Lock Screen", as: .content, using: CurfewCountdownAttributes.preview) {
  CurfewCountdownWidget()
} contentStates: {
  CurfewCountdownAttributes.previewState(.beforeCurfew)
  CurfewCountdownAttributes.previewState(.grace)
  CurfewCountdownAttributes.previewState(.checkInDue)
  CurfewCountdownAttributes.previewState(.checkedIn)
  CurfewCountdownAttributes.previewState(.ride)
}

#Preview("Island · compact", as: .dynamicIsland(.compact), using: CurfewCountdownAttributes.preview) {
  CurfewCountdownWidget()
} contentStates: {
  CurfewCountdownAttributes.previewState(.beforeCurfew)
  CurfewCountdownAttributes.previewState(.checkInDue)
  CurfewCountdownAttributes.previewState(.checkedIn)
}

#Preview("Island · expanded", as: .dynamicIsland(.expanded), using: CurfewCountdownAttributes.preview) {
  CurfewCountdownWidget()
} contentStates: {
  CurfewCountdownAttributes.previewState(.beforeCurfew)
  CurfewCountdownAttributes.previewState(.checkInDue)
  CurfewCountdownAttributes.previewState(.ride)
}
#endif
