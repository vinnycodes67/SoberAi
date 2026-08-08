import SwiftUI

/// The app shell.
///
/// Three destinations in a public build — Home, History, Settings — and a
/// fourth, Circle, only in an internal one. `DSTab.available` is what the bar
/// iterates, so a public build has no way to reach a destination that does not
/// exist rather than showing a tab that leads nowhere.
struct RootTabView: View {
  @EnvironmentObject private var model: AppModel
  @State private var tab: DSTab = .home

  var body: some View {
    // `safeAreaInset` rather than a ZStack overlay. Overlaying the bar left it
    // sitting under the home indicator and let scroll content run beneath it;
    // as an inset, SwiftUI both keeps the bar clear of the safe area and insets
    // the scrolling content behind it automatically.
    Group {
      switch tab {
      case .home:
        HomeView()
      case .history:
        HistoryView()
      case .settings:
        SettingsView()
      case .circle:
        circleDestination
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DSPalette.background.ignoresSafeArea())
    .safeAreaInset(edge: .bottom, spacing: 0) {
      DSTabBar(selection: $tab)
        .padding(.top, DSSpace.xs)
    }
    .preferredColorScheme(.dark)
  }

  @ViewBuilder
  private var circleDestination: some View {
    #if INTERNAL_BUILD
    CircleMapView()
      .environmentObject(model)
    #else
    // Unreachable: `DSTab.available` omits `.circle` in a public build. Present
    // so the switch stays exhaustive without weakening the enum.
    HomeView()
    #endif
  }
}
