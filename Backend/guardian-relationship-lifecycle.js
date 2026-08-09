import { withdrawConsentRecords } from "./guardian-consents.js";

export const relationshipLifetimeMilliseconds = 90 * 24 * 60 * 60 * 1000;
export const relationshipWarningLeadMilliseconds = 14 * 24 * 60 * 60 * 1000;
export const inactiveAuditLifetimeMilliseconds = 30 * 24 * 60 * 60 * 1000;

export function ensureRelationshipSchema(state) {
  if (!state) return null;
  state.schemaVersion ??= 2;
  state.contractVersion ??= "guardian-api-v1";
  state.consents ??= {};
  state.consentIdempotency ??= {};
  state.expiredAt ??= null;
  state.cleanupAt ??= null;

  if (state.expiresAt) {
    const warningAt = new Date(
      Date.parse(state.expiresAt) - relationshipWarningLeadMilliseconds
    ).toISOString();
    state.expiryWarning ??= { state: "notDue", warningAt, visibleAt: null };
    state.expiryWarning.warningAt = warningAt;
  } else {
    state.expiryWarning ??= null;
  }
  return state;
}

export async function persistRelationshipState(storage, state, nowMilliseconds = Date.now()) {
  ensureRelationshipSchema(state);
  await storage.put("state", state);
  // Reconcile after the initial write so a migrated or newly persisted active
  // object already inside its warning window exposes that warning immediately.
  await reconcileRelationshipLifecycle(storage, state, nowMilliseconds);
}

export async function reconcileRelationshipLifecycle(
  storage,
  state,
  nowMilliseconds = Date.now()
) {
  ensureRelationshipSchema(state);
  let changed = false;

  if (["active", "reauthorizationRequired"].includes(state.relationshipState)) {
    const expiresAt = Date.parse(state.expiresAt);
    const warningAt = expiresAt - relationshipWarningLeadMilliseconds;
    if (nowMilliseconds >= expiresAt) {
      expireRelationship(state, nowMilliseconds);
      changed = true;
    } else if (nowMilliseconds >= warningAt && state.expiryWarning?.state !== "visible") {
      state.expiryWarning = {
        state: "visible",
        warningAt: new Date(warningAt).toISOString(),
        visibleAt: new Date(nowMilliseconds).toISOString(),
      };
      changed = true;
    }
  }

  if (changed) await storage.put("state", state);
  await scheduleRelationshipAlarm(storage, state, nowMilliseconds);
  return { state, changed };
}

export async function scheduleRelationshipAlarm(storage, state, nowMilliseconds = Date.now()) {
  const nextAlarm = nextRelationshipAlarm(state, nowMilliseconds);
  if (nextAlarm == null) {
    if (typeof storage.deleteAlarm === "function") await storage.deleteAlarm();
    return null;
  }
  if (typeof storage.setAlarm === "function") await storage.setAlarm(nextAlarm);
  return nextAlarm;
}

export async function handleRelationshipAlarm(storage, nowMilliseconds = Date.now()) {
  const state = ensureRelationshipSchema(await storage.get("state"));
  if (!state) {
    if (typeof storage.deleteAlarm === "function") await storage.deleteAlarm();
    return;
  }

  if (["revoked", "expired"].includes(state.relationshipState)
    && Number.isFinite(Date.parse(state.cleanupAt))
    && nowMilliseconds >= Date.parse(state.cleanupAt)) {
    if (typeof storage.deleteAll === "function") await storage.deleteAll();
    else await storage.delete("state");
    if (typeof storage.deleteAlarm === "function") await storage.deleteAlarm();
    return;
  }

  await reconcileRelationshipLifecycle(storage, state, nowMilliseconds);
}

export function revokeRelationship(state, revokedAtMilliseconds = Date.now()) {
  ensureRelationshipSchema(state);
  if (state.relationshipState === "revoked") return false;
  const revokedAt = new Date(revokedAtMilliseconds).toISOString();
  state.relationshipState = "revoked";
  state.revokedAt = revokedAt;
  state.cleanupAt = new Date(
    revokedAtMilliseconds + inactiveAuditLifetimeMilliseconds
  ).toISOString();
  state.inviteTokenHash = null;
  state.expiryWarning = state.expiryWarning
    ? { ...state.expiryWarning, state: "revoked" }
    : null;
  state.alerts = {};
  state.aliases = {};
  state.activeEventId = null;
  state.checkInPlan = null;
  state.locationSharing = null;
  state.personDisplayName = "";
  withdrawConsentRecords(state, revokedAt);
  state.consentIdempotency = {};
  return true;
}

export function expiryWarningView(state) {
  if (state.expiryWarning?.state !== "visible") return null;
  return {
    state: "visible",
    startedAt: state.expiryWarning.warningAt,
    expiresAt: state.expiresAt,
  };
}

function expireRelationship(state, expiredAtMilliseconds) {
  const expiredAt = new Date(expiredAtMilliseconds).toISOString();
  state.relationshipState = "expired";
  state.expiredAt = expiredAt;
  state.cleanupAt = new Date(
    expiredAtMilliseconds + inactiveAuditLifetimeMilliseconds
  ).toISOString();
  state.inviteTokenHash = null;
  state.expiryWarning = state.expiryWarning
    ? { ...state.expiryWarning, state: "expired" }
    : null;
  state.alerts = {};
  state.aliases = {};
  state.activeEventId = null;
  state.checkInPlan = null;
  state.locationSharing = null;
  state.personDisplayName = "";
  state.personPublicKeyJwk = null;
  state.guardianPublicKeyJwk = null;
  state.personCapabilityId = null;
  state.guardianCapabilityId = null;
  withdrawConsentRecords(state, expiredAt);
  state.consentIdempotency = {};
}

function nextRelationshipAlarm(state, nowMilliseconds) {
  if (["active", "reauthorizationRequired"].includes(state.relationshipState)) {
    const expiresAt = Date.parse(state.expiresAt);
    if (!Number.isFinite(expiresAt)) return null;
    const warningAt = expiresAt - relationshipWarningLeadMilliseconds;
    if (state.expiryWarning?.state !== "visible" && nowMilliseconds < warningAt) return warningAt;
    return expiresAt;
  }
  if (["revoked", "expired"].includes(state.relationshipState)) {
    const cleanupAt = Date.parse(state.cleanupAt);
    return Number.isFinite(cleanupAt) ? cleanupAt : null;
  }
  return null;
}
