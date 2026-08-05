import { sha256Base64URL, verifyCapabilitySignature, validP256Jwk } from "./guardian-crypto.js";

const relationshipLifetimeMilliseconds = 90 * 24 * 60 * 60 * 1000;
const alertLifetimeMilliseconds = 24 * 60 * 60 * 1000;
const nonceLifetimeMilliseconds = 10 * 60 * 1000;
const allowedAlertFields = new Set(["occurredAt", "result", "source", "messageTemplateVersion"]);

export async function handleRelationshipRequest(storage, request) {
  const url = new URL(request.url);
  const path = url.pathname;
  const current = await storage.get("state");

  if (path.endsWith("/internal/create") && request.method === "POST") {
    if (current) return error(409, "stateConflict");
    const input = await jsonBody(request);
    if (!input.ok || !validCreateBody(input.value)) return error(422, "invalidRequest");
    const now = new Date();
    const state = {
      relationshipId: input.value.relationshipId,
      relationshipState: "pendingGuardian",
      personDisplayName: input.value.personDisplayName.trim(),
      personPublicKeyJwk: input.value.personPublicKeyJwk,
      personCapabilityId: input.value.personCapabilityId,
      guardianPublicKeyJwk: null,
      guardianCapabilityId: null,
      inviteTokenHash: await sha256Base64URL(input.value.inviteToken),
      inviteExpiresAt: input.value.inviteExpiresAt,
      createdAt: now.toISOString(),
      activatedAt: null,
      expiresAt: new Date(now.getTime() + relationshipLifetimeMilliseconds).toISOString(),
      revokedAt: null,
      nonces: {},
      alerts: {},
      aliases: {},
      activeEventId: null,
    };
    await storage.put("state", state);
    return json({
      relationshipId: state.relationshipId,
      personCapabilityId: state.personCapabilityId,
      state: state.relationshipState,
      inviteCode: `${state.relationshipId}.${input.value.inviteToken}`,
      inviteExpiresAt: state.inviteExpiresAt,
    }, 201);
  }

  if (!current) return error(404, "notFound");

  if (path.endsWith("/redeem") && request.method === "POST") {
    const input = await jsonBody(request);
    if (!input.ok || !validRedeemBody(input.value)) return error(404, "invalidInvite");
    const tokenHash = await sha256Base64URL(input.value.inviteToken);
    const sameKey = input.value.guardianPublicKeyJwk.x === current.personPublicKeyJwk.x
      && input.value.guardianPublicKeyJwk.y === current.personPublicKeyJwk.y;
    if (
      current.relationshipState !== "pendingGuardian"
      || current.inviteTokenHash !== tokenHash
      || Date.parse(current.inviteExpiresAt) <= Date.now()
      || sameKey
    ) return error(404, "invalidInvite");

    current.relationshipState = "active";
    current.guardianPublicKeyJwk = input.value.guardianPublicKeyJwk;
    current.guardianCapabilityId = input.value.guardianCapabilityId;
    current.inviteTokenHash = null;
    current.activatedAt = new Date().toISOString();
    await storage.put("state", current);
    return json({ relationship: relationshipView(current, "guardian") }, 200);
  }

  if (Date.parse(current.expiresAt) <= Date.now()) {
    current.relationshipState = "expired";
    current.inviteTokenHash = null;
    await storage.put("state", current);
    return error(404, "notFound");
  }

  const authentication = await verifyCapabilitySignature(request, current, expectedRole(path, request.method));
  if (!authentication.ok || current.relationshipState === "revoked") return error(404, "notFound");
  pruneNonces(current);
  current.nonces[authentication.nonce] = authentication.signedAt;
  // Persist replay protection before any later shape/state rejection. A valid
  // signed mutation cannot be replayed just because its first body was bad.
  await storage.put("state", current);

  const alertMatch = path.match(/\/alerts\/([0-9a-f-]{36})(?:\/(acknowledgment))?$/);

  if (request.method === "GET" && path.endsWith(`/${current.relationshipId}`)) {
    await storage.put("state", current);
    const activeAlert = current.activeEventId
      ? alertView(resolveAlert(current, current.activeEventId), current.activeEventId)
      : null;
    return json({
      relationship: relationshipView(current, authentication.role),
      activeAlert,
    });
  }

  if (request.method === "DELETE" && path.endsWith(`/${current.relationshipId}`)) {
    current.relationshipState = "revoked";
    current.revokedAt = new Date().toISOString();
    current.inviteTokenHash = null;
    await storage.put("state", current);
    return new Response(null, { status: 204, headers: responseHeaders() });
  }

  if (alertMatch && request.method === "PUT" && !alertMatch[2]) {
    const eventId = alertMatch[1];
    const input = await jsonBody(request);
    if (!input.ok || !validAlertBody(input.value) || request.headers.get("idempotency-key") !== eventId) {
      return error(422, "invalidRequest");
    }
    const fingerprint = await sha256Base64URL(JSON.stringify(input.value));
    const existing = current.alerts[eventId];
    if (existing) {
      if (existing.fingerprint !== fingerprint) return error(409, "idempotencyConflict");
      await storage.put("state", current);
      return json({ alert: alertView(existing, eventId) }, 200);
    }
    if (current.relationshipState !== "active") return error(409, "relationshipNotActive");

    const active = current.activeEventId ? current.alerts[current.activeEventId] : null;
    if (active && active.personActionState === "requestingHelp"
      && Date.now() - Date.parse(active.createdAt) < 10 * 60 * 1000) {
      current.aliases[eventId] = current.activeEventId;
      current.alerts[eventId] = { ...active, requestedEventId: eventId, canonicalEventId: current.activeEventId, fingerprint };
      await storage.put("state", current);
      return json({ alert: alertView(current.alerts[eventId], eventId) }, 200);
    }

    const now = new Date();
    const alert = {
      requestedEventId: eventId,
      canonicalEventId: eventId,
      fingerprint,
      workflowState: "reserved",
      personActionState: "requestingHelp",
      version: 1,
      createdAt: now.toISOString(),
      updatedAt: now.toISOString(),
      expiresAt: new Date(now.getTime() + alertLifetimeMilliseconds).toISOString(),
      acknowledgedAt: null,
    };
    current.alerts[eventId] = alert;
    current.activeEventId = eventId;
    await storage.put("state", current);
    return json({ alert: alertView(alert, eventId) }, 202);
  }

  if (alertMatch && request.method === "GET" && !alertMatch[2]) {
    const alert = resolveAlert(current, alertMatch[1]);
    await storage.put("state", current);
    return alert ? json({ alert: alertView(alert, alertMatch[1]) }) : error(404, "notFound");
  }

  if (alertMatch?.[2] === "acknowledgment" && request.method === "PUT") {
    const input = await jsonBody(request);
    const eventId = alertMatch[1];
    const alert = current.alerts[eventId];
    if (!input.ok || Object.keys(input.value).length !== 1 || input.value.action !== "helping"
      || !alert || alert.canonicalEventId !== eventId) return error(404, "notFound");
    if (!alert.acknowledgedAt) {
      const now = new Date().toISOString();
      alert.acknowledgedAt = now;
      alert.updatedAt = now;
      alert.version += 1;
      alert.workflowState = "guardianAcknowledged";
      alert.personActionState = "guardianConfirmed";
    }
    await storage.put("state", current);
    return json({ alert: alertView(alert, eventId) });
  }

  return error(404, "notFound");
}

