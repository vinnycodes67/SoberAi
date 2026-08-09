import assert from "node:assert/strict";
import test from "node:test";

import { base64URL, canonicalSignatureInput, sha256Hex } from "./guardian-crypto.js";
import { GuardianRelationship } from "./durable-guardian-relationship.js";
import { handleGuardianRequest } from "./guardian-handler.js";
import {
  handleRelationshipAlarm,
  inactiveAuditLifetimeMilliseconds,
  persistRelationshipState,
  relationshipLifetimeMilliseconds,
  relationshipWarningLeadMilliseconds,
} from "./guardian-relationship-lifecycle.js";

const encoder = new TextEncoder();
const origin = "https://guardian.example.test";

class MemoryStorage {
  constructor() {
    this.values = new Map();
    this.alarm = null;
  }
  async get(key) {
    const value = this.values.get(key);
    return value == null ? value : structuredClone(value);
  }
  async put(key, value) { this.values.set(key, structuredClone(value)); }
  async delete(key) { this.values.delete(key); }
  async deleteAll() { this.values.clear(); }
  async setAlarm(value) { this.alarm = Number(value); }
  async getAlarm() { return this.alarm; }
  async deleteAlarm() { this.alarm = null; }
}

class MemoryDurableState {
  constructor(storage = new MemoryStorage()) { this.storage = storage; }
  blockConcurrencyWhile(operation) { return operation(); }
}

class MemoryNamespace {
  constructor() { this.instances = new Map(); }
  idFromName(value) { return value; }
  get(id) {
    if (!this.instances.has(id)) this.instances.set(id, new GuardianRelationship(new MemoryDurableState()));
    return this.instances.get(id);
  }
  reload(id) {
    const storage = this.instances.get(id).state.storage;
    const replacement = new GuardianRelationship(new MemoryDurableState(storage));
    this.instances.set(id, replacement);
    return replacement;
  }
}

function environment(founderMode = "true") {
  return { GUARDIAN_FOUNDER_MODE: founderMode, GUARDIAN_RELATIONSHIPS: new MemoryNamespace() };
}

async function keyPair() {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"]
  );
  return { ...pair, jwk: await crypto.subtle.exportKey("jwk", pair.publicKey) };
}

async function createRelationship(env, personKey) {
  personKey ??= await keyPair();
  const response = await handleGuardianRequest(new Request(`${origin}/v1/guardian-relationships`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      personPublicKeyJwk: personKey.jwk,
      personDisplayName: "Alex",
      senderConsentVersion: "guardian-sender-v1",
    }),
  }), env);
  return { response, body: await response.clone().json(), personKey };
}

async function redeemRelationship(env, created, guardianKey, overrides = {}) {
  guardianKey ??= await keyPair();
  const separator = created.body.inviteCode.indexOf(".");
  const inviteToken = created.body.inviteCode.slice(separator + 1);
  const response = await handleGuardianRequest(new Request(
    `${origin}/v1/guardian-relationships/${created.body.relationshipId}/redeem`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        inviteToken,
        guardianPublicKeyJwk: guardianKey.jwk,
        guardianConsentVersion: "guardian-recipient-v1",
        notificationDisclosureVersion: "notification-disclosure-v1",
        differentPersonAttestation: true,
        ...overrides,
      }),
    }
  ), env);
  return { response, body: await response.clone().json(), guardianKey };
}

async function signedRequest({
  path,
  method = "GET",
  body,
  relationshipId,
  capabilityId,
  privateKey,
  idempotencyKey = "",
  nonce = base64URL(crypto.getRandomValues(new Uint8Array(18))),
  timestamp = new Date().toISOString(),
}) {
  const bodyBytes = body == null ? new Uint8Array() : encoder.encode(JSON.stringify(body));
  const input = canonicalSignatureInput({
    method,
    path,
    bodyHash: await sha256Hex(bodyBytes),
    relationshipId,
    capabilityId,
    timestamp,
    nonce,
    idempotencyKey,
  });
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    encoder.encode(input)
  );
  const headers = {
    "sober-relationship-id": relationshipId,
    "sober-capability-id": capabilityId,
    "sober-timestamp": timestamp,
    "sober-nonce": nonce,
    "sober-signature": base64URL(signature),
  };
  if (body != null) headers["content-type"] = "application/json";
  if (idempotencyKey) headers["idempotency-key"] = idempotencyKey;
  return new Request(`${origin}${path}`, {
    method,
    headers,
    ...(body == null ? {} : { body: bodyBytes }),
  });
}

async function activeRelationship() {
  const env = environment();
  const created = await createRelationship(env);
  const redeemed = await redeemRelationship(env, created);
  assert.equal(created.response.status, 201);
  assert.equal(redeemed.response.status, 200);
  return { env, created, redeemed };
}

function consentBody(consentId, overrides = {}) {
  return {
    documentVersion: consentId,
    documentDigest: "a".repeat(64),
    locale: "en-US",
    appVersion: "1.1.0",
    ...overrides,
  };
}

async function putConsent({
  env,
  created,
  redeemed,
  consentId = "guardian-sender-v1",
  body = consentBody(consentId),
  idempotencyKey = crypto.randomUUID(),
  role = "person",
  relationshipId = created.body.relationshipId,
}) {
  const identity = role === "person" ? created.personKey : redeemed.guardianKey;
  const capabilityId = role === "person"
    ? created.body.personCapabilityId
    : redeemed.body.relationship.guardianCapabilityId;
  const path = `/v1/guardian-relationships/${relationshipId}/consents/${consentId}`;
  const response = await handleGuardianRequest(await signedRequest({
    path,
    method: "PUT",
    body,
    relationshipId,
    capabilityId,
    privateKey: identity.privateKey,
    idempotencyKey,
  }), env);
  return { response, body: response.status === 204 ? null : await response.clone().json(), idempotencyKey };
}

