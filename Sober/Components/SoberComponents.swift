import SwiftUI

enum SoberMotion {
  static let press = Animation.spring(duration: 0.24, bounce: 0.08)
  static let progress = Animation.spring(duration: 0.42, bounce: 0.10)
  static let screen = Animation.spring(duration: 0.56, bounce: 0.06)

  static func entrance(order: Int) -> Animation {
    screen.delay(min(Double(order) * 0.055, 0.28))
  }
}

struct SoberWordmark: View {
  var body: some View {
    Text("sober.")
      .font(.system(.title2, design: .serif, weight: .semibold))
      .tracking(-0.7)
      .foregroundStyle(Palette.textPrimary)
      .accessibilityAddTraits(.isHeader)
  }
}

struct SoberCard<Content: View>: View {
  @ViewBuilder let content: Content

  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(18)
      .background {
        cardBackground
      }
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(
            LinearGradient(
              colors: [
                Palette.textPrimary.opacity(0.14),
                Palette.secondary.opacity(0.08),
                Palette.primary.opacity(0.14),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 1
          )
      }
      .shadow(color: Color.black.opacity(0.20), radius: 18, y: 10)
  }

  @ViewBuilder
  private var cardBackground: some View {
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    if reduceTransparency {
      shape.fill(Palette.cardBackground)
    } else {
      shape
        .fill(.thinMaterial)
        .overlay {
          shape.fill(Palette.cardBackground.opacity(0.70))
        }
    }
  }
}

struct PrimaryActionButtonStyle: ButtonStyle {
  var tint: Color = Palette.primary

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  @ViewBuilder
  func makeBody(configuration: Configuration) -> some View {
    if #available(iOS 26.0, *) {
      label(configuration)
        .glassEffect(
          .regular.tint(tint).interactive(),
          in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    } else {
      label(configuration)
        .background {
          let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
          if reduceTransparency {
            shape.fill(tint)
          } else {
            shape
              .fill(.ultraThinMaterial)
              .overlay {
                shape.fill(tint.opacity(0.88))
              }
          }
        }
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Palette.textPrimary.opacity(0.16), lineWidth: 1)
        }
        .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.976)
        .brightness(configuration.isPressed ? -0.06 : 0)
        .animation(reduceMotion ? nil : SoberMotion.press, value: configuration.isPressed)
    }
  }

  private func label(_ configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 54)
      .foregroundStyle(Palette.textPrimary)
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

struct SecondaryActionButtonStyle: ButtonStyle {
  var tint: Color = Palette.primary

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  @ViewBuilder
  func makeBody(configuration: Configuration) -> some View {
    if #available(iOS 26.0, *) {
      label(configuration)
        .glassEffect(
          .regular.interactive(),
          in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    } else {
      label(configuration)
        .background {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
              reduceTransparency
                ? Palette.cardBackground : tint.opacity(configuration.isPressed ? 0.16 : 0.08)
            )
        }
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(tint.opacity(0.46), lineWidth: 1)
        }
        .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.978)
        .animation(reduceMotion ? nil : SoberMotion.press, value: configuration.isPressed)
    }
  }

  private func label(_ configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 52)
      .foregroundStyle(tint)
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

struct SoberCardButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.986)
      .brightness(configuration.isPressed ? 0.035 : 0)
      .animation(reduceMotion ? nil : SoberMotion.press, value: configuration.isPressed)
  }
}

struct SoberGlassControlGroup<Content: View>: View {
  let spacing: CGFloat
  @ViewBuilder let content: Content

  init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }

  @ViewBuilder
  var body: some View {
    if #available(iOS 26.0, *) {
      GlassEffectContainer(spacing: spacing) {
        content
      }
    } else {
      content
    }
  }
}

struct StepProgress: View {
  let current: Int
  let total: Int

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 6) {
      ForEach(0..<total, id: \.self) { index in
        Capsule()
          .fill(index <= current ? Palette.primary : Palette.secondary.opacity(0.24))
          .frame(height: 4)
          .scaleEffect(x: index <= current ? 1 : 0.82, anchor: .leading)
          .animation(
            reduceMotion ? nil : SoberMotion.progress.delay(Double(index) * 0.025),
            value: current
          )
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Step \(current + 1) of \(total)")
  }
}

