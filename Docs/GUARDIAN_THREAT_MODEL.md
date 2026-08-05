# Guardian Mode Threat Model

Status: Gate 1 founder-build baseline

Last updated: 2026-08-05

This document defines the security and abuse boundary for Guardian Mode. It accompanies
`GUARDIAN_API.md` and `GUARDIAN_DATA_GOVERNANCE.md`; it is not evidence that the controls are already
implemented.

## Scope and safety objective

Guardian Mode lets a person deliberately link one guardian, request help after a live
`SIGNALS_DETECTED` result, and receive an authenticated acknowledgment. APNs is the acknowledgment
path and a separately verified guardian phone provides SMS reachability. The system must fail
truthfully: provider acceptance is not delivery, delivery is not human acknowledgment, and unknown
outcomes are never rendered as failed or safe.

Out of scope for v1 are medical diagnosis, sobriety/BAC decisions, fitness-to-drive claims, account
recovery, multi-device continuity, raw-video upload, passive monitoring, and emergency-services
dispatch.

## Assets

- Each role's private relationship key and the backend-held public counterpart.
- Two-sided relationship consent, revocation, expiry, and role assignment.
- Guardian APNs tokens and encrypted verified fallback phone data.
- Canonical alert identity, provider state, fallback alarm, and signed acknowledgment.
- App Attest enrollment material used to control non-founder verification SMS.
- The screened person's privacy, including the absence of camera, score, substance, and task details
  from notifications, logs, and research exports.
- Provider credentials, callback secrets, signing keys, and abuse-control state.

## Actors and trust boundaries

- The screened person and guardian are mutually consenting but neither is trusted to act for the
  other's role.
- An attacker may control a modified client, steal an invite, replay requests, obtain a lost device,
  pump SMS, forge callbacks, or observe network metadata.
- The iOS app, Worker edge, one relationship Durable Object, APNs, and Twilio are separate trust
  boundaries. Provider acceptance and callbacks are external claims requiring verification.
- Founder allowlisting is a temporary operational boundary for Gate 1, not a production security
  control. App Attest or an independently reviewed equivalent is required before non-founder
  enrollment can trigger SMS.

## Required controls and fail direction

| Threat | Required control | Failure behavior | Proof required before non-founder use |
| --- | --- | --- | --- |
| Extracted app-wide bearer sends arbitrary alerts | Delete the shared-token route when the signed relationship route lands | No compatibility fallback | Build/route test proves the old handler and secret are absent |
| Client injects alarming, diagnostic, or private text | Strict request decoder and versioned server templates | Reject unknown/sensitive fields | Contract tests cover `message`, score, metric, substance, camera, phone, and provider fields |
| Stolen capability or cross-role use | This-device-only P-256 key, role-scoped signed canonical request | Generic non-enumerating rejection | Wrong-key, wrong-role, changed-body, and malformed-signature tests |
| Request replay | Signed timestamp, 128-bit nonce, ten-minute nonce store, idempotency key | Reject replay; identical event retry returns its existing result | Replay, stale-time, and idempotency-conflict tests |
| Invite theft or self-guardian setup | Single-use expiring invite, two-sided consent, distinct verified fallback phone | No relationship activation or SMS fallback | Redeem-once, expiry, consent-version, and same-person rejection tests |
| Verification-SMS pumping | Founder allowlist in Gate 1; App Attest plus phone/IP/device abuse limits before external enrollment | Limiter or attestation outage fails closed | Environment, challenge, assertion, counter replay, wrong-app, and limiter-outage tests |
| Revoked relationship still alerts | Revocation and alert creation serialize in one relationship Durable Object | If revocation commits first, no provider call; if a call began first, no later fallback/ack | Both race orderings tested with provider spies |
| APNs or SMS ambiguous outcome creates duplicates | Persist event/alarm before provider contact; canonical event ID survives retry and relaunch; `425` maps to `statusUnknown` | No automatic resend on the ambiguous channel | Kill/relaunch, timeout, `425`, and delayed-response tests |
| Fixed limiter silently drops escalating concern | Coalesce only matching recent content; no legacy three-event rejection on signed relationships | Fourth distinct event is durably handled | Four-distinct-event and alias/fallback reservation tests |
| Coalescing misrepresented as incident count | Treat aliases as notification-control metadata | Never report one alert as one incident | Copy/schema review and export exclusion test |
| Forged Twilio delivery callback | Verify provider signature against the exact callback URL/body before transition | Reject without state change | Valid, invalid, replayed, and wrong-URL callback tests |
| Provider acceptance shown as human contact | Three screened-person action states; only guardian signature produces confirmation | Unknown/unacknowledged becomes direct-action guidance | State-mapping and copy snapshot tests approved by Claude |
| APNs token theft or stale token | Store token only in relationship object; rotate/delete per APNs lifecycle | Invalidate definitive rejects; preserve fallback | Registration, rotation, deletion, and APNs error tests |
| Critical Alerts entitlement denied | Time Sensitive push plus verified SMS; no Focus/DND override promise | Push remains acknowledgment path; SMS remains reachability path | Entitlement-denied device test and copy review |
| Logs or exports leak relationship/private data | Allowlisted structured logs, keyed digests, short retention, separate research schema | Drop/redact sensitive values | Log inspection and forbidden-field export tests |
| Lost device retains authority | Other role revokes; relationship expires after 90 days; no v1 recovery | Fresh two-sided invite required | Revocation, expiry-warning, expiry, and post-expiry signature tests |

## Alert truthfulness invariants

- `guardianConfirmed` requires a valid signed guardian acknowledgment for the relationship and
  canonical event.
- `delivered` is provider status only and is never exposed as proof that a human saw the message.
- `statusUnknown`, including HTTP `425`, never triggers an automatic resend on the ambiguous channel
  and never appears as “failed.”
- The person sees only `requestingHelp`, `guardianConfirmed`, or `actNow`; direct Call, Message, and
  Ride actions remain available.
- One canonical alert may contain aliases for repeated concerning checks. One notification is not
  one behavioral, clinical, or safety incident.

## Gate boundaries and residual risks

Founder-only Gate 1 may use explicit installation and phone allowlists on founder-controlled
devices. Before any non-founder enrollment, the team must freeze and re-review the App Attest wire
contract, pass every proof above, complete the sober repeatability gate, and obtain the required
privacy/legal/research approvals.

Residual risks remain even after implementation: SMS can be delayed, filtered, or viewed by someone
else; Time Sensitive notifications can be silenced; a guardian can be unavailable; a compromised
unlocked phone can exercise its live capability; and network/provider outages can leave delivery
unknown. The UI must continue to direct the screened person to immediate manual help and must never
promise rescue, delivery, sobriety, or safety.
