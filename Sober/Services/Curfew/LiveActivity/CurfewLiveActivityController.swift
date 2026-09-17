import ActivityKit
import Foundation
import os

// The Lock Screen / Dynamic Island countdown, driven from the same
// `CurfewPauseDecision` that drives the pause itself. The app calls `sync`
// after every reconcile; this class works out whether an activity should be
// running for tonight and starts, updates, or ends one to match.
//
// What it never carries: a Sober result, a score, or whether a check was run.
// `CurfewCountdownAttributes` has no field for any of them and this file has
// no import that could supply one.
//
// Starting from the background: `Activity.request` only succeeds while the app
// is in the foreground. Starting one while the phone sits in a pocket at
// 10:15 p.m. needs push-to-start (iOS 17.2+), which means Vinay's backend
// sends the start push using the token from `Activity.pushToStartToken` —
// not wired yet. On iOS 17.0–17.1 there is no push-to-start at all, so the
// countdown appears the next time the teen opens Sober (or when the home
// region monitor relaunches the app, which does not count as foreground).
// Until then the activity is a bonus, not the check-in path: the notification
// and the block screen carry that.

/// What the countdown should be showing for a decision, before ActivityKit
/// gets involved. Pure, so it can be unit-tested without a device.
struct CurfewLiveActivityTarget: Equatable, Sendable {
  let nightID: String
  let state: CurfewCountdownAttributes.ContentState
  /// The instant the countdown is about. Nothing is requested for an instant
  /// further out than `CurfewLiveActivityController.maximumLeadTime`.
  let relevantAt: Date
  /// When the current copy stops being true. The system dims the activity
  /// after this if the app has not updated it.
  let staleAt: Date
  /// 1 is the Dynamic Island's first pick when several activities compete.
  let relevanceScore: Double

  /// Nil means "no activity tonight": no schedule, home, or no night to count
  /// down to. The caller ends whatever is running.
  init?(decision: CurfewPauseDecision, now: Date) {
    switch decision {
    case .noSchedule, .home, .beforeCurfew(next: nil):
      return nil

    case let .beforeCurfew(next: .some(night)):
      nightID = night.id
      state = .init(phase: .beforeCurfew, curfewAt: night.curfewAt)
      relevantAt = night.curfewAt
      staleAt = night.curfewAt
      relevanceScore = 0.5

    case let .grace(night):
      nightID = night.id
      state = .init(phase: .grace, curfewAt: night.curfewAt)
      relevantAt = night.pauseStartsAt
      staleAt = night.pauseStartsAt
      relevanceScore = 0.75

    case let .checkInDue(night, _):
      nightID = night.id
      state = .init(phase: .checkInDue, curfewAt: night.curfewAt)
      relevantAt = now
      staleAt = night.endsAt
      relevanceScore = 1

    case let .checkedIn(night, nextCheckInAt):
      nightID = night.id
      state = .init(phase: .checkedIn, curfewAt: night.curfewAt, nextCheckInAt: nextCheckInAt)
      relevantAt = nextCheckInAt
      staleAt = nextCheckInAt
      relevanceScore = 0.5

    case let .liftedForRide(night):
      nightID = night.id
      state = .init(phase: .ride, curfewAt: night.curfewAt)
      relevantAt = now
      staleAt = night.endsAt
      relevanceScore = 0.75
    }
  }

  var content: ActivityContent<CurfewCountdownAttributes.ContentState> {
    ActivityContent(state: state, staleDate: staleAt, relevanceScore: relevanceScore)
  }

  func isWithinLeadTime(_ leadTime: TimeInterval, of now: Date) -> Bool {
    relevantAt.timeIntervalSince(now) <= leadTime
  }
}

@MainActor
final class CurfewLiveActivityController: CurfewLiveActivityControlling {
  /// Live Activities are shown for at most about eight hours after they start
  /// (verify on device — Apple documents the cap loosely). A countdown to a
  /// curfew further out than that would be dropped by the system before it
  /// mattered, so it is not requested until it is within range.
  nonisolated static let maximumLeadTime: TimeInterval = 8 * 60 * 60

