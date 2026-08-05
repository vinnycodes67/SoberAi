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
        .preferredColorScheme(.dark)
        .tint(Palette.primary)
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
  @State private var isShowingLaunch = true

  var body: some View {
    ZStack {
      if isShowingLaunch {
        SoberLaunchView(onFinished: finishLaunch)
          .transition(.opacity)
          .zIndex(1)
      } else {
        Group {
          if model.hasCompletedOnboarding {
            HomeView()
          } else {
            OnboardingView()
          }
        }
        .transition(.opacity)
      }
    }
    .animation(reduceMotion ? nil : SoberMotion.screen, value: model.hasCompletedOnboarding)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: isShowingLaunch)
  }

  private func finishLaunch() {
    guard isShowingLaunch else { return }
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
      isShowingLaunch = false
    }
  }
}

/// A short brand reveal adapted from Amos Gyamfi's TypingErasing.swift (Unlicense).
/// 0.5s: a cyan cursor writes “sober” beneath the living signal halo.
private struct SoberLaunchView: View {
  let onFinished: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize = 50.0
  @State private var animationTrigger = false

  var body: some View {
    Button(action: onFinished) {
      VStack(spacing: 22) {
        SignalHalo(size: 168, isActive: !reduceMotion)
          .opacity(0.82)

        typingWordmark

        Text("PRIVATE IMPAIRMENT AWARENESS")
          .font(.caption2.weight(.semibold))
          .tracking(1.4)
          .foregroundStyle(Palette.textSecondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(24)
      .contentShape(Rectangle())
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .buttonStyle(.plain)
    .soberBackground()
    .task {
      let duration = reduceMotion ? 0.55 : 2.7
      try? await Task.sleep(for: .seconds(duration))
      guard !Task.isCancelled else { return }
      onFinished()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Sober AI")
    .accessibilityHint("Loading. Double-tap to continue.")
  }

  @ViewBuilder
  private var typingWordmark: some View {
    if reduceMotion {
      launchLockup(text: "sober ai", showsCursor: false)
    } else {
      PhaseAnimator(SoberTypingPhase.allCases, trigger: animationTrigger) { phase in
        launchLockup(text: phase.text, showsCursor: phase.showsCursor)
      } animation: { phase in
        phase.animation
      }
      .onAppear {
        animationTrigger.toggle()
      }
    }
  }

  private func launchLockup(text: String, showsCursor: Bool) -> some View {
    ZStack(alignment: .leading) {
      Text("sober ai")
        .opacity(0)

      HStack(spacing: 2) {
        Text(text)

        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(Palette.primary)
          .frame(width: 4, height: wordmarkSize * 0.92)
          .opacity(showsCursor ? 1 : 0)
          .shadow(color: Palette.primary.opacity(0.5), radius: 8)
      }
    }
    .font(.system(size: wordmarkSize, weight: .semibold, design: .monospaced))
    .tracking(-2)
    .foregroundStyle(Palette.textPrimary)
    .lineLimit(1)
    .minimumScaleFactor(0.72)
    .accessibilityHidden(true)
  }
}

private enum SoberTypingPhase: CaseIterable, Equatable {
  case empty
  case s
  case so
  case sob
  case sobe
  case sober
  case soberSpace
  case soberA
  case soberAI
  case cursorOff
  case cursorOn
  case eraseI
  case eraseA
  case eraseSpace
  case writeDot
  case finalCursorOff
  case finalHold

  // Triggered phase animators return to their first phase. Keeping the settled
  // wordmark first makes the one-shot sequence finish on “sober.” instead of blank.
  static let allCases: [SoberTypingPhase] = [
    .finalHold,
    .empty,
    .s,
    .so,
    .sob,
    .sobe,
    .sober,
    .soberSpace,
    .soberA,
    .soberAI,
    .cursorOff,
    .cursorOn,
    .eraseI,
    .eraseA,
    .eraseSpace,
    .writeDot,
    .finalCursorOff,
  ]

  var text: String {
    switch self {
    case .empty:
      ""
    case .s:
      "s"
    case .so:
      "so"
    case .sob:
      "sob"
    case .sobe:
      "sobe"
    case .sober, .eraseSpace:
      "sober"
    case .soberSpace, .eraseA:
      "sober "
    case .soberA, .eraseI:
      "sober a"
    case .soberAI, .cursorOff, .cursorOn:
      "sober ai"
    case .writeDot, .finalCursorOff, .finalHold:
      "sober."
    }
  }

  var showsCursor: Bool {
    switch self {
    case .cursorOff, .finalCursorOff, .finalHold:
      false
    default:
      true
    }
  }

  var animation: Animation {
    switch self {
    case .empty:
      .linear(duration: 0.01)
    case .cursorOff, .cursorOn:
      .easeInOut(duration: 0.16)
    case .eraseI, .eraseA, .eraseSpace:
      .easeInOut(duration: 0.10)
    case .writeDot:
      .easeInOut(duration: 0.12)
    case .finalCursorOff:
      .easeInOut(duration: 0.14)
    case .finalHold:
      .linear(duration: 0.28)
    case .s, .so, .sob, .sobe, .sober, .soberSpace, .soberA, .soberAI:
      .easeInOut(duration: 0.08)
    }
  }
}
