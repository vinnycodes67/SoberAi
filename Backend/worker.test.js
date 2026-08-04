import assert from "node:assert/strict";
import test from "node:test";

import { coordinateAlert } from "./alert-coordinator-core.js";
import { handleRequest } from "./relay-handler.js";

const token = "founder-review-token-at-least-20-characters";

class MemoryStorage {
  constructor() {
    this.values = new Map();
  }

  async get(key) {
    const value = this.values.get(key);
    return value == null ? value : structuredClone(value);
  }

  async put(key, value) {
    this.values.set(key, structuredClone(value));
  }
}

class MemoryAlertCoordinator {
  constructor(env) {
    this.env = env;
    this.storage = new MemoryStorage();
    this.tail = Promise.resolve();
  }

  submit(alert) {
    const operation = this.tail.then(() => coordinateAlert(this.storage, this.env, alert));
    this.tail = operation.then(() => undefined, () => undefined);
    return operation;
  }
}

class MemoryCoordinatorNamespace {
  constructor(env) {
    this.env = env;
    this.instances = new Map();
  }

  getByName(name) {
    if (!this.instances.has(name)) {
      this.instances.set(name, new MemoryAlertCoordinator(this.env));
    }
    return this.instances.get(name);
  }
}

function request(
  payload,
  authorization = `Bearer ${token}`,
  eventID = payload.eventID ?? crypto.randomUUID(),
  idempotencyKey = eventID
) {
  return new Request("https://alerts.example.test/v1/alerts", {
    method: "POST",
    headers: {
      authorization,
      "content-type": "application/json",
      "idempotency-key": idempotencyKey,
    },
    body: JSON.stringify({ ...payload, eventID }),
  });
}

function environment(overrides = {}) {
  const env = {
    ALERT_SHARED_TOKEN: token,
    ALERT_ALLOWED_RECIPIENTS: "+15125550147",
    TWILIO_ACCOUNT_SID: "AC123",
    TWILIO_AUTH_TOKEN: "server-only-secret",
    TWILIO_FROM_NUMBER: "+15125550199",
    TEST_FETCH: async (_url, options) => {
      assert.match(String(options.body), /To=%2B15125550147/);
      assert.match(options.headers.authorization, /^Basic /);
      return new Response(JSON.stringify({ sid: "SM123" }), {
        status: 201,
        headers: { "content-type": "application/json" },
      });
    },
    ...overrides,
  };
  if (!("ALERT_COORDINATOR" in overrides)) {
    env.ALERT_COORDINATOR = new MemoryCoordinatorNamespace(env);
  }
  return env;
}

const alertPayload = {
  result: "SIGNALS_DETECTED",
  parentPhone: "512-555-0147",
  message: "Sober safety alert: Alex needs a safe ride.",
};

test("rejects callers without the shared token", async () => {
  const response = await handleRequest(request(alertPayload, "Bearer wrong"), environment());
  assert.equal(response.status, 401);
});

test("requires the body event ID to match the idempotency key", async () => {
  const response = await handleRequest(
    request(alertPayload, `Bearer ${token}`, "body-event", "header-event"),
    environment()
  );
  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: "event_id_mismatch" });
});

test("refuses to send non-concerning outcomes", async () => {
  const response = await handleRequest(
    request({ ...alertPayload, result: "NO_SIGNALS_DETECTED" }),
    environment()
  );
  assert.equal(response.status, 422);
});

test("refuses recipients outside the founder allowlist", async () => {
  const response = await handleRequest(
    request({ ...alertPayload, parentPhone: "5125550100" }),
    environment()
  );
  assert.equal(response.status, 403);
});

test("reports a newly accepted provider submission without exposing provider secrets", async () => {
  const eventID = crypto.randomUUID();
  const response = await handleRequest(request(alertPayload, undefined, eventID), environment());
  assert.equal(response.status, 202);
  const body = await response.json();
  assert.deepEqual(body, {
    submissionStatus: "accepted",
    eventID,
    reference: "SM123",
  });
  assert.equal(JSON.stringify(body).includes("server-only-secret"), false);
});

