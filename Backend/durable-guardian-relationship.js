import { handleRelationshipRequest } from "./guardian-relationship-core.js";

export class GuardianRelationship {
  constructor(state) {
    this.state = state;
  }

  fetch(request) {
    return this.state.blockConcurrencyWhile(() =>
      handleRelationshipRequest(this.state.storage, request)
    );
  }
}
