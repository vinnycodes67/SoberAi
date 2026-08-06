import SwiftUI

// Compatibility layer.
//
// The design system was rebuilt around `Space`, `Radius`, `Motion`, semantic
// `Palette` roles, and the components in `SoberComponents.swift`. Screens are
// being migrated onto it one at a time; everything below keeps the rest of the
// app compiling and inheriting the new tokens in the meantime.
//
// Nothing new should use these names. When the last screen is migrated this
// file is deleted.

// MARK: - Motion

enum SoberMotion {
  static let press = Motion.quick
  static let progress = Motion.standard
  static let screen = Motion.standard

  static func entrance(order: Int) -> Animation { Motion.entrance(order) }
}

// MARK: - Buttons

typealias PrimaryActionButtonStyle = PrimaryActionButtonStyleShim
typealias SoberCardButtonStyle = PlainPressStyle
typealias SoberPressStyle = PlainPressStyle

struct PrimaryActionButtonStyleShim: ButtonStyle {
  var tint: Color = Palette.accent

  func makeBody(configuration: Configuration) -> some View {
    PrimaryButtonStyle().makeBody(configuration: configuration)
  }
}

struct SecondaryActionButtonStyle: ButtonStyle {
  var tint: Color = Palette.textPrimary

  func makeBody(configuration: Configuration) -> some View {
    SecondaryButtonStyle().makeBody(configuration: configuration)
  }
}

// MARK: - Surfaces

struct SoberCard<Content: View>: View {
  var padding: CGFloat = Space.lg
  @ViewBuilder var content: Content

  var body: some View { Card(padding: padding) { content } }
}

struct SoberRowGroup<Content: View>: View {
  var inset: CGFloat = 0
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) { content }
      .padding(.horizontal, Space.lg)
      .background(
        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
          .fill(Palette.surface)
      )
  }
}

struct AccentCard<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Space.lg)
      .background(
        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
          .fill(Palette.accentWash)
      )
  }
}

struct InstrumentTile<Content: View>: View {
  var hue: Double = 0
  var minHeight: CGFloat?
  var watermark: String?
  @ViewBuilder var content: Content

  var body: some View {
    content
      .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
      .padding(Space.lg)
      .background(
        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
          .fill(Palette.surface)
      )
  }
}

typealias SoberDivider = Separator

struct SoberList<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View { Rows { content } }
}

struct SoberRow<Trailing: View>: View {
  let title: String
  var detail: String?
  var icon: String?
  var showsChevron = true
  @ViewBuilder var trailing: Trailing
  var action: (() -> Void)?

  init(
    title: String,
    detail: String? = nil,
    icon: String? = nil,
    showsChevron: Bool = true,
    @ViewBuilder trailing: () -> Trailing = { EmptyView() },
    action: (() -> Void)? = nil
  ) {
    self.title = title
    self.detail = detail
    self.icon = icon
    self.showsChevron = showsChevron
    self.trailing = trailing()
    self.action = action
  }

  var body: some View {
    Row(title, detail: detail, showsChevron: showsChevron, trailing: { trailing }, action: action)
  }
}

struct SoberSection<Content: View>: View {
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

  var body: some View { Section_(title, action: action) { content } }
}

struct SectionHeader<Trailing: View>: View {
  let title: String
  @ViewBuilder var trailing: Trailing

  init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
    self.title = title
    self.trailing = trailing()
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Eyebrow(title)
      Spacer(minLength: Space.xs)
      trailing
    }
    .accessibilityAddTraits(.isHeader)
  }
}

typealias SpecRow = ValueRow

extension ValueRow {
  init(label: String, value: String, valueTint: Color) {
    self.init(label: label, value: value, tint: valueTint)
  }
}

struct StatBlock: View {
  let label: String
  let value: String
  var unit: String?
  var size: CGFloat = 28

  var body: some View {
    VStack(alignment: .leading, spacing: Space.xs) {
      Eyebrow(label)
      HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
        Text(value)
          .font(SoberType.figure(size))
          .titleTracking()
          .foregroundStyle(Palette.textPrimary)
          .contentTransition(.numericText())
        if let unit {
          Text(unit)
            .font(SoberType.subheadline)
            .foregroundStyle(Palette.textMuted)
        }
      }
    }
  }
}

struct MetricStrip: View {
  struct Item: Identifiable {
    let label: String
    let value: String
    var tint: Color = Palette.textPrimary
    var id: String { label }
  }

  let items: [Item]

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(items) { item in
        VStack(alignment: .leading, spacing: Space.xxs + 1) {
          Text(item.value)
            .font(SoberType.figure(22))
            .titleTracking()
            .foregroundStyle(item.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Text(item.label)
            .font(SoberType.footnote)
            .foregroundStyle(Palette.textMuted)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
      }
    }
  }
}

typealias SignalDeviationRow = DeviationRow

struct StatusPill: View {
  let text: String
  var filled = false

  var body: some View {
    Badge(text: text, tint: filled ? Palette.accentText : Palette.textMuted)
  }
}

