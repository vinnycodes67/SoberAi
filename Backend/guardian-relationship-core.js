import { sha256Base64URL, verifyCapabilitySignature, validP256Jwk } from "./guardian-crypto.js";

const relationshipLifetimeMilliseconds = 90 * 24 * 60 * 60 * 1000;
const alertLifetimeMilliseconds = 24 * 60 * 60 * 1000;
const nonceLifetimeMilliseconds = 10 * 60 * 1000;
const allowedAlertFields = new Set(["occurredAt", "result", "source", "messageTemplateVersion"]);
const allowedCheckInProposalFields = new Set([
  "proposalId", "cadence", "localTime", "timeZoneIdentifier", "condition", "graceMinutes",
  "proposalConsentVersion",
]);
const allowedLocationSharingFields = new Set([
  "decisionId", "enabled", "participantConsentVersion",
]);
const allowedLocationSampleFields = new Set([
  "sampleId", "capturedAt", "latitude", "longitude", "horizontalAccuracyMeters", "source",
]);
const locationRetentionMilliseconds = 24 * 60 * 60 * 1000;

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
      checkInPlan: null,
      locationSharing: null,
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
  pruneExpiredAlerts(current);
  pruneStaleLocation(current);
  current.nonces[authentication.nonce] = authentication.signedAt;
  // Persist replay protection before any later shape/state rejection. A valid
  // signed mutation cannot be replayed just because its first body was bad.
  await storage.put("state", current);

  const alertMatch = path.match(/\/alerts\/([0-9a-f-]{36})(?:\/(acknowledgment))?$/);
  const completionMatch = path.match(/\/check-ins\/(plan[0-9]+-[0-9]{8}-[0-9]{4})\/completion$/);
  const locationMatch = path.match(/\/locations\/([0-9a-f-]{36})$/);

  if (request.method === "GET" && path.endsWith(`/${current.relationshipId}`)) {
    await storage.put("state", current);
    const activeAlert = current.activeEventId
      ? alertView(resolveAlert(current, current.activeEventId), current.activeEventId)
      : null;
    return json({
      relationship: relationshipView(current, authentication.role),
      activeAlert,
      checkInPlan: checkInPlanView(current.checkInPlan),
      locationSharing: locationSharingView(current),
    });
  }

  if (request.method === "DELETE" && path.endsWith(`/${current.relationshipId}`)) {
    current.relationshipState = "revoked";
    current.revokedAt = new Date().toISOString();
    current.inviteTokenHash = null;
    await storage.put("state", current);
    return new Response(null, { status: 204, headers: responseHeaders() });
  }

  if (request.method === "PUT" && path.endsWith("/check-in-plan/proposal")) {
    const input = await jsonBody(request);
    if (!input.ok || !validCheckInProposalBody(input.value)
      || request.headers.get("idempotency-key") !== input.value.proposalId) {
      return error(422, "invalidRequest");
    }
    if (current.relationshipState !== "active") return error(409, "relationshipNotActive");

    const fingerprint = await sha256Base64URL(JSON.stringify(input.value));
    if (current.checkInPlan?.proposalId === input.value.proposalId) {
      if (current.checkInPlan.fingerprint !== fingerprint) return error(409, "idempotencyConflict");
      return json({ checkInPlan: checkInPlanView(current.checkInPlan) });
    }

    const now = new Date().toISOString();
    current.checkInPlan = {
      proposalId: input.value.proposalId,
      fingerprint,
      version: (current.checkInPlan?.version ?? 0) + 1,
      state: "pendingPersonConsent",
      cadence: input.value.cadence,
      localTime: input.value.localTime,
      timeZoneIdentifier: input.value.timeZoneIdentifier,
      condition: input.value.condition,
      graceMinutes: input.value.graceMinutes,
      proposalConsentVersion: input.value.proposalConsentVersion,
      participantConsentVersion: null,
      proposedAt: now,
      decidedAt: null,
      lastCompletion: current.checkInPlan?.lastCompletion ?? null,
    };
    await storage.put("state", current);
    return json({ checkInPlan: checkInPlanView(current.checkInPlan) }, 202);
  }

  if (request.method === "PUT" && path.endsWith("/location-sharing")) {
    const input = await jsonBody(request);
    if (!input.ok || !validLocationSharingBody(input.value)
      || request.headers.get("idempotency-key") !== input.value.decisionId) {
      return error(422, "invalidRequest");
    }
    if (current.relationshipState !== "active") return error(409, "relationshipNotActive");

    const fingerprint = await sha256Base64URL(JSON.stringify(input.value));
    if (current.locationSharing?.lastDecisionId === input.value.decisionId) {
      if (current.locationSharing.lastDecisionFingerprint !== fingerprint) {
        return error(409, "idempotencyConflict");
      }
      return json({ locationSharing: locationSharingView(current) });
    }

    const now = new Date().toISOString();
    current.locationSharing = {
      enabled: input.value.enabled,
      participantConsentVersion: input.value.participantConsentVersion,
      updatedAt: now,
      latestLocation: input.value.enabled ? current.locationSharing?.latestLocation ?? null : null,
      lastDecisionId: input.value.decisionId,
      lastDecisionFingerprint: fingerprint,
    };
    await storage.put("state", current);
    return json({ locationSharing: locationSharingView(current) });
  }

  if (locationMatch && request.method === "PUT") {
    const sampleId = locationMatch[1];
    const input = await jsonBody(request);
    if (!input.ok || !validLocationSampleBody(input.value)
      || input.value.sampleId !== sampleId
      || request.headers.get("idempotency-key") !== sampleId) {
      return error(422, "invalidRequest");
    }
    if (current.relationshipState !== "active" || !current.locationSharing?.enabled) {
      return error(409, "locationSharingNotActive");
    }

    const fingerprint = await sha256Base64URL(JSON.stringify(input.value));
    if (current.locationSharing.latestLocation?.sampleId === sampleId) {
      if (current.locationSharing.latestLocation.fingerprint !== fingerprint) {
        return error(409, "idempotencyConflict");
      }
      return json({ locationSharing: locationSharingView(current) });
    }
    if (current.locationSharing.latestLocation
      && Date.parse(input.value.capturedAt)
        <= Date.parse(current.locationSharing.latestLocation.capturedAt)) {
      return json({ locationSharing: locationSharingView(current) });
    }

    current.locationSharing.latestLocation = {
      ...input.value,
      fingerprint,
      receivedAt: new Date().toISOString(),
    };
    await storage.put("state", current);
    return json({ locationSharing: locationSharingView(current) }, 202);
  }

  if (request.method === "PUT" && path.endsWith("/check-in-plan/decision")) {
    const input = await jsonBody(request);
    if (!input.ok || !validCheckInDecisionBody(input.value)) return error(422, "invalidRequest");
    const isPendingDecision = current.checkInPlan?.state === "pendingPersonConsent";
    const isActiveWithdrawal = current.checkInPlan?.state === "active" && input.value.decision === "decline";
    if (!current.checkInPlan || current.checkInPlan.version !== input.value.version
      || (!isPendingDecision && !isActiveWithdrawal)) {
      return error(409, "planNotPending");
    }
    current.checkInPlan.state = input.value.decision === "accept" ? "active" : "declined";
    current.checkInPlan.participantConsentVersion = input.value.participantConsentVersion;
    current.checkInPlan.decidedAt = new Date().toISOString();
    await storage.put("state", current);
    return json({ checkInPlan: checkInPlanView(current.checkInPlan) });
  }

  if (completionMatch && request.method === "PUT") {
    const occurrenceId = completionMatch[1];
    const input = await jsonBody(request);
    if (!input.ok || !validCheckInCompletionBody(input.value)
      || request.headers.get("idempotency-key") !== occurrenceId) {
      return error(422, "invalidRequest");
    }
    if (!current.checkInPlan || current.checkInPlan.state !== "active"
      || !occurrenceId.startsWith(`plan${current.checkInPlan.version}-`)) {
      return error(409, "planNotActive");
    }
    if (current.checkInPlan.lastCompletion?.occurrenceId !== occurrenceId) {
      current.checkInPlan.lastCompletion = {
        occurrenceId,
        completedAt: input.value.completedAt,
      };
      await storage.put("state", current);
    }
    return json({ checkInPlan: checkInPlanView(current.checkInPlan) });
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
  if (method === "PUT" && path.endsWith("/check-in-plan/proposal")) return "guardian";
  if (method === "PUT" && path.endsWith("/check-in-plan/decision")) return "person";
  if (method === "PUT" && path.endsWith("/location-sharing")) return "person";
  if (method === "PUT" && /\/locations\/[0-9a-f-]{36}$/.test(path)) return "person";
  if (method === "PUT" && /\/check-ins\/plan[0-9]+-[0-9]{8}-[0-9]{4}\/completion$/.test(path)) {
    return "person";
  }
  if (method === "PUT" && /\/alerts\/[0-9a-f-]{36}$/.test(path)) return "person";
  if (method === "PUT" && path.endsWith("/acknowledgment")) return "guardian";
  return null;
}

