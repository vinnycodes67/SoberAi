import SwiftUI

/// Sober's signature: a steady horizon cutting through a living gaze path.
/// It communicates "pause and orient" without implying a pass/fail gauge.
struct SignalHalo: View {
  var tone: Color = Palette.primary
  var size: CGFloat = 210
  var isActive = true

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isActive)) {
      timeline in
      let phase = reduceMotion ? 0.22 : timeline.date.timeIntervalSinceReferenceDate

      Canvas { context, canvasSize in
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let radius = min(canvasSize.width, canvasSize.height) * 0.40

        for index in 0..<3 {
          let inset = CGFloat(index) * 18
          let rect = CGRect(
            x: center.x - radius + inset,
            y: center.y - radius + inset,
            width: (radius - inset) * 2,
            height: (radius - inset) * 2
          )
          context.stroke(
            Path(ellipseIn: rect),
            with: .color(tone.opacity(index == 0 ? 0.34 : 0.16)),
            style: StrokeStyle(lineWidth: index == 0 ? 1.5 : 1, dash: index == 1 ? [3, 7] : [])
          )
        }

        var horizon = Path()
        horizon.move(to: CGPoint(x: center.x - radius - 18, y: center.y))
        horizon.addLine(to: CGPoint(x: center.x + radius + 18, y: center.y))
        context.stroke(horizon, with: .color(Palette.textPrimary.opacity(0.36)), lineWidth: 1)

        let angle = phase.truncatingRemainder(dividingBy: 4.8) / 4.8 * (.pi * 2)
        let orbit = radius - 1
        let dot = CGPoint(
          x: center.x + cos(angle) * orbit,
          y: center.y + sin(angle) * orbit * 0.58
        )
        let glowRect = CGRect(x: dot.x - 11, y: dot.y - 11, width: 22, height: 22)
        context.fill(Path(ellipseIn: glowRect), with: .color(tone.opacity(0.16)))
        context.fill(
          Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)),
          with: .color(tone)
        )
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
