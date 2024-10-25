import {createActor, greet_backend} from "../../declarations/greet_backend";
import {AuthClient} from "@dfinity/auth-client"
import {HttpAgent} from "@dfinity/agent";

let actor = greet_backend;

const greetButton = document.getElementById("greet");
greetButton.onclick = async (e) => {
    e.preventDefault();

    greetButton.setAttribute("disabled", true);

    // Interact with backend actor, calling the greet method
    const prinicipalID = await actor.whoami();

    greetButton.removeAttribute("disabled");

    document.getElementById("greeting").innerText = prinicipalID;

    console.log("prinicipalID: ", prinicipalID)

    return false;
};

const loginButton = document.getElementById("login");
loginButton.onclick = async (e) => {
    e.preventDefault();

    // create an auth client
    let authClient = await AuthClient.create();

    // start the login process and wait for it to finish
    await new Promise((resolve) => {
        authClient.login({
            identityProvider: process.env.II_URL,
            onSuccess: resolve,
        });
    });

    // At this point we're authenticated, and we can get the identity from the auth client:
    const identity = authClient.getIdentity();
    // Using the identity obtained from the auth client, we can create an agent to interact with the IC.
    const agent = new HttpAgent({identity});
    // Using the interface description of our webapp, we create an actor that we use to call the service methods.
    actor = createActor(process.env.GREET_BACKEND_CANISTER_ID, {
        agent,
    });

    console.log("actor: ", actor)
    console.log("identity: ", identity)

     // Extracting the necessary data from the DelegationIdentity object
     const delegations = identity._delegation.delegations.map(delegation => ({
        delegation: {
            expiration: delegation.delegation.expiration.toString(),
            pubkey: bytesToHex(delegation.delegation.pubkey), // Convert Uint8Array to hex string
        },
        signature: bytesToHex(delegation.signature) // Convert signature to hex string
    }));

    const publicKey = bytesToHex(identity._inner.getPublicKey().toDer());

    // Create the final structure
    const result = {
        delegations,
        publicKey,
        status: true // or whatever status you want to indicate
    };

    // Print the result in JSON format
    console.log(JSON.stringify(result, null, 2));

    return false;
};

// Helper function to convert ArrayBuffer to hex string
const bytesToHex = (buffer) => {
    return Array.from(new Uint8Array(buffer), (byte) =>
        byte.toString(16).padStart(2, '0')
    ).join('');
};