import SwiftUI

@main
struct SoberApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(model)
        .preferredColorScheme(.dark)
        .tint(Palette.primary)
    }
  }
}

struct RootView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      if model.hasCompletedOnboarding {
        HomeView()
      } else {
        OnboardingView()
      }
    }
    .animation(reduceMotion ? nil : SoberMotion.screen, value: model.hasCompletedOnboarding)
  }
}
