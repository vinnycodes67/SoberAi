import FamilyControls
import SwiftUI

// Setup and tonight's status, on one page the teen can always open.
// User: a teen (13–17) setting Curfew up with a guardian, or checking what
// tonight looks like. They see exactly what pauses and exactly when.
// Emotional intent: transparent and calm. Nothing here is hidden from them.
struct CurfewSetupView: View {
  @EnvironmentObject private var coordinator: CurfewCoordinator
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss

  @State private var pauseSelection = FamilyActivitySelection()
  @State private var allowSelection = FamilyActivitySelection()
  @State private var showingPausePicker = false
  @State private var showingAllowPicker = false
  @State private var weeknight = Date()
  @State private var weekend = Date()
  @State private var recheckMinutes = CurfewSchedule.standard().recheckMinutes
  @State private var graceMinutes = CurfewSchedule.standard().graceMinutes
  @State private var guardianName = ""
  @State private var showingCheckIn = false
  @State private var hasLoaded = false

  private static let maximumTokenRows = 6

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DSSpace.xl) {
          if let error = coordinator.lastError {
            Text(error)
              .font(DSFont.footnote)
              .foregroundStyle(DSPalette.accent)
              .dsReadingLine()
          }
          statusCard.dsAppear(0)
          screenTime.dsAppear(1)
          whatToPause.dsAppear(2)
          alwaysAllow.dsAppear(3)
          schedule.dsAppear(4)
          homeSection.dsAppear(5)
          safeRidePromise.dsAppear(6)
          #if DEBUG
          debugTools.dsAppear(7)
          #endif
        }
        .padding(.horizontal, DSSpace.margin)
        .padding(.top, DSSpace.sm)
        .padding(.bottom, DSSpace.xxl)
      }
      .scrollIndicators(.hidden)
      .dsPageBackground()
      .navigationTitle("Curfew")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .onAppear(perform: load)
    .sheet(isPresented: $showingCheckIn) {
      CurfewCheckInView()
        .environmentObject(coordinator)
        .environmentObject(model)
        .preferredColorScheme(.dark)
    }
  }

  // MARK: - Status

  private var statusCard: some View {
    DSCard(highlighted: coordinator.decision.isWithinCurfewNight) {
      VStack(alignment: .leading, spacing: DSSpace.sm) {
        DSEyebrow("Tonight")
        // Once a minute, and only here; the rest of the page is still.
        TimelineView(.everyMinute) { context in
          statusText(now: context.date)
        }
        if showsCheckInButton {
          Button("Check in") { showingCheckIn = true }
            .buttonStyle(DSPrimaryButtonStyle())
            .padding(.top, DSSpace.xs)
        }
      }
    }
  }

  /// Any open curfew night, except after a ride was asked for: that night is
  /// over as far as the teen is concerned, and a button would say otherwise.
  private var showsCheckInButton: Bool {
    if case .liftedForRide = coordinator.decision { return false }
    return coordinator.decision.isWithinCurfewNight
  }

  private func statusText(now: Date) -> some View {
    let (title, detail) = statusLines(now: now)
    return VStack(alignment: .leading, spacing: DSSpace.xs) {
      Text(title)
        .font(DSFont.title)
        .dsTitleTracking()
        .monospacedDigit()
        .foregroundStyle(DSPalette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      Text(detail)
        .font(DSFont.callout)
        .monospacedDigit()
        .foregroundStyle(DSPalette.textSecondary)
        .dsReadingLine()
    }
  }

  private func statusLines(now: Date) -> (String, String) {
    switch coordinator.decision {
    case .noSchedule:
      return ("No curfew set", "Save a schedule below and this iPhone will know when to ask you to check in.")
    case let .beforeCurfew(next):
      guard let next else { return ("No curfew coming up", "Check the schedule below.") }
      return ("\(CurfewCopy.countdownPrefix) \(time(next.curfewAt))", countdown(to: next.curfewAt, from: now))
    case let .grace(night):
      return (
        "\(CurfewCopy.countdownPrefix) \(time(night.curfewAt))",
        "It is past curfew. Apps pause at \(time(night.pauseStartsAt)) unless you check in or get home."
      )
    case .home:
      return ("Home.", "Nothing to do tonight.")
    case .liftedForRide:
      return (
        "You asked for a ride. Nothing more tonight.",
        CurfewCopy.safeRidePromise(guardianName: coordinator.state.guardianDisplayName)
      )
    case let .checkedIn(_, nextCheckInAt):
      let last = coordinator.state.tonight?.lastCheckInAt.map(time) ?? "tonight"
      return (
        "Checked in \(last) · next check-in \(time(nextCheckInAt))",
        "Apps stay open. If you are still out at \(time(nextCheckInAt)), you will be asked again."
      )
    case .checkInDue:
      return (CurfewCopy.pausedTitle, CurfewCopy.stillWorks)
    }
  }

  private func countdown(to curfewAt: Date, from now: Date) -> String {
    let minutes = max(0, Int(curfewAt.timeIntervalSince(now) / 60))
    if minutes > 36 * 60 {
      return "Next curfew is \(curfewAt.formatted(.dateTime.weekday(.wide)))."
    }
    if minutes >= 60 {
      return "\(minutes / 60) h \(minutes % 60) min until curfew."
    }
    return "\(minutes) min until curfew."
  }

  private func time(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }

  // MARK: - Screen Time

  private var screenTime: some View {
    DSSection("Screen Time") {
      DSRows {
        DSValueRow(label: "Screen Time", value: screenTimeLabel, tint: DSPalette.textSecondary)
      }
      Text("Your guardian approves this through Family Sharing. Sober only pauses the apps and categories you choose below.")
        .font(DSFont.footnote)
        .foregroundStyle(DSPalette.textMuted)
        .dsReadingLine()
      if coordinator.screenTimeAuthorization != .approved {
        Button("Allow Screen Time") {
          Task { await coordinator.requestScreenTimeAuthorization() }
        }
        .buttonStyle(DSSecondaryButtonStyle())
        .disabled(coordinator.screenTimeAuthorization == .unavailable)
      }
    }
  }

  private var screenTimeLabel: String {
    switch coordinator.screenTimeAuthorization {
    case .notDetermined: "Not asked yet"
    case .approved: "Allowed"
    case .denied: "Not allowed"
    case .unavailable: "Unavailable on this device"
    }
  }

  // MARK: - Pickers

  private var whatToPause: some View {
    DSSection("What to pause") {
      selectionCard(
        selection: pauseSelection,
        hint: "Choose Social, Games and Entertainment. Leave Travel out; that is where ride apps live.",
        emptyAction: "Choose apps to pause",
        changeAction: "Change what pauses",
        onChoose: { showingPausePicker = true }
      )
    }
    .familyActivityPicker(isPresented: $showingPausePicker, selection: $pauseSelection)
    .onChange(of: showingPausePicker) { _, isShowing in
      if !isShowing, hasLoaded { coordinator.savePauseSelection(pauseSelection) }
    }
  }

  private var alwaysAllow: some View {
    DSSection("Always allow") {
      selectionCard(
        selection: allowSelection,
        hint: "Add Uber, Lyft, Maps and Messages here so they stay open whatever is paused.",
        emptyAction: "Choose apps to keep open",
        changeAction: "Change what stays open",
        onChoose: { showingAllowPicker = true }
      )
      Text(CurfewCopy.stillWorks)
        .font(DSFont.footnote)
        .foregroundStyle(DSPalette.textSecondary)
        .dsReadingLine()
    }
    .familyActivityPicker(isPresented: $showingAllowPicker, selection: $allowSelection)
    .onChange(of: showingAllowPicker) { _, isShowing in
      if !isShowing, hasLoaded { coordinator.saveAllowSelection(allowSelection) }
    }
  }

  private func selectionCard(
    selection: FamilyActivitySelection,
    hint: String,
    emptyAction: String,
    changeAction: String,
    onChoose: @escaping () -> Void
  ) -> some View {
    DSCard {
      VStack(alignment: .leading, spacing: DSSpace.sm) {
        Text(summary(of: selection))
          .font(DSFont.headline)
          .monospacedDigit()
          .foregroundStyle(DSPalette.textPrimary)
        Text(hint)
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textMuted)
          .dsReadingLine()
        tokenRows(selection)
        Button(isEmpty(selection) ? emptyAction : changeAction, action: onChoose)
          .buttonStyle(DSSecondaryButtonStyle())
          .padding(.top, DSSpace.xxs)
      }
    }
  }

  /// The teen always sees what is on the list. Tokens are opaque to code, but
  /// `Label` renders the real app name and icon.
  @ViewBuilder
  private func tokenRows(_ selection: FamilyActivitySelection) -> some View {
    let tokens = Array(selection.applicationTokens.prefix(Self.maximumTokenRows))
    if !tokens.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(tokens, id: \.self) { token in
          Label(token)
            .font(DSFont.body)
            .foregroundStyle(DSPalette.textPrimary)
            .frame(minHeight: DSHit.minimum)
        }
        if selection.applicationTokens.count > tokens.count {
          Text("and \(selection.applicationTokens.count - tokens.count) more")
            .font(DSFont.footnote)
            .foregroundStyle(DSPalette.textMuted)
        }
      }
    }
  }

  private func summary(of selection: FamilyActivitySelection) -> String {
    if isEmpty(selection) { return "Nothing chosen yet" }
    return [
      count(selection.applicationTokens.count, "app"),
      count(selection.categoryTokens.count, "category", plural: "categories"),
      count(selection.webDomainTokens.count, "website"),
    ].joined(separator: " · ")
  }

  private func isEmpty(_ selection: FamilyActivitySelection) -> Bool {
    selection.applicationTokens.isEmpty
      && selection.categoryTokens.isEmpty
      && selection.webDomainTokens.isEmpty
  }

  private func count(_ n: Int, _ singular: String, plural: String? = nil) -> String {
    "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
  }

  // MARK: - Schedule

  private var schedule: some View {
    DSSection("Schedule") {
      DSRows {
        DatePicker("Weeknights", selection: $weeknight, displayedComponents: .hourAndMinute)
          .font(DSFont.body)
          .foregroundStyle(DSPalette.textPrimary)
          .frame(minHeight: DSHit.minimum)
          .padding(.vertical, DSSpace.xs)
        DSSeparator()
        DatePicker("Weekends", selection: $weekend, displayedComponents: .hourAndMinute)
          .font(DSFont.body)
          .foregroundStyle(DSPalette.textPrimary)
          .frame(minHeight: DSHit.minimum)
          .padding(.vertical, DSSpace.xs)
        DSSeparator()
        Stepper(
          value: $recheckMinutes,
          in: CurfewSchedule.minimumRecheckMinutes...240,
          step: 15
        ) {
          stepperLabel("Check in every", value: "\(recheckMinutes) min")
        }
        .frame(minHeight: DSHit.minimum)
        .padding(.vertical, DSSpace.xs)
        DSSeparator()
        Stepper(
          value: $graceMinutes,
          in: 0...CurfewSchedule.maximumGraceMinutes,
          step: 5
        ) {
          stepperLabel("Grace after curfew", value: "\(graceMinutes) min")
        }
        .frame(minHeight: DSHit.minimum)
        .padding(.vertical, DSSpace.xs)
      }
      .tint(DSPalette.accent)

      Text("Your guardian sets this. Until then, this phone uses the example schedule.")
        .font(DSFont.footnote)
        .foregroundStyle(DSPalette.textMuted)
        .dsReadingLine()

      Button("Save schedule", action: saveSchedule)
        .buttonStyle(DSSecondaryButtonStyle())

      if coordinator.device.monitoredActivityCount > 0 {
        Text("\(coordinator.device.monitoredActivityCount) check-in windows registered with Screen Time.")
          .font(DSFont.footnote)
          .monospacedDigit()
          .foregroundStyle(DSPalette.textMuted)
      }
    }
  }

  private func stepperLabel(_ label: String, value: String) -> some View {
    HStack {
      Text(label)
        .font(DSFont.body)
        .foregroundStyle(DSPalette.textPrimary)
      Spacer(minLength: DSSpace.sm)
      Text(value)
        .font(DSFont.body)
        .monospacedDigit()
        .foregroundStyle(DSPalette.textSecondary)
    }
  }

  // MARK: - Home

  private var homeSection: some View {
    DSSection("Home") {
      DSRows {
        DSValueRow(label: "Location", value: homeAuthorizationLabel, tint: DSPalette.textSecondary)
        if let reading = coordinator.state.home {
          DSSeparator()
          DSValueRow(
            label: "Last reading",
            value: "\(reading.isHome ? "Home" : "Not home") · \(time(reading.observedAt))",
            tint: DSPalette.textSecondary
          )
        }
      }
      Text("Whether you are home is worked out on this iPhone and stays here. A check-in shares where you are at that moment, and only when you tap it.")
        .font(DSFont.footnote)
        .foregroundStyle(DSPalette.textMuted)
        .dsReadingLine()
      if coordinator.state.home == nil && model.guardianHomeAnchor == nil {
        Text("There is no private Home saved on this iPhone yet. Set Home in Guardian settings first.")
          .font(DSFont.footnote)
          .foregroundStyle(DSPalette.textSecondary)
          .dsReadingLine()
      }
      if coordinator.homeAuthorization != .always {
        Button("Allow Always location") { coordinator.requestHomeAuthorization() }
          .buttonStyle(DSSecondaryButtonStyle())
          .disabled(coordinator.homeAuthorization == .unavailable)
      }
    }
  }

  private var homeAuthorizationLabel: String {
    switch coordinator.homeAuthorization {
    case .notDetermined: "Not asked yet"
    case .whenInUse: "Only while using Sober · Always is needed at curfew"
    case .always: "Always"
    case .denied: "Off in iPhone Settings"
    case .unavailable: "Unavailable on this device"
    }
  }

  // MARK: - Safe Ride Promise

  private var safeRidePromise: some View {
    DSSection("Safe Ride Promise") {
      DSCard {
        VStack(alignment: .leading, spacing: DSSpace.sm) {
          Text(CurfewCopy.safeRidePromise(guardianName: guardianName))
            .font(DSFont.body)
            .foregroundStyle(DSPalette.textPrimary)
            .dsReadingLine()
          TextField("Guardian’s name", text: $guardianName)
            .font(DSFont.body)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .padding(DSSpace.md)
            .foregroundStyle(DSPalette.textPrimary)
            .background(
              RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
                .fill(DSPalette.surfaceRaised)
            )
            .onChange(of: guardianName) { _, name in
              if hasLoaded { coordinator.setGuardianName(name) }
            }
          DSValueRow(label: "Promise", value: promiseStatus, tint: DSPalette.textSecondary)
          Text("Your guardian signs this at setup: if you ask for a ride, no questions tonight.")
            .font(DSFont.footnote)
            .foregroundStyle(DSPalette.textMuted)
            .dsReadingLine()
        }
      }
    }
  }

  private var promiseStatus: String {
    if let signedAt = coordinator.state.safeRidePromiseSignedAt {
      return "Signed \(signedAt.formatted(date: .abbreviated, time: .omitted))"
    }
    return "Not yet signed"
  }

  // MARK: - Debug

  #if DEBUG
  private var debugTools: some View {
    DSSection("Debug") {
      HStack(spacing: DSSpace.lg) {
        Button("Pause now (debug)") { coordinator.debugPauseNow() }
          .buttonStyle(DSTertiaryButtonStyle(tint: DSPalette.textSecondary))
        Button("Lift (debug)") { coordinator.debugLiftNow() }
          .buttonStyle(DSTertiaryButtonStyle(tint: DSPalette.textSecondary))
      }
      Button("Sign promise (debug)") { coordinator.signSafeRidePromise() }
        .buttonStyle(DSTertiaryButtonStyle(tint: DSPalette.textSecondary))
      Text("Shield applied: \(coordinator.state.isShieldApplied ? "yes" : "no")")
        .font(DSFont.footnote)
        .foregroundStyle(DSPalette.textMuted)
    }
  }
  #endif

  // MARK: - Load and save

  private func load() {
    guard !hasLoaded else { return }
    coordinator.refresh()
    pauseSelection = coordinator.device.loadPauseSelection() ?? FamilyActivitySelection()
    allowSelection = coordinator.device.loadAllowSelection() ?? FamilyActivitySelection()
    let schedule = coordinator.state.schedule ?? .standard()
    weeknight = date(from: schedule.weeknight)
    weekend = date(from: schedule.weekend)
    recheckMinutes = schedule.recheckMinutes
    graceMinutes = schedule.graceMinutes
    guardianName = coordinator.state.guardianDisplayName ?? ""
    hasLoaded = true
  }

  private func saveSchedule() {
    var schedule = coordinator.state.schedule ?? .standard()
    schedule.weeknight = components(of: weeknight)
    schedule.weekend = components(of: weekend)
    schedule.recheckMinutes = recheckMinutes
    schedule.graceMinutes = graceMinutes
    schedule.timeZoneIdentifier = TimeZone.current.identifier
    coordinator.saveSchedule(schedule)
  }

  private func date(from components: DateComponents) -> Date {
    Calendar.current.date(
      bySettingHour: components.hour ?? 0,
      minute: components.minute ?? 0,
      second: 0,
      of: Date()
    ) ?? Date()
  }

  private func components(of date: Date) -> DateComponents {
    let calendar = Calendar.current
    return CurfewSchedule.time(
      calendar.component(.hour, from: date),
      calendar.component(.minute, from: date)
    )
  }
}
