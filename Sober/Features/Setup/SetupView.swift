import SwiftUI

/// Everything that is not the check.
///
/// Deliberately an ordinary grouped list. Settings that look like settings
/// are a kindness: nobody should have to learn a bespoke visual language to
/// change a phone number. The developer group sits last, behind a wide gap
/// and an unmistakable heading, so it reads as instrumentation rather than a
/// feature.
struct SettingsTabView: View {
  @EnvironmentObject private var model: AppModel

  @State private var showingResearch = false
  @State private var showingReset = false
  @State private var previewScenario: FounderScenario?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Space.xl) {
          Section_("Getting home") {
            Rows {
              NavigationLink {
                GuardianSetupView(showsDoneButton: false)
              } label: {
                Row("Guardian Mode", detail: guardianSummary, showsChevron: false) { chevron }
              }
              .buttonStyle(PlainPressStyle())
            }
          }

          Section_("Your data") {
            Rows {
              NavigationLink { BaselineDetailContent() } label: {
                Row(
                  "Baseline",
                  detail: model.baselineReady
                    ? "Established" : "\(model.baselineSessions) of 5 sessions",
                  showsChevron: false
                ) { chevron }
              }
              .buttonStyle(PlainPressStyle())

              Separator()

              NavigationLink { HistoryView() } label: {
                Row(
                  "History",
                  detail: "\(model.researchSessions.count) sessions on this iPhone",
                  showsChevron: false
                ) { chevron }
              }
              .buttonStyle(PlainPressStyle())

              Separator()

              NavigationLink { RetentionPolicyContent() } label: {
                Row("Privacy", detail: "What is stored, and for how long", showsChevron: false) {
                  chevron
                }
              }
              .buttonStyle(PlainPressStyle())
            }
          }

          Section_("About") {
            Rows {
              NavigationLink { AboutContent() } label: {
                Row("What Sober is", detail: "And what it cannot do", showsChevron: false) {
                  chevron
                }
              }
              .buttonStyle(PlainPressStyle())

              Separator()

              Row("Reset prototype", detail: "Erases everything on this iPhone",
                  showsChevron: false, action: { showingReset = true })
            }
          }

          #if DEBUG
          developer
            .padding(.top, Space.md)
          #endif

          Text("Version 0.2")
            .font(SoberType.footnote)
            .foregroundStyle(Palette.textMuted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Space.md)
        }
        .padding(.horizontal, Space.margin)
        .padding(.bottom, 108)
      }
      .scrollIndicators(.hidden)
      .pageBackground()
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.large)
      .sheet(isPresented: $showingResearch) {
        ResearchModeView().environmentObject(model)
      }
      .fullScreenCover(item: $previewScenario) { scenario in
        ScreeningFlowView(configuration: ScreeningLaunch(mode: .check, scenario: scenario))
          .environmentObject(model)
      }
      .alert("Reset the prototype?", isPresented: $showingReset) {
        Button("Cancel", role: .cancel) {}
        Button("Reset and delete", role: .destructive) {
          model.resetPrototype()
        }
      } message: {
        Text(
          "This clears onboarding, your Safety Circle, and consent, and permanently deletes all \(model.researchSessions.count) stored session\(model.researchSessions.count == 1 ? "" : "s") and your measured baseline. Export first if you need the data. This cannot be undone."
        )
      }
    }
  }

  private var chevron: some View {
    Image(systemName: "chevron.right")
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(Palette.textMuted.opacity(0.6))
  }

  private var guardianSummary: String {
    switch model.guardianRole {
    case .none: "Off"
    case .teen: "Paired as a teen driver"
    case .parent: "Paired as a parent"
    }
  }

  #if DEBUG
  @ViewBuilder
  private var developer: some View {
    Section_("Developer") {
      Rows {
        Row(
          "Research Center",
          detail: "Consent, context, export, delete",
          action: { showingResearch = true })
        ForEach([FounderScenario.signals, .inconclusive, .noSignals]) { scenario in
          Separator()
          Row("Preview: \(scenario.rawValue)", showsChevron: false) {
            Circle()
              .fill(color(for: scenario))
              .frame(width: 7, height: 7)
          } action: {
            previewScenario = scenario
          }
        }
      }
    }
  }

  private func color(for scenario: FounderScenario) -> Color {
    switch scenario {
    case .signals: Palette.outsideRange
    case .inconclusive: Palette.unmeasured
    case .noSignals, .live: Palette.withinRange
    }
  }
  #endif
}
