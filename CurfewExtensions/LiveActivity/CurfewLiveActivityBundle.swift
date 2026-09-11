import ActivityKit
import SwiftUI
import WidgetKit

@main
struct CurfewLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    CurfewCountdownWidget()
  }
}

/// Stub countdown; the Live Activity agent replaces this.
struct CurfewCountdownWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CurfewCountdownAttributes.self) { context in
      Text("\(CurfewCopy.countdownPrefix) \(context.state.curfewAt, style: .time)")
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.curfewAt, style: .timer)
        }
      } compactLeading: {
        Text("Curfew")
      } compactTrailing: {
        Text(context.state.curfewAt, style: .timer)
      } minimal: {
        Text("C")
      }
    }
  }
}
