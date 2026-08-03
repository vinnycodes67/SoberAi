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

  var body: some View {
    Group {
      if model.hasCompletedOnboarding {
        HomeView()
      } else {
        OnboardingView()
      }
    }
    .animation(.easeInOut(duration: 0.35), value: model.hasCompletedOnboarding)
  }
}
