import FamilyControls
import Foundation

// Reads the shared state, asks the evaluator, and makes the phone match the
// answer. Called from the app (foreground, after a check-in, on a home
// reading) and from the DeviceActivity monitor extension (each hourly slot),
// so it has no actor and no framework beyond ManagedSettings via the shield.
//
// Idempotent: the shield is re-applied or re-cleared every time, which the
// system treats as a no-op when nothing changed, and the state is only saved
// when something did change.
enum CurfewRuntime {
  @discardableResult
  static func reconcile(
    now: Date = Date(),
    store: any CurfewStateStoring,
    shield: CurfewShieldController = CurfewShieldController(),
    postsNotifications: Bool = true
  ) -> CurfewPauseDecision {
    let original = store.load()
    var state = original

    let decision = CurfewPauseEvaluator.evaluate(
      now: now,
      schedule: state.schedule,
      home: state.home,
      tonight: state.tonight
    )

    // A new night starts with an empty check-in record. Old check-ins never
    // carry over; the evaluator already ignores a record for another night.
    var nightChanged = false
    if let night = decision.night, decision.isWithinCurfewNight, state.tonight?.nightID != night.id {
      state.tonight = CurfewTonight(nightID: night.id)
      nightChanged = true
    }

    let wasApplied = state.isShieldApplied
    let pause = decision.shouldPause ? CurfewSelectionCodec.decode(state.pauseSelectionData) : nil

    if let pause {
      let allow = CurfewSelectionCodec.decode(state.allowSelectionData) ?? FamilyActivitySelection()
      shield.apply(pause: pause, allow: allow)
      if postsNotifications, !wasApplied || nightChanged, let nightID = decision.night?.id {
        CurfewNotifications.enqueueCheckInDue(nightID: nightID)
      }
      state.isShieldApplied = true
    } else {
      shield.lift()
      if postsNotifications {
        CurfewNotifications.clearCheckInDue()
      }
      state.isShieldApplied = false
    }

    if state.isShieldApplied != wasApplied {
      state.shieldChangedAt = now
    }
    if state != original {
      try? store.save(state)
    }
    return decision
  }
}
