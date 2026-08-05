import SwiftUI

/// Parent side: which nights and what time the driving-check window opens.
/// The window always ends at 6 AM, or earlier the moment the teen
/// completes a valid check — that part isn't configurable here.
struct GuardianScheduleView: View {
  @Binding var schedule: DrivingSchedule
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          ScreenHeader(
            eyebrow: "Guardian Mode",
            title: "When should we watch?",
            detail:
              "On these nights, starting at this time, we'll check whether a completion happened before driving starts. The window always closes at 6 AM."
          )

          SoberCard {
            VStack(alignment: .leading, spacing: 14) {
              Text("Active nights").font(.headline)
              HStack(spacing: 8) {
                ForEach(Weekday.allCases, id: \.self) { day in
                  dayToggle(day)
                }
              }
            }
          }

          SoberCard {
            VStack(alignment: .leading, spacing: 14) {
              Text("Start time").font(.headline)
              DatePicker(
                "Start time",
                selection: startTimeBinding,
                displayedComponents: .hourAndMinute
              )
              .datePickerStyle(.wheel)
              .labelsHidden()
              .frame(maxWidth: .infinity)
            }
          }

          Text(
            "If the phone is off or left at home during the window, we can't detect anything — no alert is sent in that case."
          )
          .font(.caption)
          .foregroundStyle(Palette.textSecondary)
        }
        .padding(22)
      }
      .soberBackground()
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private func dayToggle(_ day: Weekday) -> some View {
    let isOn = schedule.activeDays.contains(day)
    return Button {
      if isOn {
        schedule.activeDays.remove(day)
      } else {
        schedule.activeDays.insert(day)
      }
    } label: {
      Text(day.shortLabel)
        .font(.caption.weight(.semibold))
        .frame(width: 42, height: 42)
        .background(
          isOn ? Palette.primary : Palette.secondary.opacity(0.18),
          in: Circle()
        )
        .foregroundStyle(isOn ? Palette.textPrimary : Palette.textSecondary)
    }
    .buttonStyle(.plain)
  }

  private var startTimeBinding: Binding<Date> {
    Binding(
      get: {
        Calendar.current.date(
          bySettingHour: schedule.startHour, minute: schedule.startMinute, second: 0, of: Date())
          ?? Date()
      },
      set: { newValue in
        let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
        schedule.startHour = components.hour ?? schedule.startHour
        schedule.startMinute = components.minute ?? schedule.startMinute
      }
    )
  }
}