test("founder mode creates a pending relationship and one-time invite", async () => {
  const env = environment();
  const created = await createRelationship(env);
  assert.equal(created.response.status, 201);
  assert.equal(created.body.state, "pendingGuardian");
  assert.match(created.body.relationshipId, /^rel_/);
  assert.match(created.body.inviteCode, new RegExp(`^${created.body.relationshipId}\\.`));
  const state = await env.GUARDIAN_RELATIONSHIPS.instances.get(created.body.relationshipId).state.storage.get("state");
  assert.equal(JSON.stringify(state).includes(created.body.inviteCode), false);
});

test("relationship creation rejects a public key that is not a P-256 point", async () => {
  const env = environment();
  const response = await handleGuardianRequest(new Request(`${origin}/v1/guardian-relationships`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      personPublicKeyJwk: {
        kty: "EC", crv: "P-256",
        x: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        y: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      },
      personDisplayName: "Alex",
      senderConsentVersion: "guardian-sender-v1",
    }),
  }), env);

  assert.equal(response.status, 422);
  assert.equal(env.GUARDIAN_RELATIONSHIPS.instances.size, 0);
});

test("relationship creation stays closed outside the founder build", async () => {
  const created = await createRelationship(environment("false"));
  assert.equal(created.response.status, 404);
});

test("guardian redeems an invite exactly once with a different key", async () => {
  const env = environment();
  const created = await createRelationship(env);
  const first = await redeemRelationship(env, created);
  const replay = await redeemRelationship(env, created);
  assert.equal(first.response.status, 200);
  assert.equal(first.body.relationship.state, "active");
  assert.equal(replay.response.status, 404);

  const env2 = environment();
  const created2 = await createRelationship(env2);
  const sameKey = await redeemRelationship(env2, created2, created2.personKey);
  assert.equal(sameKey.response.status, 404);
});

test("guardian redemption rejects a public key that is not a P-256 point", async () => {
  const env = environment();
  const created = await createRelationship(env);
  const redeemed = await redeemRelationship(env, created, undefined, {
    guardianPublicKeyJwk: {
      kty: "EC", crv: "P-256",
      x: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      y: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    },
  });

  assert.equal(redeemed.response.status, 404);
  assert.equal(redeemed.body.error.code, "invalidInvite");
});

test("signed relationship reads are role-scoped and replay protected", async () => {
  const { env, created, redeemed } = await activeRelationship();
  const path = `/v1/guardian-relationships/${created.body.relationshipId}`;
  const nonce = base64URL(crypto.getRandomValues(new Uint8Array(18)));
  const request = await signedRequest({
    path,
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey,
    nonce,
  });
  const first = await handleGuardianRequest(request, env);
  const replay = await handleGuardianRequest(request.clone(), env);
  assert.equal(first.status, 200);
  assert.equal((await first.json()).relationship.role, "person");
  assert.equal(replay.status, 404);

  const guardianRead = await handleGuardianRequest(await signedRequest({
    path,
    relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey,
  }), env);
  assert.equal(guardianRead.status, 200);
  assert.equal((await guardianRead.json()).relationship.role, "guardian");
});

test("a role records and retrieves only its exact consent acceptance", async () => {
  const { env, created, redeemed } = await activeRelationship();
  const accepted = await putConsent({ env, created, redeemed });
  assert.equal(accepted.response.status, 200);
  assert.deepEqual(Object.keys(accepted.body.consent).sort(), [
    "acceptedAt", "appVersion", "consentId", "documentDigest", "documentVersion",
    "locale", "role", "withdrawnAt",
  ]);
  assert.equal(accepted.body.consent.consentId, "guardian-sender-v1");
  assert.equal(accepted.body.consent.role, "person");
  assert.equal(accepted.body.consent.withdrawnAt, null);

  const guardianAccepted = await putConsent({
    env,
    created,
    redeemed,
    consentId: "notification-disclosure-v1",
    role: "guardian",
  });
  assert.equal(guardianAccepted.response.status, 200);

  const path = `/v1/guardian-relationships/${created.body.relationshipId}`;
  const personRead = await handleGuardianRequest(await signedRequest({
    path,
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey,
  }), env);
  const personRelationship = (await personRead.json()).relationship;
  assert.deepEqual(personRelationship.consents.map((record) => record.consentId), [
    "guardian-sender-v1",
  ]);
  assert.equal(personRelationship.expiryWarning, null);

  const guardianRead = await handleGuardianRequest(await signedRequest({
    path,
    relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey,
  }), env);
  const guardianRelationship = (await guardianRead.json()).relationship;
  assert.deepEqual(guardianRelationship.consents.map((record) => record.consentId), [
    "notification-disclosure-v1",
  ]);
  assert.equal(guardianRelationship.guardianReachability, "unavailable");
});

test("consent authorization rejects the wrong role, capability, and relationship", async () => {
  const first = await activeRelationship();
  const wrongRole = await putConsent({
    ...first,
    consentId: "guardian-sender-v1",
    role: "guardian",
  });
  assert.equal(wrongRole.response.status, 404);

  const path = `/v1/guardian-relationships/${first.created.body.relationshipId}/consents/guardian-sender-v1`;
  const unknownCapability = await handleGuardianRequest(await signedRequest({
    path,
    method: "PUT",
    body: consentBody("guardian-sender-v1"),
    relationshipId: first.created.body.relationshipId,
    capabilityId: "rcap_not_this_relationship",
    privateKey: first.created.personKey.privateKey,
    idempotencyKey: crypto.randomUUID(),
  }), first.env);
  assert.equal(unknownCapability.status, 404);

  const secondCreated = await createRelationship(first.env);
  const secondRedeemed = await redeemRelationship(first.env, secondCreated);
  assert.equal(secondRedeemed.response.status, 200);
  const wrongRelationshipPath = `/v1/guardian-relationships/${secondCreated.body.relationshipId}/consents/guardian-sender-v1`;
  const wrongRelationship = await handleGuardianRequest(await signedRequest({
    path: wrongRelationshipPath,
    method: "PUT",
    body: consentBody("guardian-sender-v1"),
    relationshipId: first.created.body.relationshipId,
    capabilityId: first.created.body.personCapabilityId,
    privateKey: first.created.personKey.privateKey,
    idempotencyKey: crypto.randomUUID(),
  }), first.env);
  assert.equal(wrongRelationship.status, 404);
});