function expectedRole(path, method) {
  if (method === "PUT" && /\/alerts\/[0-9a-f-]{36}$/.test(path)) return "person";
  if (method === "PUT" && path.endsWith("/acknowledgment")) return "guardian";
  return null;
}

function relationshipView(state, role) {
  return {
    relationshipId: state.relationshipId,
    state: state.relationshipState,
    role,
    personDisplayName: state.personDisplayName,
    activatedAt: state.activatedAt,
    expiresAt: state.expiresAt,
    guardianReachability: state.relationshipState === "active" ? "inApp" : "unavailable",
    ...(role === "guardian" ? { guardianCapabilityId: state.guardianCapabilityId } : {}),
  };
}

function alertView(alert, requestedEventId) {
  if (!alert) return null;
  return {
    requestedEventId,
    canonicalEventId: alert.canonicalEventId,
    workflowState: alert.workflowState,
    personActionState: alert.personActionState,
    version: alert.version,
    createdAt: alert.createdAt,
    updatedAt: alert.updatedAt,
    expiresAt: alert.expiresAt,
    guardian: { acknowledgedAt: alert.acknowledgedAt },
    nextPollAfterMilliseconds: 2000,
  };
}

function resolveAlert(state, eventId) {
  const canonical = state.aliases[eventId] ?? eventId;
  return state.alerts[canonical] ?? state.alerts[eventId] ?? null;
}

function validCreateBody(value) {
  return value
    && typeof value.relationshipId === "string"
    && typeof value.personCapabilityId === "string"
    && typeof value.inviteToken === "string"
    && typeof value.inviteExpiresAt === "string"
    && typeof value.personDisplayName === "string"
    && value.personDisplayName.trim().length > 0
    && [...value.personDisplayName.trim()].length <= 80
    && validP256Jwk(value.personPublicKeyJwk);
}

function validRedeemBody(value) {
  return value
    && Object.keys(value).every((key) => [
      "inviteToken", "guardianPublicKeyJwk", "guardianCapabilityId",
      "guardianConsentVersion", "notificationDisclosureVersion", "differentPersonAttestation",
    ].includes(key))
    && typeof value.inviteToken === "string"
    && typeof value.guardianCapabilityId === "string"
    && value.guardianConsentVersion === "guardian-recipient-v1"
    && value.notificationDisclosureVersion === "notification-disclosure-v1"
    && value.differentPersonAttestation === true
    && validP256Jwk(value.guardianPublicKeyJwk);
}

function validAlertBody(value) {
  return value
    && Object.keys(value).length === allowedAlertFields.size
    && Object.keys(value).every((key) => allowedAlertFields.has(key))
    && value.result === "SIGNALS_DETECTED"
    && value.source === "liveCheck"
    && value.messageTemplateVersion === "guardian-help-v1"
    && Number.isFinite(Date.parse(value.occurredAt));
}

async function jsonBody(request) {
  try {
    const value = await request.json();
    return value && typeof value === "object" && !Array.isArray(value)
      ? { ok: true, value }
      : { ok: false };
  } catch {
    return { ok: false };
  }
}

function pruneNonces(state) {
  state.nonces ??= {};
  for (const [nonce, createdAt] of Object.entries(state.nonces)) {
    if (Date.now() - createdAt > nonceLifetimeMilliseconds) delete state.nonces[nonce];
  }
}

function responseHeaders() {
  return { "cache-control": "no-store", "content-type": "application/json; charset=utf-8" };
}

function json(value, status = 200) {
  return new Response(JSON.stringify({ ...value, requestId: `req_${crypto.randomUUID()}` }), {
    status,
    headers: responseHeaders(),
  });
}

function error(status, code) {
  return json({ error: { code, message: "The request could not be completed.", retryable: status >= 500 } }, status);
}
