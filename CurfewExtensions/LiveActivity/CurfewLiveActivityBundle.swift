import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@main
struct CurfewLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    CurfewCountdownWidget()
  }
}

/// The Lock Screen banner and the Dynamic Island for tonight's curfew.
///
/// Matte near-black, white and grey type, and orange in exactly one place: the
/// "Open Sober to check in" call to action while a check-in is due. Checked in
/// is grey. Nothing here says passed, cleared, or safe (the Safe Ride Promise
/// is the feature's name), and nothing here knows a Sober result exists.
///
/// A tap anywhere lands on the check-in through `CurfewNotifications.deepLinkURL`,
/// the same URL the notification and the shield action use.
struct CurfewCountdownWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CurfewCountdownAttributes.self) { context in
      CurfewLockScreenView(context: context)
        .activityBackgroundTint(CurfewCountdownPalette.background)
        .activitySystemActionForegroundColor(CurfewCountdownPalette.textPrimary)
        .widgetURL(CurfewNotifications.deepLinkURL)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          CurfewPhaseGlyph(phase: context.state.phase)
            .font(.title3)
            .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          CurfewCompactTrailing(state: context.state)
            .font(.title3.weight(.medium))
            .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.bottom) {
          CurfewCountdownText(context: context)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
      } compactLeading: {
        CurfewPhaseGlyph(phase: context.state.phase)
          .font(.body)
      } compactTrailing: {
        CurfewCompactTrailing(state: context.state)
          .font(.body.weight(.medium))
      } minimal: {
        CurfewPhaseGlyph(phase: context.state.phase)
          .font(.body)
      }
      .widgetURL(CurfewNotifications.deepLinkURL)
      .keylineTint(
        context.state.phase == .checkInDue
          ? CurfewCountdownPalette.accent
          : CurfewCountdownPalette.textSecondary
      )
    }
  }
}