test("consent input is exact and malformed records never persist", async () => {
  const setup = await activeRelationship();
  const malformedBodies = [
    consentBody("guardian-sender-v1", { documentVersion: "guardian-sender-v2" }),
    consentBody("guardian-sender-v1", { documentDigest: "not-a-sha256-digest" }),
    consentBody("guardian-sender-v1", { locale: "en_US" }),
    consentBody("guardian-sender-v1", { appVersion: "1.1.0\u0085debug" }),
    { ...consentBody("guardian-sender-v1"), note: "free text is forbidden" },
  ];
  for (const body of malformedBodies) {
    const result = await putConsent({ ...setup, body });
    assert.equal(result.response.status, 422);
  }
  const missingIdempotency = await putConsent({ ...setup, idempotencyKey: "" });
  assert.equal(missingIdempotency.response.status, 422);
  const controlIdempotency = await putConsent({
    ...setup,
    idempotencyKey: "receipt\u0085injection",
  });
  assert.equal(controlIdempotency.response.status, 422);
  const unknownConsent = await putConsent({
    ...setup,
    consentId: "unreviewed-consent-v1",
    body: consentBody("unreviewed-consent-v1"),
  });
  assert.equal(unknownConsent.response.status, 404);

  const state = await setup.env.GUARDIAN_RELATIONSHIPS.instances
    .get(setup.created.body.relationshipId).state.storage.get("state");
  assert.deepEqual(state.consents, {});
});

test("consent acceptance is replay safe and detects idempotency conflicts", async () => {
  const setup = await activeRelationship();
  const idempotencyKey = crypto.randomUUID();
  const first = await putConsent({ ...setup, idempotencyKey });
  const replay = await putConsent({ ...setup, idempotencyKey });
  assert.equal(first.response.status, 200);
  assert.equal(replay.response.status, 200);
  assert.equal(replay.body.consent.acceptedAt, first.body.consent.acceptedAt);
  const persisted = await setup.env.GUARDIAN_RELATIONSHIPS.instances
    .get(setup.created.body.relationshipId).state.storage.get("state");
  assert.equal(JSON.stringify(persisted.consentIdempotency).includes(idempotencyKey), false);

  const changedReplay = await putConsent({
    ...setup,
    idempotencyKey,
    body: consentBody("guardian-sender-v1", { appVersion: "1.1.1" }),
  });
  assert.equal(changedReplay.response.status, 409);
  assert.equal(changedReplay.body.error.code, "idempotencyConflict");

  const changedAcceptance = await putConsent({
    ...setup,
    body: consentBody("guardian-sender-v1", { appVersion: "1.1.1" }),
  });
  assert.equal(changedAcceptance.response.status, 409);
  assert.equal(changedAcceptance.body.error.code, "consentConflict");
});

test("consent records survive a Durable Object reload", async () => {
  const setup = await activeRelationship();
  await putConsent(setup);
  setup.env.GUARDIAN_RELATIONSHIPS.reload(setup.created.body.relationshipId);

  const path = `/v1/guardian-relationships/${setup.created.body.relationshipId}`;
  const response = await handleGuardianRequest(await signedRequest({
    path,
    relationshipId: setup.created.body.relationshipId,
    capabilityId: setup.created.body.personCapabilityId,
    privateKey: setup.created.personKey.privateKey,
  }), setup.env);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).relationship.consents[0].consentId, "guardian-sender-v1");
});

test("revoked and expired relationships cannot add consent records", async () => {
  const revokedSetup = await activeRelationship();
  const revokedPath = `/v1/guardian-relationships/${revokedSetup.created.body.relationshipId}`;
  assert.equal((await handleGuardianRequest(await signedRequest({
    path: revokedPath,
    method: "DELETE",
    relationshipId: revokedSetup.created.body.relationshipId,
    capabilityId: revokedSetup.created.body.personCapabilityId,
    privateKey: revokedSetup.created.personKey.privateKey,
  }), revokedSetup.env)).status, 204);
  assert.equal((await putConsent(revokedSetup)).response.status, 404);

  const expiredSetup = await activeRelationship();
  const storage = expiredSetup.env.GUARDIAN_RELATIONSHIPS.instances
    .get(expiredSetup.created.body.relationshipId).state.storage;
  const state = await storage.get("state");
  state.expiresAt = new Date(Date.now() - 1).toISOString();
  await storage.put("state", state);
  assert.equal((await putConsent(expiredSetup)).response.status, 404);
  assert.equal((await storage.get("state")).relationshipState, "expired");
});

test("person creates only a minimal live concerning alert", async () => {
  const { env, created } = await activeRelationship();
  const eventId = crypto.randomUUID();
  const path = `/v1/guardian-relationships/${created.body.relationshipId}/alerts/${eventId}`;
  const body = {
    occurredAt: new Date().toISOString(),
    result: "SIGNALS_DETECTED",
    source: "liveCheck",
    messageTemplateVersion: "guardian-help-v1",
  };
  const response = await handleGuardianRequest(await signedRequest({
    path, method: "PUT", body, relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: eventId,
  }), env);
  assert.equal(response.status, 202);
  const result = await response.json();
  assert.equal(result.alert.personActionState, "requestingHelp");
  assert.equal(result.alert.canonicalEventId, eventId);

  const forbidden = { ...body, message: "client-controlled content" };
  const rejected = await handleGuardianRequest(await signedRequest({
    path: `${path.slice(0, -1)}0`, method: "PUT", body: forbidden,
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey,
    idempotencyKey: `${eventId.slice(0, -1)}0`,
  }), env);
  assert.equal(rejected.status, 422);
});

