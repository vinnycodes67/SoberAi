import SwiftUI

/// A precise hairline ring with a symbol at its centre.
///
/// Replaces the old glowing halo. Where that was atmosphere, this is
/// instrumentation: fixed stroke weights, no glow, no gradient, and a tint
/// that only ever encodes state. When `isWorking` is set, a single accent arc
/// sweeps the ring to show the app is busy — the only continuous motion left
/// in the app.
struct StateMark: View {
  let symbol: String
  var tint: Color = Palette.accent
  var size: CGFloat = 96
  var isWorking = false

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var sweep = false

  var body: some View {
    ZStack {
      Circle()
        .stroke(Palette.line, lineWidth: 1)

      // Inner rule, inset — reads as a machined bezel rather than decoration.
      Circle()
        .stroke(Palette.line, lineWidth: 1)
        .padding(size * 0.11)

      if isWorking && !reduceMotion {
        Circle()
          .trim(from: 0, to: 0.18)
          .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
          .rotationEffect(.degrees(sweep ? 360 : 0))
          .animation(
            .linear(duration: 1.4).repeatForever(autoreverses: false),
            value: sweep
          )
      }

      Image(systemName: symbol)
        .font(.system(size: size * 0.28, weight: .light))
        .foregroundStyle(tint)
    }
    .frame(width: size, height: size)
    .onAppear {
      guard isWorking, !reduceMotion, scenePhase == .active else { return }
      sweep = true
    }
    .accessibilityHidden(true)
  }
}
