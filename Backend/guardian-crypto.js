const encoder = new TextEncoder();

export function base64URL(bytes) {
  let binary = "";
  for (const byte of new Uint8Array(bytes)) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export function decodeBase64URL(value) {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export async function sha256Hex(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function sha256Base64URL(value) {
  return base64URL(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
}

export function canonicalSignatureInput({
  method,
  path,
  bodyHash,
  relationshipId,
  capabilityId,
  timestamp,
  nonce,
  idempotencyKey = "",
}) {
  return [
    "guardian-api-v1",
    method.toUpperCase(),
    path,
    bodyHash,
    relationshipId,
    capabilityId,
    timestamp,
    nonce,
    idempotencyKey,
  ].join("\n");
}

export async function verifyCapabilitySignature(request, state, expectedRole) {
  const relationshipId = request.headers.get("sober-relationship-id") ?? "";
  const capabilityId = request.headers.get("sober-capability-id") ?? "";
  const timestamp = request.headers.get("sober-timestamp") ?? "";
  const nonce = request.headers.get("sober-nonce") ?? "";
  const encodedSignature = request.headers.get("sober-signature") ?? "";
  const idempotencyKey = request.headers.get("idempotency-key") ?? "";
  const role = capabilityId === state.personCapabilityId
    ? "person"
    : capabilityId === state.guardianCapabilityId
      ? "guardian"
      : null;

  if (relationshipId !== state.relationshipId || !role || (expectedRole && role !== expectedRole)) {
    return { ok: false };
  }

  const signedAt = Date.parse(timestamp);
  if (!Number.isFinite(signedAt) || Math.abs(Date.now() - signedAt) > 5 * 60 * 1000) {
    return { ok: false };
  }
  if (!/^[A-Za-z0-9_-]{20,}$/.test(nonce) || state.nonces?.[nonce]) {
    return { ok: false };
  }

  const publicKeyJwk = role === "person" ? state.personPublicKeyJwk : state.guardianPublicKeyJwk;
  if (!publicKeyJwk || !encodedSignature) return { ok: false };

  try {
    const bodyBytes = new Uint8Array(await request.clone().arrayBuffer());
    const url = new URL(request.url);
    const input = canonicalSignatureInput({
      method: request.method,
      path: url.pathname,
      bodyHash: await sha256Hex(bodyBytes),
      relationshipId,
      capabilityId,
      timestamp,
      nonce,
      idempotencyKey,
    });
    const publicKey = await crypto.subtle.importKey(
      "jwk",
      publicKeyJwk,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"]
    );
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      decodeBase64URL(encodedSignature),
      encoder.encode(input)
    );
    return valid ? { ok: true, role, nonce, signedAt } : { ok: false };
  } catch {
    return { ok: false };
  }
}

export function validP256Jwk(value) {
  return value
    && value.kty === "EC"
    && value.crv === "P-256"
    && typeof value.x === "string"
    && typeof value.y === "string"
    && /^[A-Za-z0-9_-]{40,50}$/.test(value.x)
    && /^[A-Za-z0-9_-]{40,50}$/.test(value.y);
}

