import SwiftUI

/// A tab in the floating bar.
///
/// Deliberately generic: the bar takes whatever cases you give it, so wiring
/// it to the app's real sections is a matter of editing this enum rather than
/// touching the bar itself.
enum DSTab: String, CaseIterable, Identifiable {
  case home
  case history
  case circle
  case settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: "Home"
    case .history: "History"
    case .circle: "Circle"
    case .settings: "Settings"
    }
  }

  var icon: String {
    switch self {
    case .home: "house"
    case .history: "clock"
    case .circle: "person.2"
    case .settings: "gearshape"
    }
  }
}

/// A floating Liquid Glass tab bar.
///
/// On iOS 26 the bar and its selection pill are placed inside a single
/// `GlassEffectContainer`. That is what makes the glass behave the way
/// Apple's own does: both shapes sample the same backdrop, so the pill
/// dissolves and re-forms between tabs rather than sliding as an opaque
/// object across a separate pane. `.interactive()` gives the material its
/// touch response.
///
/// Older systems fall back to layered material, which cannot refract, so it
/// compensates with an inner lift and a hairline rim.
///
/// ## Usage
///
/// ```swift
/// ZStack(alignment: .bottom) {
///   content
///   DSTabBar(selection: $tab).padding(.bottom, DSSpace.xs)
/// }
/// ```
///
/// Give scrolling content `.padding(.bottom, DSSpace.tabBarClearance)` so the
/// last row is never trapped beneath the bar.
struct DSTabBar: View {
  @Binding var selection: DSTab

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Namespace private var pill

  var body: some View {
    Group {
      if #available(iOS 26.0, *), !reduceTransparency {
        GlassEffectContainer(spacing: DSSpace.xxs) { bar }
      } else {
        bar
      }
    }
    .padding(.horizontal, DSSpace.lg)
  }

  private var bar: some View {
    HStack(spacing: DSSpace.xxs) {
      ForEach(DSTab.allCases) { item($0) }
    }
    .padding(5)
    .background { surface }
    .overlay {
      Capsule()
        .strokeBorder(
          LinearGradient(
            colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
            startPoint: .top,
            endPoint: .bottom
          ),
          lineWidth: 0.5
        )
    }
    .shadow(color: .black.opacity(0.44), radius: 20, y: 8)
  }

  private func item(_ tab: DSTab) -> some View {
    let selected = tab == selection
    return Button {
      if reduceMotion {
        selection = tab
      } else {
        withAnimation(.spring(duration: 0.34, bounce: 0.14)) { selection = tab }
      }
    } label: {
      VStack(spacing: 3) {
        Image(systemName: selected ? "\(tab.icon).fill" : tab.icon)
          .font(.system(size: 17, weight: .regular))
        Text(tab.title).font(DSFont.caption)
      }
      .foregroundStyle(selected ? DSPalette.onAccent : DSPalette.textSecondary)
      .frame(maxWidth: .infinity)
      .frame(height: 48)
      .background { selectionPill(selected) }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(tab.title)
    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
  }

  @ViewBuilder
  private func selectionPill(_ selected: Bool) -> some View {
    if selected {
      if #available(iOS 26.0, *), !reduceTransparency {
        Capsule()
          .fill(DSPalette.accent)
          .glassEffect(.regular.tint(DSPalette.accent).interactive(), in: Capsule())
          .matchedGeometryEffect(id: "dsTabSelection", in: pill)
      } else {
        Capsule()
          .fill(DSPalette.accent)
          .matchedGeometryEffect(id: "dsTabSelection", in: pill)
      }
    }
  }

  @ViewBuilder
  private var surface: some View {
    if reduceTransparency {
      Capsule().fill(DSPalette.surfaceRaised)
    } else if #available(iOS 26.0, *) {
      Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
    } else {
      ZStack {
        Capsule().fill(.ultraThinMaterial)
        // Material alone reads flat on a near-black page. A faint vertical
        // lift restores the sense of a curved surface catching light.
        Capsule().fill(
          LinearGradient(
            colors: [Color.white.opacity(0.07), Color.white.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        Capsule().fill(Color.black.opacity(0.18))
      }
    }
  }
}
