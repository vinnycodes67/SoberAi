import SwiftUI

@main
struct SoberApp: App {
  @StateObject private var model: AppModel

  init() {
    #if INTERNAL_BUILD
    // Before anything else: a background relaunch for the Curfew home region
    // never builds a scene, so the region delegate must exist by the end of
    // launch or the arrival home is lost (Services/Curfew/HomeRegion).
    CurfewBackgroundLaunch.prepare()
    #endif
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
  /// The launch mark is fading out. Separate from `isShowingLaunch` because
  /// the fade is a plain property animation on a view that stays put: as a
  /// removal transition it was dropped intermittently and the mark cut away.
  @State private var isLaunchLeaving = false
  /// Opens as the fade starts. The first screen arrives just after the mark
  /// has lifted: overlapping them put the fading wordmark on top of the
  /// incoming headline, which read as muddy rather than smooth.
  @State private var firstScreenMayReveal = false
  /// The first screen mounts just after the launch mark's first frame, so
  /// building it never delays the mark itself, and is ready well before the
  /// handoff.
  @State private var isFirstScreenMounted = false

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
      DSPalette.background.ignoresSafeArea()

      // Built from the first frame, underneath the launch mark. Creating the
      // first screen at the moment of handoff stalled the main thread long
      // enough to swallow the dissolve, so the mark cut instead of fading.
      // Its `soberReveal` elements wait for `soberLaunchFinished`.
      if isFirstScreenMounted || !isShowingLaunch {
        rootContent
          .environment(\.soberLaunchFinished, !isShowingLaunch || firstScreenMayReveal)
          .accessibilityHidden(isShowingLaunch && !firstScreenMayReveal)
      }

      if isShowingLaunch {
        SoberLaunchView(isLeaving: isLaunchLeaving, onFinished: finishLaunch)
          .zIndex(1)
      }
    }
    .animation(reduceMotion ? nil : SoberMotion.screen, value: model.hasCompletedOnboarding)
    .task {
      guard isShowingLaunch else { return }
      try? await Task.sleep(for: .milliseconds(120))
      isFirstScreenMounted = true
    }
    // Reduce Motion decides which eye task a check runs, and so which baseline
    // readiness counts.
    .onChange(of: reduceMotion, initial: true) { _, enabled in
      model.setReduceMotion(enabled)
    }
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
    guard isShowingLaunch, !firstScreenMayReveal else { return }
    firstScreenMayReveal = true
    // A symmetric ease, not the reveal curve: that curve's long tail left a
    // faint blurred wordmark hanging over the first screen.
    let fade = reduceMotion ? 0.2 : 0.38
    Task { @MainActor in
      withAnimation(.easeInOut(duration: fade)) {
        isLaunchLeaving = true
      }
      try? await Task.sleep(for: .seconds(fade + 0.05))
      isShowingLaunch = false
    }
  }
}

/// A single matte brand reveal. The wordmark comes into focus, its accent
/// line draws out from the centre, the tagline follows, and then the whole mark
/// dissolves while the first screen builds in underneath. About a second end
/// to end; a tap skips it. Reduce Motion shortens it to a brief plain fade.
private struct SoberLaunchView: View {
  let isLeaving: Bool
  let onFinished: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var wordmarkVisible = false
  @State private var lineDrawn = false
  @State private var taglineVisible = false

  var body: some View {
    Button(action: onFinished) {
      ZStack {
        DSPalette.background.ignoresSafeArea()

        VStack(spacing: DSSpace.sm) {
          Text("Sober")
            .font(DSFont.hero)
            .dsHeroTracking()
            .foregroundStyle(DSPalette.textPrimary)
            .opacity(wordmarkVisible ? 1 : 0)
            .blur(radius: wordmarkVisible || reduceMotion ? 0 : 8)
            .offset(y: wordmarkVisible || reduceMotion ? 0 : 6)

          Capsule(style: .continuous)
            .fill(DSPalette.accent)
            .frame(width: 34, height: 3)
            .scaleEffect(x: lineDrawn ? 1 : 0.001, y: 1)
            .opacity(lineDrawn ? 1 : 0)

          Text("PRIVATE CHECK. SAFER WAY HOME.")
            .font(DSFont.caption)
            .tracking(0.7)
            .foregroundStyle(DSPalette.textMuted)
            .opacity(taglineVisible ? 1 : 0)
            .offset(y: taglineVisible || reduceMotion ? 0 : 4)
        }
        // Leaving: the mark grows a touch and softens as the layer fades, so it
        // reads as dissolving into the first screen rather than being cut.
        .scaleEffect(isLeaving && !reduceMotion ? 1.06 : 1)
        .blur(radius: isLeaving && !reduceMotion ? 8 : 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(DSSpace.lg)
      .contentShape(Rectangle())
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .buttonStyle(.plain)
    .background(DSPalette.background)
    .opacity(isLeaving ? 0 : 1)
    .allowsHitTesting(!isLeaving)
    .task {
      if reduceMotion {
        withAnimation(.easeOut(duration: 0.2)) {
          wordmarkVisible = true
          lineDrawn = true
          taglineVisible = true
        }
        try? await Task.sleep(for: .seconds(0.35))
      } else {
        withAnimation(SoberMotion.reveal(duration: 0.6)) { wordmarkVisible = true }
        withAnimation(SoberMotion.reveal(duration: 0.55, delay: 0.18)) { lineDrawn = true }
        withAnimation(SoberMotion.reveal(duration: 0.5, delay: 0.3)) { taglineVisible = true }
        try? await Task.sleep(for: .seconds(0.8))
      }
      guard !Task.isCancelled else { return }
      onFinished()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Sober")
    .accessibilityHint("Double-tap to continue.")
  }
}
