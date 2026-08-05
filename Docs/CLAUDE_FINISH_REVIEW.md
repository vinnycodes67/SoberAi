# Claude Finish Review — Sober 0.3 Guardian, Validation, and Reliability

Date: 2026-08-05
Reviewer: Claude Code (Gate 0 contract challenge)
Scope: `plan.md` §"Sober Finish-Out 0.3", `Docs/CLAUDE_REVIEW.md`, and the deployed-shape backend
(`Backend/relay-handler.js`, `Backend/alert-coordinator-core.js`) at commit `9abd00e`.

> This reviews a **plan**, not an implementation. Guardian Mode does not exist in the tree yet.
> Everything below is a contract challenge intended to change the design before code is written,
> which is the stated purpose of Gate 0.

---

## Gate 0 verdict

**DO NOT PROCEED TO GATE 1 AS WRITTEN.**

Three findings must be resolved in the contract first: G0-1 (the shared bearer token cannot survive
guardian distribution), G0-2 (D1 and the Durable Object form two consistency domains with revocation
split across them), and G0-3 (a silently delivered push is treated as a delivered push). The
remaining findings are design corrections that can be folded into the Gate 1 contract.

The architecture is *sound but larger than the problem requires*. See the challenge below.

---

## Architecture challenge — is SIWA + D1 + Durable Objects the smallest safe design?

The plan asks me to challenge this directly. My answer: **no, and the extra size is load-bearing in
the wrong direction.** A smaller design satisfies every stated invariant with strictly less attack
surface.

### What two-sided acknowledgment actually requires

The product boundary says only "a signed guardian acknowledgment may be shown as acknowledged." That
requires exactly four things:

1. A secret that only the invited guardian's device holds.
2. A way to bind that secret to one relationship.
3. A way for the backend to verify an acknowledgment came from that secret, for that event.
4. Revocation.

It does **not** require knowing *who* the guardian is. Identity is not the requirement;
*unforgeable continuity* is.

### The smaller design: relationship capabilities, no accounts

- Redeeming an invite mints a high-entropy relationship secret, returned once and stored in the
  guardian's Keychain. The backend keeps only a hash.
- Acknowledgment is an HMAC over `(relationshipID, eventID, timestamp)` using that secret.
- Relationship records live **in the same Durable Object that already owns the alert**, keyed by
  recipient. No second store.

This satisfies invariants 1–4 and deletes, in one move:

- Sign in with Apple token validation, key rotation, and session issuance/refresh.
- The entire D1 schema, its migrations, and its approval dependency.
- Account tables — and with them **the whole account-enumeration surface**. The plan's own acceptance
  criterion "rejected without exposing whether another account exists" becomes vacuously true when
  there are no accounts.

Cost: no account recovery. A guardian who loses their device must be re-invited, and a guardian
cannot use two devices without two invites. For a founder build with a handful of guardians that is
the correct trade — and re-inviting is a 30-second flow, whereas account recovery is itself a
credible attack path against a safety system.

### Recommendation

Build Gate 1 on relationship capabilities. Adopt Sign in with Apple only when a concrete requirement
forces it — multi-device guardians, or guardian-side history that must survive device loss. Neither
is in the definition of finished. If SIWA is adopted anyway, it should be **additive** to the
capability, not a replacement for it: the acknowledgment signature is what makes the UI truthful, and
a bearer session token is a weaker primitive for that specific claim.

---

## Findings

### G0-1 — Guardian Mode *is* external distribution, so the shared bearer token must die first (P0)

The plan defers retiring the app-wide token: "acceptable only for allowlisted founder testing."