test("deduplicates concurrent retries and calls the provider only once", async () => {
  const eventID = crypto.randomUUID();
  let providerCalls = 0;
  let releaseProvider;
  const providerGate = new Promise((resolve) => {
    releaseProvider = resolve;
  });
  const env = environment({
    TEST_FETCH: async () => {
      providerCalls += 1;
      await providerGate;
      return new Response(JSON.stringify({ sid: "SM-DEDUPE" }), { status: 201 });
    },
  });

  const firstResponsePromise = handleRequest(request(alertPayload, undefined, eventID), env);
  const duplicateResponsePromise = handleRequest(request(alertPayload, undefined, eventID), env);
  releaseProvider();

  const [firstResponse, duplicateResponse] = await Promise.all([
    firstResponsePromise,
    duplicateResponsePromise,
  ]);
  assert.equal(providerCalls, 1);
  assert.equal(firstResponse.status, 202);
  assert.equal(duplicateResponse.status, 200);
  assert.equal((await firstResponse.json()).submissionStatus, "accepted");
  assert.deepEqual(await duplicateResponse.json(), {
    submissionStatus: "deduplicated",
    eventID,
    reference: "SM-DEDUPE",
  });
});

test("rejects reuse of an event ID for different alert content", async () => {
  const eventID = crypto.randomUUID();
  const env = environment();
  await handleRequest(request(alertPayload, undefined, eventID), env);

  const response = await handleRequest(
    request({ ...alertPayload, message: "Different safety message" }, undefined, eventID),
    env
  );
  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: "event_id_conflict" });
});

test("maps a permanent provider rejection without returning provider details", async () => {
  const env = environment({
    TEST_FETCH: async () =>
      new Response(JSON.stringify({ message: "provider account secret detail" }), { status: 400 }),
  });
  const response = await handleRequest(request(alertPayload), env);
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { error: "provider_rejected" });
});

test("rejects a malformed successful provider response", async () => {
  const env = environment({
    TEST_FETCH: async () => new Response("not-json", { status: 201 }),
  });
  const response = await handleRequest(request(alertPayload), env);
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { error: "provider_invalid_response" });
});

test("maps transient provider statuses and allows the same event to retry", async () => {
  for (const providerStatus of [429, 500]) {
    const eventID = crypto.randomUUID();
    let providerCalls = 0;
    const env = environment({
      TEST_FETCH: async () => {
        providerCalls += 1;
        return new Response("temporarily unavailable", { status: providerStatus });
      },
    });

    for (let attempt = 0; attempt < 2; attempt += 1) {
      const response = await handleRequest(request(alertPayload, undefined, eventID), env);
      assert.equal(response.status, 503);
      assert.deepEqual(await response.json(), { error: "provider_temporarily_unavailable" });
    }
    assert.equal(providerCalls, 2);
  }
});

test("fails closed when the durable coordinator binding is missing", async () => {
  const response = await handleRequest(
    request(alertPayload),
    environment({ ALERT_COORDINATOR: undefined })
  );

  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: "durable_coordinator_not_configured" });
});

test("rate limits distinct alert events for the same recipient", async () => {
  let providerCalls = 0;
  const env = environment({
    ALERT_MAX_PER_RATE_WINDOW: "2",
    TEST_FETCH: async () => {
      providerCalls += 1;
      return new Response(JSON.stringify({ sid: `SM-${providerCalls}` }), { status: 201 });
    },
  });

  const first = await handleRequest(request(alertPayload), env);
  const second = await handleRequest(request(alertPayload), env);
  const third = await handleRequest(request(alertPayload), env);

  assert.equal(first.status, 202);
  assert.equal(second.status, 202);
  assert.equal(third.status, 429);
  assert.deepEqual(await third.json(), { error: "recipient_rate_limited" });
  assert.equal(providerCalls, 2);
});

test("persists deduplication across separate handler calls", async () => {
  const env = environment();
  const eventID = crypto.randomUUID();

  const first = await handleRequest(request(alertPayload, undefined, eventID), env);
  const retry = await handleRequest(request(alertPayload, undefined, eventID), env);

  assert.equal(first.status, 202);
  assert.equal(retry.status, 200);
  assert.equal((await retry.json()).submissionStatus, "deduplicated");
});
