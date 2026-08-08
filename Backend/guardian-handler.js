import { base64URL, isUsableP256PublicKey, validP256Jwk } from "./guardian-crypto.js";

const encoder = new TextEncoder();

export async function handleGuardianRequest(request, env) {
  const url = new URL(request.url);
  if (request.method === "POST" && url.pathname === "/v1/guardian-relationships") {
    if (env.GUARDIAN_FOUNDER_MODE !== "true") return responseError(404, "notFound");
    if (!env.GUARDIAN_RELATIONSHIPS) return responseError(503, "dependencyUnavailable");
    const body = await parseJSON(request);
    if (!body || !validCreationBody(body)
      || !(await isUsableP256PublicKey(body.personPublicKeyJwk))) {
      return responseError(422, "invalidRequest");
    }

    const relationshipId = `rel_${crypto.randomUUID().replaceAll("-", "")}`;
    const personCapabilityId = `rcap_${crypto.randomUUID().replaceAll("-", "")}`;
    const inviteToken = base64URL(crypto.getRandomValues(new Uint8Array(24)));
    const inviteExpiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    return relationshipObject(env, relationshipId).fetch(new Request(
      `${url.origin}/v1/guardian-relationships/${relationshipId}/internal/create`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          relationshipId,
          personCapabilityId,
          inviteToken,
          inviteExpiresAt,
          personDisplayName: body.personDisplayName,
          personPublicKeyJwk: body.personPublicKeyJwk,
        }),
      }
    ));
  }

  if (url.pathname.includes("/internal/")) return responseError(404, "notFound");

  const match = url.pathname.match(/^\/v1\/guardian-relationships\/(rel_[A-Za-z0-9]+)(?:\/|$)/);
  if (match && env.GUARDIAN_RELATIONSHIPS) {
    if (request.method === "POST" && url.pathname.endsWith("/redeem")) {
      const body = await parseJSON(request);
      if (!body || !(await isUsableP256PublicKey(body.guardianPublicKeyJwk))) {
        return responseError(404, "invalidInvite");
      }
      body.guardianCapabilityId = `rcap_${crypto.randomUUID().replaceAll("-", "")}`;
      request = new Request(request, { body: JSON.stringify(body) });
    }
    return relationshipObject(env, match[1]).fetch(request);
  }

  // The legacy app-wide bearer-token relay is intentionally not routed.
  if (url.pathname === "/v1/alerts") return responseError(410, "legacyRouteRemoved");
  return responseError(404, "notFound");
}

function relationshipObject(env, relationshipId) {
  const namespace = env.GUARDIAN_RELATIONSHIPS;
  const id = typeof namespace.idFromName === "function" ? namespace.idFromName(relationshipId) : relationshipId;
  return namespace.get(id);
}

function validCreationBody(body) {
  const allowed = new Set([
    "personPublicKeyJwk", "personDisplayName", "senderConsentVersion", "phoneConsentVersion",
  ]);
  return Object.keys(body).every((key) => allowed.has(key))
    && validP256Jwk(body.personPublicKeyJwk)
    && typeof body.personDisplayName === "string"
    && body.personDisplayName.trim().length > 0
    && body.senderConsentVersion === "guardian-sender-v1";
}

async function parseJSON(request) {
  try {
    return JSON.parse(new TextDecoder().decode(await request.arrayBuffer()));
  } catch {
    return null;
  }
}

function responseError(status, code) {
  return new Response(JSON.stringify({
    error: { code, message: "The request could not be completed.", retryable: status >= 500 },
    requestId: `req_${crypto.randomUUID()}`,
  }), {
    status,
    headers: { "cache-control": "no-store", "content-type": "application/json; charset=utf-8" },
  });
}
