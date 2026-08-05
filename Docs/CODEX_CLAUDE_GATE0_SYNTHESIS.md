# Codex + Claude Gate 0 Synthesis

Date: 2026-08-05

Claude session: `370a1417-5c80-4a9d-88d5-9c530dbc3cdf`

This is Codex's faithful synthesis of Claude's read-only, code-grounded review of the Guardian,
validation, and reliability plan. It does not claim that contract text is implemented.

## Claude verdict

**ACCEPT WITH REQUIRED CHANGES.**

Claude accepted the one-app/two-role shape, relationship-scoped P-256 capabilities, one
`GuardianRelationship` Durable Object for revocation and alert serialization, signed guardian
acknowledgment, immediate APNs submission, and one 30-second SMS fallback.

Claude rejected treating the contract as evidence that the shipping code already has those controls.
At commit `a141a79`, the existing Worker and iOS alert service remain the founder SMS implementation;
Guardian Mode is still a design contract.

## Required code and contract changes

1. **Delete the shared-token alert path before guardian distribution.** The current app-wide bearer
   token is extractable from a distributed binary. The old endpoint must not coexist with Guardian
   endpoints.
2. **Server owns all alert text.** The current relay accepts `payload.message`; Guardian v1 must
   reject client-authored message bodies and generate the minimal text from a versioned template.
3. **Replace the current fixed event limiter in code.** The current fourth distinct event inside ten
   minutes receives `429`. Signed active relationships need the reviewed canonical-alert/coalescing
   behavior, with a test proving the fourth event is handled and fallback uses no new reservation.
4. **Treat `425` as unknown, not failed.** A provider may already have sent the alert. iOS must never
   render that case as failed or automatically resend that channel.
5. **Persist the event identity across relaunch.** Killing the app after server reservation but
   before receipt recovery must reconcile the same event ID rather than create a duplicate alert.
6. **Provider delivery claims require signed callbacks.** No UI state may say delivered before the
   Twilio callback endpoint verifies the provider signature and durably records the transition.
7. **Design for Critical Alerts denial.** Time Sensitive notifications may remain silent under Focus.
   Push is the guardian acknowledgment path; verified SMS is the reachability path. The product may
   not promise Focus/DND override without Apple's separate entitlement and guardian opt-in.
8. **Collapse the impaired-user status surface.** Show only requesting help, guardian confirmed, or
   contact them yourself now. Keep provider-specific states internal and direct actions prominent.
9. **App Attest gates non-founder enrollment SMS.** Founder allowlisting is not enough once the app
   leaves founder-controlled devices.
10. **Relationship expiry is visible.** Both roles receive advance warning, and expiry returns the
    screened person's Safety Circle to explicitly unconfigured.

## Required validation changes

1. A self-described sober baseline is an unverified reference, not ground truth. Baseline collection
   needs confounder recording and abstention rules.
2. App participant-ID rotation cannot prove participant-held-out evaluation across exports. Formal
   studies need a stable study-issued subject key held in an approved separate linkage system.
3. Each device/subgroup analysis needs a pre-registered minimum sample count. Below it, report
   insufficient evidence rather than “no gap found.”
4. The sober repeatability pilot must quantify false `SIGNALS_DETECTED` and abstention rates before
   any non-founder guardian receives a live alert. Guardian plumbing can be built and tested on
   founder-controlled devices in parallel.

## Revised execution gate

Gate 1 is founder-only engineering. Gate 2 is founder-only integration and adversarial code review.
Gate 3 produces physical-device repeatability evidence. Only a passing pre-registered Gate 3 result
allows a consenting non-founder guardian into Gate 4. Model training remains later and shadow-only.

## Final re-review

After Codex revised the plan and contracts, Claude traced every required change against the files in
the same read-only session. Its final verdict was:

**CONTRACT READY FOR FOUNDER-ONLY GATE 1.**

The review left three scoped follow-ups:

1. Freeze the App Attest enrollment wire protocol before any non-founder enrollment. This does not
   block founder-allowlisted Gate 1 engineering.
2. Add `Docs/GUARDIAN_THREAT_MODEL.md` before or while opening Gate 1.
3. State explicitly that coalescing can hide repeated checks: one alert is not one incident.

The threat model and coalescing decision are now documented. The App Attest wire contract remains a
hard Gate 4 entry requirement and must receive another review before non-founder enrollment.

Every contract promise still needs a named passing backend/iOS test before it can be called
implemented. Founder decisions on the Critical Alerts-denied behavior and 30-second fallback limits,
plus qualified research/privacy/legal review, remain human dependencies.
