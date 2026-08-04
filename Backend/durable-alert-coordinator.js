import { DurableObject } from "cloudflare:workers";

import { coordinateAlert } from "./alert-coordinator-core.js";

export class AlertCoordinator extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx = ctx;
    this.env = env;
  }

  async submit(alert) {
    return this.ctx.blockConcurrencyWhile(async () => {
      try {
        return await coordinateAlert(this.ctx.storage, this.env, alert);
      } catch {
        // A Durable Object storage failure must fail closed. The app will show
        // the manual call/message fallback rather than risk a duplicate send.
        return { status: 503, body: { error: "durable_coordinator_failure" } };
      }
    });
  }
}
