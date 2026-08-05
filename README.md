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
- Mirrored TrueDepth preview with face, centering, distance, lighting, stability, frame-rate, dropout, sample-count, and capture-duration quality gating
- Separate left/right gaze, blink, head-motion, and target samples held in a bounded in-memory buffer
- Research-only fixation jitter, pursuit error, saccade error, asymmetry, optional blink-rate, and head-compensation summaries
- A transparent weighted prototype scorer that refuses to guess on unusable capture
- Exactly three result states: signals detected, inconclusive, no signals detected
- No green/pass/cleared/safe state
- Ride, call, and message actions on every result — all require a tap, nothing sends automatically
- Safety Circle pre-commitment setup: name one contact ahead of time for a fast manual call/message
- Guardian Mode: mutual, visible QR pairing between a teen and parent phone over CloudKit, with a driving-window check-in that shares only a completed/missed fact, never a score
- A founder-only Research Center with explicit consent, contextual confounders, local session count, JSON export, and delete-all controls
- Versioned, pseudonymous research envelopes stored locally with file protection where available
- Founder previews for all result states using visibly labeled sample data
- Availability-gated iOS 26 Liquid Glass controls, calm motion, Dynamic Type, Reduce Motion, and Reduce Transparency support with an iOS 17 material fallback
- Unit tests for safety invariants, ocular quality, research storage/baselines, and Guardian Mode's schedule/retry rules

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

There is intentionally no backend for parent notification: automatic SMS
relays cost real money at any scale (carrier fees, and eventually A2P 10DLC
registration) and this project has no budget for either. Getting help after a
concerning result works two ways instead, both free:

1. The manual **Call**/**Message** buttons on the result screen, which open
   the native Phone/Messages apps via `tel:`/`sms:` — no backend involved.
2. **Guardian Mode**, for a paired teen/parent pair: mutual QR pairing over
   CloudKit, free with the same Apple Developer account already required to
   ship any iOS app. It shares only a completed/missed fact for a driving
   window, delivered as a push via `CKQuerySubscription` — never a score or
   raw data, and never without both phones having visibly paired first.

For the quickest review:

1. Complete both consent switches.
2. Choose **Explore founder demo**.
3. Open **Safety Circle** and add a contact so the manual call/message
   buttons have somewhere to reach.
4. Run the live prototype from **Start a check**.
5. Scroll to **Review every safety state** to inspect all result paths.
6. Open **Research Center** to review consent, context, session count, baseline
   quality, JSON export, and delete-all behavior.
7. Open **Guardian Mode** to try QR pairing and the driving-schedule setup.

## Verify it

```bash
xcodebuild \
  -project Sober.xcodeproj \
  -scheme Sober \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

## Important prototype limits

- The scorer thresholds and weights are illustrative and have no clinical validity.
- Simulator live capture is unsupported and therefore inconclusive; only explicitly labeled founder previews use sample data.
- The ocular protocol is not HGN detection, a standardized field sobriety test, or a clinically validated impairment measure.
- No pupil segmentation, PLR protocol, voice task, balance task, or trained CoreML impairment model is included.
- Five high-quality sessions unlock the prototype baseline. That is a product-development minimum, not an evidence-backed clinical threshold.
- Research context is self-reported. The app has no supervised labels, breath-reference hardware integration, controlled-study ground truth, or model-training pipeline yet.
- Raw camera frames are not persisted by app code, but the prototype privacy copy still requires legal review before any external distribution.
- Guardian Mode's CloudKit pairing and push delivery have not been exercised on physical hardware or with a real Apple Developer account/provisioning profile — see the caveat in the Guardian Mode commit for what's unverified.
- Ride links open the provider; production destination and location handling remain to be implemented.

Read [Founder Review](Docs/FOUNDER_REVIEW.md) before deciding what to build next.
The visual and motion rules live in [DESIGN.md](DESIGN.md).