test("wrong role cannot create or acknowledge an alert", async () => {
  const { env, created, redeemed } = await activeRelationship();
  const eventId = crypto.randomUUID();
  const alertPath = `/v1/guardian-relationships/${created.body.relationshipId}/alerts/${eventId}`;
  const body = {
    occurredAt: new Date().toISOString(), result: "SIGNALS_DETECTED",
    source: "liveCheck", messageTemplateVersion: "guardian-help-v1",
  };
  const guardianCreate = await handleGuardianRequest(await signedRequest({
    path: alertPath, method: "PUT", body, relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey, idempotencyKey: eventId,
  }), env);
  assert.equal(guardianCreate.status, 404);

  const personCreate = await handleGuardianRequest(await signedRequest({
    path: alertPath, method: "PUT", body, relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: eventId,
  }), env);
  assert.equal(personCreate.status, 202);
  const ackPath = `${alertPath}/acknowledgment`;
  const personAck = await handleGuardianRequest(await signedRequest({
    path: ackPath, method: "PUT", body: { action: "helping" }, relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: eventId,
  }), env);
  assert.equal(personAck.status, 404);
});

test("guardian sees the pending alert and signed acknowledgment reaches the person", async () => {
  const { env, created, redeemed } = await activeRelationship();
  const eventId = crypto.randomUUID();
  const alertPath = `/v1/guardian-relationships/${created.body.relationshipId}/alerts/${eventId}`;
  const alertBody = {
    occurredAt: new Date().toISOString(), result: "SIGNALS_DETECTED",
    source: "liveCheck", messageTemplateVersion: "guardian-help-v1",
  };
  await handleGuardianRequest(await signedRequest({
    path: alertPath, method: "PUT", body: alertBody, relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: eventId,
  }), env);

  const relationshipPath = `/v1/guardian-relationships/${created.body.relationshipId}`;
  const guardianPoll = await handleGuardianRequest(await signedRequest({
    path: relationshipPath, relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey,
  }), env);
  assert.equal((await guardianPoll.json()).activeAlert.personActionState, "requestingHelp");

  const acknowledgment = await handleGuardianRequest(await signedRequest({
    path: `${alertPath}/acknowledgment`, method: "PUT", body: { action: "helping" },
    relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey, idempotencyKey: eventId,
  }), env);
  assert.equal(acknowledgment.status, 200);
  assert.equal((await acknowledgment.json()).alert.personActionState, "guardianConfirmed");

  const personPoll = await handleGuardianRequest(await signedRequest({
    path: alertPath, relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey,
  }), env);
  assert.equal((await personPoll.json()).alert.personActionState, "guardianConfirmed");
});

test("expired alerts, aliases, and the active pointer are pruned after 24 hours", async () => {
  const { env, created, redeemed } = await activeRelationship();
  const base = `/v1/guardian-relationships/${created.body.relationshipId}`;
  const body = {
    occurredAt: new Date().toISOString(), result: "SIGNALS_DETECTED",
    source: "liveCheck", messageTemplateVersion: "guardian-help-v1",
  };
  const canonicalEventId = crypto.randomUUID();
  await handleGuardianRequest(await signedRequest({
    path: `${base}/alerts/${canonicalEventId}`, method: "PUT", body,
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: canonicalEventId,
  }), env);

  const aliasEventId = crypto.randomUUID();
  await handleGuardianRequest(await signedRequest({
    path: `${base}/alerts/${aliasEventId}`, method: "PUT", body,
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: aliasEventId,
  }), env);

  const storage = env.GUARDIAN_RELATIONSHIPS.instances
    .get(created.body.relationshipId).state.storage;
  const state = await storage.get("state");
  for (const alert of Object.values(state.alerts)) {
    alert.expiresAt = new Date(Date.now() - 1_000).toISOString();
  }
  await storage.put("state", state);

  const guardianRead = await handleGuardianRequest(await signedRequest({
    path: base, relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey,
  }), env);
  assert.equal((await guardianRead.json()).activeAlert, null);

  const pruned = await storage.get("state");
  assert.deepEqual(pruned.alerts, {});
  assert.deepEqual(pruned.aliases, {});
  assert.equal(pruned.activeEventId, null);
});

test("alert idempotency survives separate handler calls", async () => {
  const { env, created } = await activeRelationship();
  const eventId = crypto.randomUUID();
  const path = `/v1/guardian-relationships/${created.body.relationshipId}/alerts/${eventId}`;
  const body = {
    occurredAt: new Date().toISOString(), result: "SIGNALS_DETECTED",
    source: "liveCheck", messageTemplateVersion: "guardian-help-v1",
  };
  const send = () => signedRequest({
    path, method: "PUT", body, relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: eventId,
  }).then((request) => handleGuardianRequest(request, env));
  assert.equal((await send()).status, 202);
  assert.equal((await send()).status, 200);
});

test("revocation is durable and blocks later alerts", async () => {
  const { env, created } = await activeRelationship();
  const relationshipPath = `/v1/guardian-relationships/${created.body.relationshipId}`;
  const revoked = await handleGuardianRequest(await signedRequest({
    path: relationshipPath, method: "DELETE", relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId, privateKey: created.personKey.privateKey,
  }), env);
  assert.equal(revoked.status, 204);

  const eventId = crypto.randomUUID();
  const body = {
    occurredAt: new Date().toISOString(), result: "SIGNALS_DETECTED",
    source: "liveCheck", messageTemplateVersion: "guardian-help-v1",
  };
  const blocked = await handleGuardianRequest(await signedRequest({
    path: `${relationshipPath}/alerts/${eventId}`, method: "PUT", body,
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId, privateKey: created.personKey.privateKey,
    idempotencyKey: eventId,
  }), env);
  assert.equal(blocked.status, 404);
});

