const DEFAULT_DEDUP_WINDOW_SECONDS = 24 * 60 * 60;
const MIN_DEDUP_WINDOW_SECONDS = 10 * 60;
const MAX_DEDUP_WINDOW_SECONDS = 7 * 24 * 60 * 60;
const DEFAULT_RATE_WINDOW_SECONDS = 10 * 60;
const DEFAULT_MAX_ALERTS_PER_WINDOW = 3;
const MAX_ALERTS_PER_WINDOW = 10;
const PROVIDER_TIMEOUT_MILLISECONDS = 10_000;

function boundedNumber(value, fallback, minimum, maximum) {
  const parsed = Number(value);
  const resolved = Number.isFinite(parsed) ? parsed : fallback;
  return Math.min(maximum, Math.max(minimum, resolved));
}

function deduplicationWindowMilliseconds(env) {
  return boundedNumber(
    env.ALERT_DEDUP_WINDOW_SECONDS,
    DEFAULT_DEDUP_WINDOW_SECONDS,
    MIN_DEDUP_WINDOW_SECONDS,
    MAX_DEDUP_WINDOW_SECONDS
  ) * 1_000;
}

function rateWindowMilliseconds(env) {
  return boundedNumber(
    env.ALERT_RATE_WINDOW_SECONDS,
    DEFAULT_RATE_WINDOW_SECONDS,
    60,
    24 * 60 * 60
  ) * 1_000;
}

function maximumAlertsPerWindow(env) {
  return Math.floor(
    boundedNumber(
      env.ALERT_MAX_PER_RATE_WINDOW,
      DEFAULT_MAX_ALERTS_PER_WINDOW,
      1,
      MAX_ALERTS_PER_WINDOW
    )
  );
}

class ProviderSubmissionError extends Error {
  constructor(kind) {
    super(kind);
    this.kind = kind;
  }
}

function providerErrorResult(error) {
  switch (error?.kind) {
    case "rejected":
      return { status: 502, body: { error: "provider_rejected" } };
    case "invalid_response":
      return { status: 502, body: { error: "provider_invalid_response" } };
    default:
      return { status: 503, body: { error: "provider_temporarily_unavailable" } };
  }
}

async function submitToProvider({ recipient, message, eventID, env }) {
  const accountSID = String(env.TWILIO_ACCOUNT_SID ?? "");
  const authToken = String(env.TWILIO_AUTH_TOKEN ?? "");
  const fromDigits = String(env.TWILIO_FROM_NUMBER ?? "").replace(/\D/g, "");
  const from = fromDigits.length === 10 ? `+1${fromDigits}` : `+${fromDigits}`;
  const body = new URLSearchParams({ To: recipient, From: from, Body: message });
  const outboundFetch = env.TEST_FETCH ?? fetch;

  let response;
  try {
    response = await outboundFetch(
      `https://api.twilio.com/2010-04-01/Accounts/${accountSID}/Messages.json`,
      {
        method: "POST",
        headers: {
          authorization: `Basic ${btoa(`${accountSID}:${authToken}`)}`,
          "content-type": "application/x-www-form-urlencoded;charset=UTF-8",
        },
        body,
        signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MILLISECONDS),
      }
    );
  } catch {
    throw new ProviderSubmissionError("temporarily_unavailable");
  }

  if (
    response.status === 408
    || response.status === 425
    || response.status === 429
    || response.status >= 500
  ) {
    throw new ProviderSubmissionError("temporarily_unavailable");
  }
  if (!response.ok) throw new ProviderSubmissionError("rejected");

  let providerResult;
  try {
    providerResult = await response.json();
  } catch {
    throw new ProviderSubmissionError("invalid_response");
  }

  if (typeof providerResult?.sid !== "string" || providerResult.sid.trim().length === 0) {
    throw new ProviderSubmissionError("invalid_response");
  }

  return { reference: providerResult.sid };
}

function emptyState() {
  return { schemaVersion: 1, events: {}, rateReservations: [] };
}

function prunedState(stored, now, rateWindow) {
  const state = stored?.schemaVersion === 1 ? stored : emptyState();
  state.events = Object.fromEntries(
    Object.entries(state.events ?? {}).filter(([, event]) => event.expiresAt > now)
  );
  state.rateReservations = (state.rateReservations ?? []).filter(
    (reservation) => reservation.at > now - rateWindow
      && state.events[reservation.eventID] != null
  );
  return state;
}

/**
 * Runs inside a Durable Object selected from a hash of the parent phone number.
 * The caller serializes this function with `blockConcurrencyWhile` because the
 * external provider request must not interleave with another alert to the same
 * recipient. Alert volume is tiny and correctness is more important than
 * per-recipient throughput.
 *
 * A durable `submitting` record is written before contacting the provider. If
 * the object crashes after Twilio accepts but before the receipt is stored, a
 * retry fails closed with 425 instead of risking a second alarming SMS.
 */
export async function coordinateAlert(storage, env, alert, now = Date.now()) {
  const rateWindow = rateWindowMilliseconds(env);
  const dedupWindow = deduplicationWindowMilliseconds(env);
  const state = prunedState(await storage.get("coordinator"), now, rateWindow);
  const existing = state.events[alert.eventID];

  if (existing) {
    if (existing.fingerprint !== alert.fingerprint) {
      return { status: 409, body: { error: "event_id_conflict" } };
    }
    if (existing.status === "accepted") {
      return {
        status: 200,
        body: {
          submissionStatus: "deduplicated",
          eventID: alert.eventID,
          reference: existing.reference,
        },
      };
    }
    return { status: 425, body: { error: "submission_status_unknown" } };
  }

  if (state.rateReservations.length >= maximumAlertsPerWindow(env)) {
    await storage.put("coordinator", state);
    return { status: 429, body: { error: "recipient_rate_limited" } };
  }

  state.events[alert.eventID] = {
    fingerprint: alert.fingerprint,
    status: "submitting",
    createdAt: now,
    expiresAt: now + dedupWindow,
  };
  state.rateReservations.push({ eventID: alert.eventID, at: now });
  await storage.put("coordinator", state);

  let result;
  try {
    result = await submitToProvider({
      recipient: alert.recipient,
      message: alert.message,
      eventID: alert.eventID,
      env,
    });
  } catch (error) {
    delete state.events[alert.eventID];
    state.rateReservations = state.rateReservations.filter(
      (reservation) => reservation.eventID !== alert.eventID
    );
    await storage.put("coordinator", state);
    return providerErrorResult(error);
  }

  state.events[alert.eventID] = {
    ...state.events[alert.eventID],
    status: "accepted",
    reference: result.reference,
  };
  // If this write fails after provider acceptance, let the Durable Object fail
  // closed. The previously persisted `submitting` record prevents an automatic
  // retry from sending a duplicate when delivery status is uncertain.
  await storage.put("coordinator", state);
  return {
    status: 202,
    body: {
      submissionStatus: "accepted",
      eventID: alert.eventID,
      reference: result.reference,
    },
  };
}
