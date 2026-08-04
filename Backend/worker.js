import { handleRequest } from "./relay-handler.js";

export { AlertCoordinator } from "./durable-alert-coordinator.js";
export { handleRequest } from "./relay-handler.js";

export default {
  fetch: handleRequest,
};
