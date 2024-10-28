import { createActor, greet_backend } from "../../declarations/greet_backend";
import { AuthClient, IdleOptions } from "@dfinity/auth-client";
import { HttpAgent } from "@dfinity/agent";
import { fromHexString } from "@dfinity/candid";
import { Ed25519PublicKey } from "@dfinity/identity";
import { IdbStorage } from "@dfinity/auth-client/lib/cjs/storage";

// Initialize the actor with the greet_backend
let actor = greet_backend;

// Helper function to convert ArrayBuffer to hex string
const bytesToHex = (buffer) => {
    return Array.from(new Uint8Array(buffer), (byte) =>
        byte.toString(16).padStart(2, '0')
    ).join('');
};

// Function to handle login and setup authentication
const setupAuth = async () => {
    const url = new URL(window.location.href);
    const sessionKey = url.searchParams.get("sessionkey") ?? ""; // Extract session key from the URL

    let options = { storage: new IdbStorage() };

    if (sessionKey) {
        const derPublicKey = fromHexString(sessionKey); // Convert the session key from hex
        const publicKey = Ed25519PublicKey.fromDer(derPublicKey);
        options.identity = new SessionIdentity(publicKey); // Assuming SessionIdentity class is defined somewhere
    }

    // Create the Auth instance with options
    const auth = await AuthClient.create(options); 

    console.log("auth : ", auth)

    // Check if authenticated using the auth instance
    if (await auth.isAuthenticated()) {
        console.log("Successfully authenticated");

        const agent = new HttpAgent({ identity: options.identity });

        // Create an actor to interact with the backend
        actor = createActor(process.env.GREET_BACKEND_CANISTER_ID, {
            agent,
        });

        console.log("actor: ", actor);
        console.log("identity: ", options.identity);

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
