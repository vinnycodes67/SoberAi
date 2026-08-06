import SwiftUI

// MARK: - Buttons
//
// Five roles, one size system. Every button in the app is one of these; a
// screen with two primaries has no primary.

/// The single most important action on a screen. Filled accent, full width.
struct PrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(SoberType.headline)
      .frame(maxWidth: .infinity)
      .frame(minHeight: Hit.primary)
      .foregroundStyle(Palette.onAccent)
      .background(
        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
          .fill(Palette.accent)
      )
      .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.4)
      .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
  }
}

/// A supporting action. Filled surface, no border.
struct SecondaryButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(SoberType.headline)
      .frame(maxWidth: .infinity)
      .frame(minHeight: Hit.control)
      .foregroundStyle(Palette.textPrimary)
      .background(
        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
          .fill(configuration.isPressed ? Palette.surfaceSecondary : Palette.surface)
      )
      .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
  }
}

/// A low-emphasis action. Text only.
struct TertiaryButtonStyle: ButtonStyle {
  var tint: Color = Palette.accentText

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(SoberType.headline)
      .frame(minHeight: Hit.minimum)
      .foregroundStyle(tint)
      .opacity(configuration.isPressed ? 0.6 : 1)
      .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
  }
}

/// Deleting, resetting, anything unrecoverable.
struct DestructiveButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(SoberType.headline)
      .frame(maxWidth: .infinity)
      .frame(minHeight: Hit.control)
      .foregroundStyle(Palette.critical)
      .opacity(configuration.isPressed ? 0.6 : 1)
      .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
  }
}

/// Whole-row and custom-shaped controls.
struct PlainPressStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.55 : 1)
      .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
  }
}

// MARK: - Structure

/// A group heading over content, drawing nothing itself.
///
/// This is the default container in the app. A framed card is the exception:
/// a page of identical rounded boxes is the clearest sign that no one decided
/// what mattered.
struct Section_<Content: View>: View {
  let title: String?
  var action: (label: String, perform: () -> Void)?
  @ViewBuilder var content: Content

  init(
    _ title: String? = nil,
    action: (label: String, perform: () -> Void)? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.action = action
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Space.sm) {
      if title != nil || action != nil {
        HStack(alignment: .firstTextBaseline) {
          if let title {
            Eyebrow(title)
              .accessibilityAddTraits(.isHeader)
          }
          Spacer(minLength: Space.xs)
          if let action {
            Button(action.label, action: action.perform)
              .font(SoberType.footnoteStrong)
              .foregroundStyle(Palette.accentText)
          }
        }
      }
      content
    }
  }
}

/// A hairline. Almost invisible by design.
struct Separator: View {
  var body: some View {
    Rectangle().fill(Palette.separator).frame(height: 0.5)
  }
}

/// A card. A soft surface with generous padding and a large radius. No
/// border, no shadow: elevation is communicated by the fill alone.
struct Card<Content: View>: View {
  var padding: CGFloat = Space.lg
  @ViewBuilder var content: Content

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(padding)
      .background(
        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
          .fill(Palette.surface)
      )
  }
}

/// A list of rows separated by hairlines, sitting directly on the page.
struct Rows<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) { content }
  }
}

/// A row: title, optional secondary line, optional accessory.
struct Row<Trailing: View>: View {
  let title: String
  var detail: String?
  var showsChevron = true
  @ViewBuilder var trailing: Trailing
  var action: (() -> Void)?

  init(
    _ title: String,
    detail: String? = nil,
    showsChevron: Bool = true,
    @ViewBuilder trailing: () -> Trailing = { EmptyView() },
    action: (() -> Void)? = nil
  ) {
    self.title = title
    self.detail = detail
    self.showsChevron = showsChevron
    self.trailing = trailing()
    self.action = action
  }

  var body: some View {
    let content = HStack(spacing: Space.sm) {
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text(title)
          .font(SoberType.body)
          .foregroundStyle(Palette.textPrimary)
        if let detail {
          Text(detail)
            .font(SoberType.subheadline)
            .foregroundStyle(Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: Space.xs)
      trailing
      if showsChevron {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(Palette.textMuted.opacity(0.6))
      }
    }
    .frame(minHeight: Hit.minimum)
    .padding(.vertical, Space.sm)
    .contentShape(Rectangle())

    if let action {
      Button(action: action) { content }.buttonStyle(PlainPressStyle())
    } else {
      content
    }
  }
}

/// A label and value on one line.
struct ValueRow: View {
  let label: String
  let value: String
  var tint: Color = Palette.textPrimary

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .font(SoberType.body)
        .foregroundStyle(Palette.textSecondary)
      Spacer(minLength: Space.sm)
      Text(value)
        .font(SoberType.body)
        .monospacedDigit()
        .foregroundStyle(tint)
    }
    .frame(minHeight: Hit.minimum)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - States

/// An empty state: a sentence and, where there is one, a way out of it.
struct EmptyStateView: View {
  let title: String
  let message: String
  var action: (label: String, perform: () -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: Space.sm) {
      Text(title)
        .font(SoberType.title)
        .titleTracking()
        .foregroundStyle(Palette.textPrimary)
      Text(message)
        .font(SoberType.body)
        .foregroundStyle(Palette.textSecondary)
        .readingLine()
      if let action {
        Button(action.label, action: action.perform)
          .buttonStyle(TertiaryButtonStyle())
          .padding(.top, Space.xs)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, Space.xxl)
  }
}

/// The app's loading state. A label, and nothing else moving.
struct LoadingStateView: View {
  let message: String

