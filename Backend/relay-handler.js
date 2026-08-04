const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

export function normalizePhone(value) {
  const digits = String(value ?? "").replace(/\D/g, "");
  if (digits.length === 10) return `+1${digits}`;
  if (digits.length >= 11 && digits.length <= 15) return `+${digits}`;
  return null;
}

function allowedRecipients(env) {
  return new Set(
    String(env.ALERT_ALLOWED_RECIPIENTS ?? "")
      .split(",")
      .map(normalizePhone)
      .filter(Boolean)
  );
}

async function sha256Bytes(value) {
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))
  );
}

async function sha256Hex(value) {
  const bytes = await sha256Bytes(value);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function constantTimeEqual(left, right) {
  const [leftDigest, rightDigest] = await Promise.all([
    sha256Bytes(left),
    sha256Bytes(right),
  ]);
  let difference = 0;
  for (let index = 0; index < leftDigest.length; index += 1) {
    difference |= leftDigest[index] ^ rightDigest[index];
  }
  return difference === 0 && left.length === right.length;
}

async function authorized(request, env) {
  const expected = String(env.ALERT_SHARED_TOKEN ?? "");
  const provided = String(request.headers.get("authorization") ?? "");
  if (expected.length < 20) return false;
  return constantTimeEqual(provided, `Bearer ${expected}`);
}

async function coordinatorForRecipient(recipient, env) {
  const namespace = env.ALERT_COORDINATOR;
  if (!namespace) return null;
  const name = await sha256Hex(`sober-parent-alert:${recipient}`);
  if (typeof namespace.getByName === "function") return namespace.getByName(name);
  if (typeof namespace.idFromName === "function" && typeof namespace.get === "function") {
    return namespace.get(namespace.idFromName(name));
  }
  return null;
}

export async function handleRequest(request, env) {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!(await authorized(request, env))) return json({ error: "unauthorized" }, 401);

  let payload;
  try {
    payload = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const eventID = String(payload.eventID ?? "").trim();
  const idempotencyKey = String(request.headers.get("idempotency-key") ?? "").trim();
  if (!eventID || eventID.length > 128 || !idempotencyKey) {
    return json({ error: "invalid_event_id" }, 422);
  }
  if (eventID !== idempotencyKey) return json({ error: "event_id_mismatch" }, 409);
  if (payload.result !== "SIGNALS_DETECTED") {
    return json({ error: "result_not_alertable" }, 422);
  }

  const recipient = normalizePhone(payload.parentPhone);
  if (!recipient || !allowedRecipients(env).has(recipient)) {
    return json({ error: "recipient_not_allowed" }, 403);
  }

  const message = String(payload.message ?? "").trim();
  if (!message || message.length > 600) return json({ error: "invalid_message" }, 422);

  const accountSID = String(env.TWILIO_ACCOUNT_SID ?? "");
  const authToken = String(env.TWILIO_AUTH_TOKEN ?? "");
  const from = normalizePhone(env.TWILIO_FROM_NUMBER);
  if (!accountSID || !authToken || !from) {
    return json({ error: "provider_not_configured" }, 503);
  }

  const coordinator = await coordinatorForRecipient(recipient, env);
  if (!coordinator || typeof coordinator.submit !== "function") {
    return json({ error: "durable_coordinator_not_configured" }, 503);
  }

  const fingerprint = await sha256Hex(JSON.stringify([payload.result, recipient, message]));
  try {
    const result = await coordinator.submit({
      eventID,
      fingerprint,
      recipient,
      message,
    });
    return json(result.body, result.status);
  } catch {
    return json({ error: "durable_coordinator_unavailable" }, 503);
  }
}