  private let now: @Sendable () -> Date
  private let logger = Logger(subsystem: "com.soberprototype.internal", category: "curfew")
  /// The most recent piece of ActivityKit work. Each `sync` waits for the one
  /// before it, so two refreshes in quick succession (a check-in refreshes and
  /// the scene activates, say) cannot both see "no activity yet" and start two.
  private var inFlight: Task<Void, Never>?

  init(now: @escaping @Sendable () -> Date = { Date() }) {
    self.now = now
  }

  func sync(decision: CurfewPauseDecision, guardianName: String?) async {
    let now = now()
    let logger = logger
    await enqueue {
      guard let target = CurfewLiveActivityTarget(decision: decision, now: now) else {
        // No schedule any more: take the countdown down at once. Home, or the
        // night is over: let it linger dimmed the way ended activities do.
        let policy: ActivityUIDismissalPolicy = decision == .noSchedule ? .immediate : .default
        await Self.endAll(dismissalPolicy: policy, logger: logger)
        return
      }
      guard target.isWithinLeadTime(Self.maximumLeadTime, of: now) else {
        // Tomorrow's curfew, typically reached the moment tonight's window
        // closes. Anything still running belongs to a finished night.
        await Self.endAll(dismissalPolicy: .default, logger: logger)
        return
      }

      let attributes = CurfewCountdownAttributes(nightID: target.nightID, guardianName: guardianName)
      await Self.reconcile(attributes: attributes, content: target.content, logger: logger)
    }
  }

  func endAll() async {
    let logger = logger
    await enqueue { await Self.endAll(dismissalPolicy: .default, logger: logger) }
  }

  /// Runs `work` after whatever was queued before it and waits for it.
  private func enqueue(_ work: @escaping @Sendable () async -> Void) async {
    let previous = inFlight
    let task = Task {
      await previous?.value
      await work()
    }
    inFlight = task
    await task.value
  }

  // MARK: - ActivityKit

  // `Activity` is not Sendable, so everything that touches one stays inside
  // these nonisolated helpers rather than crossing in and out of the main
  // actor. They are handed only Sendable values.

  private nonisolated static func reconcile(
    attributes: CurfewCountdownAttributes,
    content: ActivityContent<CurfewCountdownAttributes.ContentState>,
    logger: Logger
  ) async {
    var current: Activity<CurfewCountdownAttributes>?
    for activity in Activity<CurfewCountdownAttributes>.activities {
      let matches = activity.attributes.nightID == attributes.nightID
        && activity.attributes.guardianName == attributes.guardianName
      if matches, current == nil {
        current = activity
      } else {
        // Another night, a duplicate, or a stale guardian name (attributes
        // cannot change in place). Stale content should not linger.
        await activity.end(nil, dismissalPolicy: .immediate)
        logger.info("Ended stale curfew activity for \(activity.attributes.nightID, privacy: .public)")
      }
    }

    if let current {
      // Updates are budgeted by the system; skip the ones that change nothing.
      let unchanged = current.content.state == content.state
        && current.content.staleDate == content.staleDate
      if !unchanged {
        await current.update(content)
        logger.debug("Updated curfew activity to \(content.state.phase.rawValue, privacy: .public)")
      }
      return
    }

    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      logger.notice("Live Activities are off in Settings; no curfew countdown")
      return
    }
    do {
      _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
      logger.info("Started curfew activity for \(attributes.nightID, privacy: .public)")
    } catch let error as ActivityAuthorizationError {
      // Includes: not in the foreground, too many activities, attributes too
      // large, or the user turned them off since the check above.
      logger.error("Could not start curfew activity: \(error.localizedDescription, privacy: .public)")
    } catch {
      logger.error("Could not start curfew activity: \(error.localizedDescription, privacy: .public)")
    }
  }

  private nonisolated static func endAll(
    dismissalPolicy: ActivityUIDismissalPolicy,
    logger: Logger
  ) async {
    let running = Activity<CurfewCountdownAttributes>.activities
    guard !running.isEmpty else { return }
    for activity in running {
      await activity.end(nil, dismissalPolicy: dismissalPolicy)
    }
    logger.info("Ended curfew activities: \(running.count)")
  }
}