test("activation schedules the relationship warning exactly fourteen days before expiry", async () => {
  const { env, created } = await activeRelationship();
  const storage = env.GUARDIAN_RELATIONSHIPS.instances
    .get(created.body.relationshipId).state.storage;
  const state = await storage.get("state");
  assert.equal(
    Date.parse(state.expiresAt) - Date.parse(state.activatedAt),
    relationshipLifetimeMilliseconds
  );
  assert.equal(
    await storage.getAlarm(),
    Date.parse(state.expiresAt) - relationshipWarningLeadMilliseconds
  );
});

test("alarm persistence failure leaves an invite retryable and inert", async () => {
  const env = environment();
  const created = await createRelationship(env);
  const storage = env.GUARDIAN_RELATIONSHIPS.instances
    .get(created.body.relationshipId).state.storage;
  const setAlarm = storage.setAlarm.bind(storage);
  storage.setAlarm = async () => { throw new Error("synthetic alarm write failure"); };
  await assert.rejects(() => redeemRelationship(env, created));
  assert.equal((await storage.get("state")).relationshipState, "pendingGuardian");

  storage.setAlarm = setAlarm;
  const retried = await redeemRelationship(env, created);
  assert.equal(retried.response.status, 200);
  assert.equal((await storage.get("state")).relationshipState, "active");
});

test("a stale lifecycle alarm is rescheduled from durable relationship state", async () => {
  const { env, created } = await activeRelationship();
  const storage = env.GUARDIAN_RELATIONSHIPS.instances
    .get(created.body.relationshipId).state.storage;
  const state = await storage.get("state");
  await storage.setAlarm(Date.now() + 1234);
  await handleRelationshipAlarm(storage, Date.parse(state.activatedAt) + 1000);
  assert.equal(
    await storage.getAlarm(),
    Date.parse(state.expiresAt) - relationshipWarningLeadMilliseconds
  );
});

test("an object first observed inside the warning window persists a visible warning", async () => {
  const { env, created, redeemed } = await activeRelationship();
  const storage = env.GUARDIAN_RELATIONSHIPS.instances
    .get(created.body.relationshipId).state.storage;
  const state = await storage.get("state");
  const observedAt = Date.now();
  state.expiresAt = new Date(observedAt + 7 * 24 * 60 * 60 * 1000).toISOString();
  state.expiryWarning = null;
  await storage.put("state", state);
  env.GUARDIAN_RELATIONSHIPS.reload(created.body.relationshipId);

  await handleRelationshipAlarm(storage, observedAt);
  const persisted = await storage.get("state");
  assert.equal(persisted.expiryWarning.state, "visible");
  assert.equal(await storage.getAlarm(), Date.parse(persisted.expiresAt));

  const path = `/v1/guardian-relationships/${created.body.relationshipId}`;
  const guardianRead = await handleGuardianRequest(await signedRequest({
    path,
    relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey,
  }), env);
  const warning = (await guardianRead.json()).relationship.expiryWarning;
  assert.deepEqual(Object.keys(warning).sort(), ["expiresAt", "startedAt", "state"]);
  assert.equal(warning.state, "visible");
});

test("persisting active state already inside fourteen days creates its warning immediately", async () => {
  const setup = await activeRelationship();
  const existingStorage = setup.env.GUARDIAN_RELATIONSHIPS.instances
    .get(setup.created.body.relationshipId).state.storage;
  const state = await existingStorage.get("state");
  const storage = new MemoryStorage();
  const createdAt = Date.now();
  state.expiresAt = new Date(createdAt + 7 * 24 * 60 * 60 * 1000).toISOString();
  state.expiryWarning = null;

  await persistRelationshipState(storage, state, createdAt);

  const persisted = await storage.get("state");
  assert.equal(persisted.expiryWarning.state, "visible");
  assert.equal(await storage.getAlarm(), Date.parse(persisted.expiresAt));
});

test("duplicate warning alarm delivery is idempotent and retains the expiry alarm", async () => {
  const { env, created } = await activeRelationship();
  const storage = env.GUARDIAN_RELATIONSHIPS.instances
    .get(created.body.relationshipId).state.storage;
  const state = await storage.get("state");
  const warningAt = Date.parse(state.expiresAt) - relationshipWarningLeadMilliseconds;
  await handleRelationshipAlarm(storage, warningAt);
  const first = await storage.get("state");
  await handleRelationshipAlarm(storage, warningAt + 5000);
  const duplicate = await storage.get("state");
  assert.equal(duplicate.expiryWarning.visibleAt, first.expiryWarning.visibleAt);
  assert.equal(await storage.getAlarm(), Date.parse(state.expiresAt));
});

test("the Durable Object alarm handler delegates to lifecycle reconciliation", async () => {
  const { env, created } = await activeRelationship();
  const instance = env.GUARDIAN_RELATIONSHIPS.instances.get(created.body.relationshipId);
  const state = await instance.state.storage.get("state");
  state.expiresAt = new Date(Date.now() - 1).toISOString();
  await instance.state.storage.put("state", state);
  await instance.alarm();
  assert.equal((await instance.state.storage.get("state")).relationshipState, "expired");
});

test("the expiry alarm commits expiry, withdraws consent, and removes live authority", async () => {
  const setup = await activeRelationship();
  await putConsent(setup);
  const storage = setup.env.GUARDIAN_RELATIONSHIPS.instances
    .get(setup.created.body.relationshipId).state.storage;
  const active = await storage.get("state");
  const expiresAt = Date.parse(active.expiresAt);
  await handleRelationshipAlarm(storage, expiresAt);

  const expired = await storage.get("state");
  assert.equal(expired.relationshipState, "expired");
  assert.equal(expired.expiryWarning.state, "expired");
  assert.equal(expired.personPublicKeyJwk, null);
  assert.equal(expired.guardianPublicKeyJwk, null);
  assert.equal(expired.consents["guardian-sender-v1"].withdrawnAt, expired.expiredAt);
  assert.equal(
    await storage.getAlarm(),
    Date.parse(expired.cleanupAt)
  );
});

