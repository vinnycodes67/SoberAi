import SwiftUI

/// The app shell.
///
/// Three destinations in a public build — Home, History, Settings — and a
/// fourth, Circle, only in an internal one. `DSTab.available` is what the bar
/// iterates, so a public build has no way to reach a destination that does not
/// exist rather than showing a tab that leads nowhere.
struct RootTabView: View {
  @EnvironmentObject private var model: AppModel
  @State private var tab: DSTab = RootTabView.initialTab

  /// Debug builds accept `-sober-initial-tab <name>` so a UI test or a manual
  /// pass can land directly on a destination instead of driving taps to reach
  /// it. Never compiled into a Release build, and it can only select a tab the
  /// build actually has.
  static var initialTab: DSTab {
    #if DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    if let flagIndex = arguments.firstIndex(of: "-sober-initial-tab"),
      let raw = arguments[safe: flagIndex + 1],
      let requested = DSTab(rawValue: raw),
      DSTab.available.contains(requested)
    {
      return requested
    }
    #endif
    return .home
  }

  var body: some View {
    // `safeAreaInset` rather than a ZStack overlay. Overlaying the bar left it
    // sitting under the home indicator and let scroll content run beneath it;
    // as an inset, SwiftUI both keeps the bar clear of the safe area and insets
    // the scrolling content behind it automatically.
    destination
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DSPalette.background.ignoresSafeArea())
    .safeAreaInset(edge: .bottom, spacing: 0) {
      DSTabBar(selection: tabSelection)
        .padding(.top, DSSpace.xs)
    }
    .preferredColorScheme(.dark)
    .onChange(of: model.privacyLockIsLocked) { _, isLocked in
      if isLocked { requestUnlockForSelectedTab() }
    }
  }

  @ViewBuilder
  private var destination: some View {
    if tab.requiresPrivacyLock && model.privacyShieldIsVisible {
      PrivacySnapshotShield()
    } else if tab.requiresPrivacyLock && model.privacyLockIsLocked {
      PrivacyLockGateView(
        isAuthenticating: model.privacyLockIsAuthenticating,
        error: model.privacyLockError,
        onUnlock: { Task { await model.unlockProtectedContent() } },
        onHome: { tab = .home }
      )
    } else {
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
  }

  private var tabSelection: Binding<DSTab> {
    Binding(
      get: { tab },
      set: { destination in
        tab = destination
        requestUnlockForSelectedTab()
      }
    )
  }

  private func requestUnlockForSelectedTab() {
    guard tab.requiresPrivacyLock, model.privacyLockIsLocked else { return }
    Task { await model.unlockProtectedContent() }
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

/// 0.5-second shape: one quiet lock, one sentence, one unlock action.
/// User: someone returning to private history or settings.
/// Emotional intent: calm control, with a clear path back to Home.
private struct PrivacyLockGateView: View {
  let isAuthenticating: Bool
  let error: String?
  let onUnlock: () -> Void
  let onHome: () -> Void

  var body: some View {
    VStack(spacing: DSSpace.xl) {
      Spacer(minLength: DSSpace.xl)

      VStack(spacing: DSSpace.md) {
        Image(systemName: "lock.fill")
          .font(.system(size: 30, weight: .medium))
          .foregroundStyle(DSPalette.textSecondary)
          .accessibilityHidden(true)

        Text("Private screen locked")
          .font(DSFont.title)
          .dsTitleTracking()
          .foregroundStyle(DSPalette.textPrimary)
          .accessibilityAddTraits(.isHeader)

        Text("Use Face ID, Touch ID, or your device passcode. Home and safety actions stay available without unlocking.")
          .font(DSFont.body)
          .foregroundStyle(DSPalette.textSecondary)
          .multilineTextAlignment(.center)
          .dsReadingLine()
          .fixedSize(horizontal: false, vertical: true)
      }

      if let error {
        Text(error)
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textSecondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(spacing: DSSpace.sm) {
        Button(action: onUnlock) {
          if isAuthenticating {
            ProgressView()
              .tint(DSPalette.onAccent)
              .accessibilityLabel("Waiting for iOS verification")
          } else {
            Text("Unlock private screens")
          }
        }
        .buttonStyle(DSPrimaryButtonStyle())
        .disabled(isAuthenticating)

        Button("Go to Home", action: onHome)
          .buttonStyle(DSTertiaryButtonStyle(tint: DSPalette.textSecondary))
      }

      Spacer(minLength: DSSpace.xl)
    }
    .frame(maxWidth: 520)
    .padding(.horizontal, DSSpace.margin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DSPalette.background.ignoresSafeArea())
  }
}

/// Opaque app-switcher snapshot cover for private destinations. It appears as
/// soon as the scene becomes inactive, before the authentication timeout.
private struct PrivacySnapshotShield: View {
  var body: some View {
    VStack(spacing: DSSpace.sm) {
      Image(systemName: "lock.fill")
        .font(.system(size: 22, weight: .medium))
      Text("Sober")
        .font(DSFont.headline)
    }
    .foregroundStyle(DSPalette.textSecondary)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DSPalette.background.ignoresSafeArea())
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Private Sober screen hidden")
  }
}

extension Array {
  /// Bounds-checked subscript, used only for reading a launch argument's value.
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
