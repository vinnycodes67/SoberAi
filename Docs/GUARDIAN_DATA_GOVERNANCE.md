# Guardian Data Governance Contract

Status: Gate 0 revision for Claude re-review

Schema family: `guardian-data-v1`

Last updated: 2026-08-05

This document records Guardian v1 data, retention, redaction, consent, and research separation. It
is the hard technical maximum for founder staging, not an approved legal policy. External testing
remains blocked until privacy/legal review approves or shortens these rules.

## Storage architecture

Guardian v1 has no account database and no D1 dependency. One `GuardianRelationship` Durable Object
stores one relationship and its alerts so authorization, revocation, alarms, and provider calls use
one consistency boundary. A separate phone-keyed `AbuseLimiter` Durable Object stores only short
verification rate-limit reservations; it never decides whether an active relationship may alert.

The server stores public verification keys, never role private keys or bearer session secrets.

## Data-minimization rules

- Guardian infrastructure never receives camera frames, landmarks, task metrics, scores, baseline
  values, inferred substances, BAC estimates, or research-session content.
- The alert request contains only a relationship path, event UUID, occurrence time,
  `SIGNALS_DETECTED`, `liveCheck`, and a template version.
- Notification and SMS text is generated from a fixed server template. Arbitrary user text is
  prohibited.
- Phone numbers are encrypted only while needed for verification or active fallback. Keyed digests
  provide equality checks and provider-callback lookup without logging raw values.
- APNs tokens must be recoverable to send, so they are encrypted plus keyed-digested.
- Free text is prohibited except one bounded display label. Revocation reasons are fixed enums.
- Direct identifiers never enter alert fingerprints, metrics, request IDs, research records,
  analytics, or logs.

## Identifier and key classes

| Value | Server storage | On-device storage |
| --- | --- | --- |
| Relationship, capability, challenge IDs | Opaque values inside relationship object | Relationship-scoped Keychain record |
| Role private signing key | Never | This-device-only Keychain/Secure Enclave where available |
| Role public signing key | P-256 public JWK | Reconstructable from private key |
| Alert event ID | UUID in Durable Object for 24 hours | Pending receipt in Keychain |
| Installation ID | Keyed digest only | Random this-device-only Keychain value |
| Invite token | Keyed hash only; raw returned once | Universal-link handoff only |
| Verification code | Slow password hash only for ten minutes | Entry only; never persisted |
| Person self phone | Ciphertext during challenge, then keyed digest only | Entry only; discarded after request |
| Guardian fallback phone | Ciphertext plus keyed digest while active | Entry only; discarded after verification |
| APNs token | Ciphertext plus keyed digest | OS callback; cached only for a pending registration retry |
| Provider message ID | Keyed digest only | Never |

Encryption and HMAC keys are separate, environment-specific secrets with rotation runbooks.
Staging and production keys, objects, APNs environments, and provider accounts cannot be shared.

## `GuardianRelationship` record

No field may be added without a schema update, migration/compatibility handling, privacy tests, and
consent analysis.

### Relationship metadata

| Field | Purpose |
| --- | --- |
| `schema_version`, `contract_version` | Decode and behavior compatibility |
| `relationship_id` | Opaque routing key |
| `state` | `pendingPersonVerification`, `pendingGuardian`, `active`, `reauthorizationRequired`, `revoked`, `expired` |
| `person_capability_id`, `person_public_key`, `person_key_state` | Person request verification |
| `guardian_capability_id`, `guardian_public_key`, `guardian_key_state` | Guardian request verification; null before redemption |
| `person_display_name_ciphertext` | Bounded label visible only to guardian |
| `person_self_phone_hmac` | Same-phone guardian rejection; no callable phone number |
| `created_at`, `activated_at`, `updated_at`, `expires_at`, `revoked_at` | Lifecycle and 90-day hard expiry |
| `revoked_by_role`, `revocation_reason_code` | Fixed-enum, non-free-text audit |

Public keys are credentials but not secrets. They are still excluded from logs and client responses
other than the creating role's local derivation.

### Invite

| Field | Purpose |
| --- | --- |
| `invite_token_hmac` | One-time redemption without raw token storage |
| `invite_created_at`, `invite_expires_at`, `invite_consumed_at` | Atomic 24-hour single use |

### Consent records

Each role action stores:

| Field | Purpose |
| --- | --- |
| `consent_id`, `role` | Exact relationship-scoped disclosure and actor |
| `document_version`, `document_digest` | Immutable accepted text |
| `accepted_at`, `locale`, `app_version` | Reproducible context |
| `withdrawn_at` | Withdrawal without rewriting history |

No IP, full user agent, handwritten signature, email, or free-text note is collected.

### Phone-verification challenges

| Field | Purpose |
| --- | --- |
| `challenge_id`, `role`, `phone_ciphertext`, `phone_hmac` | Exact scoped destination while verifying |
| `code_hash`, `attempt_count` | One-time code and five-attempt limit |
| `created_at`, `expires_at`, `consumed_at` | Ten-minute lifetime |
| `consent_document_version`, `consent_document_digest` | Exact phone-use disclosure |

