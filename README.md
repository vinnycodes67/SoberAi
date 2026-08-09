# Sober

A native iOS founder-review MVP for a private impairment-awareness check and
ride-home intervention. Built with Swift 6, SwiftUI, ARKit, and an iOS 17
deployment target.

> This is an interaction and technical prototype—not a validated medical
> device, impairment detector, BAC estimator, or safe-to-drive test. Do not use
> it to decide whether to drive or operate machinery.

## Public v1

- Separate biometric processing and retention consent
- Five-session starter baseline built from complete, high-quality sober sessions
- Four-hour self-report gate that overrides task scoring
- Six-trial color/shape reaction task with latency, errors, misses, anticipations, and variability
- Motor tracking, time-estimation, and a 25-second fixation/pursuit/structured-saccade ocular protocol, with a separate 11-second Reduced Motion variant
- Mirrored TrueDepth preview with face, centering, distance, lighting, stability, frame-rate, dropout, sample-count, and capture-duration quality gating
- Separate left/right gaze, blink, head-motion, and target samples held in a bounded in-memory buffer
- Research-only fixation jitter, pursuit error, saccade error, asymmetry, optional blink-rate, and head-compensation summaries
- A transparent weighted prototype scorer that refuses to guess on unusable capture
- Exactly three result states: signals detected, inconclusive, no signals detected
- No green/pass/cleared/safe state
- A read-only **How results work** path that shows all three states without
  using the camera, scoring a session, or modifying History or the baseline
- Ride, call, and message actions on every result
- Safety Circle ride destination stored only on this iPhone
- Privacy Lock, local deletion/reset, archive recovery, and a plain-language
  inventory of what is and is not stored
- Availability-gated iOS 26 Liquid Glass controls, calm motion, Dynamic Type,
  Reduce Motion, and Reduce Transparency support with an iOS 17 material fallback
- Unit, UI, archive, and public-binary checks for the safety boundaries

## Internal v1.1 prototype

The `SoberInternal` target retains unfinished founder-only work that is not a
public v1 capability:

- Single-use guardian invites and relationship-scoped P-256 signed requests
- Immediate in-app help requests for live `SIGNALS_DETECTED` results
- Guardian-proposed daily check-in times with explicit screened-person acceptance or decline
- Optional “away from Home” condition using a one-time, foreground-only location check; the Home coordinate stays in this-device-only Keychain storage
- Local daily reminders and completion-only Guardian status; neither the location nor screening outcome is shared
- A private Circle Map with a consented latest-location marker, accuracy radius, freshness state, and foreground/background permission controls
- Circle sharing is person-controlled, signed per relationship, immediately pausable, and retains no route history in the founder MVP
- Exactly three screened-person help states: requesting help, guardian confirmed, or contact someone now
- Stable alert event IDs persisted before submission, Durable Object coordination, replay rejection, coalescing, and revocation
- A founder-only Research Center with explicit consent, contextual confounders, local session count, JSON export, and delete-all controls
- Versioned, pseudonymous research envelopes stored locally with file protection where available
- Founder previews for all result states using visibly labeled sample data

Guardian, Circle location sharing, and Research Center are compile-time gated
from public navigation. They remain blocked from public release until their
identity, delivery, security, privacy, and physical-device gates are complete.

## Run it

Requirements: macOS with Xcode 26+, an iOS 17+ simulator or iPhone, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Sober.xcodeproj
```

Select the public `Sober` scheme for the local-only v1 surface. Use
`SoberInternal` only for founder-controlled Guardian, Circle, Research, and
sample-result review. The simulator is useful for UI review, but a live check
correctly becomes inconclusive because face tracking is unavailable. For camera
calibration and the ocular protocol, use an iPhone with TrueDepth and select
your Apple development team in the target's Signing & Capabilities settings.

### Run founder-only Guardian Mode

The same app supports both roles. One founder creates a single-use invite; a
second founder redeems it as Guardian. Every later request is signed by that
role's device key. The founder slice uses in-app polling so the complete
invite → request → “I'm helping” → confirmation loop can be reviewed without
claiming that push or SMS is already configured.

1. Start the local Worker:

   ```bash
   cd Backend
   npx wrangler dev --ip 127.0.0.1 --port 8787
   ```

2. Run the iOS app in the simulator. `project.yml` points the founder Debug
   build at `http://127.0.0.1:8787`.
3. Open **Guardian Mode**, accept the consent, and create an invite.
4. On a second founder installation, open **Guardian Mode**, paste the invite,
   accept the guardian consent, and join.
5. Keep the Guardian screen open during founder testing; it reconciles every
   three seconds. A concerning live result creates the minimal request and the
   guardian can tap **I'm helping**.
