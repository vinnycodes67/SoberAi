import SwiftUI

/// What the app has learned about one person's usual range.
///
/// This is the screen that makes the product's central claim inspectable: every
/// comparison is against this person and nobody else. It is deliberately not a
/// score. There is no total, no grade, and no trend line, because a summary
/// number across five unrelated measures would imply a composite the engine
/// never computes.
///
/// Before a baseline exists it says so plainly rather than showing an empty
/// chart, and it never implies a partial baseline is usable.
struct YourSteadyView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DSSpace.xl) {
        header

        if model.baselineReady {
          portrait
          whatItMeans
          contributingSessions
        } else {
          notYet
        }

        limitations
      }
      .padding(.horizontal, DSSpace.margin)
      .padding(.bottom, DSSpace.xxl)
    }
    .background(DSPalette.background.ignoresSafeArea())
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: DSSpace.sm) {
      DSEyebrow("Your steady")
      Text(model.baselineReady ? "What usual looks like for you." : "Still learning your usual.")
        .font(DSFont.hero)
        .dsHeroTracking()
        .foregroundStyle(DSPalette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      Text(
        "Each measure is compared with your own earlier sessions. The check considers those "
          + "comparisons together only to choose one of three cautious result states — never a "
          + "score or driving clearance."
      )
      .font(DSFont.callout)
      .foregroundStyle(DSPalette.textSecondary)
      .dsReadingLine()
    }
    .padding(.top, DSSpace.lg)
  }

  private var portrait: some View {
    VStack(alignment: .leading, spacing: DSSpace.md) {
      // No marker: this screen shows the range itself, not any one check.
      // Putting a tick here would invite reading it as a current verdict.
      DSBaselinePortrait(tracks: DSPortraitTrack.all, isEstablished: true)
      DSPortraitLegend()
    }
  }

  private var whatItMeans: some View {
    DSSection("How it is used") {
      DSCard {
        VStack(alignment: .leading, spacing: DSSpace.sm) {
          Text(
            "A check asks whether each measure fell outside your usual range. Enough change across "
              + "the available measures is what makes a result say changes were detected."
          )
          .font(DSFont.body)
          .foregroundStyle(DSPalette.textSecondary)
          .dsReadingLine()
          Text(
            "A measure that could not be read is left out. It is never counted as normal."
          )
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
          .dsReadingLine()
        }
      }
    }
  }

  private var contributingSessions: some View {
    DSSection("Built from") {
      DSRows {
        DSValueRow(label: "Eligible sessions", value: "\(eligibleCount)")
        DSSeparator()
        DSValueRow(label: "Not added", value: "\(excludedCount)")
        DSSeparator()
        DSValueRow(label: "Minimum required", value: "\(minimumRequired)")
        if profileVariant != .full {
          DSSeparator()
          DSValueRow(label: "Recorded with", value: profileVariant.displayName)
        }
      }
    }
  }

  private var notYet: some View {
    VStack(alignment: .leading, spacing: DSSpace.lg) {
      // Dashed bands rather than a progress bar: the portrait is honestly
      // incomplete, which reads as an invitation instead of a chore.
      DSBaselinePortrait(tracks: DSPortraitTrack.all, isEstablished: false)
      DSPortraitLegend()

      DSCard {
        VStack(alignment: .leading, spacing: DSSpace.sm) {
          DSStepMeter(filled: model.baselineSessions, total: minimumRequired)
          Text("\(model.baselineSessions) of \(minimumRequired) baseline sessions recorded")
            .font(DSFont.footnoteStrong)
            .foregroundStyle(DSPalette.textPrimary)
          Text(
            "Record these while sober. Until the range exists, a check cannot tell you whether anything changed."
          )
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
          .dsReadingLine()

          if excludedCount > 0 {
            Text(
              "\(excludedCount) session\(excludedCount == 1 ? " wasn’t" : "s weren’t") added — the camera couldn’t get a clear enough read, or not every task finished. History shows which."
            )
            .font(DSFont.footnote)
            .foregroundStyle(DSPalette.textMuted)
            .dsReadingLine()
            .padding(.top, DSSpace.xxs)
          }

          // Without this, someone whose count dropped to zero after changing
          // iPhones would think their sessions had been lost.
          if otherVariantCount > 0 {
            Text(
              "\(otherVariantCount) earlier session\(otherVariantCount == 1 ? " was" : "s were") recorded with a different version of the check, with or without the eye task or with Reduce Motion set differently. \(otherVariantCount == 1 ? "It is" : "They are") kept, but only sessions from the version this iPhone runs can be compared with its checks."
            )
            .font(DSFont.footnote)
            .foregroundStyle(DSPalette.textMuted)
            .dsReadingLine()
            .padding(.top, DSSpace.xxs)
          }
        }
      }
    }
  }

  private var limitations: some View {
    DSSection("What this is not") {
      DSCard {
        VStack(alignment: .leading, spacing: DSSpace.xs) {
          limitation("It is not a blood alcohol estimate.")
          limitation("It is not a medical or diagnostic measure.")
          limitation("Being inside your usual range does not mean it is safe to drive.")
          limitation(
            "\(BaselineThresholds.requiredSessionsInWordsCapitalized) sessions is enough to start comparing, not enough to be a validated reference."
          )
        }
      }
    }
  }

  private func limitation(_ text: String) -> some View {
    Text(text)
      .font(DSFont.footnote)
      .foregroundStyle(DSPalette.textSecondary)
      .dsReadingLine()
  }

  // MARK: - Figures
  //
  // Read from the measured profile, falling back to the stored count before
  // research data has loaded. Never from the founder preview.

  /// The protocol readiness is counting: the one the next check on this
  /// iPhone runs, since that is the only partition it can be compared with.
  private var profileVariant: OcularProtocolVariant { model.nextCheckVariant }

  private var profile: BaselineProfileSummary? { model.baselineProfile }

  /// Eligible sessions filed under a variant this iPhone's check does not run,
  /// typically from before a move to or from an iPhone without Face ID, or
  /// recorded with Reduce Motion set the other way.
  private var otherVariantCount: Int {
    model.baselineVariantBreakdown
      .filter { $0.key != profileVariant }
      .values
      .map(\.eligibleSessionCount)
      .reduce(0, +)
  }

  private var eligibleCount: Int {
    profile?.eligibleSessionCount ?? model.measuredEligibleSessions
  }

  private var excludedCount: Int {
    profile?.excludedSessionCount ?? 0
  }

  private var minimumRequired: Int {
    profile?.minimumRequiredSessions ?? BaselineThresholds.requiredSessions
  }
}
