import SwiftUI

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

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(18)
      .background(
        Palette.cardBackground.opacity(0.94),
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(Palette.secondary.opacity(0.18), lineWidth: 1)
      }
  }
}

struct PrimaryActionButtonStyle: ButtonStyle {
  var tint: Color = Palette.primary

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 54)
      .foregroundStyle(Palette.textPrimary)
      .background(
        tint.opacity(configuration.isPressed ? 0.72 : 1),
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
  }
}

struct SecondaryActionButtonStyle: ButtonStyle {
  var tint: Color = Palette.primary

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 52)
      .foregroundStyle(tint)
      .background(
        tint.opacity(configuration.isPressed ? 0.16 : 0.08),
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(tint.opacity(0.46), lineWidth: 1)
      }
  }
}

struct StepProgress: View {
  let current: Int
  let total: Int

  var body: some View {
    HStack(spacing: 6) {
      ForEach(0..<total, id: \.self) { index in
        Capsule()
          .fill(index <= current ? Palette.primary : Palette.secondary.opacity(0.24))
          .frame(height: 4)
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

extension View {
  func soberBackground() -> some View {
    background(Palette.backgroundGradient.ignoresSafeArea())
  }
}
