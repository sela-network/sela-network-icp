import { Actor, HttpAgent } from "@dfinity/agent";

import canisterIds from "../../.dfx/local/canister_ids.json" assert { type: "json" };

// Imports and re-exports candid interface
import { idlFactory } from "../declarations/backend/backend.did.mjs";
export { idlFactory } from "../declarations/backend/backend.did.mjs";
// CANISTER_ID is replaced by webpack based on node environment
export const canisterId = canisterIds.backend.local;

/**
 *
 * @param {string | import("@dfinity/principal").Principal} canisterId Canister ID of Agent
 * @param {{agentOptions?: import("@dfinity/agent").HttpAgentOptions; actorOptions?: import("@dfinity/agent").ActorConfig}} [options]
 * @return {import("@dfinity/agent").ActorSubclass<import("../declarations/backend/backend.did.js")._SERVICE>}
 */
export const createActor = (canisterId, options) => {
  const agent = new HttpAgent({ ...options?.agentOptions });

  // Fetch root key for certificate validation during development
  if (process.env.NODE_ENV !== "production") {
    agent.fetchRootKey().catch((err) => {
      console.warn(
        "Unable to fetch root key. Check to ensure that your local replica is running"
      );
      console.error(err);
    });
  }

  // Creates an actor with using the candid interface and the HttpAgent
  return Actor.createActor(idlFactory, {
    agent,
    canisterId,
    ...options?.actorOptions,
  });
};

/**
 * A ready-to-use agent for the backend canister
 * @type {import("@dfinity/agent").ActorSubclass<import("../declarations/backend/backend.did.js")._SERVICE>}
 */
export const backend_code = createActor(canisterId, {
  agentOptions: { host: "http://127.0.0.1:4943" },
});