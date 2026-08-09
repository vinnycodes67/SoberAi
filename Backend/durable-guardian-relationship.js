import { handleRelationshipRequest } from "./guardian-relationship-core.js";
import { handleRelationshipAlarm } from "./guardian-relationship-lifecycle.js";

export class GuardianRelationship {
  constructor(state) {
    this.state = state;
  }

  fetch(request) {
    return this.state.blockConcurrencyWhile(() =>
      handleRelationshipRequest(this.state.storage, request)
    );
  }
  alarm() {
    return this.state.blockConcurrencyWhile(() =>
      handleRelationshipAlarm(this.state.storage)
    );
  }
}