Person success deletes ciphertext and retains only `person_self_phone_hmac`. Guardian success moves
the ciphertext/digest to active fallback. Failures and expiry delete challenge secrets.

### Fallback phone

| Field | Purpose |
| --- | --- |
| `fallback_phone_ciphertext`, `fallback_phone_hmac` | Verified guardian SMS destination |
| `fallback_phone_state` | `notConfigured`, `pendingVerification`, `verified`, `revoked` |
| `fallback_phone_verified_at`, `fallback_phone_revoked_at` | Eligibility and deletion enforcement |
| `sms_consent_record` | Current `guardian-sms-fallback-v1` record |

### Role devices

At most one person and one guardian device record exist:

| Field | Purpose |
| --- | --- |
| `role`, `installation_id_hmac` | Signed role ownership without OS tracking IDs |
| `apns_token_ciphertext`, `apns_token_hmac` | APNs send and rotation |
| `apns_environment`, `bundle_id`, `authorization_state` | Topic/environment eligibility |
| `state`, `registered_at`, `rotated_at`, `invalidated_at` | Lifecycle |

No device model, serial, IDFA, IDFV, contacts, location, or notification history is stored.

### Signature replay window

| Field | Purpose |
| --- | --- |
| `capability_id`, `nonce_hmac`, `request_timestamp`, `expires_at` | Reject replay for ten minutes |

The object prunes expired nonce entries on every authenticated mutation and a scheduled alarm.

### Durable alert state

| Field | Purpose |
| --- | --- |
| `requested_event_id`, `canonical_event_id` | Idempotency and safe coalescing |
| `request_fingerprint` | Detect event reuse with changed content |
| `workflow_state`, `ui_state`, `version` | Monotonic reconciliation |
| `created_at`, `updated_at`, `expires_at` | 24-hour lifetime |
| `message_template_version` | Template audit without storing body |
| `push_state`, `push_accepted_at`, `push_error_class` | APNs truth without response body/token |
| `fallback_state`, `fallback_availability`, `fallback_scheduled_for`, `fallback_fired_at` | Exactly-one fallback |
| `sms_state`, `sms_provider_id_hmac`, `sms_updated_at`, `sms_error_class` | Callback lookup and transport truth |
| `sms_callback_token_hmac` | Authenticate callback routing after provider-signature validation |
| `guardian_opened_at` | Optional operational telemetry; never person-facing |
| `guardian_acknowledged_at`, `acknowledgment_signature_digest` | Verified human action without raw signature retention |

Error classes are low-cardinality enums such as `invalidToken`, `rateLimited`, `provider5xx`,
`timeout`, and `unknown`. Raw provider bodies and identifiers are not stored.

### Phone abuse limiter

The phone-keyed limiter stores only `phone_hmac`, coarse action (`personVerify` or
`guardianFallbackVerify`), reservation timestamps, and expiry. It contains no relationship ID,
phone ciphertext, code, name, payload, consent, or alert data. Limiter unavailability prevents a
new verification SMS but cannot revoke or authorize an active alert.

## On-device records

Relationship Keychain storage may contain only:

- role private key reference, relationship ID, role capability ID, and contract version;
- relationship state and expiry;
- random installation ID;
- one pending receipt per event: requested UUID, canonical UUID if coalesced, last server version,
  last truthful UI state, creation/expiry, and next safe poll time.

Pending receipts contain no metric, camera data, substance inference, message, phone, provider
reference, or guardian identifier. Corrupt receipts are discarded and never create a new event ID
or automatic resend. Records are deleted at event/relationship expiry, revocation, or local reset.

`UserDefaults` contains presentation preferences only. A notification payload contains an opaque
relationship ID, one event UUID when applicable, a route code, and generic text; relationship
context is fetched after signed authorization.

## Technical retention schedule

These are founder-staging maximums. Backups and restored objects cannot extend them.

| Record | Maximum | Deletion trigger |
| --- | --- | --- |
| Unverified relationship | 20 minutes | Challenge expiry or successful transition |
| Verification phone ciphertext/code hash | 10 minutes | Success, expiry, five failures, or revocation |
| Person self-phone digest | Active relationship only | Delete within 24 hours of revocation/expiry |
| Invite token hash | 24 hours | Redemption, expiry, revocation, or relationship deletion |
| Active relationship and public keys | 90 days | Revocation, expiry, or new two-sided relationship |
| Revoked relationship/consent audit | 30 days | Hard delete after founder dispute/debug window |
| Active fallback phone | Active verified consent only | Logical revocation immediately; hard delete within 24 hours |
| APNs token | Eligible relationship/device only | Invalidate immediately; hard delete within 24 hours |
| Signature nonce | 10 minutes | Replay-window expiry |
| Alert, alias, and provider digest | 24 hours from canonical event | Hard delete within one hour after expiry |
| Phone abuse reservation | 24 hours | Rolling deletion |
| Privacy-safe operational event | 30 days | Rolling deletion |
| Security audit event | 90 days | Rolling deletion; no payload/direct identifier |
| On-device pending receipt | Alert/relationship expiry | Immediate local deletion |

