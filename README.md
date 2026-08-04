# Sober

A native iOS founder-review MVP for a private impairment-awareness check and
ride-home intervention. Built with Swift 6, SwiftUI, ARKit, and an iOS 17
deployment target.

> This is an interaction and technical prototype—not a validated medical
> device, impairment detector, BAC estimator, or safe-to-drive test. Do not use
> it to decide whether to drive or operate machinery.

## What is included

- Separate biometric processing and retention consent
- Five-session starter baseline built from complete, high-quality sober sessions
- Four-hour self-report gate that overrides task scoring
- Six-trial color/shape reaction task with latency, errors, misses, anticipations, and variability
- Motor tracking, time-estimation, and a 25-second fixation/pursuit/structured-saccade ocular protocol, with a separate 11-second Reduced Motion variant
- Mirrored TrueDepth preview with face, centering, distance, lighting, stability, frame-rate, dropout, and sample-count gating
- Separate left/right gaze, blink, head-motion, and target samples held in a bounded in-memory buffer
- Research-only fixation jitter, pursuit error, saccade error, asymmetry, blink-rate, and head-compensation summaries
- A transparent weighted prototype scorer that refuses to guess on unusable capture
- Exactly three result states: signals detected, inconclusive, no signals detected
- No green/pass/cleared/safe state
- Ride, call, and message actions on every result
- Safety Circle pre-commitment setup with explicit parent-alert consent
- Immediate automatic parent alert for live `SIGNALS_DETECTED` results
- Visible sending, relay-accepted, and failed states with manual call/message fallback
- Stable alert event IDs plus per-recipient durable relay coordination, 24-hour duplicate suppression, and rate limiting
- A founder-only Research Center with explicit consent, contextual confounders, local session count, JSON export, and delete-all controls
- Versioned, pseudonymous research envelopes stored locally with file protection where available
- Founder previews for all result states using visibly labeled sample data
- Unit tests for safety invariants, ocular quality, research storage/baselines, and alert reliability

## Run it

Requirements: macOS with Xcode 26+, an iOS 17+ simulator or iPhone, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Sober.xcodeproj
```

Select the `Sober` scheme and run on an iPhone simulator. The simulator is useful
for founder result previews, but a live check correctly becomes inconclusive
because face tracking is unavailable. For camera calibration and the ocular
protocol, use an iPhone with TrueDepth and select your Apple development team in
the target's Signing & Capabilities settings.

### Configure automatic parent alerts

iOS does not permit an app to silently send an SMS through Messages. Sober
therefore posts the safety event to the relay in [`Backend/`](Backend/), which
sends the parent SMS through Twilio. The app shares only the result category,
names, parent phone number, time, and safety copy—never raw camera data,
landmarks, task scores, or a BAC estimate.

1. From `Backend/`, deploy the Worker with `npx wrangler deploy`. The checked-in
   `wrangler.toml` creates the SQLite-backed `AlertCoordinator` Durable Object.
2. Add the five secrets listed in `Backend/wrangler.toml` with
   `npx wrangler secret put <NAME>`. Keep
   `ALERT_ALLOWED_RECIPIENTS` restricted to founder phone numbers during MVP
   review.
3. Set these user-defined Xcode build settings for the Sober target:

   ```text
   SOBER_PARENT_ALERT_API_URL = https://<worker>/v1/alerts
   SOBER_PARENT_ALERT_TOKEN = <same value as ALERT_SHARED_TOKEN>
   ```

The shared build token plus recipient allowlist are acceptable only for a
closed founder prototype. The relay also limits one recipient to three new
alerts per ten minutes by default. Before public testing, replace the shared
token with per-install credentials, verified parent pairing, abuse controls,
and App Attest. Never put Twilio credentials in the iOS app.

For the quickest review:

1. Complete both consent switches.
2. Choose **Explore founder demo**.
3. Open **Safety Circle**, add the parent number, enable automatic alerts, and
   consent to sharing the safety result.
4. Run the live prototype from **Start a check**.
5. Scroll to **Review every safety state** to inspect all result paths.
6. Open **Research Center** to review consent, context, session count, baseline
   quality, JSON export, and delete-all behavior.
7. Confirm that a concerning result immediately shows sending/relay-accepted
   status and cannot be dismissed until the warning is acknowledged.

## Verify it

```bash
xcodebuild \
  -project Sober.xcodeproj \
  -scheme Sober \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test

(cd Backend && npm test)
(cd Backend && npx wrangler deploy --dry-run)
```

## Important prototype limits

- The scorer thresholds and weights are illustrative and have no clinical validity.
- Simulator live capture is unsupported and therefore inconclusive; only explicitly labeled founder previews use sample data.
- The ocular protocol is not HGN detection, a standardized field sobriety test, or a clinically validated impairment measure.
- No pupil segmentation, PLR protocol, voice task, balance task, or trained CoreML impairment model is included.
- Five high-quality sessions unlock the prototype baseline. That is a product-development minimum, not an evidence-backed clinical threshold.
- Research context is self-reported. The app has no supervised labels, breath-reference hardware integration, controlled-study ground truth, or model-training pipeline yet.
- Raw camera frames are not persisted by app code, but the prototype privacy copy still requires legal review before any external distribution.
- Parent alert delivery requires a deployed relay and network access. “Accepted” means the relay/provider accepted the submission; it does not confirm handset delivery. Founder previews never send real messages.
- Relay coordination is durable per recipient and fails closed when provider acceptance is uncertain. It still cannot prove exactly-once carrier delivery across Twilio and storage failures; a public deployment needs delivery-status webhooks and operational testing across retries, regions, and deploys.
- The relay’s shared token and recipient allowlist are founder-only controls, not production authentication or parent verification.
- Ride links open the provider; production destination and location handling remain to be implemented.

Read [Founder Review](Docs/FOUNDER_REVIEW.md) before deciding what to build next.