struct PrototypeBadge: View {
  var body: some View { Badge(text: "Prototype", tint: Palette.warning) }
}

struct SoberWordmark: View {
  var body: some View {
    Text("Sober")
      .font(SoberType.headline)
      .titleTracking()
      .foregroundStyle(Palette.textPrimary)
      .accessibilityAddTraits(.isHeader)
  }
}

struct ScreenHeader: View {
  let eyebrow: String
  let title: String
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: Space.xs) {
      Text(eyebrow)
        .font(SoberType.footnoteStrong)
        .foregroundStyle(Palette.textMuted)
      Text(title)
        .font(SoberType.hero)
        .heroTracking()
        .foregroundStyle(Palette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      Text(detail)
        .font(SoberType.body)
        .foregroundStyle(Palette.textSecondary)
        .readingLine()
        .padding(.top, Space.xxs)
    }
  }
}

struct AvatarStack: View {
  var count: Int

  var body: some View {
    HStack(spacing: -6) {
      ForEach(0..<max(count, 1), id: \.self) { _ in
        Circle()
          .fill(Palette.surfaceSecondary)
          .frame(width: 20, height: 20)
          .overlay { Circle().stroke(Palette.background, lineWidth: 2) }
      }
    }
    .accessibilityHidden(true)
  }
}

struct StepProgress: View {
  let current: Int
  let total: Int

  var body: some View { StepMeter(filled: current + 1, total: total) }
}

struct TickMeter: View {
  let filled: Int
  let total: Int

  var body: some View { StepMeter(filled: filled, total: total) }
}

struct ProgressRing: View {
  let completed: Int
  let total: Int
  var size: CGFloat = 120

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var fraction: Double {
    guard total > 0 else { return 0 }
    return min(max(Double(completed) / Double(total), 0), 1)
  }

  var body: some View {
    ZStack {
      Circle().stroke(Palette.separator, lineWidth: 2)
      Circle()
        .trim(from: 0, to: fraction)
        .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .animation(reduceMotion ? nil : Motion.standard, value: fraction)
      Text("\(completed) of \(total)")
        .font(SoberType.footnote)
        .foregroundStyle(Palette.textMuted)
    }
    .frame(width: size, height: size)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Task \(completed) of \(total)")
  }
}

struct GlassIconButton: View {
  let systemImage: String
  var accessibilityLabelText: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .regular))
        .foregroundStyle(Palette.textMuted)
        .frame(width: Hit.minimum, height: Hit.minimum)
        .contentShape(Rectangle())
    }
    .buttonStyle(PlainPressStyle())
    .accessibilityLabel(accessibilityLabelText)
  }
}

struct SoberGlassControlGroup<Content: View>: View {
  let spacing: CGFloat
  @ViewBuilder var content: Content

  init(spacing: CGFloat = Space.sm, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }

  var body: some View { content }
}

// MARK: - Chips

struct ContextChip: View {
  let icon: String
  let label: String
  var flagged = false

  var body: some View {
    Text(label)
      .font(SoberType.footnote)
      .foregroundStyle(Palette.textSecondary)
      .padding(.horizontal, Space.sm)
      .padding(.vertical, Space.xs)
      .background(Capsule().fill(Palette.surface))
  }
}

struct ContextChipItem: Identifiable, Hashable {
  let icon: String
  let label: String
  var id: String { icon + label }
}

struct FlowChips: View {
  let items: [ContextChipItem]

  var body: some View {
    FlowLayout(spacing: Space.xs, lineSpacing: Space.xs) {
      ForEach(items) { ContextChip(icon: $0.icon, label: $0.label) }
    }
  }
}

/// SwiftUI has no flow container, and chip counts are data-dependent, so a
/// fixed `HStack` would clip at large Dynamic Type.
struct FlowLayout: Layout {
  var spacing: CGFloat = Space.xs
  var lineSpacing: CGFloat = Space.xs

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + spacing + size.width > maxWidth {
        widest = max(widest, x); x = 0; y += lineHeight + lineSpacing; lineHeight = 0
      }
      x += (x > 0 ? spacing : 0) + size.width
      lineHeight = max(lineHeight, size.height)
    }
    return CGSize(width: min(max(widest, x), maxWidth), height: y + lineHeight)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > bounds.minX, x + spacing + size.width > bounds.maxX {
        x = bounds.minX; y += lineHeight + lineSpacing; lineHeight = 0
      }
      if x > bounds.minX { x += spacing }
      subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
      x += size.width
      lineHeight = max(lineHeight, size.height)
    }
  }
}

// MARK: - View helpers

extension View {
  func soberBackground() -> some View { pageBackground() }
  func soberHeaderScrim() -> some View { headerScrim() }
  func soberEntrance(order: Int = 0) -> some View { appear(order) }
  func soberGlassCircle(tint: Color? = nil) -> some View {
    background(Circle().fill(Palette.surface))
  }
  func soberGlassCapsule(tint: Color? = nil) -> some View {
    background(Capsule().fill(Palette.surface))
  }
}