test("revocation is replay-safe, cancels expiry warning work, and schedules cleanup", async () => {
  const setup = await activeRelationship();
  await putConsent(setup);
  const path = `/v1/guardian-relationships/${setup.created.body.relationshipId}`;
  const revoke = () => signedRequest({
    path,
    method: "DELETE",
    relationshipId: setup.created.body.relationshipId,
    capabilityId: setup.created.body.personCapabilityId,
    privateKey: setup.created.personKey.privateKey,
  }).then((request) => handleGuardianRequest(request, setup.env));
  assert.equal((await revoke()).status, 204);
  assert.equal((await revoke()).status, 204);

  const storage = setup.env.GUARDIAN_RELATIONSHIPS.instances
    .get(setup.created.body.relationshipId).state.storage;
  const revoked = await storage.get("state");
  assert.equal(revoked.relationshipState, "revoked");
  assert.equal(revoked.expiryWarning.state, "revoked");
  assert.equal(revoked.personDisplayName, "");
  assert.equal(revoked.consents["guardian-sender-v1"].withdrawnAt, revoked.revokedAt);
  assert.equal(await storage.getAlarm(), Date.parse(revoked.cleanupAt));
  assert.equal(
    Date.parse(revoked.cleanupAt) - Date.parse(revoked.revokedAt),
    inactiveAuditLifetimeMilliseconds
  );
});

test("inactive relationship cleanup deletes durable state and its alarm", async () => {
  const setup = await activeRelationship();
  const path = `/v1/guardian-relationships/${setup.created.body.relationshipId}`;
  await handleGuardianRequest(await signedRequest({
    path,
    method: "DELETE",
    relationshipId: setup.created.body.relationshipId,
    capabilityId: setup.created.body.personCapabilityId,
    privateKey: setup.created.personKey.privateKey,
  }), setup.env);
  const storage = setup.env.GUARDIAN_RELATIONSHIPS.instances
    .get(setup.created.body.relationshipId).state.storage;
  const revoked = await storage.get("state");
  await handleRelationshipAlarm(storage, Date.parse(revoked.cleanupAt));
  assert.equal(await storage.get("state"), undefined);
  assert.equal(await storage.getAlarm(), null);
  await handleRelationshipAlarm(storage, Date.parse(revoked.cleanupAt) + 1000);
  assert.equal(await storage.getAlarm(), null);
});

test("actNow is unreachable without a server-owned provider outcome", async () => {
  const setup = await activeRelationship();
  const eventId = crypto.randomUUID();
  const path = `/v1/guardian-relationships/${setup.created.body.relationshipId}/alerts/${eventId}`;
  const input = {
    occurredAt: new Date().toISOString(),
    result: "SIGNALS_DETECTED",
    source: "liveCheck",
    messageTemplateVersion: "guardian-help-v1",
    automaticDeliveryOutcome: "unknown",
  };
  const injection = await handleGuardianRequest(await signedRequest({
    path,
    method: "PUT",
    body: input,
    relationshipId: setup.created.body.relationshipId,
    capabilityId: setup.created.body.personCapabilityId,
    privateKey: setup.created.personKey.privateKey,
    idempotencyKey: eventId,
  }), setup.env);
  assert.equal(injection.status, 422);

  delete input.automaticDeliveryOutcome;
  const created = await handleGuardianRequest(await signedRequest({
    path,
    method: "PUT",
    body: input,
    relationshipId: setup.created.body.relationshipId,
    capabilityId: setup.created.body.personCapabilityId,
    privateKey: setup.created.personKey.privateKey,
    idempotencyKey: eventId,
  }), setup.env);
  assert.equal((await created.json()).alert.personActionState, "requestingHelp");
  const state = await setup.env.GUARDIAN_RELATIONSHIPS.instances
    .get(setup.created.body.relationshipId).state.storage.get("state");
  assert.equal(JSON.stringify(state).includes("actNow"), false);
});

test("legacy shared-token route is removed from the compiled handler", async () => {
  const response = await handleGuardianRequest(new Request(`${origin}/v1/alerts`, {
    method: "POST",
    headers: { authorization: "Bearer legacy", "content-type": "application/json" },
    body: JSON.stringify({ message: "arbitrary" }),
  }), environment());
  assert.equal(response.status, 410);
  assert.equal((await response.json()).error.code, "legacyRouteRemoved");
});

test("guardian proposes a daily check-in but cannot activate it", async () => {
  const { env, created, redeemed } = await activeRelationship();
  const proposalId = crypto.randomUUID();
  const path = `/v1/guardian-relationships/${created.body.relationshipId}/check-in-plan/proposal`;
  const body = {
    proposalId,
    cadence: "daily",
    localTime: "22:30",
    timeZoneIdentifier: "America/Chicago",
    condition: "awayFromHome",
    graceMinutes: 15,
    proposalConsentVersion: "guardian-check-in-proposer-v1",
  };
  const response = await handleGuardianRequest(await signedRequest({
    path, method: "PUT", body, relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey, idempotencyKey: proposalId,
  }), env);
  assert.equal(response.status, 202);
  const plan = (await response.json()).checkInPlan;
  assert.equal(plan.state, "pendingPersonConsent");
  assert.equal(plan.condition, "awayFromHome");
  assert.equal(JSON.stringify(plan).includes("latitude"), false);

  const guardianDecision = await handleGuardianRequest(await signedRequest({
    path: path.replace("proposal", "decision"), method: "PUT",
    body: { version: plan.version, decision: "accept", participantConsentVersion: "guardian-check-in-participant-v1" },
    relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey,
  }), env);
  assert.equal(guardianDecision.status, 404);
});

