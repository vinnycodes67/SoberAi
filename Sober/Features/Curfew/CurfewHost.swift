import SwiftUI

/// Mounts Curfew on the root of the internal app: owns the coordinator, feeds
/// it scene and URL events, and presents the check-in sheet.
struct CurfewHostModifier: ViewModifier {
  @StateObject private var coordinator = CurfewCoordinator()
  @EnvironmentObject private var model: AppModel
  @Environment(\.scenePhase) private var scenePhase

  func body(content: Content) -> some View {
    content
      .environmentObject(coordinator)
      .onAppear { coordinator.start() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { coordinator.sceneBecameActive() }
      }
      .onOpenURL { url in coordinator.handle(url: url) }
      .sheet(isPresented: $coordinator.isPresentingCheckIn) {
        CurfewCheckInView()
          .environmentObject(coordinator)
          .environmentObject(model)
          .preferredColorScheme(.dark)
      }
  }
}

extension View {
  func curfewHost() -> some View {
    modifier(CurfewHostModifier())
  }
}
