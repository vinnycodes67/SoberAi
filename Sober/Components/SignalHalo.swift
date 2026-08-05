import SwiftUI

/// Sober's signature: a steady horizon cutting through a living gaze path.
/// It communicates "pause and orient" without implying a pass/fail gauge.
struct SignalHalo: View {
  var tone: Color = Palette.primary
  var size: CGFloat = 210
  var isActive = true

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion || !isActive)) {
      timeline in
      let phase = reduceMotion ? 0.22 : timeline.date.timeIntervalSinceReferenceDate

      Canvas { context, canvasSize in
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let radius = min(canvasSize.width, canvasSize.height) * 0.40
        let pulse = reduceMotion ? 0.5 : (sin(phase * 1.35) + 1) / 2

        let fieldRect = CGRect(
          x: center.x - radius * 1.18,
          y: center.y - radius * 1.18,
          width: radius * 2.36,
          height: radius * 2.36
        )
        context.fill(
          Path(ellipseIn: fieldRect),
          with: .radialGradient(
            Gradient(colors: [
              tone.opacity(0.11 + pulse * 0.025),
              tone.opacity(0.025),
              Color.clear,
            ]),
            center: center,
            startRadius: 0,
            endRadius: radius * 1.18
          )
        )

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

        var activeArc = Path()
        activeArc.addArc(
          center: center,
          radius: radius,
          startAngle: .degrees(-36 + phase * 10),
          endAngle: .degrees(42 + phase * 10),
          clockwise: false
        )
        context.stroke(
          activeArc,
          with: .linearGradient(
            Gradient(colors: [Color.clear, tone.opacity(0.9), Color.clear]),
            startPoint: CGPoint(x: center.x - radius, y: center.y - radius),
            endPoint: CGPoint(x: center.x + radius, y: center.y + radius)
          ),
          style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
        )

        var horizon = Path()
        horizon.move(to: CGPoint(x: center.x - radius - 18, y: center.y))
        horizon.addLine(to: CGPoint(x: center.x + radius + 18, y: center.y))
        context.stroke(horizon, with: .color(Palette.textPrimary.opacity(0.36)), lineWidth: 1)

        let angle = phase.truncatingRemainder(dividingBy: 4.8) / 4.8 * (.pi * 2)
        let orbit = radius - 1
        for trailIndex in 1...5 {
          let trailAngle = angle - Double(trailIndex) * 0.075
          let trailDot = CGPoint(
            x: center.x + cos(trailAngle) * orbit,
            y: center.y + sin(trailAngle) * orbit * 0.58
          )
          let trailSize = CGFloat(6 - trailIndex) * 0.62
          context.fill(
            Path(
              ellipseIn: CGRect(
                x: trailDot.x - trailSize / 2,
                y: trailDot.y - trailSize / 2,
                width: trailSize,
                height: trailSize
              )
            ),
            with: .color(tone.opacity(Double(6 - trailIndex) * 0.075))
          )
        }

        let dot = CGPoint(
          x: center.x + cos(angle) * orbit,
          y: center.y + sin(angle) * orbit * 0.58
        )
        let glowSize = 20 + pulse * 6
        let glowRect = CGRect(
          x: dot.x - glowSize / 2,
          y: dot.y - glowSize / 2,
          width: glowSize,
          height: glowSize
        )
        context.fill(Path(ellipseIn: glowRect), with: .color(tone.opacity(0.12 + pulse * 0.08)))
        context.fill(
          Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)),
          with: .color(tone)
        )

        context.fill(
          Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)),
          with: .color(Palette.textPrimary.opacity(0.62))
        )
      }
    }
    .frame(width: size, height: size)
    .shadow(color: tone.opacity(0.16), radius: 24)
    .accessibilityHidden(true)
  }
}
