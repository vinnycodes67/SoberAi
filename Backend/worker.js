import { handleGuardianRequest } from "./guardian-handler.js";

export { GuardianRelationship } from "./durable-guardian-relationship.js";
export { handleGuardianRequest } from "./guardian-handler.js";

export default {
  fetch: handleGuardianRequest,
};