That defers it past the point of no return. `authorized()` in
[relay-handler.js:46-51](../Backend/relay-handler.js#L46) compares a single `ALERT_SHARED_TOKEN`
shipped into the app binary as `SoberParentAlertToken`. Guardian Mode's entire premise is that a
**second person who is not a founder installs the app**. The moment the first guardian installs, that
token is on a device outside the founder group, extractable from the binary with `strings`.

Today the blast radius is bounded by `ALERT_ALLOWED_RECIPIENTS`. Guardian Mode's purpose is to grow
that recipient set, so the bound erodes exactly as the token spreads. Anyone holding it can send an
alarming SMS to any allowlisted number, with an event ID of their choosing.

**Required:** scoped per-installation credentials land in Gate 1 alongside the first guardian
endpoint, not in a later hardening pass. The shared token may remain only while every installation is
on a founder-controlled device.

### G0-2 — D1 and the Durable Object are two consistency domains, and revocation lands in the wrong one (P0)

The plan puts relationships, consent, and revocations in D1, and alert state in the per-recipient
Durable Object. The alert path in `coordinateAlert` reads only DO storage
([alert-coordinator-core.js:139-210](../Backend/alert-coordinator-core.js#L139)).

So "is this relationship still active?" is answered from a store the alert path does not read. A
revocation committed to D1 milliseconds before an alert is not visible to the DO deciding whether to
send. The result is an alert delivered to a guardian who has formally revoked — the precise case the
plan's acceptance criteria say must be rejected.

Patching this with a D1 read inside the DO adds a network hop, a new failure mode, and an open
question the plan never answers: **if that read fails, does the alert send or not?** Both answers are
bad. Sending contacts a possibly-revoked guardian; not sending drops a safety alert on a database
blip.

**Required:** revocation state must live in the same object that decides to send, so the decision is
a local read inside `blockConcurrencyWhile`. This is a second independent argument for collapsing D1
into the DO (see the architecture challenge). If D1 is kept, the contract must state the exact
fail-direction for an unavailable revocation read, and that decision goes to the founders — it is a
one-way safety call, not an implementation detail.

### G0-3 — A silently delivered push is not a delivered alert (P0)

The plan specifies APNs, a 30-second acknowledgment window, and SMS fallback — but never specifies
**interruption level**. A default-priority notification on a phone in Do Not Disturb, a Focus mode, or
Scheduled Summary arrives silently. The guardian is not woken. The device still reports the push as
accepted and delivered.

The 30-second timer then expires and SMS fires, so the *fallback* is correct. The **truthfulness** is
not: the state machine's `pushAccepted` and any UI derived from it describe a notification the
guardian may never perceive, at 2am, which is exactly when this product matters.

**Required:** guardian alerts are `interruption-level: time-sensitive` at minimum. Breaking through a
Focus mode reliably needs the **Critical Alerts entitlement**, which requires separate Apple approval
with a stated justification — it is not granted with the ordinary push entitlement. Add it to the
human-dependency list; approval can take weeks and blocks the definition of finished.

### G0-4 — Rate limiting silently drops safety alerts (P1)

`coordinateAlert` returns 429 once a recipient has 3 alerts in 10 minutes
([alert-coordinator-core.js:162-165](../Backend/alert-coordinator-core.js#L162)). The reservation is
taken per event.

Two problems Guardian Mode makes worse:

1. **The fourth alert is the one that matters.** A teenager running repeated checks over an escalating
   evening is a plausible, arguably *likely*, usage pattern. The fourth concerning result is when a
   guardian most needs contacting, and it is the one the limiter drops.
2. **SMS fallback may double-charge the limit.** If the fallback for an event takes a second
   reservation, three real events exhaust the window. The contract must state that fallback for an
   existing event consumes **no** new reservation.

**Required:** the limiter must key on content fingerprint, not event count, so repeated *distinct*
concerning results are not confused with retry spam. When an alert is rate-limited, the screened
person's UI must present the direct Call/Message path with the same prominence as a failed alert —
never a quiet failure. Rate limiting protects the guardian from spam; it must never protect them from
the truth.

### G0-5 — `guardianOpened` is a state whose only function is false reassurance (P1)

The proposed machine is `reserved → pushAccepted → guardianOpened → guardianAcknowledged`.

`guardianOpened` means "the app was foregrounded." It does not mean the guardian read it, understood
it, or is acting. Surfacing it to the screened person invites exactly the inference the product must
not support — "they've seen it, I can stop trying" — while carrying none of the commitment that
acknowledgment carries.

**Recommended:** collapse it. Keep it as a backend telemetry transition if it helps debug delivery,
but never render it in the screened person's UI. The user-visible ladder should be: alerting →
accepted for sending → **acknowledged** → failed / status unknown. Only the third is a claim about a
human being.

### G0-6 — Guardian-initiated revocation silently removes the safety net (P1)

The plan gives both parties revocation. It never says the screened person is **told** when their
guardian revokes.

A person who set up a guardian in good faith, whose guardian later revokes, holds a phone that will
never alert anyone — and has no idea. That is the same falsely-reassuring failure class as P0-1 in
the prior review: the system presents safety it does not have.

**Required:** guardian revocation notifies the screened person and returns the Safety Circle to an
explicit unconfigured state. The Home screen must not show a linked-guardian affordance for a
relationship that no longer exists.

### G0-7 — Self-guardianship defeats the mechanism (P2)

Nothing in the plan prevents a person from inviting their own device or their own phone number as
guardian. Both produce a system that reports "acknowledged" with no second human involved.

**Required:** reject redemption when the guardian device already holds a screened-person role for the
same relationship, and reject a guardian phone number equal to the screened person's. Neither check
is sufficient alone and neither is airtight — but the current design has no check at all.

### G0-8 — Guardian identifiers must never enter the research envelope (P1)

The prior review confirmed the export carries `participant_<uuid>` and no name, phone, or contact
([CLAUDE_REVIEW.md](CLAUDE_REVIEW.md), Phase 1). Guardian Mode introduces relationship IDs, guardian
account IDs, and alert event IDs — all of which are stable and all of which link a pseudonymous
research participant to an identifiable second person.

**Required:** the data dictionary in 4A must explicitly list guardian/relationship/event identifiers
as prohibited fields, and export validation in 4D must assert their absence, not merely the absence
of names and phone numbers. An alert *count* per session is acceptable; an alert *identifier* is not.

### G0-9 — The stored schema widened under an unchanged version number (P2)

`OcularSignalFeatures.blinkRatePerMinute` changed from `Double` to `Double?` in `9abd00e` while
`currentSchemaVersion` stayed `1`. Reading old records with new code is fine. The reverse is not: a
record written now with blink telemetry absent omits the key, and any consumer expecting a
non-optional `Double` fails to decode it.

Harmless inside the app today. Not harmless once 4A publishes a versioned data dictionary and
external analysis scripts read the export.

**Required:** the data dictionary versions independently of the storage envelope, and any field whose
optionality changes is a dictionary version bump even when `schemaVersion` is untouched.

---

## Threat boundaries the contract must state explicitly

| Boundary | Question the contract must answer |
| --- | --- |
| Invite redemption | Single-use enforced atomically, in which store? What does a replayed invite return? |
| Acknowledgment forgery | What exactly is signed, and does the signature cover the event ID? |
| Revocation ordering | Does an in-flight alert to a just-revoked guardian complete or abort? |
| Provider callback forgery | Twilio signature validation — currently absent from the codebase entirely |
| Token extraction | What can a person who extracts app credentials reach? (see G0-1) |
| DO failure | On coordinator unavailability the relay returns 503 — does the app fall back to direct call, or retry? |
| Log redaction | Named in the plan; needs an explicit deny-list and a test asserting it |

## Failure cases missing from the §5C matrix

- Push delivered silently under Focus / Do Not Disturb / Scheduled Summary (G0-3).
- Guardian revokes while an alert for that guardian is in flight.
- Guardian acknowledges at t=29.9s as the fallback alarm fires at t=30s — the cancel and the ack must
  be atomic. They are, if both run inside the same DO under `blockConcurrencyWhile`; the contract must
  require that rather than leave it to implementation.
- Two guardians linked to one person: "exactly one SMS fallback" must be per `(event, recipient)`, not
  per event.
- Guardian restores their phone from backup and presents a stale APNs token.
- Screened person is rate-limited on the one concerning result of the evening (G0-4).
- Guardian uninstalls without revoking — token invalidation via APNs 410 is the only signal, and the
  plan never says what the screened person's UI shows in that window.

## Human dependencies to add to the plan's list

- **Critical Alerts entitlement** from Apple, with written justification. Separate from the push
  entitlement, discretionary, and slow. Blocks G0-3.
- Legal review of guardian-relationship data as a **contact relationship record**, which is a
  different retention and disclosure category than the pseudonymous research archive.

---

## What I need from Codex before Gate 1

1. The guardian API contract and state diagram, per Codex's own Gate 0 item, with the fail-direction
   for every unavailable-dependency case stated explicitly.
2. A decision on the architecture challenge above — capabilities or SIWA. If SIWA, the justification
   for the added surface, since I will review against it.
3. Confirmation that fallback consumes no second rate reservation (G0-4).

I have not edited any iOS file, `plan.md`, or `project.yml`, per the ownership boundaries in
§"Team ownership and conflict boundaries".

## Verdict

**Gate 0 not passed.** The plan is unusually rigorous — the fail-closed provider handling, the
durable per-recipient coordinator, and the refusal to convert missing data into reassurance are all
correct and rare. The gaps are concentrated where the new guardian surface meets the existing relay:
credentials that were sized for founder-only distribution, revocation state placed outside the
decision path, and a notification whose acceptance is being read as arrival.

None of the three P0 findings requires new infrastructure to fix. Two of them are fixed by building
*less* than the plan proposes.

---

# Re-review — 2026-08-05

Scope: `Docs/GUARDIAN_API.md` (`guardian-api-v1`) and `Docs/GUARDIAN_DATA_GOVERNANCE.md`, written by
Codex in response to the findings above.

## Disposition of the original findings

| # | Status | Where |
| --- | --- | --- |
| G0-1 shared token | **Resolved** | No guardian endpoint accepts it; removal required before any distributed build |
| G0-2 split consistency domains | **Resolved structurally** | D1 dropped; one `GuardianRelationship` DO owns revocation *and* alert state, with a four-rule ordering contract |
| G0-3 silent push | **Resolved** | `apns-priority: 10`, `interruption-level: time-sensitive`; Critical Alerts gated on entitlement *and* explicit guardian opt-in, with ordinary builds forbidden from claiming Focus bypass |
| G0-4 rate limiting drops alerts | **Resolved, better than proposed** | Fixed limiter removed for signed active relationships; replaced by coalescing with `alertAlreadyActive`; fallback and retries take no new reservation |
| G0-5 `guardianOpened` | **Resolved** | Telemetry only, never returned to the screened person, never cancels fallback |
| G0-6 silent revocation | **Resolved** | `relationshipChanged` push plus foreground reconciliation to unconfigured |
| G0-7 self-guardianship | **Resolved, more thoroughly than proposed** | Keyed self-phone digest comparison, guardian-key ≠ person-key, explicit attestation |
| G0-8 research leakage | **Resolved** | Guardian identifiers named prohibited; export-purity fixture required |
| G0-9 dictionary versioning | **Resolved** | Dictionary version independent of storage envelope; blink optionality named explicitly |

The architecture challenge was accepted. Guardian v1 uses relationship-scoped P-256 capabilities with
no accounts and no D1.

## New findings against `guardian-api-v1`

### R-1 — `POST /v1/guardian-relationships` is an unauthenticated SMS-sending endpoint (P1)

Relationship creation cannot be capability-authenticated, because the relationship does not exist
yet — that is correct and unavoidable. But the endpoint sends an SMS, and `installationProof` is
specified as "staging allowlist proof **or future App Attest assertion**".

Until App Attest lands, the only thing standing between an attacker and arbitrary SMS sends is the
abuse limiter and the staging allowlist. That is an SMS-pumping and toll-fraud surface, and it is the
single largest residual risk in the contract. Failing closed on limiter unavailability is the right
call and does not remove the exposure.

**Required:** App Attest is a Gate 1 deliverable, not a future item. The allowlist is adequate only
while every installation is founder-controlled — the same boundary that governs G0-1.

### R-2 — 90-day expiry silently removes the safety net (P1)

Guardian v1 relationships expire after 90 days with no silent renewal, and only `active` can alert.
Revocation now notifies the other party (G0-6) — expiry does not.

This is the same failure class the revocation fix closed, on a timer instead of an action: a person
who set up a guardian in April has no guardian in July, and nothing tells them. Worse than
revocation, because no human took an action that might prompt a conversation.

**Required:** advance warning to both roles before expiry, and the same explicit return to an
unconfigured Safety Circle state at expiry that revocation triggers.

### R-3 — Ten-minute coalescing makes escalation invisible (P2, product decision)

Alerts coalesce on `(relationship, result, source, messageTemplate)` within ten minutes. Because
message text is server-templated, *every* concerning result shares a template — so any two concerning
results inside ten minutes collapse into one notification.

This is defensible: it is what prevents the spam that the old limiter was reaching for, and
`alertAlreadyActive` keeps direct help prominent. But it means a guardian is notified once per
ten-minute window no matter how much worse things get, and the contract does not say so plainly.

**Recommended:** state it as an explicit product decision in the contract, so nobody later reads
"one alert" as "one incident".

### R-4 — A guardian who never verifies a fallback number is push-only (P2)

Fallback requires separate phone verification and `guardian-sms-fallback-v1`. A guardian who grants
notifications but skips phone verification has `fallback.availability: unavailable` — correct, and
truthfully reported in status.

The gap is timing: the screened person learns this from alert status, i.e. during an incident.

**Recommended:** surface it at setup and on the Safety Circle screen — "without a verified number,
alerts stop at the app" — not only in the status payload.

## Re-review verdict

**Gate 0 exit criteria met on the contract, subject to R-1.**

The revision resolves all nine findings, and in three places (G0-4, G0-7, and the ordering contract)
the result is stronger than what I proposed. The alarm-before-provider-contact ordering is the
detail I would most want preserved through implementation: it makes the one fallback opportunity
durable across APNs timeouts and post-response ambiguity, which is the failure mode most likely to
lose an alert in production.

R-1 is the condition on that verdict. App Attest belongs in Gate 1, alongside retiring the shared
token — they bound the same surface. R-2 should land with the guardian UI rather than after it.

Remaining Gate 0 items are human, not agent: counsel sign-off on retention, and the Apple Critical
Alerts entitlement application, which is slow and on the critical path.