struct ScreenHeader: View {
  let eyebrow: String
  let title: String
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(eyebrow.uppercased())
        .font(.caption.weight(.semibold))
        .tracking(1.4)
        .foregroundStyle(Palette.primary)
      Text(title)
        .font(.system(.largeTitle, design: .serif, weight: .semibold))
        .tracking(-1.1)
        .foregroundStyle(Palette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      Text(detail)
        .font(.body)
        .foregroundStyle(Palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct PrototypeBadge: View {
  var body: some View {
    Text("FOUNDER PROTOTYPE")
      .font(.caption2.weight(.bold))
      .tracking(1.2)
      .foregroundStyle(Palette.warning)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Palette.warning.opacity(0.1), in: Capsule())
      .overlay { Capsule().stroke(Palette.warning.opacity(0.34), lineWidth: 1) }
  }
}

private struct SoberEntranceModifier: ViewModifier {
  let order: Int

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isVisible = false

  func body(content: Content) -> some View {
    content
      .opacity(isVisible ? 1 : 0)
      .offset(y: reduceMotion || isVisible ? 0 : 10)
      .scaleEffect(reduceMotion || isVisible ? 1 : 0.992, anchor: .top)
      .onAppear {
        guard !isVisible else { return }
        if reduceMotion {
          isVisible = true
        } else {
          withAnimation(SoberMotion.entrance(order: order)) {
            isVisible = true
          }
        }
      }
  }
}

private struct SoberGlassCircleModifier: ViewModifier {
  let tint: Color?

  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      if let tint {
        content.glassEffect(.regular.tint(tint).interactive(), in: Circle())
      } else {
        content.glassEffect(.regular.interactive(), in: Circle())
      }
    } else {
      content
        .background {
          Circle()
            .fill(reduceTransparency ? Palette.cardBackground : Palette.cardBackground.opacity(0.68))
            .background(.ultraThinMaterial, in: Circle())
        }
        .overlay {
          Circle().stroke(Palette.textPrimary.opacity(0.16), lineWidth: 1)
        }
    }
  }
}

private struct SoberGlassCapsuleModifier: ViewModifier {
  let tint: Color?

  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      if let tint {
        content.glassEffect(.regular.tint(tint), in: Capsule())
      } else {
        content.glassEffect(.regular, in: Capsule())
      }
    } else {
      content
        .background {
          Capsule()
            .fill(reduceTransparency ? Palette.cardBackground : Palette.cardBackground.opacity(0.66))
            .background(.ultraThinMaterial, in: Capsule())
        }
        .overlay {
          Capsule().stroke(Palette.textPrimary.opacity(0.16), lineWidth: 1)
        }
    }
  }
}

private struct SoberAmbientBackground: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    TimelineView(
      .animation(
        minimumInterval: 1.0 / 18.0,
        paused: reduceMotion || reduceTransparency || scenePhase != .active
      )
    ) { timeline in
      GeometryReader { proxy in
        let phase = reduceMotion || reduceTransparency
          ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
        let width = proxy.size.width
        let height = proxy.size.height

        ZStack {
          Palette.backgroundGradient

          ambientOrb(
            color: Palette.primary,
            diameter: max(width * 1.08, 360),
            x: width * (0.18 + sin(phase / 11) * 0.07),
            y: height * (0.12 + cos(phase / 13) * 0.035),
            opacity: reduceTransparency ? 0 : 0.16
          )

          ambientOrb(
            color: Palette.item3,
            diameter: max(width * 0.92, 310),
            x: width * (0.88 + cos(phase / 14) * 0.06),
            y: height * (0.74 + sin(phase / 12) * 0.045),
            opacity: reduceTransparency ? 0 : 0.10
          )

          LinearGradient(
            colors: [Color.clear, Palette.surface.opacity(0.42)],
            startPoint: .top,
            endPoint: .bottom
          )
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func ambientOrb(
    color: Color,
    diameter: CGFloat,
    x: CGFloat,
    y: CGFloat,
    opacity: Double
  ) -> some View {
    Circle()
      .fill(
        RadialGradient(
          colors: [color.opacity(opacity), color.opacity(opacity * 0.34), Color.clear],
          center: .center,
          startRadius: 0,
          endRadius: diameter / 2
        )
      )
      .frame(width: diameter, height: diameter)
      .position(x: x, y: y)
      .blur(radius: 24)
  }
}

extension View {
  func soberBackground() -> some View {
    background {
      SoberAmbientBackground()
        .ignoresSafeArea()
    }
  }

  func soberEntrance(order: Int = 0) -> some View {
    modifier(SoberEntranceModifier(order: order))
  }

  func soberGlassCircle(tint: Color? = nil) -> some View {
    modifier(SoberGlassCircleModifier(tint: tint))
  }

  func soberGlassCapsule(tint: Color? = nil) -> some View {
    modifier(SoberGlassCapsuleModifier(tint: tint))
  }
}