6. On the Guardian installation, choose a daily time and send the check-in plan
   for approval. On the screened person's installation, review and accept or
   decline it. An away-from-Home plan also asks the person to save Home while
   physically there; that coordinate never leaves their phone.
7. Open **Circle Map** on the screened person's installation and deliberately
   turn on sharing. Grant foreground location first; use **Allow background
   updates** only if that person wants the map to stay current after leaving
   Sober. The Guardian installation can then refresh the same map.

For two physical devices, deploy the Worker and change
`SOBER_GUARDIAN_API_URL` in `project.yml` to its HTTPS origin before regenerating
the project. Do not distribute that build beyond founder-controlled devices:
founder relationship creation intentionally bypasses phone verification and
App Attest, and APNs/SMS fallback is not implemented yet.

For the quickest review:

1. Complete both consent switches.
2. Choose **Explore founder demo**.
3. Open **Safety Circle** and give the ride destination a recognizable name and
   full street address.
4. Open **Guardian Mode** and create or redeem the founder invite.
5. Run the live prototype from **Start a check**.
6. Scroll to **Review every safety state** to inspect all result paths.
7. Open **Research Center** to review consent, context, session count, baseline
   quality, JSON export, and delete-all behavior.
8. Confirm that a concerning result shows **Requesting help**, never provider
   delivery language, and changes to **Your guardian is helping** only after the
   second installation signs the acknowledgment.

## Verify it

```bash
xcodegen generate

xcodebuild \
  -project Sober.xcodeproj \
  -scheme Sober \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test \
  -only-testing:SoberTests

Scripts/run-ui-tests.sh
Scripts/check-release-metadata.sh
Scripts/check-public-binary.sh
Scripts/rehearse-app-store-package.sh
npm test --prefix Backend
git diff --check
```

The UI script retains compact-device and large-accessibility screenshots inside
timestamped `.xcresult` bundles under `.artifacts/ui-tests/`. See
[Phase 3 Integration](Docs/PHASE_3_INTEGRATION.md) for the CI and evidence
boundary, [Local Data Recovery](Docs/LOCAL_DATA_RECOVERY_RUNBOOK.md) for archive
failures, and [Release Rollback](Docs/RELEASE_ROLLBACK_RUNBOOK.md) for stop-ship
and rollback rehearsal. Phase 5 owners should use
[App Store Submission](Docs/APP_STORE_SUBMISSION.md),
[App Review Rehearsal](Docs/APP_REVIEW_REHEARSAL.md), and the
[Phase 5 Release Checklist](Docs/PHASE_5_RELEASE_CHECKLIST.md) together; an
unsigned local archive is not proof of Apple validation or TestFlight upload.

## Important prototype limits

- The scorer thresholds and weights are illustrative and have no clinical validity.
- Simulator live capture is unsupported and therefore inconclusive; only explicitly labeled founder previews use sample data.
- The ocular protocol is not HGN detection, a standardized field sobriety test, or a clinically validated impairment measure.
- No pupil segmentation, PLR protocol, voice task, balance task, or trained CoreML impairment model is included.
- Five high-quality sessions unlock the prototype baseline. That is a product-development minimum, not an evidence-backed clinical threshold.
- Research context is self-reported. The app has no supervised labels, breath-reference hardware integration, controlled-study ground truth, or model-training pipeline yet.
- Raw camera frames are not persisted by app code, but the prototype privacy copy still requires legal review before any external distribution.
- Guardian Mode is founder-only. It currently uses signed in-app polling; APNs, notification deep links, phone verification, App Attest, and the 30-second SMS fallback remain blocked work.
- Scheduled check-ins use ordinary local notifications, which can be delayed or hidden by system notification settings and Focus. Their away-from-Home condition still uses only the private, one-time Home comparison.
- Circle Map is a separate, explicit location-sharing feature. Foreground sharing works only while Sober is active; background updates require the person's separate Always Location authorization and display the system location indicator. Force-quitting the app, disabling Location Services, Low Power behavior, poor GPS/Wi-Fi/cellular conditions, or iOS scheduling can delay updates, so the UI always shows age and accuracy instead of claiming continuous real-time tracking.
- The founder relay stores only the latest Circle location and expires it after 24 hours. It has no route history, multi-member circles, place alerts, crash detection, identity recovery, or production security review yet.
- A missed or overdue check-in means only that no completion was recorded. It must never be displayed or communicated as evidence of impairment.
- A guardian confirmation is real only after the backend accepts the guardian device's signed acknowledgment. The UI makes no delivery/open claim from transport state.
- The device signing key and minimal pending event receipt are stored in this-device-only Keychain storage. This founder build does not provide account recovery or multi-device continuity.
- Ride links open the provider; production ride handoff still needs device testing.

Read [Founder Review](Docs/FOUNDER_REVIEW.md) before deciding what to build next.
The visual and motion rules live in [DESIGN.md](DESIGN.md).