test("person explicitly accepts and can later withdraw from a check-in plan", async () => {
  const { env, created, redeemed } = await activeRelationship();
  const proposalId = crypto.randomUUID();
  const proposalPath = `/v1/guardian-relationships/${created.body.relationshipId}/check-in-plan/proposal`;
  const proposal = {
    proposalId, cadence: "daily", localTime: "21:15", timeZoneIdentifier: "America/Chicago",
    condition: "always", graceMinutes: 10,
    proposalConsentVersion: "guardian-check-in-proposer-v1",
  };
  const proposed = await handleGuardianRequest(await signedRequest({
    path: proposalPath, method: "PUT", body: proposal, relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey, idempotencyKey: proposalId,
  }), env);
  const version = (await proposed.json()).checkInPlan.version;
  const decisionPath = proposalPath.replace("proposal", "decision");
  const accepted = await handleGuardianRequest(await signedRequest({
    path: decisionPath, method: "PUT",
    body: { version, decision: "accept", participantConsentVersion: "guardian-check-in-participant-v1" },
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId, privateKey: created.personKey.privateKey,
  }), env);
  assert.equal(accepted.status, 200);
  assert.equal((await accepted.json()).checkInPlan.state, "active");

  const withdrawn = await handleGuardianRequest(await signedRequest({
    path: decisionPath, method: "PUT",
    body: { version, decision: "decline", participantConsentVersion: "guardian-check-in-participant-v1" },
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId, privateKey: created.personKey.privateKey,
  }), env);
  assert.equal(withdrawn.status, 200);
  assert.equal((await withdrawn.json()).checkInPlan.state, "declined");
});

test("only the person can record completion and no result is stored", async () => {
  const { env, created, redeemed } = await activeRelationship();
  const proposalId = crypto.randomUUID();
  const base = `/v1/guardian-relationships/${created.body.relationshipId}`;
  const proposal = {
    proposalId, cadence: "daily", localTime: "20:00", timeZoneIdentifier: "America/Chicago",
    condition: "always", graceMinutes: 15,
    proposalConsentVersion: "guardian-check-in-proposer-v1",
  };
  const proposed = await handleGuardianRequest(await signedRequest({
    path: `${base}/check-in-plan/proposal`, method: "PUT", body: proposal,
    relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey, idempotencyKey: proposalId,
  }), env);
  const version = (await proposed.json()).checkInPlan.version;
  await handleGuardianRequest(await signedRequest({
    path: `${base}/check-in-plan/decision`, method: "PUT",
    body: { version, decision: "accept", participantConsentVersion: "guardian-check-in-participant-v1" },
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId, privateKey: created.personKey.privateKey,
  }), env);

  const occurrenceId = `plan${version}-20260805-2000`;
  const completionBody = { status: "completed", completedAt: "2026-08-06T01:04:00.000Z" };
  const completionPath = `${base}/check-ins/${occurrenceId}/completion`;
  const guardianAttempt = await handleGuardianRequest(await signedRequest({
    path: completionPath, method: "PUT", body: completionBody,
    relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey, idempotencyKey: occurrenceId,
  }), env);
  assert.equal(guardianAttempt.status, 404);

  const completed = await handleGuardianRequest(await signedRequest({
    path: completionPath, method: "PUT", body: completionBody,
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId, privateKey: created.personKey.privateKey,
    idempotencyKey: occurrenceId,
  }), env);
  const plan = (await completed.json()).checkInPlan;
  assert.equal(plan.lastCompletion.occurrenceId, occurrenceId);
  assert.deepEqual(Object.keys(plan.lastCompletion).sort(), ["completedAt", "occurrenceId"]);
});

test("invalid timezone and location-bearing proposal fields are rejected", async () => {
  const { env, created, redeemed } = await activeRelationship();
  const proposalId = crypto.randomUUID();
  const path = `/v1/guardian-relationships/${created.body.relationshipId}/check-in-plan/proposal`;
  const body = {
    proposalId, cadence: "daily", localTime: "22:30", timeZoneIdentifier: "Not/AZone",
    condition: "awayFromHome", graceMinutes: 15, latitude: 41.8,
    proposalConsentVersion: "guardian-check-in-proposer-v1",
  };
  const response = await handleGuardianRequest(await signedRequest({
    path, method: "PUT", body, relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey, idempotencyKey: proposalId,
  }), env);
  assert.equal(response.status, 422);
});

test("only the person can enable Circle location sharing", async () => {
  const { env, created, redeemed } = await activeRelationship();
  const base = `/v1/guardian-relationships/${created.body.relationshipId}`;
  const decisionId = crypto.randomUUID();
  const body = {
    decisionId,
    enabled: true,
    participantConsentVersion: "circle-location-participant-v1",
  };

  const guardianAttempt = await handleGuardianRequest(await signedRequest({
    path: `${base}/location-sharing`, method: "PUT", body,
    relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey, idempotencyKey: decisionId,
  }), env);
  assert.equal(guardianAttempt.status, 404);

  const enabled = await handleGuardianRequest(await signedRequest({
    path: `${base}/location-sharing`, method: "PUT", body,
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: decisionId,
  }), env);
  assert.equal(enabled.status, 200);
  const sharing = (await enabled.json()).locationSharing;
  assert.equal(sharing.enabled, true);
  assert.equal(typeof sharing.updatedAt, "string");
  assert.equal(sharing.latestLocation, null);
});

