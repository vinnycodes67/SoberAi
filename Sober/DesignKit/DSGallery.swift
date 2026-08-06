import SwiftUI

#if DEBUG

/// A working gallery of everything in DesignKit.
///
/// Present it from anywhere to see the system running on a real device
/// instead of in a mockup:
///
/// ```swift
/// .sheet(isPresented: $showingGallery) { DSGallery() }
/// ```
///
/// It has no dependency on app state, so it can also be driven straight from
/// an Xcode preview.
struct DSGallery: View {
  @State private var tab: DSTab = .home
  @State private var toggle = true

  var body: some View {
    ZStack(alignment: .bottom) {
      ScrollView {
        VStack(alignment: .leading, spacing: DSSpace.xl) {
          heroCard
          typeScale
          colours
          buttons
          rows
          portrait
          states
        }
        .padding(.horizontal, DSSpace.margin)
        .padding(.top, DSSpace.md)
        .padding(.bottom, DSSpace.tabBarClearance)
      }
      .scrollIndicators(.hidden)
      .dsPageBackground()

      DSTabBar(selection: $tab).padding(.bottom, DSSpace.xs)
    }
    .preferredColorScheme(.dark)
  }

  private var heroCard: some View {
    DSCard(highlighted: true) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: DSSpace.xs) {
          Circle().fill(DSPalette.textMuted).frame(width: 7, height: 7)
          Text("Last check")
            .font(DSFont.footnoteStrong)
            .foregroundStyle(DSPalette.textMuted)
        }
        Text("Nothing unusual.")
          .font(DSFont.hero)
          .dsHeroTracking()
          .foregroundStyle(DSPalette.textPrimary)
          .padding(.top, DSSpace.xs)
        Text("2 hours ago. A check takes about two minutes.")
          .font(DSFont.callout)
          .foregroundStyle(DSPalette.textSecondary)
          .dsReadingLine()
          .padding(.top, DSSpace.sm)
      }
    }
  }

  private var typeScale: some View {
    DSSection("Type") {
      VStack(alignment: .leading, spacing: DSSpace.sm) {
        specimen("hero 34", DSFont.hero, "Take a moment")
        specimen("title 22", DSFont.title, "Against your baseline")
        specimen("headline 17", DSFont.headline, "Safety Circle")
        specimen("body 17", DSFont.body, "A check takes two minutes")
        specimen("subheadline 15", DSFont.subheadline, "Uber and Jordan")
        specimen("footnote 13", DSFont.footnote, "Stored on this iPhone")
        HStack(alignment: .firstTextBaseline, spacing: DSSpace.sm) {
          Text("caption 11").font(DSFont.caption2).foregroundStyle(DSPalette.textMuted)
            .frame(width: 96, alignment: .leading)
          DSEyebrow("Developer")
        }
      }
    }
  }

  private func specimen(_ name: String, _ font: Font, _ sample: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: DSSpace.sm) {
      Text(name)
        .font(DSFont.caption2)
        .foregroundStyle(DSPalette.textMuted)
        .frame(width: 96, alignment: .leading)
      Text(sample).font(font).foregroundStyle(DSPalette.textPrimary)
        .lineLimit(1).minimumScaleFactor(0.6)
    }
  }

  private var colours: some View {
    DSSection("Colour") {
      VStack(alignment: .leading, spacing: DSSpace.sm) {
        HStack(spacing: 0) {
          swatch(DSPalette.background, "bg")
          swatch(DSPalette.surface, "surface")
          swatch(DSPalette.surfaceRaised, "raised")
          swatch(DSPalette.accent, "accent")
          swatch(DSPalette.withinRange, "within")
          swatch(DSPalette.unmeasured, "unread")
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous))
        Text("Orange means attention: the primary action, and a measure outside the usual range. Nothing else is coloured.")
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
          .dsReadingLine()
      }
    }
  }

  private func swatch(_ color: Color, _ label: String) -> some View {
    VStack(spacing: 0) {
      Rectangle().fill(color).frame(height: 44)
      Text(label)
        .font(DSFont.caption)
        .foregroundStyle(DSPalette.textMuted)
        .padding(.vertical, 4)
    }
    .frame(maxWidth: .infinity)
  }

  private var buttons: some View {
    DSSection("Buttons") {
      VStack(spacing: DSSpace.sm) {
        Button("Start check") {}.buttonStyle(DSPrimaryButtonStyle())
        Button("Call Jordan") {}.buttonStyle(DSSecondaryButtonStyle())
        Button("Show all") {}.buttonStyle(DSTertiaryButtonStyle())
        Button("Disabled") {}.buttonStyle(DSPrimaryButtonStyle()).disabled(true)
      }
    }
  }

  private var rows: some View {
    DSSection("Rows", action: ("All", {})) {
      DSRows {
        DSRow("Safety Circle", detail: "Uber and Jordan") {}
        DSSeparator()
        DSRow("Guardian Mode", detail: "Paired as a parent") {
          DSBadge(text: "On", tint: DSPalette.accent)
        } action: {}
        DSSeparator()
        DSValueRow(label: "Reaction", value: "382 to 441 ms")
      }
    }
  }

  private var portrait: some View {
    DSSection("Baseline portrait") {
      VStack(alignment: .leading, spacing: DSSpace.sm) {
        Text("Each bar is one measure. The block is your usual range. The tick is where a check landed.")
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
          .dsReadingLine()
        DSBaselinePortrait(
          tracks: DSBaselinePortrait.tracks(fromRisks: [
            "reaction": 0.78, "tracking": 0.31, "timing": 0.18,
            "gaze": 0.88, "pupil": 0.35,
          ]),
          isEstablished: true
        )
        DSPortraitLegend()
      }
    }
  }

  private var states: some View {
    DSSection("States") {
      VStack(alignment: .leading, spacing: DSSpace.lg) {
        VStack(alignment: .leading, spacing: DSSpace.xs) {
          DSStepMeter(filled: 2, total: 5)
          Text("2 of 5 baseline sessions recorded")
            .font(DSFont.footnote)
            .foregroundStyle(DSPalette.textMuted)
        }
        Toggle(isOn: $toggle) {
          Text("Safety Circle active").font(DSFont.body)
        }
        .tint(DSPalette.accent)
        DSEmptyState(
          title: "No sessions yet",
          message: "Completed checks appear here, newest first. Nothing is uploaded.",
          action: ("Record a baseline session", {})
        )
      }
    }
  }
}

#Preview("DesignKit") {
  DSGallery()
}

#endif
