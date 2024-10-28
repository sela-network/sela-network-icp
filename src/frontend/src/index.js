import { createActor, backend } from "../../declarations/backend";
import { AuthClient } from "@dfinity/auth-client";
import { HttpAgent } from "@dfinity/agent";
import { fromHexString } from "@dfinity/candid";
import { Ed25519PublicKey } from "@dfinity/identity";
import { IdbStorage } from "@dfinity/auth-client/lib/cjs/storage";

// Initialize the actor with the backend
let actor = backend;

// Helper function to convert ArrayBuffer to hex string
const bytesToHex = (buffer) => {
    return Array.from(new Uint8Array(buffer), (byte) =>
        byte.toString(16).padStart(2, '0')
    ).join('');
};

// SessionIdentity class definition
class SessionIdentity {
    constructor(publicKey) {
        this.publicKey = publicKey;
    }

    getPublicKey() {
        return this.publicKey;
    }

    async sign(blob) {
        throw new Error("Not implemented");
    }
}

// Function to handle login and setup authentication
const setupAuth = async () => {
    const url = new URL(window.location.href);
    const sessionKey = url.searchParams.get("sessionkey") ?? ""; // Extract session key from the URL

    let options = { storage: new IdbStorage() };

    if (sessionKey) {
        const derPublicKey = fromHexString(sessionKey);
        const publicKey = Ed25519PublicKey.fromDer(derPublicKey);
        options.identity = new SessionIdentity(publicKey);

        // Create the Auth instance with options
        const auth = await AuthClient.create(options); 

        console.log("auth: ", auth);

        // Start the login process and wait for it to finish
        await new Promise((resolve) => {
            auth.login({
                identityProvider: process.env.II_URL,
                onSuccess: resolve,
            });
        });

        // Check if authenticated using the auth instance
        if (await auth.isAuthenticated()) {
            console.log("Successfully authenticated");

            const agent = new HttpAgent({ identity: options.identity });

            // Create an actor to interact with the backend
            actor = createActor(process.env.BACKEND_CANISTER_ID, {
                agent,
            });

            const identity = auth.getIdentity();

            console.log("actor: ", actor);
            console.log("identity: ", identity);

            const delegations = options.identity._delegation.delegations.map(delegation => ({
                delegation: {
                    expiration: delegation.delegation.expiration.toString(),
                    pubkey: bytesToHex(delegation.delegation.pubkey),
                },
                signature: bytesToHex(delegation.signature)
            }));

            const publicKeyHex = bytesToHex(options.identity.getPublicKey().toDer());

            const result = {
                delegations,
                publicKey: publicKeyHex,
                status: true
            };

            console.log(JSON.stringify(result, null, 2));
        } else {
            console.error("Authentication failed");
        }
    } else {
        console.log("Session key is not present");
    }
};

// Attach event listeners to buttons
const greetButton = document.getElementById("greet");
greetButton.onclick = async (e) => {
    e.preventDefault();
    greetButton.setAttribute("disabled", true);

    const principalID = await actor.whoami();
    greetButton.removeAttribute("disabled");

    document.getElementById("greeting").innerText = principalID;
    console.log("principalID: ", principalID);
    return false;
};

const loginButton = document.getElementById("login");
loginButton.onclick = async (e) => {
    e.preventDefault();
    await setupAuth(); // Call the setupAuth function to handle authentication
    return false;
};
