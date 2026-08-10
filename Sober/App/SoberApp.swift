import SwiftUI

@main
struct SoberApp: App {
  @StateObject private var model: AppModel

  init() {
    #if DEBUG
    if let fixtureModel = UITestConfiguration.makeModel() {
      _model = StateObject(wrappedValue: fixtureModel)
      return
    }
    UITestLaunchConfiguration.current.prepare()
    #endif
    _model = StateObject(wrappedValue: AppModel())
  }

  var body: some Scene {
    WindowGroup {
      appContent
    }
  }

  @ViewBuilder
  private var appContent: some View {
    #if DEBUG
    RootView()
      .environmentObject(model)
      .modifier(UITestEnvironmentModifier(configuration: .current))
      .preferredColorScheme(.dark)
      .tint(DSPalette.accent)
    #else
    RootView()
      .environmentObject(model)
      .preferredColorScheme(.dark)
      .tint(DSPalette.accent)
    #endif
  }
}

struct RootView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var isShowingLaunch: Bool

  init() {
    #if DEBUG
    _isShowingLaunch = State(
      initialValue: !UITestConfiguration.isActive
        && !UITestLaunchConfiguration.current.isActive
    )
    #else
    _isShowingLaunch = State(initialValue: true)
    #endif
  }

  var body: some View {
    ZStack {
      if isShowingLaunch {
        SoberLaunchView(onFinished: finishLaunch)
          .transition(.opacity)
          .zIndex(1)
      } else {
        rootContent
        .transition(.opacity)
      }
    }
    .animation(reduceMotion ? nil : SoberMotion.screen, value: model.hasCompletedOnboarding)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: isShowingLaunch)
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        model.privacySceneBecameActive()
      case .inactive:
        model.privacySceneBecameInactive()
      case .background:
        model.privacySceneEnteredBackground()
      @unknown default:
        model.privacySceneBecameInactive()
      }
    }
  }

  @ViewBuilder
  private var rootContent: some View {
    #if DEBUG
    if let destination = UITestLaunchConfiguration.current.directDestination {
      UITestFixtureView(destination: destination)
    } else if model.hasCompletedOnboarding {
      RootTabView()
    } else {
      OnboardingView()
    }
    #else
    if model.hasCompletedOnboarding {
      RootTabView()
    } else {
      OnboardingView()
    }
    #endif
  }

  private func finishLaunch() {
    guard isShowingLaunch else { return }
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.14)) {
      isShowingLaunch = false
    }
  }
}

/// A single matte brand reveal. It yields to the real first screen in 420 ms,
/// with another 140 ms for the root crossfade, keeping cold-start choreography
/// below the 600 ms product limit.
private struct SoberLaunchView: View {
  let onFinished: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isRevealed = false

  var body: some View {
    Button(action: onFinished) {
      ZStack {
        DSPalette.background.ignoresSafeArea()

        VStack(spacing: DSSpace.sm) {
          Text("Sober")
            .font(DSFont.hero)
            .dsHeroTracking()
            .foregroundStyle(DSPalette.textPrimary)

          Capsule(style: .continuous)
            .fill(DSPalette.accent)
            .frame(width: 34, height: 3)

          Text("PRIVATE CHECK. SAFER WAY HOME.")
            .font(DSFont.caption)
            .tracking(0.7)
            .foregroundStyle(DSPalette.textMuted)
        }
        .opacity(isRevealed ? 1 : 0)
        .scaleEffect(reduceMotion || isRevealed ? 1 : 0.985)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(DSSpace.lg)
      .contentShape(Rectangle())
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .buttonStyle(.plain)
    .background(DSPalette.background)
    .onAppear {
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
        isRevealed = true
      }
    }
    .task {
      let duration = reduceMotion ? 0.12 : 0.42
      try? await Task.sleep(for: .seconds(duration))
      guard !Task.isCancelled else { return }
      onFinished()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Sober")
    .accessibilityHint("Double-tap to continue.")
  }
}
