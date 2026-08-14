import SwiftUI

// MARK: - Buttons
//
// Four roles, one sizing system. A screen with two primaries has no primary.

/// The single most important action on a screen.
struct DSPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> StyleContent {
    StyleContent(configuration: configuration)
  }

  struct StyleContent: View {
    let configuration: ButtonStyle.Configuration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      configuration.label
        .font(DSFont.headline)
        .frame(maxWidth: .infinity)
        .frame(minHeight: DSHit.primary)
        .foregroundStyle(DSPalette.onAccent)
        .background(
          RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
            .fill(DSPalette.accent)
        )
        .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.4)
        .animation(reduceMotion ? nil : DSMotion.quick, value: configuration.isPressed)
    }
  }
}

/// A supporting action.
struct DSSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> StyleContent {
    StyleContent(configuration: configuration)
  }

  struct StyleContent: View {
    let configuration: ButtonStyle.Configuration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      configuration.label
        .font(DSFont.headline)
        .frame(maxWidth: .infinity)
        .frame(minHeight: DSHit.control)
        .foregroundStyle(DSPalette.textPrimary)
        .background(
          RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
            .fill(configuration.isPressed ? DSPalette.surfaceRaised : DSPalette.surface)
        )
        .animation(reduceMotion ? nil : DSMotion.quick, value: configuration.isPressed)
    }
  }
}

/// Low emphasis. Text only.
struct DSTertiaryButtonStyle: ButtonStyle {
  var tint: Color = DSPalette.accent

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(DSFont.headline)
      .frame(minHeight: DSHit.minimum)
      .foregroundStyle(tint)
      .opacity(configuration.isPressed ? 0.6 : 1)
      .animation(reduceMotion ? nil : DSMotion.quick, value: configuration.isPressed)
  }
}

/// Whole-row and custom-shaped controls.
struct DSPressStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.55 : 1)
      .animation(reduceMotion ? nil : DSMotion.quick, value: configuration.isPressed)
  }
}

// MARK: - Structure

/// A group heading over content, drawing nothing itself.
///
/// This is the default container. A framed card is the exception: a page of
/// identical rounded boxes is the clearest sign that nobody decided what
/// mattered.
struct DSSection<Content: View>: View {
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
    VStack(alignment: .leading, spacing: DSSpace.sm) {
      if title != nil || action != nil {
        HStack(alignment: .firstTextBaseline) {
          if let title {
            DSEyebrow(title).accessibilityAddTraits(.isHeader)
          }
          Spacer(minLength: DSSpace.xs)
          if let action {
            Button(action.label, action: action.perform)
              .font(DSFont.footnoteStrong)
              .foregroundStyle(DSPalette.accent)
          }
        }
      }
      content
    }
  }
}

/// A hairline. Almost invisible by design.
struct DSSeparator: View {
  var body: some View {
    Rectangle().fill(DSPalette.separator).frame(height: 0.5)
  }
}

/// A card: a soft surface with generous padding and a large radius. No
/// border, no shadow. Elevation is communicated by fill alone.
struct DSCard<Content: View>: View {
  var padding: CGFloat = DSSpace.lg
  /// The one specular edge in the system. Reserve it for a screen's hero
  /// surface; applied to every card it stops being emphasis and becomes
  /// texture.
  var highlighted: Bool = false
  @ViewBuilder var content: Content

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(padding)
      .background(
        RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
          .fill(DSPalette.surface)
      )
      .overlay {
        if highlighted {
          RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
            .strokeBorder(
              LinearGradient(
                colors: [Color.white.opacity(0.10), Color.white.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
              ),
              lineWidth: 0.5
            )
        }
      }
  }
}

/// A list of rows separated by hairlines, sitting directly on the page.
struct DSRows<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) { content }
  }
}

/// A row: title, optional secondary line, optional accessory.
struct DSRow<Trailing: View>: View {
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
    let content = HStack(spacing: DSSpace.sm) {
      VStack(alignment: .leading, spacing: DSSpace.xxs) {
        Text(title)
          .font(DSFont.body)
          .foregroundStyle(DSPalette.textPrimary)
        if let detail {
          Text(detail)
            .font(DSFont.subheadline)
            .foregroundStyle(DSPalette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: DSSpace.xs)
      trailing
      if showsChevron {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(DSPalette.textMuted.opacity(0.6))
          .accessibilityHidden(true)
      }
    }
    .frame(minHeight: DSHit.minimum)
    .padding(.vertical, DSSpace.sm)
    .contentShape(Rectangle())

    if let action {
      Button(action: action) { content }.buttonStyle(DSPressStyle())
    } else {
      content
    }
  }
}

/// A label and value on one line.
struct DSValueRow: View {
  let label: String
  let value: String
  var tint: Color = DSPalette.textPrimary
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: DSSpace.xxs) {
          labelText
          valueText
        }
      } else {
        HStack(alignment: .firstTextBaseline) {
          labelText
          Spacer(minLength: DSSpace.sm)
          valueText
        }
      }
    }
    .frame(minHeight: DSHit.minimum)
    .accessibilityElement(children: .combine)
  }

  private var labelText: some View {
    Text(label)
      .font(DSFont.body)
      .foregroundStyle(DSPalette.textSecondary)
  }

  private var valueText: some View {
    Text(value)
      .font(DSFont.body)
      .monospacedDigit()
      .foregroundStyle(tint)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// A quiet state marker.
struct DSBadge: View {
  let text: String
  var tint: Color = DSPalette.textMuted

  var body: some View {
    Text(text)
      .font(DSFont.footnote)
      .foregroundStyle(tint)
      .padding(.horizontal, DSSpace.sm)
      .padding(.vertical, DSSpace.xxs + 1)
      .background(
        RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
          .fill(tint.opacity(0.12))
      )
  }
}

/// Segmented progress. Pair it with a sentence: a bare row of marks is a
/// diagram without a caption.
struct DSStepMeter: View {
  let filled: Int
  let total: Int

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: DSSpace.xxs + 1) {
      ForEach(0..<total, id: \.self) { index in
        Capsule()
          .fill(index < filled ? DSPalette.accent : DSPalette.surfaceRaised)
          .frame(height: 4)
          .animation(reduceMotion ? nil : DSMotion.standard, value: filled)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(filled) of \(total) complete")
  }
}

/// An empty state: a sentence and, where one exists, a way out of it. No
/// illustration, no icon, no encouragement.
struct DSEmptyState: View {
  let title: String
  let message: String
  var action: (label: String, perform: () -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: DSSpace.sm) {
      Text(title)
        .font(DSFont.title)
        .dsTitleTracking()
        .foregroundStyle(DSPalette.textPrimary)
      Text(message)
        .font(DSFont.body)
        .foregroundStyle(DSPalette.textSecondary)
        .dsReadingLine()
      if let action {
        Button(action.label, action: action.perform)
          .buttonStyle(DSTertiaryButtonStyle())
          .padding(.top, DSSpace.xs)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, DSSpace.xxl)
  }
}

// MARK: - Page

extension View {
  /// The page ground.
  func dsPageBackground() -> some View {
    background(DSPalette.background.ignoresSafeArea())
  }

  /// Staggered fade-in for a screen's blocks.
  func dsAppear(_ order: Int = 0) -> some View {
    modifier(DSAppearModifier(order: order))
  }
}

private struct DSAppearModifier: ViewModifier {
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
          withAnimation(DSMotion.entrance(order)) { visible = true }
        }
      }
  }
}