function locationSharingView(state) {
  const sharing = state.locationSharing;
  if (!sharing) return { enabled: false, updatedAt: null, latestLocation: null };
  return {
    enabled: sharing.enabled,
    updatedAt: sharing.updatedAt,
    latestLocation: sharing.enabled && sharing.latestLocation
      ? {
        latitude: sharing.latestLocation.latitude,
        longitude: sharing.latestLocation.longitude,
        horizontalAccuracyMeters: sharing.latestLocation.horizontalAccuracyMeters,
        capturedAt: sharing.latestLocation.capturedAt,
      }
      : null,
  };
}

function pruneStaleLocation(state) {
  if (state.locationSharing?.latestLocation
    && Date.now() - Date.parse(state.locationSharing.latestLocation.capturedAt)
      > locationRetentionMilliseconds) {
    state.locationSharing.latestLocation = null;
  }
}

function pruneExpiredAlerts(state) {
  state.alerts ??= {};
  state.aliases ??= {};
  const now = Date.now();
  for (const [eventId, alert] of Object.entries(state.alerts)) {
    if (!Number.isFinite(Date.parse(alert.expiresAt)) || Date.parse(alert.expiresAt) <= now) {
      delete state.alerts[eventId];
    }
  }
  for (const [requestedEventId, canonicalEventId] of Object.entries(state.aliases)) {
    if (!state.alerts[requestedEventId] || !state.alerts[canonicalEventId]) {
      delete state.aliases[requestedEventId];
    }
  }
  if (state.activeEventId && !state.alerts[state.activeEventId]) {
    state.activeEventId = null;
  }
}

