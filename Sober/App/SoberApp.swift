import BackgroundTasks
import SwiftUI
import UIKit

@main
struct SoberApp: App {
  @StateObject private var model = AppModel()
  @StateObject private var guardianCoordinator = GuardianCoordinator()
  @UIApplicationDelegateAdaptor(SoberAppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(model)
        .environmentObject(guardianCoordinator)
        // Locked dark. The app is opened at night by someone deciding
        // whether to drive; a light page would be hostile in that moment.
        // This also carries the appearance into system surfaces: alerts,
        // pickers, and the keyboard.
        .preferredColorScheme(.dark)
        .tint(Palette.accent)
        // Every screen inherits the bundled face; anything that slips through
        // without an explicit `SoberType` font still lands on General Sans
        // rather than falling back to the system font.
        .font(SoberType.body)
        .foregroundStyle(Palette.textPrimary)
        .onAppear {
          guardianCoordinator.configure(model: model)
          appDelegate.guardianCoordinator = guardianCoordinator
          if model.guardianRole == .teen {
            guardianCoordinator.startTeenMonitoring()
          } else if model.guardianRole == .parent {
            guardianCoordinator.startParentMonitoring()
          }
        }
    }
  }
}

/// Only exists to register the two OS-level entry points Guardian Mode
/// needs before the app finishes launching: the background catch-up task
/// and remote (CloudKit) push notifications. Nothing else in the app goes
/// through this delegate.
final class SoberAppDelegate: NSObject, UIApplicationDelegate {
  weak var guardianCoordinator: GuardianCoordinator?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GuardianCoordinator.registerBackgroundTask { [weak self] task in
      guard let coordinator = self?.guardianCoordinator else {
        task.setTaskCompleted(success: true)
        return
      }
      Task { @MainActor in
        coordinator.runBackgroundCatchUp(task: task)
      }
    }
    application.registerForRemoteNotifications()
    return true
  }

  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    guard let coordinator = guardianCoordinator else {
      completionHandler(.noData)
      return
    }
    Task { @MainActor in
      await coordinator.handleRemoteNotification()
      completionHandler(.newData)
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
