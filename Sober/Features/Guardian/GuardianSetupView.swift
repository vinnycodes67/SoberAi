import SwiftUI

/// Home-reachable settings screen for Guardian Mode, mirroring how Safety
/// Circle and Research Center are reached — not part of onboarding, since
/// Guardian Mode is an independent, opt-in system alongside them.
struct GuardianSetupView: View {
  /// False when this is a tab destination rather than a presented sheet —
  /// there is nothing to dismiss, so the Done button must not appear.
  var showsDoneButton = true
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var guardianCoordinator: GuardianCoordinator
  @Environment(\.dismiss) private var dismiss
  @State private var showingPairing = false
  @State private var showingSchedule = false

  var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: Space.md) {
          ScreenHeader(
            eyebrow: "Guardian Mode",
            title: "A check-in, not a monitor.",
            detail:
              "Pairing is mutual and visible on both phones. The other person only ever sees whether a check happened before driving, never a score, never camera or pupil data."
          )

          roleCard

          if model.guardianRole == .teen {
            teenSection
          } else if model.guardianRole == .parent {
            parentSection
          }
        }
        .padding(Space.lg)
      }
      .soberBackground()
      .sheet(isPresented: $showingPairing) {
        pairingSheet
      }
      .sheet(isPresented: $showingSchedule) {
        GuardianScheduleView(schedule: $model.drivingSchedule)
      }
      .onChange(of: model.guardianRole) { _, role in
        if role == .teen {
          guardianCoordinator.startTeenMonitoring()
        } else if role == .parent {
          guardianCoordinator.startParentMonitoring()
        } else {
          guardianCoordinator.stopTeenMonitoring()
        }
      }
      .navigationTitle("Guardian Mode")
      .navigationBarTitleDisplayMode(.inline)
  }

  private var roleCard: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: Space.sm) {
        Text("This phone is").font(SoberType.body)
        Picker("Role", selection: $model.guardianRole) {
          Text("Not set up").tag(GuardianRole.none)
          Text("A teen driver").tag(GuardianRole.teen)
          Text("A parent").tag(GuardianRole.parent)
        }
        .pickerStyle(.segmented)
        Text(roleDetail)
          .font(SoberType.footnote)
          .foregroundStyle(Palette.textSecondary)
      }
    }
  }

  private var roleDetail: String {
    switch model.guardianRole {
    case .none:
      return "Guardian Mode is off. Nothing else about how you use Sober changes."
    case .teen:
      return
        "Pair with a parent. If you start driving during the scheduled window without completing a check, they'll get an alert."
    case .parent:
      return
        "Pair with your teen and set the driving schedule. You'll only ever see whether they checked in."
    }
  }

  @ViewBuilder
  private var teenSection: some View {
    pairingStatusCard
    if case .paired = guardianCoordinator.pairing.status {
      windowStatusCard
    }
  }

  @ViewBuilder
  private var parentSection: some View {
    pairingStatusCard
    if case .paired = guardianCoordinator.pairing.status {
      scheduleCard
      recentEventsCard
    }
  }

  private var pairingStatusCard: some View {
    Button { showingPairing = true } label: {
      SoberCard {
        HStack(spacing: Space.sm) {
          ZStack {
            Circle().fill(Palette.surfaceRaised)
            Image(systemName: pairingIcon)
              .foregroundStyle(Palette.textSecondary)
          }
          .frame(width: 50, height: 50)
          VStack(alignment: .leading, spacing: Space.xxs) {
            Text("Pairing")
              .font(SoberType.body)
              .foregroundStyle(Palette.textPrimary)
            Text(pairingSummary)
              .font(SoberType.subheadline)
              .foregroundStyle(Palette.textSecondary)
              .multilineTextAlignment(.leading)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(SoberType.footnoteStrong)
            .foregroundStyle(Palette.textSecondary)
        }
      }
    }
    .buttonStyle(SoberCardButtonStyle())
  }

  private var pairingIcon: String {
    if case .paired = guardianCoordinator.pairing.status { return "checkmark.circle.fill" }
    return "qrcode"
  }

  private var pairingSummary: String {
    switch guardianCoordinator.pairing.status {
    case .paired(let info): "Paired with \(info.participantName)"
    case .awaitingAcceptance: "Invite ready, waiting for a scan"
    case .working: "Setting up…"
    case .failed(let message): message
    case .notPaired: "Not paired yet"
    }
  }

  @ViewBuilder
  private var pairingSheet: some View {
    if model.guardianRole == .teen {
      GuardianPairingInviteView(pairing: guardianCoordinator.pairing) { info in
        model.guardianPairingInfo = info
        guardianCoordinator.startTeenMonitoring()
      }
    } else {
      GuardianPairingScanView(pairing: guardianCoordinator.pairing) { info in
        model.guardianPairingInfo = info
        guardianCoordinator.startParentMonitoring()
      }
    }
  }

  private var windowStatusCard: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: Space.xs) {
        Text("Tonight's window").font(SoberType.body)
        if let window = model.drivingSchedule.window(containing: Date()) {
          let state = model.guardianCheckWindowState(for: window.id)
          Text(state.isSatisfied ? "Check completed for tonight." : "Check not completed yet.")
            .font(SoberType.subheadline)
            .foregroundStyle(state.isSatisfied ? Palette.textSecondary : Palette.warning)
          if let retestAt = state.retestAvailableAt, Date() < retestAt {
            Text(
              "One retest available at \(retestAt.formatted(date: .omitted, time: .shortened))."
            )
            .font(SoberType.footnote)
            .foregroundStyle(Palette.textSecondary)
          }
        } else {
          Text("No active window right now.")
            .font(SoberType.subheadline)
            .foregroundStyle(Palette.textSecondary)
        }
      }
    }
  }

  private var scheduleCard: some View {
    Button { showingSchedule = true } label: {
      SoberCard {
        HStack(spacing: Space.sm) {
          ZStack {
            Circle().fill(Palette.surfaceRaised)
            Image(systemName: "calendar.badge.clock")
              .foregroundStyle(Palette.textSecondary)
          }
          .frame(width: 50, height: 50)
          VStack(alignment: .leading, spacing: Space.xxs) {
            Text("Driving schedule")
              .font(SoberType.body)
              .foregroundStyle(Palette.textPrimary)
            Text(scheduleSummary)
              .font(SoberType.subheadline)
              .foregroundStyle(Palette.textSecondary)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(SoberType.footnoteStrong)
            .foregroundStyle(Palette.textSecondary)
        }
      }
    }
    .buttonStyle(SoberCardButtonStyle())
  }

  private var scheduleSummary: String {
    let days = Weekday.allCases
      .filter { model.drivingSchedule.activeDays.contains($0) }
      .map(\.shortLabel)
      .joined(separator: ", ")
    let time =
      Calendar.current.date(
        bySettingHour: model.drivingSchedule.startHour,
        minute: model.drivingSchedule.startMinute,
        second: 0,
        of: Date()
      )?.formatted(date: .omitted, time: .shortened) ?? ""
    return days.isEmpty ? "No nights selected" : "\(days) at \(time)"
  }

  private var recentEventsCard: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: Space.sm) {
        HStack {
          Text("Recent check-ins").font(SoberType.body)
          Spacer()
          Button {
            Task { await guardianCoordinator.refreshParentEvents() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .accessibilityLabel("Refresh")
        }
        if guardianCoordinator.parentEvents.isEmpty {
          Text("No check-ins recorded yet.")
            .font(SoberType.subheadline)
            .foregroundStyle(Palette.textSecondary)
        } else {
          ForEach(Array(guardianCoordinator.parentEvents.prefix(6).enumerated()), id: \.offset) {
            _, event in
            HStack {
              Circle()
                .fill(event.outcome == .completed ? Palette.textMuted : Palette.accent)
                .frame(width: 7, height: 7)
              Text(event.outcome == .completed ? "Completed" : "Missed")
                .font(SoberType.subheadline)
              Spacer()
              Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                .font(SoberType.footnote)
                .foregroundStyle(Palette.textSecondary)
            }
          }
        }
      }
    }
  }
}
