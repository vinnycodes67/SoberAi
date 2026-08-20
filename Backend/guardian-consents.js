import { sha256Base64URL } from "./guardian-crypto.js";

const consentRoles = Object.freeze({
  "guardian-sender-v1": "person",
  "person-phone-verification-v1": "person",
  "guardian-recipient-v1": "guardian",
  "notification-disclosure-v1": "guardian",
  "guardian-sms-fallback-v1": "guardian",
  "guardian-check-in-proposer-v1": "guardian",
  "guardian-check-in-participant-v1": "person",
  "circle-location-participant-v1": "person",
});

const acceptanceFields = new Set([
  "documentVersion", "documentDigest", "locale", "appVersion",
]);

export function roleForConsent(consentId) {
  return consentRoles[consentId] ?? null;
}

export function validConsentAcceptance(value, consentId) {
  if (!value || Object.keys(value).length !== acceptanceFields.size
    || !Object.keys(value).every((key) => acceptanceFields.has(key))
    || value.documentVersion !== consentId
    || typeof value.documentDigest !== "string"
    || !/^[0-9a-f]{64}$/.test(value.documentDigest)
    || typeof value.locale !== "string"
    || value.locale.length < 2
    || value.locale.length > 35
    || typeof value.appVersion !== "string"
    || value.appVersion.length < 1
    || value.appVersion.length > 64
    || value.appVersion.trim() !== value.appVersion
    || /\p{Cc}/u.test(value.appVersion)) return false;

  try {
    return new Intl.Locale(value.locale).toString() === value.locale;
  } catch {
    return false;
  }
}

export function validIdempotencyKey(value) {
  return typeof value === "string"
    && value.length >= 1
    && value.length <= 128
    && !/\p{Cc}/u.test(value);
}

export async function recordConsentAcceptance({
  state,
  consentId,
  role,
  acceptance,
  idempotencyKey,
  acceptedAt,
}) {
  state.consents ??= {};
  state.consentIdempotency ??= {};
  const canonicalAcceptance = JSON.stringify({
    appVersion: acceptance.appVersion,
    documentDigest: acceptance.documentDigest,
    documentVersion: acceptance.documentVersion,
    locale: acceptance.locale,
  });
  const fingerprint = await sha256Base64URL(canonicalAcceptance);
  const receiptKey = await sha256Base64URL(JSON.stringify([
    "consent-idempotency-v1", state.relationshipId, idempotencyKey,
  ]));
  const existing = state.consents[consentId];
  const replay = state.consentIdempotency[receiptKey];

  if (replay && (replay.consentId !== consentId || replay.fingerprint !== fingerprint)) {
    return { ok: false, conflict: "idempotencyConflict" };
  }

  if (existing) {
    const existingFingerprint = await fingerprintForRecord(existing);
    if (existingFingerprint !== fingerprint) {
      return { ok: false, conflict: "consentConflict" };
    }
    if (!replay) {
      state.consentIdempotency[receiptKey] = { consentId, fingerprint };
    }
    return { ok: true, created: false, changed: !replay, record: existing };
  }

  const record = {
    consentId,
    role,
    documentVersion: acceptance.documentVersion,
    documentDigest: acceptance.documentDigest,
    acceptedAt,
    locale: acceptance.locale,
    appVersion: acceptance.appVersion,
    withdrawnAt: null,
  };
  state.consents[consentId] = record;
  state.consentIdempotency[receiptKey] = { consentId, fingerprint };
  return { ok: true, created: true, changed: true, record };
}

export function consentView(record) {
  return {
    consentId: record.consentId,
    role: record.role,
    documentVersion: record.documentVersion,
    documentDigest: record.documentDigest,
    acceptedAt: record.acceptedAt,
    locale: record.locale,
    appVersion: record.appVersion,
    withdrawnAt: record.withdrawnAt,
  };
}

export function consentViewsForRole(state, role) {
  return Object.values(state.consents ?? {})
    .filter((record) => record.role === role)
    .sort((left, right) => left.consentId.localeCompare(right.consentId))
    .map(consentView);
}

export function withdrawConsentRecords(state, withdrawnAt) {
  for (const record of Object.values(state.consents ?? {})) {
    record.withdrawnAt ??= withdrawnAt;
  }
}

async function fingerprintForRecord(record) {
  return sha256Base64URL(JSON.stringify({
    appVersion: record.appVersion,
    documentDigest: record.documentDigest,
    documentVersion: record.documentVersion,
    locale: record.locale,
  }));
}
