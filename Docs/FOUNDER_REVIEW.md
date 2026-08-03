# Sober MVP — founder review

## The ten-minute walkthrough

1. **Onboarding:** Is the product boundary unmistakable before consent?
2. **Consent:** Would you personally understand what is processed, retained, and deleted?
3. **Home:** Does “Pause. Check in.” feel nonjudgmental enough to use in a real moment?
4. **Night Out Mode:** Is pre-commitment the core product or a supporting feature?
5. **Self-report:** Say **Yes** and confirm the app skips tasks rather than trying to talk you out of known use.
6. **Live task loop:** Check whether the interaction feels achievable in under two minutes.
7. **Founder previews:** Review all three outcomes, especially **No signals detected**.
8. **Intervention:** Confirm ride, call, and message are visible before the user can leave.
9. **Dismissal:** Confirm the result requires a four-second dwell plus explicit acknowledgement.
10. **Language:** Search for any phrase that could be interpreted as permission to drive.

## Decisions this build made

- **Personal B2C intervention, not workplace enforcement.** The newer master prompt explicitly prohibits employer, law-enforcement, and third-party result sharing. This conflicts with the earlier handoff's view that B2B has a better liability shape; the MVP follows the explicit safety constraint.
- **Psychomotor first, gaze secondary.** Reaction, coordination, and timing produce the primary prototype features. ARKit gaze is an experimental quality/smoothness input, not a pupil-size or BAC claim.
- **Reported use ends the test.** A “yes” produces signals detected; “not sure” produces inconclusive. The app does not run tasks that might falsely reassure the user.
- **No pass state.** The least concerning state still says it does not mean sober or safe to drive and requires acknowledgement.
- **Founder demo data is obvious.** Every forced state is marked as a sample result. The live simulator path labels the guided-gaze portion as a demo trace.
- **Three baselines only for reviewability.** Production should not inherit this value without a validation decision.

## Decisions the founders still need to make

1. Is this a consumer product centered on getting home, or a workplace product centered on human review? Do not blend both trust models.
2. Is the first validated target alcohol, cannabis, fatigue, or “change from baseline” without substance attribution?
3. Is Night Out Mode the wedge, with measurement as an optional hook?
4. What minimum sober baseline count will the study protocol require?
5. Does guided gaze earn its privacy and engineering cost after a Phase-1 signal study?
6. Who owns clinical validation, legal review, and university/IRB partnerships?
7. What evidence must exist before anyone outside the founding team may use a live score?

## Recommended next gate

Do not tune the UI scorer. Build a research-only capture target that exports
timestamped head-local gaze and task metrics with explicit participant consent,
then test chair-spin vestibular nystagmus and fatigue as positive controls. The
go/no-go question is whether the phone produces a stable signal—not whether the
current demo score looks plausible.

Before external testing, obtain counsel on biometric consent/retention and on
the product's claims. Before commercial launch, create a real deletion policy,
accessibility test plan, App Store medical-claims response, and validation plan.
