# Sober

A native iOS founder-review MVP for a private impairment-awareness check and
ride-home intervention. Built with Swift 6, SwiftUI, ARKit, and an iOS 17
deployment target.

> This is an interaction and technical prototype—not a validated medical
> device, impairment detector, BAC estimator, or safe-to-drive test. Do not use
> it to decide whether to drive or operate machinery.

## What is included

- Separate biometric processing and retention consent
- Three-session starter baseline flow with the research limitation shown in UI
- Four-hour self-report gate that overrides task scoring
- Reaction, motor tracking, time-estimation, and guided-gaze tasks
- TrueDepth face-relative gaze sample harness with in-memory ring buffering
- Quality gating and a transparent weighted prototype scorer
- Exactly three result states: signals detected, inconclusive, no signals detected
- No green/pass/cleared/safe state
- Ride, call, and message actions on every result
- Night Out Mode pre-commitment setup
- Founder previews for all result states using visibly labeled sample data
- Unit tests for the safety-critical result invariants

## Run it

Requirements: macOS with Xcode 26+, an iOS 17+ simulator or iPhone, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Sober.xcodeproj
```

Select the `Sober` scheme and run on an iPhone simulator. For the guided-gaze
harness, use an iPhone with TrueDepth and select your Apple development team in
the target's Signing & Capabilities settings.

For the quickest review:

1. Complete both consent switches.
2. Choose **Explore founder demo**.
3. Run the live prototype from **Start a check**.
4. Scroll to **Review every safety state** to inspect all result paths.
5. Confirm that the result cannot be dismissed until the warning is acknowledged.

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
- Simulator gaze uses labeled sample data; supported iPhones use an early ARKit harness.
- Guided gaze is not HGN detection and does not run the FFT/onset-angle pipeline yet.
- No pupil segmentation, PLR protocol, voice task, balance task, CoreML model, or research export is included.
- Three sessions are used only to keep the MVP reviewable; the handoff's cited evidence points to 10–20 sober sessions for a defensible baseline.
- Raw camera frames are not persisted by app code, but the prototype privacy copy still requires legal review before any external distribution.
- Ride links open the provider; production destination and location handling remain to be implemented.

Read [Founder Review](Docs/FOUNDER_REVIEW.md) before deciding what to build next.
