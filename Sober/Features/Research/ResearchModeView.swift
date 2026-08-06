import SwiftUI

struct ResearchModeView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var exportURL: URL?
  @State private var preparingExport = false
  @State private var showingDeleteConfirmation = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Space.md) {
          ScreenHeader(
            eyebrow: "Research Center",
            title: "Build evidence, not confidence theater.",
            detail:
              "Sober stores structured task data locally. It does not train itself, upload raw face video, or claim clinical accuracy."
          )

          consentCard
          baselineCard
          contextCard
          dataCard

          if let error = model.researchDataError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .font(SoberType.footnote)
              .foregroundStyle(Palette.warning)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(Space.lg)
      }
      .soberBackground()
      .navigationTitle("Research Mode")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .task { await model.reloadResearchData() }
    .alert("Delete all local research data?", isPresented: $showingDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        Task {
          await model.deleteAllResearchData()
          exportURL = nil
        }
      }
    } message: {
      Text("This deletes stored sessions, the measured baseline, and any export file this build wrote from this iPhone. It cannot be undone.")
    }
  }

  private var consentCard: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: Space.sm) {
        Toggle(isOn: $model.researchConsent) {
          VStack(alignment: .leading, spacing: Space.xxs) {
            Text("Record checks for research")
              .font(SoberType.body)
            Text("Store completed check sessions locally for export and future offline analysis")
              .font(SoberType.footnote)
              .foregroundStyle(Palette.textSecondary)
          }
        }
        .tint(Palette.accent)

        Divider().overlay(Palette.line)

        Label(
          "Baseline sessions are stored locally for your personal reference. If you enable research later, earlier baselines are included in the export; this switch also adds ordinary checks.",
          systemImage: "lock.iphone"
        )
        .font(SoberType.footnote)
        .foregroundStyle(Palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var baselineCard: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: Space.sm) {
        HStack {
          VStack(alignment: .leading, spacing: Space.xxs) {
            Text("Measured sober baseline")
              .font(SoberType.body)
            Text("Only complete sessions with camera quality ≥72% count")
              .font(SoberType.footnote)
              .foregroundStyle(Palette.textSecondary)
          }
          Spacer()
          Text("\(eligibleBaselineCount)/5")
            .font(SoberType.figure(24))
            .foregroundStyle(Palette.accent)
        }

        HStack(spacing: Space.xs) {
          ForEach(0..<5, id: \.self) { index in
            Capsule()
              .fill(index < eligibleBaselineCount ? Palette.accent : Palette.line)
              .frame(height: 7)
          }
        }

        if let profile = model.baselineProfile, profile.excludedSessionCount > 0 {
          Text("\(profile.excludedSessionCount) session\(profile.excludedSessionCount == 1 ? " was" : "s were") excluded for incomplete or low-quality capture.")
            .font(SoberType.footnote)
            .foregroundStyle(Palette.warning)
        }

        let fullCount = model.baselineVariantBreakdown[.full]?.eligibleSessionCount ?? 0
        let reducedCount = model.baselineVariantBreakdown[.reducedMotion]?.eligibleSessionCount ?? 0
        Text("Full-protocol baseline: \(fullCount)/5 • Reduced-motion baseline: \(reducedCount)/5")
          .font(SoberType.footnote)
          .foregroundStyle(Palette.accent)

        Text("Median and median absolute deviation are calculated locally. These values are research features and do not change the prototype scorer.")
          .font(SoberType.footnote)
          .foregroundStyle(Palette.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var contextCard: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: Space.md) {
        VStack(alignment: .leading, spacing: Space.xxs) {
          Text("Session context")
            .font(SoberType.body)
          Text("These factors can change performance without alcohol.")
            .font(SoberType.footnote)
            .foregroundStyle(Palette.textSecondary)
        }

        Stepper(value: $model.researchPreferences.sleepHours, in: 0...14, step: 0.5) {
          HStack {
            Text("Sleep last night")
            Spacer()
            Text("\(model.researchPreferences.sleepHours, specifier: "%.1f") h")
              .monospacedDigit()
              .foregroundStyle(Palette.accent)
          }
        }

        Divider().overlay(Palette.line)
        contextToggle("Caffeine within 6 hours", isOn: $model.researchPreferences.caffeineWithinSixHours)
        contextToggle("Medication may affect performance", isOn: $model.researchPreferences.medicationMayAffectPerformance)
        contextToggle("Illness or injury may affect performance", isOn: $model.researchPreferences.illnessOrInjuryMayAffectPerformance)
        contextToggle("Strenuous exercise within 2 hours", isOn: $model.researchPreferences.strenuousExerciseWithinTwoHours)

        Picker("Vision correction", selection: $model.researchPreferences.visionCorrection) {
          Text("None").tag(ResearchVisionCorrection.none)
          Text("Glasses").tag(ResearchVisionCorrection.glasses)
          Text("Contacts").tag(ResearchVisionCorrection.contactLenses)
          Text("Not set").tag(ResearchVisionCorrection.unknown)
        }
      }
    }
  }

  private var dataCard: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: Space.sm) {
        HStack {
          VStack(alignment: .leading, spacing: Space.xxs) {
            Text("Local dataset")
              .font(SoberType.body)
            Text("\(model.researchSessions.count) versioned session\(model.researchSessions.count == 1 ? "" : "s")")
              .font(SoberType.footnote)
              .foregroundStyle(Palette.textSecondary)
          }
          Spacer()
          Image(systemName: "externaldrive.fill")
            .foregroundStyle(Palette.accent)
        }

        Text("Participant key: \(shortParticipantID)")
          .font(SoberType.footnote)
          .foregroundStyle(Palette.textSecondary)

        if let exportURL {
          ShareLink(item: exportURL) {
            Label("Share JSON export", systemImage: "square.and.arrow.up")
          }
          .buttonStyle(PrimaryActionButtonStyle())
        } else {
          Button {
            preparingExport = true
            Task {
              exportURL = await model.prepareResearchExport()
              preparingExport = false
            }
          } label: {
            if preparingExport {
              ProgressView().tint(Palette.textPrimary)
            } else {
              Label("Prepare JSON export", systemImage: "doc.badge.arrow.up")
            }
          }
          .buttonStyle(PrimaryActionButtonStyle())
          .disabled(!model.researchConsent || model.researchSessions.isEmpty || preparingExport)
          .opacity(model.researchConsent && !model.researchSessions.isEmpty ? 1 : 0.42)
        }

        Button("Delete local research data", role: .destructive) {
          showingDeleteConfirmation = true
        }
        .frame(maxWidth: .infinity)
        .disabled(model.researchSessions.isEmpty)
      }
    }
  }

  private var eligibleBaselineCount: Int {
    model.baselineProfile?.eligibleSessionCount ?? (model.isFounderPreview ? 5 : 0)
  }

  private var shortParticipantID: String {
    String(model.participantID.rawValue.suffix(12))
  }

  private func contextToggle(_ title: String, isOn: Binding<Bool>) -> some View {
    Toggle(title, isOn: isOn)
      .font(SoberType.subheadline)
      .tint(Palette.accent)
  }
}