test("person publishes only a latest precise location and guardian can read it", async () => {
  const { env, created, redeemed } = await activeRelationship();
  const base = `/v1/guardian-relationships/${created.body.relationshipId}`;
  const decisionId = crypto.randomUUID();
  const sharingBody = {
    decisionId, enabled: true,
    participantConsentVersion: "circle-location-participant-v1",
  };
  await handleGuardianRequest(await signedRequest({
    path: `${base}/location-sharing`, method: "PUT", body: sharingBody,
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: decisionId,
  }), env);

  const sampleId = crypto.randomUUID();
  const sample = {
    sampleId,
    capturedAt: new Date().toISOString(),
    latitude: 41.8781,
    longitude: -87.6298,
    horizontalAccuracyMeters: 12.5,
    source: "coreLocation",
  };
  const published = await handleGuardianRequest(await signedRequest({
    path: `${base}/locations/${sampleId}`, method: "PUT", body: sample,
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: sampleId,
  }), env);
  assert.equal(published.status, 202);

  const olderSampleId = crypto.randomUUID();
  const older = await handleGuardianRequest(await signedRequest({
    path: `${base}/locations/${olderSampleId}`, method: "PUT",
    body: {
      sampleId: olderSampleId,
      capturedAt: new Date(Date.now() - 60_000).toISOString(),
      latitude: 39.7392,
      longitude: -104.9903,
      horizontalAccuracyMeters: 9,
      source: "coreLocation",
    },
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: olderSampleId,
  }), env);
  assert.equal(older.status, 200);

  const guardianRead = await handleGuardianRequest(await signedRequest({
    path: base, relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey,
  }), env);
  const sharing = (await guardianRead.json()).locationSharing;
  assert.equal(sharing.enabled, true);
  assert.deepEqual(Object.keys(sharing.latestLocation).sort(), [
    "capturedAt", "horizontalAccuracyMeters", "latitude", "longitude",
  ]);
  assert.equal(sharing.latestLocation.latitude, sample.latitude);
  assert.equal(JSON.stringify(sharing).includes(sampleId), false);
});

test("stopping Circle sharing immediately removes the visible location", async () => {
  const { env, created } = await activeRelationship();
  const base = `/v1/guardian-relationships/${created.body.relationshipId}`;
  const enableId = crypto.randomUUID();
  await handleGuardianRequest(await signedRequest({
    path: `${base}/location-sharing`, method: "PUT",
    body: {
      decisionId: enableId, enabled: true,
      participantConsentVersion: "circle-location-participant-v1",
    },
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: enableId,
  }), env);
  const sampleId = crypto.randomUUID();
  await handleGuardianRequest(await signedRequest({
    path: `${base}/locations/${sampleId}`, method: "PUT",
    body: {
      sampleId, capturedAt: new Date().toISOString(), latitude: 34.0522,
      longitude: -118.2437, horizontalAccuracyMeters: 18, source: "coreLocation",
    },
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: sampleId,
  }), env);

  const disableId = crypto.randomUUID();
  const stopped = await handleGuardianRequest(await signedRequest({
    path: `${base}/location-sharing`, method: "PUT",
    body: {
      decisionId: disableId, enabled: false,
      participantConsentVersion: "circle-location-participant-v1",
    },
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: disableId,
  }), env);
  const sharing = (await stopped.json()).locationSharing;
  assert.equal(sharing.enabled, false);
  assert.equal(sharing.latestLocation, null);
});

test("Circle location rejects extra fields and invalid coordinates", async () => {
  const { env, created } = await activeRelationship();
  const base = `/v1/guardian-relationships/${created.body.relationshipId}`;
  const decisionId = crypto.randomUUID();
  await handleGuardianRequest(await signedRequest({
    path: `${base}/location-sharing`, method: "PUT",
    body: {
      decisionId, enabled: true,
      participantConsentVersion: "circle-location-participant-v1",
    },
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: decisionId,
  }), env);

  const sampleId = crypto.randomUUID();
  const rejected = await handleGuardianRequest(await signedRequest({
    path: `${base}/locations/${sampleId}`, method: "PUT",
    body: {
      sampleId, capturedAt: new Date().toISOString(), latitude: 120,
      longitude: -87.6, horizontalAccuracyMeters: 8, source: "coreLocation",
      speed: 72,
    },
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: sampleId,
  }), env);
  assert.equal(rejected.status, 422);
});

test("Circle location is pruned after the 24-hour retention window", async () => {
  const { env, created, redeemed } = await activeRelationship();
  const base = `/v1/guardian-relationships/${created.body.relationshipId}`;
  const decisionId = crypto.randomUUID();
  await handleGuardianRequest(await signedRequest({
    path: `${base}/location-sharing`, method: "PUT",
    body: {
      decisionId, enabled: true,
      participantConsentVersion: "circle-location-participant-v1",
    },
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: decisionId,
  }), env);
  const sampleId = crypto.randomUUID();
  await handleGuardianRequest(await signedRequest({
    path: `${base}/locations/${sampleId}`, method: "PUT",
    body: {
      sampleId, capturedAt: new Date().toISOString(), latitude: 40.7128,
      longitude: -74.0060, horizontalAccuracyMeters: 22, source: "coreLocation",
    },
    relationshipId: created.body.relationshipId,
    capabilityId: created.body.personCapabilityId,
    privateKey: created.personKey.privateKey, idempotencyKey: sampleId,
  }), env);

  const storage = env.GUARDIAN_RELATIONSHIPS.instances
    .get(created.body.relationshipId).state.storage;
  const state = await storage.get("state");
  state.locationSharing.latestLocation.capturedAt = new Date(
    Date.now() - 25 * 60 * 60 * 1000
  ).toISOString();
  await storage.put("state", state);

  const guardianRead = await handleGuardianRequest(await signedRequest({
    path: base, relationshipId: created.body.relationshipId,
    capabilityId: redeemed.body.relationship.guardianCapabilityId,
    privateKey: redeemed.guardianKey.privateKey,
  }), env);
  assert.equal((await guardianRead.json()).locationSharing.latestLocation, null);
  assert.equal((await storage.get("state")).locationSharing.latestLocation, null);
});
