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

  /// The destinations a build actually has.
  ///
  /// Circle is Guardian, which is not in public v1. The bar iterates this
  /// rather than `allCases` so a public build cannot render a tab that leads
  /// nowhere — the plan's rule is to ship fewer real destinations rather than
  /// a placeholder one.
  static var available: [DSTab] {
    #if INTERNAL_BUILD
    return [.home, .history, .circle, .settings]
    #else
    return [.home, .history, .settings]
    #endif
  }

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

  /// Privacy Lock protects stored personal context, never the safety route.
  /// Home contains the live check, result, Ride, Call, and Message actions.
  var requiresPrivacyLock: Bool {
    switch self {
    case .history, .settings:
      return true
    case .home, .circle:
      return false
    }
  }
}

/// A floating tab bar.
///
/// ## Usage
///
/// Attach it as a bottom safe-area inset, not as an overlay. As an inset SwiftUI
/// both keeps the bar clear of the home indicator and insets scrolling content
/// behind it, so no page needs to reserve clearance by hand:
///
/// ```swift
/// content.safeAreaInset(edge: .bottom, spacing: 0) {
///   DSTabBar(selection: $tab).padding(.top, DSSpace.xs)
/// }
/// ```
struct DSTabBar: View {
  @Binding var selection: DSTab

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Namespace private var pill

  var body: some View {
    bar
      .padding(.horizontal, DSSpace.lg)
  }

  private var bar: some View {
    HStack(spacing: DSSpace.xxs) {
      ForEach(DSTab.available) { item($0) }
    }
    .padding(5)
    .background { surface }
    .overlay {
      Capsule()
        .strokeBorder(DSPalette.separator, lineWidth: 0.5)
    }
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
          .accessibilityHidden(true)
        // Labels are dropped at accessibility sizes. Three scaled words cannot
        // share one bar: they wrapped mid-word, overlapped the selection pill,
        // and left the bar unusable. The icon plus the element's accessibility
        // label still names every destination.
        if !dynamicTypeSize.isAccessibilitySize {
          Text(tab.title).font(DSFont.caption)
        }
      }
      .foregroundStyle(selected ? DSPalette.onAccent : DSPalette.textSecondary)
      .frame(maxWidth: .infinity)
      // minHeight, not height: the label scales with Dynamic Type and a fixed
      // box clips it at accessibility sizes.
      .frame(minHeight: 48)
      .background { selectionPill(selected) }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(tab.title)
    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
  }

  @ViewBuilder
  private func selectionPill(_ selected: Bool) -> some View {
    // A solid fill, never a tinted glass. The bar is the glass; giving the pill
    // its own tinted material stacked it on top of an accent fill and bloomed
    // into an orange halo that swallowed the adjacent labels.
    if selected {
      Capsule()
        .fill(DSPalette.accent)
        .matchedGeometryEffect(id: "dsTabSelection", in: pill)
    }
  }

  /// Matte, not glass.
  ///
  /// The bar was the system's one deliberate exception to "no materials". In
  /// practice it sampled whatever scrolled behind it — an orange primary button,
  /// hero type — and smeared it across the bar until the labels were unreadable.
  /// A material that inverts legibility depending on the content underneath is
  /// the wrong choice for the one control that is always on screen.
  ///
  /// An opaque raised surface with a hairline rim reads the same over every
  /// screen, which is what a persistent control needs.
  private var surface: some View {
    Capsule().fill(DSPalette.surfaceRaised)
  }
}