Durable Object backups, snapshots, and disaster recovery must use no more than 24-hour retention and
must reapply revocation/deletion tombstones before serving restored state. If the platform cannot
guarantee this, external testing is blocked.

Provider retention is separate. Before external testing, the privacy notice and vendor settings must
state and minimize APNs, SMS-provider, and Cloudflare retention. Sober cannot claim provider deletion
without contractual and configuration evidence.

## Consent and revocation behavior

1. The person accepts `guardian-sender-v1` and `person-phone-verification-v1` before a verification
   SMS creates an invite.
2. The guardian separately accepts `guardian-recipient-v1` and
   `notification-disclosure-v1` during redemption.
3. SMS fallback requires `guardian-sms-fallback-v1`, a short-lived code, a distinct public key, and a
   phone digest different from the verified person's self-phone digest.
4. Relationship activation requires current two-sided consent. Fallback activation is optional and
   separately consented.
5. Notification denial never fabricates receipt or acknowledgment. A verified fallback is attempted;
   otherwise the app reports failure and keeps direct help actions prominent.
6. Either role may revoke. The relationship object serializes revocation with alert reservation. A
   provider request already started cannot be recalled; later alarms/actions are blocked.
7. Guardian revocation emits a generic relationship-change push to the person and always reconciles
   on foreground. The app must return to an explicit unconfigured Safety Circle state.
8. Material disclosure changes set `reauthorizationRequired`; new automatic alerts stop until the
   required signed acceptances exist.
9. Relationship expiry is not silent renewal. Both people must complete a new invite.
10. Guardian data is never merged into, linked from, or exported with research data.

## Research separation and dictionary versioning

The research data dictionary must explicitly mark these fields prohibited:

- relationship, capability, invite, challenge, device, installation, alert event, provider, and
  acknowledgment identifiers;
- guardian/person public keys, phone digests, notification state, and alert timestamps;
- Guardian consent, revocation, delivery, and open telemetry.

A non-identifying boolean or count describing whether a safety intervention was offered may be
included only if the approved study protocol requires it; it cannot carry an identifier or exact
provider timestamp.

The external research data-dictionary version is independent of the local storage-envelope version.
Changing optionality, units, missing-value meaning, protocol inclusion, or transformation increments
the dictionary version even when the app can still decode the same storage schema. In particular,
optional blink telemetry cannot remain under an unchanged dictionary contract.

## Logging allowlist

Structured logs may contain only:

- privacy-safe request ID;
- environment-specific HMAC correlation keys for relationship, event, capability, and device;
- endpoint template, method, response class, stable error, and retryability;
- low-cardinality state transition, provider class, result class, and fallback reason;
- attempt count, latency, timestamp, deployment version, and environment;
- callback-signature valid/invalid boolean, never the signature;
- limiter outcome, never the raw bucket value.

Logs, traces, metrics, analytics, crashes, and support exports must never contain:

- private keys, raw signatures, nonces, invite tokens, verification codes, APNs tokens, provider
  credentials, encryption/HMAC keys, or allowlist configuration;
- raw relationship, capability, invite, challenge, device, installation, or provider IDs;
- names, labels, phone numbers, emails, IP addresses, exact user agents, or universal-link URLs;
- message bodies, request/response bodies, headers, query strings, exception-local provider objects,
  Durable Object state, or environment bindings;
- screening results beyond the invariant that an authorized alert was requested;
- scores, metrics, camera/ocular data, substance inference, or research records.

Middleware defaults to allowlisted metadata. Full-object serialization is prohibited.

## Required privacy tests

- Object schemas contain only listed fields; migrations handle every version explicitly.
- Synthetic secrets, keys, signatures, names, phones, tokens, bodies, and provider IDs never appear
  in captured logs, traces, analytics, exceptions, or dry-run output.
- Alert decoding rejects extra sensitive fields.
- Push and SMS fixtures contain only generic text and opaque routing data.
- Research exports contain no Guardian identifier class listed above.
- Export fixtures declare a data-dictionary version independent of storage schema, and optionality
  changes fail compatibility tests without a dictionary-version bump.
- Invite, challenge, signature nonce, relationship, alert, device, log, and backup retention jobs
  pass clock-driven boundary tests.
- Same key and same verified phone cannot activate a guardian.
- Revocation blocks new provider work immediately and removes every derived digest on schedule.
- Key rotation rewrites current ciphertext without plaintext logging.
- Restored state reapplies revocation and expiry before accepting requests.

## Launch blockers

External TestFlight or human-subject use is blocked until:

- privacy/legal review approves this schema, contact-relationship category, providers, retention,
  consent copy, deletion, and incident handling;
- Apple capabilities for push, associated domains, and Time Sensitive notifications are configured;
- Apple approves the Critical Alerts entitlement if the founders require Focus override as part of
  the product claim;
- founder staging proves that no Guardian identifiers enter research exports.

Approval must cite the exact contract digest and schema version. Silence and app usage are not
approval.
