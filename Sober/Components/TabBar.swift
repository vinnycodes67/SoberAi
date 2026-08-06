import SwiftUI

enum SoberTab: String, CaseIterable, Identifiable {
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
/// Apple's own does: the shapes sample the same backdrop, so the pill
/// dissolves and re-forms between tabs rather than sliding as an opaque
/// object across a separate pane. `.interactive()` gives the material its
/// touch response.
///
/// Older systems fall back to layered material. That cannot refract, so it
/// compensates with an inner top highlight and a hairline rim, which is what
/// reads as "glass" without the real thing behind it.
struct SoberTabBar: View {
  @Binding var selection: SoberTab

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Namespace private var pill

  var body: some View {
    Group {
      if #available(iOS 26.0, *), !reduceTransparency {
        GlassEffectContainer(spacing: Space.xxs) {
          bar
        }
      } else {
        bar
      }
    }
    .padding(.horizontal, Space.lg)
  }

  private var bar: some View {
    HStack(spacing: Space.xxs) {
      ForEach(SoberTab.allCases) { tab in
        item(tab)
      }
    }
    .padding(5)
    .background { surface }
    .overlay {
      // The rim. On real glass this is a hairline; on the fallback it does
      // more work, because it is standing in for refraction.
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

  private func item(_ tab: SoberTab) -> some View {
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
          .symbolRenderingMode(.monochrome)
        Text(tab.title)
          .font(SoberType.caption)
      }
      .foregroundStyle(selected ? Palette.onAccent : Palette.textSecondary)
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
          .fill(Palette.accent)
          .glassEffect(.regular.tint(Palette.accent).interactive(), in: Capsule())
          .matchedGeometryEffect(id: "selection", in: pill)
      } else {
        Capsule()
          .fill(Palette.accent)
          .matchedGeometryEffect(id: "selection", in: pill)
      }
    }
  }

  @ViewBuilder
  private var surface: some View {
    if reduceTransparency {
      Capsule().fill(Palette.surfaceRaised)
    } else if #available(iOS 26.0, *) {
      Capsule()
        .fill(.clear)
        .glassEffect(.regular, in: Capsule())
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
