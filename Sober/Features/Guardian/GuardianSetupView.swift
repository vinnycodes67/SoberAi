import SwiftUI

/// Home-reachable settings screen for Guardian Mode, mirroring how Safety
/// Circle and Research Center are reached — not part of onboarding, since
/// Guardian Mode is an independent, opt-in system alongside them.
struct GuardianSetupView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var guardianCoordinator: GuardianCoordinator
  @Environment(\.dismiss) private var dismiss
  @State private var showingPairing = false
  @State private var showingSchedule = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          ScreenHeader(
            eyebrow: "Guardian Mode",
            title: "A check-in, not a monitor.",
            detail:
              "Pairing is mutual and visible on both phones. The other person only ever sees whether a check happened before driving — never a score, never camera or pupil data."
          )

          roleCard

          if model.guardianRole == .teen {
            teenSection
          } else if model.guardianRole == .parent {
            parentSection
          }
        }
        .padding(22)
      }
      .soberBackground()
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(isPresented: $showingPairing) {
        pairingSheet
          .preferredColorScheme(.dark)
      }
      .sheet(isPresented: $showingSchedule) {
        GuardianScheduleView(schedule: $model.drivingSchedule)
          .preferredColorScheme(.dark)
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
    }
  }

  private var roleCard: some View {
    SoberCard {
      VStack(alignment: .leading, spacing: 14) {
        Text("This phone is").font(.headline)
        Picker("Role", selection: $model.guardianRole) {
          Text("Not set up").tag(GuardianRole.none)
          Text("A teen driver").tag(GuardianRole.teen)
          Text("A parent").tag(GuardianRole.parent)
        }
        .pickerStyle(.segmented)
        Text(roleDetail)
          .font(.caption)
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
        HStack(spacing: 14) {
          ZStack {
            Circle().fill(Palette.item1.opacity(0.16))
            Image(systemName: pairingIcon)
              .foregroundStyle(Palette.item1)
          }
          .frame(width: 50, height: 50)
          VStack(alignment: .leading, spacing: 4) {
            Text("Pairing")
              .font(.headline)
              .foregroundStyle(Palette.textPrimary)
            Text(pairingSummary)
              .font(.subheadline)
              .foregroundStyle(Palette.textSecondary)
              .multilineTextAlignment(.leading)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
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
    case .awaitingAcceptance: "Invite ready — waiting for a scan"
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
      VStack(alignment: .leading, spacing: 8) {
        Text("Tonight's window").font(.headline)
        if let window = model.drivingSchedule.window(containing: Date()) {
          let state = model.guardianCheckWindowState(for: window.id)
          Text(state.isSatisfied ? "Check completed for tonight." : "Check not completed yet.")
            .font(.subheadline)
            .foregroundStyle(state.isSatisfied ? Palette.textSecondary : Palette.warning)
          if let retestAt = state.retestAvailableAt, Date() < retestAt {
            Text(
              "One retest available at \(retestAt.formatted(date: .omitted, time: .shortened))."
            )
            .font(.caption)
            .foregroundStyle(Palette.textSecondary)
          }
        } else {
          Text("No active window right now.")
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
        }
      }
    }
  }

  private var scheduleCard: some View {
    Button { showingSchedule = true } label: {
      SoberCard {
        HStack(spacing: 14) {
          ZStack {
            Circle().fill(Palette.item2.opacity(0.16))
            Image(systemName: "calendar.badge.clock")
              .foregroundStyle(Palette.item2)
          }
          .frame(width: 50, height: 50)
          VStack(alignment: .leading, spacing: 4) {
            Text("Driving schedule")
              .font(.headline)
              .foregroundStyle(Palette.textPrimary)
            Text(scheduleSummary)
              .font(.subheadline)
              .foregroundStyle(Palette.textSecondary)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
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
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Recent check-ins").font(.headline)
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
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
        } else {
          ForEach(Array(guardianCoordinator.parentEvents.prefix(6).enumerated()), id: \.offset) {
            _, event in
            HStack {
              Circle()
                .fill(event.outcome == .completed ? Palette.primary : Palette.error)
                .frame(width: 7, height: 7)
              Text(event.outcome == .completed ? "Completed" : "Missed")
                .font(.subheadline)
              Spacer()
              Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
            }
          }
        }
      }
    }
  }
}
