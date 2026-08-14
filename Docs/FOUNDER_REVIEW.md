# Sober MVP — founder review

## The ten-minute walkthrough

1. **Onboarding:** Is the product boundary unmistakable before consent?
2. **Consent:** Would you personally understand what is processed, retained, and deleted?
3. **Home:** Does “Pause. Check in.” feel nonjudgmental enough to use in a real moment?
4. **Safety Circle:** Add the parent number, enable automatic alerts, and confirm the sharing consent is explicit.
5. **Self-report:** Say **Yes** and confirm the app skips tasks rather than trying to talk you out of known use.
6. **Camera calibration:** On a TrueDepth iPhone, confirm the mirrored preview and all six quality indicators respond to position, light, distance, and motion.
7. **Live task loop:** Complete the reaction choices and all four ocular phases; confirm the interaction remains understandable and nonjudgmental.
8. **Research Center:** Review explicit research consent, context/confounders, five-session baseline quality, JSON export, and delete-all behavior.
9. **Founder previews:** Review all three outcomes, especially **No changes detected**.
10. **Intervention:** Confirm a concerning result begins the parent alert immediately and clearly separates relay acceptance from carrier delivery.
11. **Dismissal:** Confirm the result requires a four-second dwell plus explicit acknowledgement.
12. **Language:** Search for any phrase that could be interpreted as permission to drive.

## Decisions this build made

- **Personal B2C intervention, not workplace enforcement.** Parent alerts are now a narrow, explicitly authorized safety exception. Raw biometric data and detailed task scores remain on-device; there is still no employer or law-enforcement mode.
- **Psychomotor first, gaze secondary.** Reaction, coordination, and timing produce the primary prototype features. ARKit gaze now covers fixation, horizontal/vertical pursuit, and a structured saccade sequence, but remains an experimental research input—not HGN, pupil-size, BAC, or sobriety detection.
- **Reported use ends the test.** A “yes” produces signals detected; “not sure” produces inconclusive. The app does not run tasks that might falsely reassure the user.
- **No pass state.** The least concerning state still says it does not mean sober or safe to drive and requires acknowledgement.
- **Unusable capture refuses to guess.** Unsupported devices, interrupted capture, low sample counts, and poor tracking across the capture cannot produce a measured “no signals detected” result; one good final frame cannot rescue a mostly bad run. Reduced Motion uses a separate fixation-and-jump-target protocol and never pools its baseline with the full protocol.
- **Founder demo data is obvious.** Every forced state is marked as a sample result. The live simulator path is unsupported and therefore inconclusive.
- **Five baselines only for prototype research.** Eligible baselines must be complete and high quality; the app uses robust median/MAD summaries. Production should not inherit the count or thresholds without a validation decision.
- **Research data stays separate from scoring.** Versioned pseudonymous sessions and contextual confounders can be exported or deleted from Research Center, but baseline deltas do not silently retune the safety scorer.
- **Concerning results notify the parent automatically.** Live `SIGNALS_DETECTED` outcomes post a minimal safety event to the configured relay as the result screen appears. Sample founder results never send.
- **Delivery language is precise.** A result says the alert was accepted for sending, never that it reached the parent. Manual call/message actions remain available.
- **Retries are durably coordinated within the prototype contract.** The app reuses one event ID. A per-recipient Durable Object reserves the event before contacting Twilio, suppresses duplicates for 24 hours, rate-limits new alerts, and fails closed when provider status is uncertain.

## Decisions the founders still need to make

1. Is this a consumer product centered on getting home, or a workplace product centered on human review? Do not blend both trust models.
2. Is the first validated target alcohol, cannabis, fatigue, or “change from baseline” without substance attribution?
3. Is Safety Circle the wedge, with measurement as an optional hook?
4. What minimum sober baseline count, collection cadence, and recapture policy will the study protocol require?
5. Does guided gaze earn its privacy and engineering cost after a Phase-1 signal study?
6. Who owns clinical validation, legal review, and university/IRB partnerships?
7. What evidence must exist before anyone outside the founding team may use a live score?
8. What parent-verification, revocation, escalation, and abuse-reporting process is required before external testing?
9. Which labeled reference should anchor the first study: calibrated breath alcohol, clinician assessment, fatigue protocol, or another controlled ground truth?
10. What error costs are acceptable for parent alerts, especially false alarms and missed concerning events?

## Recommended next gate

Do not tune the UI scorer yet. The research-only capture/export layer now exists.
The next gate is a written study protocol, physical-device repeatability testing,
and collection against a defensible supervised reference under appropriate
oversight. Start with safe positive controls such as fatigue and repeatability;
do not run informal controlled-alcohol sessions. The go/no-go question is whether
the phone produces a stable, separable signal—not whether the demo score looks
plausible.

Before external testing, obtain counsel on biometric consent/retention and on
the product's claims. Before commercial launch, create a real deletion policy,
accessibility test plan, App Store medical-claims response, and validation plan.

## Required pre-share checks for this build

- Run the full ocular flow on at least two supported TrueDepth iPhones and record camera-quality failure modes.
- Verify Research Center export/delete across termination and relaunch; inspect the JSON for raw images, names, phone numbers, or other unintended identifiers.
- Deploy the alert relay only with founder-number allowlisting, then verify one live accepted send, one transient retry, and one intentional failure.
- Treat relay acceptance as submission evidence only. Durable coordination is implemented, but Twilio status callbacks and deployed failure testing are still required before using delivery language.
- Review the completed independent Claude report and its post-review continuation in `Docs/CLAUDE_REVIEW.md`.