  var body: some View {
    HStack(spacing: Space.sm) {
      ProgressView().controlSize(.small)
      Text(message)
        .font(SoberType.subheadline)
        .foregroundStyle(Palette.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// A quiet state marker.
struct Badge: View {
  let text: String
  var tint: Color = Palette.textMuted

  var body: some View {
    Text(text)
      .font(SoberType.footnote)
      .foregroundStyle(tint)
      .padding(.horizontal, Space.sm)
      .padding(.vertical, Space.xxs + 1)
      .background(
        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
          .fill(tint.opacity(0.12))
      )
  }
}

// MARK: - Measurement
//
// The one place the app draws a number rather than printing it.

/// Where a single measure sits against the person's own usual range.
///
/// The band is their baseline; the marker is tonight. This is the product's
/// claim made visible: every row compares someone only to themselves, and no
/// row summarises the others. The composite risk score is never drawn.
struct DeviationRow: View {
  let detail: SignalDetail

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: Space.sm) {
      HStack(alignment: .firstTextBaseline) {
        Text(detail.label)
          .font(SoberType.body)
          .foregroundStyle(Palette.textPrimary)
        Spacer(minLength: Space.sm)
        Text(detail.value)
          .font(SoberType.footnoteStrong)
          .monospacedDigit()
          .foregroundStyle(detail.concern ? Palette.critical : Palette.textSecondary)
      }

      if let risk = detail.risk {
        track(risk: risk)
      } else {
        Text("Not measured")
          .font(SoberType.footnote)
          .foregroundStyle(Palette.textMuted)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(detail.label)
    .accessibilityValue(
      detail.risk == nil
        ? "\(detail.value), not measured"
        : "\(detail.value), \(detail.concern ? "outside" : "within") your usual range"
    )
  }

  private func track(risk: Double) -> some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let clamped = min(max(risk, 0), 1)
      // Everything below the concern threshold is, by the engine's own
      // definition, this person's usual range.
      let band = width * SignalDetail.concernThreshold

      ZStack(alignment: .leading) {
        Capsule().fill(Palette.separator).frame(height: 2)
        Capsule().fill(Palette.textMuted.opacity(0.5)).frame(width: band, height: 2)
        Circle()
          .fill(detail.concern ? Palette.critical : Palette.accent)
          .frame(width: 8, height: 8)
          .offset(x: max(min(clamped * width, width - 8), 0))
          .animation(reduceMotion ? nil : Motion.standard, value: clamped)
      }
      .frame(height: 8)
    }
    .frame(height: 8)
  }
}

/// Explains the band once per group, never per row.
struct DeviationLegend: View {
  var body: some View {
    HStack(spacing: Space.md) {
      HStack(spacing: Space.xs) {
        Capsule().fill(Palette.textMuted.opacity(0.5)).frame(width: 14, height: 2)
        Text("Your usual range")
      }
      HStack(spacing: Space.xs) {
        Circle().fill(Palette.accent).frame(width: 7, height: 7)
        Text("Tonight")
      }
      Spacer(minLength: 0)
    }
    .font(SoberType.footnote)
    .foregroundStyle(Palette.textMuted)
  }
}

/// Segmented progress.
struct StepMeter: View {
  let filled: Int
  let total: Int

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: Space.xxs + 1) {
      ForEach(0..<total, id: \.self) { index in
        Capsule()
          .fill(index < filled ? Palette.accent : Palette.separator)
          .frame(height: 2)
          .animation(reduceMotion ? nil : Motion.standard, value: filled)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(filled) of \(total) complete")
  }
}

// MARK: - Page

extension View {
  func pageBackground() -> some View {
    background(Palette.background.ignoresSafeArea())
  }

  /// Fades content out under a pinned header rather than cutting it.
  func headerScrim() -> some View {
    background {
      LinearGradient(
        colors: [Palette.background, Palette.background, Palette.background.opacity(0)],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea(edges: .top)
      .allowsHitTesting(false)
    }
  }

  func appear(_ order: Int = 0) -> some View {
    modifier(AppearModifier(order: order))
  }
}

private struct AppearModifier: ViewModifier {
  let order: Int

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var visible = false

  func body(content: Content) -> some View {
    content
      .opacity(visible ? 1 : 0)
      .onAppear {
        guard !visible else { return }
        if reduceMotion {
          visible = true
        } else {
          withAnimation(Motion.entrance(order)) { visible = true }
        }
      }
  }
}
