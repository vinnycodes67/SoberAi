# Guardian App Attest Security Design

Status: implementation gate; no entitlement, production credential, or non-founder enrollment is
authorized by this document

Design version: `sober-app-attest-v1`

Last updated: 2026-08-08

## Decision

App Attest is a layered abuse and app-integrity signal for Guardian v1.1. It is not an account,
person identity, device identity, phone-ownership proof, relationship capability, jailbreak oracle,
or guarantee that a request is benign. Relationship-scoped P-256 capabilities in
`Docs/GUARDIAN_API.md` remain the authority after relationship creation.

Before a non-founder installation can make the unauthenticated relationship-creation request that
may initiate person-phone verification, the server must have:

1. verified an Apple attestation for that app installation;
2. verified a fresh assertion bound to the exact creation request;
3. atomically consumed a single-use server challenge and advanced the key counter; and
4. passed the independent phone, installation, and network abuse limits.

Failure of any required control prevents the external side effect. It does not disable on-device
screening, Call/Message/Ride actions, an already-authorized relationship, or founder review on an
explicit allowlist. A kill switch may close enrollment; it may never silently make attestation
optional for external verification traffic.

This design follows Apple's current [client integration guidance](https://developer.apple.com/documentation/DeviceCheck/establishing-your-app-s-integrity),
[server validation procedure](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server),
[attestation validation guide](https://developer.apple.com/documentation/devicecheck/attestation-object-validation-guide),
and [rollout guidance](https://developer.apple.com/documentation/DeviceCheck/preparing-to-use-the-app-attest-service).
Apple explicitly describes App Attest and DeviceCheck as inputs to an overall risk assessment, not
as a complete fraud solution.

## Scope and non-goals

In scope:

- an App Attest key for the installation initiating Guardian relationship creation;
- one-time attestation and assertion challenges;
- server verification, counters, replay prevention, rotation, revocation, retention, and risk;
- a concrete wire boundary that can be frozen before implementation; and
- evidence required before two physical devices can pass the non-founder enrollment gate.

Not in scope:

- APNs keys, Key IDs, Team ID values, push routes, notification entitlements, SMS credentials, an
  SMS vendor decision, A2P registration, accounts, D1, or identity recovery;
- adding App Attest to every relationship request or alert poll;
- treating an App Attest key as the screened person or Guardian; or
- changing screening stimuli, baseline semantics, alert payloads, consent, or public-v1 boundaries.

The App ID prefix/Team configuration and bundle identifiers are deployment inputs. No value is
guessed, requested, or embedded in fixtures by this design. The App Attest key identifier returned
by `DCAppAttestService.generateKey()` is unrelated to an APNs provider Key ID.

## Trust boundaries and threat model

Trust boundaries:

1. **iOS process:** request construction is untrusted, but the App Attest private key is managed by
   the framework/Secure Enclave and is not exported.
2. **Apple App Attest service and PKI:** certifies an app-instance key during attestation. Assertions
   are later generated on device and verified by Sober without an Apple network call.
3. **Cloudflare edge Worker:** validates public request shape, performs keyed routing, and passes
   enrollment work to the installation object. Headers and bodies are never logged.
4. **`EnrollmentAttestation` Durable Object:** serializes challenges, key state, assertion counters,
   request authorization, and replay receipts for one keyed App Attest key. It cannot authorize an
   alert or read alert content.
5. **`GuardianRelationship` Durable Object:** remains the sole relationship/consent/revocation/alert
   authority after creation. It receives only a verified installation reference and risk snapshot.
6. **Abuse limiters and phone provider:** independently control whether a verification message may
   be attempted. App Attest success does not bypass them.

| Threat | Required control | Failure result |
| --- | --- | --- |
| Modified client authors a creation request | Apple chain/app identity verification plus assertion bound to exact bytes | No verification side effect |
| Captured attestation/assertion is replayed | Random single-use challenge, purpose binding, counter, and idempotency receipt | Generic rejection; no counter rollback |
| Assertion is moved to another body/path/environment | Canonical method, normalized path, body hash, key handle, and environment binding | Signature/binding rejection |
| Genuine device becomes a signing oracle for many clients | Installation/phone/network limits, unique key association, Apple risk metric, anomaly response | Throttle or close enrollment |
| Reinstall is used to reset state | New installation/key is treated as new, risk metric and phone/network limits remain | No relationship authority recovery |
| Old or stolen local app data is restored | This-device-only installation record; App Attest key fails after reinstall/restore | Re-attest as new installation |
| Concurrent assertions race counters | One installation Durable Object and client-side serialized assertion actor | Only strictly increasing committed counter wins |
| Unsupported device claims bypass | Server-issued unsupported disposition, never a client boolean | No external verification message |
| Apple is unavailable | Existing assertions continue; new attestation uses bounded retry with same key/input | New external enrollment pauses |
| Sober verifier accepts test roots in production | Separate verifier dependency and environment build/deploy assertion | Deployment fails closed |
| App Attest is mistaken for identity | Relationship invite, role keys, distinct-phone checks, and consent remain mandatory | No authority or identity claim |

Residual risk remains: a genuine supported device can be controlled by an attacker; a compromised
OS can weaken assumptions; Apple or Sober infrastructure can fail; and a valid app can still submit
harmful or fraudulent user input. App Attest raises abuse cost and improves request provenance. It
does not remove those risks.

## Client key lifecycle

`GuardianAppAttestClient` is an actor so one installation never creates or submits assertions
concurrently.

1. Read `DCAppAttestService.shared.isSupported`.
2. Load `installationId` and the App Attest `keyId` reference from this-device-only Keychain. The
   installation ID is 32 random bytes, base64url without padding. Store no attestation object.
3. If supported and no key exists, call `generateKey()`, then persist the returned key identifier.
4. Request an attestation challenge, SHA-256 hash the exact returned `clientData` bytes, and call
   `attestKey(_:clientDataHash:)`.
5. Submit the unmodified attestation object. Persist the server's opaque `keyHandle` only after the
   server confirms verification.
6. For guarded relationship creation, request an assertion challenge bound to the already-encoded
   request, hash returned `clientData`, and call `generateAssertion(_:clientDataHash:)`.
7. Submit the original exact request bytes and assertion headers. Do not re-encode after challenge
   issuance.

Apple says keys survive ordinary app updates but not reinstall, device migration, or restoration
from backup. Those events create a new installation and key; they do not recover a Guardian
relationship. `invalidKey` triggers server invalidation followed by one rate-limited new-key flow,
not an unbounded key-generation loop.

The client interface to implement is:

```swift
protocol GuardianAppAttesting: Sendable {
  var isSupported: Bool { get async }
  func ensureAttestedKey() async throws -> AppAttestKeyRegistration
  func assertionHeaders(
    method: String,
    normalizedPath: String,
    exactBody: Data,
    idempotencyKey: String
  ) async throws -> [String: String]
  func invalidateLocalReference() async throws
}

struct AppAttestKeyRegistration: Sendable {
  let keyHandle: String
  let environment: AppAttestEnvironment
  let attestedAt: Date
}
```

Production code uses `DCAppAttestService`; tests inject a fake that cannot be selected by a
production build configuration. When the internal v1.1 target reaches the rollout gate, its reviewed
signing configuration supplies `com.apple.developer.devicecheck.appattest-environment` for that
environment. The public-v1 target never receives that entitlement, and this design does not guess an
App ID prefix, Team ID, or signing value.

## Wire encoding and canonical client data

- TLS and `Cache-Control: no-store` are mandatory.
- JSON is UTF-8, camelCase, and rejects unknown fields.
- Binary values use base64url without padding.
- `nonce` is 32 server-random bytes; challenge IDs and key handles are opaque prefixed IDs.
- Challenge lifetime is 120 seconds. A consumed, expired, wrong-purpose, or wrong-environment
  challenge returns the same non-enumerating error.
- Request bodies are capped before parsing: 2 KiB for challenge JSON, 16 KiB for key registration,
  and the existing Guardian creation limit for relationship creation.
- `bodySha256` is lowercase SHA-256 hex of the exact bytes sent later.

The server returns exact canonical `clientData` bytes as base64url. The client decodes and hashes
those bytes; it never independently rebuilds the string.

Attestation `clientData` is UTF-8 with no trailing newline:

```text
sober-app-attest-v1
attestation
<challengeId>
<nonce base64url>
<installationId>
<App Attest keyId>
<development|production>
```

Assertion `clientData` is:

```text
sober-app-attest-v1
assertion
<challengeId>
<nonce base64url>
<keyHandle>
<uppercase HTTP method>
<normalized path without query>
<lowercase exact-body SHA-256 hex>
<Idempotency-Key>
<development|production>
```

Line values must not contain control characters or newlines. `clientDataHash` is
`SHA256(clientData)`. The installation object stores only the hash/keyed binding needed to verify
the response, not raw canonical data or request bodies.

## Server endpoints

All responses use the `Docs/GUARDIAN_API.md` error envelope and privacy-safe request ID.

### `POST /v1/app-attest/attestation-challenges`

Exact request:

```json
{
  "installationId": "<base64url 32 random bytes>",
  "keyId": "<opaque identifier returned by DCAppAttestService>",
  "environment": "development"
}
```

The Worker validates sizes/encoding, HMACs the installation and key identifiers, applies challenge
limits, and routes to the installation object. Response:

```json
{
  "challengeId": "aac_...",
  "clientData": "<base64url canonical bytes>",
  "expiresAt": "2026-08-08T18:02:00.000Z",
  "requestId": "req_..."
}
```

### `PUT /v1/app-attest/keys/registration`

Exact request:

```json
{
  "challengeId": "aac_...",
  "installationId": "<same installation ID>",
  "keyId": "<same App Attest key ID>",
  "environment": "development",
  "attestationObject": "<base64url unmodified CBOR>"
}
```

Success consumes the challenge and returns:

```json
{
  "keyHandle": "aak_...",
  "state": "attested",
  "attestedAt": "2026-08-08T18:00:12.000Z",
  "assertionRequiredFor": ["guardianRelationshipCreation"],
  "requestId": "req_..."
}
```

An exact registration retry returns the prior success. Changed content conflicts. The object does
not associate this key with a person, phone, or Guardian role.

### `POST /v1/app-attest/assertion-challenges`

Exact request:

```json
{
  "keyHandle": "aak_...",
  "purpose": "guardianRelationshipCreation",
  "method": "POST",
  "path": "/v1/guardian-relationships",
  "bodySha256": "<lowercase exact-body SHA-256 hex>",
  "idempotencyKey": "<same key used on creation>"
}
```

Only that purpose/method/path combination is accepted in v1.1. The response has the same
`challengeId`, `clientData`, and `expiresAt` fields as the attestation challenge.

### Guarded relationship creation

`POST /v1/guardian-relationships` keeps the exact JSON in `Docs/GUARDIAN_API.md` and adds:

```text
Idempotency-Key: <opaque 1–128 printable characters>
Sober-App-Attest-Key-Handle: aak_...
Sober-App-Attest-Challenge-ID: aac_...
Sober-App-Attest-Assertion: <base64url CBOR assertion>
```

The Worker sends the exact request binding to the installation object. The object verifies the
assertion, consumes the challenge, advances the counter, and durably records an approved
authorization keyed by `(idempotencyKey, canonical request digest)` before relationship creation.
An exact retry reuses that authorization without regenerating an assertion or advancing the
counter. Changed content returns `409 idempotencyConflict`. Only then may the Worker call the
relationship object and the independent phone abuse limiter. Cross-object failure cannot cause a
second assertion or verification message: the approved authorization remains replayable for that
exact idempotency key for ten minutes, and relationship creation is independently idempotent.

Founder mode may continue to use an explicit installation and phone allowlist without these
headers. `GUARDIAN_FOUNDER_MODE` and external enrollment are mutually exclusive deployment modes.

The server modules expose this boundary; cryptographic parsing is not embedded in the Worker router:

```ts
interface AppAttestCryptographicVerifier {
  verifyAttestation(input: {
    attestationObject: Uint8Array;
    clientDataHash: Uint8Array;
    expectedKeyId: string;
    expectedAppId: string;
    environment: "development" | "production";
    allowedValidationCategories: readonly string[];
    allowedBundleVersions: readonly string[];
  }): Promise<VerifiedAppAttestation>;

  verifyAssertion(input: {
    assertionObject: Uint8Array;
    clientDataHash: Uint8Array;
    publicKeySpki: Uint8Array;
    expectedRpIdHash: Uint8Array;
    previousCounter: number;
  }): Promise<{ counter: number }>;
}

interface EnrollmentAttestationAuthority {
  issueAttestationChallenge(input: AttestationChallengeInput): Promise<ChallengeOutput>;
  registerKey(input: KeyRegistrationInput): Promise<KeyRegistrationOutput>;
  issueAssertionChallenge(input: AssertionChallengeInput): Promise<ChallengeOutput>;
  authorizeGuardianCreation(input: GuardedCreationInput): Promise<ExactRequestAuthorization>;
  revokeKey(input: { keyHandle: string; reason: AppAttestRevocationReason }): Promise<void>;
}
```

`VerifiedAppAttestation` contains only the verified SPKI, app/environment/category/version facts,
receipt, and initial counter. `ExactRequestAuthorization` contains only the key-handle digest,
idempotency digest, request digest, risk band, environment, verification time, and expiry. Concrete
types reject unknown fields and enforce the byte/length bounds in this document.

## Apple attestation verification

The server verifier is a pure, versioned module with strict CBOR, ASN.1, certificate, COSE, and
authenticator-data parsers. It must implement every current Apple validation step, not merely verify
one signature:

1. Decode CBOR with definite bounds; require `fmt: apple-appattest`, the expected `authData`, `x5c`,
   and receipt structure; reject duplicate keys, trailing data, indefinite oversized objects, and
   unknown critical data.
2. Validate the credential/intermediate certificate chain, dates, algorithms, constraints, and
   signatures to the separately configured Apple App Attest root. Production never trusts a test
   root or a root supplied in the request.
3. Rebuild `clientDataHash` from the stored challenge and compute
   `nonce = SHA256(authData || clientDataHash)`.
4. Decode credential-certificate extension OID `1.2.840.113635.100.8.2` and constant-time compare
   its octet string with the nonce.
5. Hash the credential certificate's P-256 public key in X9.62 uncompressed form and compare it with
   the decoded App Attest key ID.
6. Verify the RP ID hash equals `SHA256(configuredAppIdPrefix + "." + configuredBundleId)`.
7. Require the attestation counter to be zero.
8. Require the AAGUID/environment value Apple specifies for the configured development or
   production environment. Development and production keys/receipts never cross environments.
9. Require credential ID to equal the key ID.
10. Validate Apple's `validationCategory` extension against an environment allowlist: development
    signing only in founder development; TestFlight or App Store distribution in external
    production. Invalid, ad-hoc, enterprise, and unexpected categories are rejected unless a later
    reviewed deployment profile explicitly permits one.
11. Validate the bundle-version extension against a server allowlist/minimum version so an attested
    but obsolete vulnerable binary cannot enroll.

On success, extract and store the verified public key and independently validated receipt. Never
store the attestation object. Certificate, AAGUID, validation category, or bundle-version policy
changes require new fixtures and security review.

## Assertion verification and replay prevention

For each guarded request, inside the installation object's serialized turn:

1. Validate key state, environment, purpose, challenge state/expiry, and exact stored request
   binding before expensive cryptography.
2. Strictly decode assertion CBOR as exactly `signature` plus `authenticatorData` within size caps.
3. Compute `clientDataHash`, then `nonce = SHA256(authenticatorData || clientDataHash)`.
4. Verify the DER ECDSA signature over `nonce` with the attested public key. Reject non-canonical,
   malformed, wrong-curve, or trailing signature encodings.
5. Recheck the RP ID hash in the assertion and the stored, attestation-verified validation category
   and bundle version under the current configured policy.
6. Read the unsigned 32-bit big-endian counter and require `counter > storedCounter` and
   `counter > 0`. Equality, decrease, wrap, or malformed length revokes the assertion attempt.
7. Atomically mark the challenge consumed, store the new counter, and write the exact idempotency
   authorization before returning success.
8. On verification failure, do not advance the counter, but consume a structurally valid challenge
   after the configured attempt limit so it cannot be an oracle.

Because valid counters can arrive out of order, the iOS actor serializes challenge/assertion/request
submission. The server still treats a lower late counter as replay. A counter anomaly increments a
security event and can revoke the key after two anomalies; it never grants relationship authority.

## Storage schema and retention

One installation-keyed `EnrollmentAttestation` Durable Object stores:

| Field | Purpose |
| --- | --- |
| `schema_version`, `design_version` | Migration and verifier compatibility |
| `key_handle_hmac`, `key_id_hmac`, `installation_id_hmac` | Equality/routing without raw identifiers |
| `environment`, `app_id_hash`, `validation_category`, `bundle_version` | Frozen app/environment policy evidence |
| `public_key_spki` | Assertion verification; public credential material |
| `receipt_ciphertext`, `receipt_updated_at` | Optional Apple risk-metric refresh without logging receipt |
| `state`, `attested_at`, `revoked_at`, `revocation_reason` | `pending`, `attested`, `rotating`, `revoked`, `expired` lifecycle |
| `assertion_counter`, `last_asserted_at` | Strict monotonic replay check |
| `challenge_id_hmac`, `purpose`, `client_data_hash`, `binding_hmac`, `issued_at`, `expires_at`, `consumed_at`, `attempt_count` | One outstanding challenge |
| `authorization_idempotency_hmac`, `request_digest_hmac`, `authorization_expires_at` | Exact retry after counter advancement |
| `risk_band`, `risk_checked_at`, `risk_receipt_age` | Low-cardinality risk result, not a stable device score |
| `rotation_parent_hmac`, `rotation_deadline` | Bounded old/new key overlap |

Raw key IDs, installation IDs, challenges, client data, bodies, assertions, attestation objects,
receipts, certificate chains, IP addresses, and Apple errors are excluded from logs. Challenge state
expires after two minutes; approved request authorization after ten minutes; operational events
after 30 days; security events after 90 days. An active key is re-attested or expired after at most
90 days. Revoked key material and encrypted receipt are hard-deleted within 24 hours; a minimal
keyed revocation tombstone may remain for 90 days to stop immediate reenrollment replay.

The relationship record stores only `app_attest_key_handle_hmac`, `app_attest_verified_at`,
`app_attest_environment`, and a low-cardinality risk band snapshot. The installation object remains
the counter authority. No App Attest identifier enters research data.

## Rotation, reinstall, and revocation

- **Routine rotation:** server marks `rotationRequired`; the old key assertion authorizes one new-key
  attestation. Both key handles overlap for at most 24 hours, then the old key is revoked.
- **Invalid key:** invalidate the local reference, mark the server key revoked when reachable, and
  allow one rate-limited new-key registration. Never retry `generateKey()` in a loop.
- **Reinstall/migration/restore:** create a new installation ID and key. No old relationship
  capability is restored; Guardian v1 still requires revocation and a fresh two-sided invite.
- **Server revocation:** fraud signal, counter anomaly, key association collision, environment
  mismatch, obsolete vulnerable build, or incident response can revoke a key. Revoking App Attest
  enrollment blocks new guarded setup; relationship revocation remains a separate explicit action.
- **Lost device:** App Attest supplies no recovery. The other relationship role revokes and creates
  a new relationship.

The same verified public key/key ID may not attach to two installation handles or two incompatible
environments. Equality checks are constant-time over keyed digests.

## Unsupported devices and outage policy

| Condition | Existing on-device/relationship behavior | External relationship creation |
| --- | --- | --- |
| `isSupported == false` | Continue local safety features and valid relationship capabilities | Fail closed before verification side effect; show compatibility path |
| Apple `serverUnavailable` during first attestation | Retry later with the same key and `clientDataHash` until challenge expiry; do not generate a new key | Paused |
| Apple throttling | Honor backoff/rollout kill switch; preserve key | Paused |
| Already-attested key during Apple outage | Assertions continue because they are on-device/server verified | Allowed only if assertion, counters, and all abuse limits pass |
| Risk-metric refresh unavailable after cryptographic attestation | Keep `riskUnavailable`; no identity claim | At most one provider attempt under stricter phone/network limits, only after SMS/provider approval |
| Sober limiter/installation object unavailable | Existing local/manual help remains | Fail closed; no provider call |
| Assertion malformed, stale, replayed, or wrong binding | No effect on existing relationship authority | Rejected generically |

Unsupported users are not labeled fraudulent. A future support-assisted alternative must receive a
separate threat/privacy review and may not be introduced as an unreviewed bypass. Apple recommends
checking `isSupported` and handling availability gracefully; for Sober, graceful behavior preserves
local safety and existing capabilities while the high-abuse unauthenticated SMS boundary stays
closed.

## Risk, rate limits, and response policy

Initial server-configured ceilings, all enforced before any verification provider call:

- attestation challenges: 5 per keyed installation/key per 10 minutes and 30 per coarse keyed
  network bucket per hour;
- new attested keys: 3 per keyed installation per 24 hours, with Apple risk-band escalation;
- assertion challenges for relationship creation: 10 per key per 10 minutes;
- failed attestation/assertion verification: 5 per key or installation per hour, then a 24-hour
  cooldown; and
- one outstanding challenge per key/purpose; issuing a replacement invalidates the prior challenge.

Phone-digest and provider-attempt limits in `GUARDIAN_API.md` remain independent and stricter where
required. If Apple's approximate key metric is 0–2, the initial risk band is `normal`; 3–5 is
`elevated` and receives half the setup rate; above 5 is `high` and blocks automated external setup
pending review. These are launch controls, not claims that a person or device is fraudulent, and
must be tuned from privacy-safe evidence. A missing metric is `unavailable`, never `normal`.

Errors are non-enumerating. Client-visible distinctions are limited to `retryLater`,
`unsupportedForExternalSetup`, or generic `setupUnavailable`; raw Apple/verifier reason codes are
security telemetry only.

## Privacy, logging, and observability

Operational metrics use environment, build cohort, endpoint, outcome class, latency bucket, and
risk band only. Required counters include challenge issuance/expiry/consumption, attestation
success/failure class, assertion success/replay/counter anomaly, key rotation/revocation, Apple
unavailability, limiter denial, authorization replay, and guarded side effects prevented.

Alerts fire on sudden attestation failure changes by build/environment, counter-replay spikes,
unexpected validation categories, high key-generation bands, test-root configuration in a
production deployment, and any guarded provider call without an approved assertion authorization.

Never log or send to analytics: raw or masked phone, name, relationship/capability ID, key ID/handle,
installation ID, challenge, assertion, attestation object, public key, receipt, certificate,
signature, client data, request/body hash, IP, headers, request/response body, or Apple raw error.
Request IDs are independently random and cannot encode these values.

## Local tests and fixtures

The verifier has three layers:

1. pure CBOR/ASN.1/authenticator parsing tests with bounded synthetic inputs;
2. cryptographic end-to-end fixtures signed by a repository test CA accepted only by an injected
   `TestAppAttestTrustStore`; and
3. Apple sandbox/development integration fixtures captured from an owned physical device and kept
   in access-controlled CI fixture storage, not committed with reusable receipts.

Production dependency construction accepts only `AppleProductionAppAttestTrustStore`. A build-time
test asserts no test root, fake attester, or bypass symbol is reachable from the Worker entry point.
Fixtures cover every Apple validation step, byte mutation, wrong app/environment/category/version,
expired/untrusted certificate, nonce mismatch, key-ID mismatch, counter zero/equal/decrease/wrap,
challenge replay/expiry/purpose mismatch, changed body/path/idempotency key, Durable Object reload,
concurrent counters, exact retry after counter commit, rotation, reinstall, revocation, limiter
failure, and log redaction.

Simulator and local Worker tests use the fake client plus test-root verifier and must be visibly
labeled synthetic. They cannot count as Apple acceptance evidence. No fixture fabricates a
production Apple success.

## Rollout and rollback

1. **Parser gate:** land verifier, negative fixtures, schema migrations, and secret/log scans with
   no entitlement and no production decision.
2. **Founder development report-only:** physical founder devices use the development environment;
   server evaluates but founder allowlist remains the actual gate.
3. **TestFlight production report-only:** enable the production App Attest environment for a small
   internal cohort; verify validation category, version, counters, latency, and Apple capacity.
4. **Founder enforcement:** require assertion plus allowlist. A mismatch closes setup and cannot be
   bypassed remotely except by disabling setup entirely.
5. **External staged enforcement:** only after the App Store master plan's repeatability,
   privacy/legal, two-device, phone-provider, and security review gates pass. Ramp 1%, 10%, 50%,
   100% while respecting Apple's current capacity guidance and an immediate close-enrollment switch.

Rollback disables new relationship creation; it does not accept unattested creation. Existing
relationship capability traffic continues unless separately revoked. Development/production
objects, roots, metrics, and deployment configuration remain isolated.

## Two-device acceptance evidence

Before external enrollment, record one reviewed evidence bundle from two distinct supported
physical iPhones using the intended TestFlight production build:

1. Device A creates and attests installation key A; device B independently creates and attests key
   B. Evidence records only hashed fixture labels, model/OS/build, environment, validation category,
   bundle version, timestamps, and pass/fail steps.
2. Each device produces two assertions with strictly increasing counters. Replay, body mutation,
   wrong path, wrong key handle, and cross-device assertion swaps are rejected.
3. Kill/relaunch and Durable Object reload preserve the counter and exact-idempotency retry.
4. Reinstall one device proves the old App Attest key is unavailable and does not recover the old
   Guardian capability or relationship.
5. Revoke one enrollment key and prove new guarded setup is rejected while an independently valid
   existing relationship remains governed by its role capability.
6. Exercise `serverUnavailable`, unsupported-device fixture, limiter outage, and risk-unavailable
   policy without a real provider side effect.
7. After an SMS provider and owner policy are approved, repeat the exact guarded creation once per
   device with allowlisted numbers and prove one provider attempt per idempotency key. Until then,
   use a provider spy and mark live side-effect evidence blocked—not passed.

The evidence bundle includes test commands, server build commit, sanitized state-transition traces,
screenshots of client result states, reviewer/sign-off names, failures, and remediation. It excludes
raw identifiers, objects, receipts, phone data, keys, signatures, and credentials.

## Reconciliation with Guardian and App Store plans

- The frozen public-v1 boundary in `Docs/APP_STORE_MASTER_PLAN.md` remains controlling: the public
  archive has no Guardian route, backend, location, notification, background mode, App Attest
  entitlement, or App Attest client. This internal v1.1 design does not alter source exclusions or
  public capabilities and must be integrated only after the App Store branch chain lands.
- `Docs/GUARDIAN_API.md` remains `guardian-api-v1`. The App Attest endpoints and creation headers are
  a frozen additive v1.1 setup layer; relationship capability signatures are unchanged.
- One `GuardianRelationship` object remains the alert/revocation consistency boundary. The minimal
  installation object exists only because attestation precedes relationship creation and because a
  monotonic key counter must serialize across retries.
- Founder creation stays founder-controlled. Removing its allowlist before this design is
  implemented and reviewed is blocked.
- App Attest does not unlock APNs, SMS, `personActionState.actNow`, notification routes, or
  entitlements. Those retain their own provider/evidence dependencies.
- No non-founder live Guardian alert proceeds until the App Store master plan's sober-repeatability
  and human-review gates pass, even if App Attest is valid.

Implementation starts only after an independent security re-review freezes the root source,
environment configuration, exact creation body/idempotency contract, parser library, migration,
rate-limit values, and unsupported-device product path.