function checkInPlanView(plan) {
  if (!plan) return null;
  return {
    proposalId: plan.proposalId,
    version: plan.version,
    state: plan.state,
    cadence: plan.cadence,
    localTime: plan.localTime,
    timeZoneIdentifier: plan.timeZoneIdentifier,
    condition: plan.condition,
    graceMinutes: plan.graceMinutes,
    proposedAt: plan.proposedAt,
    decidedAt: plan.decidedAt,
    lastCompletion: plan.lastCompletion,
  };
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

function validCheckInProposalBody(value) {
  if (!value || Object.keys(value).length !== allowedCheckInProposalFields.size
    || !Object.keys(value).every((key) => allowedCheckInProposalFields.has(key))) return false;
  if (typeof value.proposalId !== "string"
    || !/^[0-9a-f-]{36}$/.test(value.proposalId)
    || value.cadence !== "daily"
    || !/^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(value.localTime)
    || typeof value.timeZoneIdentifier !== "string"
    || value.timeZoneIdentifier.length < 1
    || value.timeZoneIdentifier.length > 64
    || !["always", "awayFromHome"].includes(value.condition)
    || !Number.isInteger(value.graceMinutes)
    || value.graceMinutes < 0
    || value.graceMinutes > 120
    || value.proposalConsentVersion !== "guardian-check-in-proposer-v1") return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value.timeZoneIdentifier });
  } catch {
    return false;
  }
  return true;
}

function validCheckInDecisionBody(value) {
  return value
    && Object.keys(value).length === 3
    && Number.isInteger(value.version)
    && value.version > 0
    && ["accept", "decline"].includes(value.decision)
    && value.participantConsentVersion === "guardian-check-in-participant-v1";
}

function validCheckInCompletionBody(value) {
  return value
    && Object.keys(value).length === 2
    && value.status === "completed"
    && typeof value.completedAt === "string"
    && Number.isFinite(Date.parse(value.completedAt));
}

function validLocationSharingBody(value) {
  return value
    && Object.keys(value).length === allowedLocationSharingFields.size
    && Object.keys(value).every((key) => allowedLocationSharingFields.has(key))
    && typeof value.decisionId === "string"
    && /^[0-9a-f-]{36}$/.test(value.decisionId)
    && typeof value.enabled === "boolean"
    && value.participantConsentVersion === "circle-location-participant-v1";
}

function validLocationSampleBody(value) {
  if (!value
    || Object.keys(value).length !== allowedLocationSampleFields.size
    || !Object.keys(value).every((key) => allowedLocationSampleFields.has(key))
    || typeof value.sampleId !== "string"
    || !/^[0-9a-f-]{36}$/.test(value.sampleId)
    || value.source !== "coreLocation"
    || !Number.isFinite(value.latitude) || value.latitude < -90 || value.latitude > 90
    || !Number.isFinite(value.longitude) || value.longitude < -180 || value.longitude > 180
    || !Number.isFinite(value.horizontalAccuracyMeters)
    || value.horizontalAccuracyMeters < 0 || value.horizontalAccuracyMeters > 1000
    || typeof value.capturedAt !== "string") return false;
  const capturedAt = Date.parse(value.capturedAt);
  return Number.isFinite(capturedAt)
    && capturedAt <= Date.now() + 5 * 60 * 1000
    && capturedAt >= Date.now() - locationRetentionMilliseconds;
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
