import { createActor } from '../../declarations/backend';
import { AuthClient } from '@dfinity/auth-client';
import { HttpAgent } from '@dfinity/agent';
import { fromHexString } from '@dfinity/candid';
import { Ed25519KeyIdentity, Ed25519PublicKey } from '@dfinity/identity';
import { IdbStorage } from '@dfinity/auth-client/lib/cjs/storage';
import { ws, sendMessage } from './utils/ws';

// Initialize the actor with the backend
const backend = createActor(process.env.BACKEND_CANISTER_ID);
let actor = backend;
let authClient; // Declare authClient globally
let result;

// Helper function to convert ArrayBuffer to hex string
const bytesToHex = (buffer) => {
  return Array.from(new Uint8Array(buffer), (byte) =>
    byte.toString(16).padStart(2, '0')
  ).join('');
};

const setupAuth = async () => {
  const url = new URL(window.location.href);
  const sessionKey = url.searchParams.get('sessionkey') ?? ''; // Extract session key from the URL

  let options = { storage: new IdbStorage() };

  if (sessionKey) {
    const derPublicKey = fromHexString(sessionKey);
    const publicKey = Ed25519PublicKey.fromDer(derPublicKey);
    options.identity = Ed25519KeyIdentity.generate(); // Generate a key identity here

    // Create the Auth instance with options
    authClient = await AuthClient.create(options); // Initialize authClient here

    console.log('auth: ', authClient);

    // Start the login process and wait for it to finish
    await new Promise((resolve) => {
      authClient.login({
        identityProvider: process.env.II_URL,
        onSuccess: resolve,
      });
    });

    // Check if authenticated using the auth instance
    if (await authClient.isAuthenticated()) {
      console.log('Successfully authenticated');

      const identity = authClient.getIdentity();
      const agent = new HttpAgent({ identity: identity });

      // Create an actor to interact with the backend
      actor = createActor(process.env.BACKEND_CANISTER_ID, {
        agent,
      });

      console.log('actor: ', actor);
      console.log('identity: ', identity);

      // Send a message to WebSocket after successful authentication
      const message = {
        message: `User ${identity.getPrincipal().toString()} has logged in`,
      };
      sendMessage(message.message);

      const response = await actor.backend_health_check(); // Assuming actor is already defined
      console.log("Backend Health Check Response:", response); // Should log "OK"

      const ws_response = await actor.health_check(); // Assuming actor is already defined
      console.log("WS Health Check Response:", ws_response); // Should log "OK"


      // Log the principal for debugging
      console.log('Principal:', identity.getPrincipal().toString());
      let principalID = identity.getPrincipal().toString()

      const attributes = []; // Define any attributes if needed

      await testDB_operations(principalID);
    
      const delegations = identity._delegation.delegations.map(
        (delegation) => ({
          delegation: {
            expiration: delegation.delegation.expiration.toString(),
            pubkey: bytesToHex(delegation.delegation.pubkey),
          },
          signature: bytesToHex(delegation.signature),
        })
      );

      const publicKey = bytesToHex(identity.getPublicKey().toDer());

      // Create the final structure
      result = {
        delegations,
        publicKey,
      };

      console.log(JSON.stringify(result, null, 2));
    } else {
      console.error('Authentication failed');
    }
  } else {
    console.log('Session key is not present');
  }
};

const testDB_operations = async (pid) => {
  try {
    // Insert the principal ID and random ID into the database
    const dbInsertResponse = await actor.registerUser(pid.toString());
    console.log("DB Insert Response:", dbInsertResponse);
  
    if (dbInsertResponse) {
      console.log("Data stored successfully");
    } else {
      console.error("Failed to store data:", dbInsertResponse.err);
    }
  
    // Retrieve the user data
    const dbGetResponse = await actor.getUserData(pid.toString());
    console.log("DB Get Response:", dbGetResponse);
  
    if (dbGetResponse.ok) {
      console.log("Retrieved user data:", dbGetResponse.ok);
    } else {
      console.error("Failed to retrieve user data:", dbGetResponse.err);
    }

    // update the user data
    const dbUpdateResponse = await actor.updateUserData(pid.toString(), "12345");
    console.log("DB Update Response:", dbUpdateResponse);
  
    if (dbUpdateResponse.ok) {
      console.log("Retrieved user data:", dbUpdateResponse.ok);
    } else {
      console.error("Failed to Update user data:", dbUpdateResponse.err);
    }

  } catch (error) {
    console.error("An error occurred:", error);
  }
}

// Function to handle logout
const handleLogout = async () => {
  if (!authClient) {
    console.error('Auth client is not initialized');
    return; // Exit if authClient is not initialized
  }

  try {
    await authClient.logout(); // Call the logout method
    console.log("Successfully logged out");

    // Update the UI after logout
    document.getElementById("getData").innerText = ""; // Clear data message
    document.getElementById("login").style.display = "block"; // Show login button
    document.getElementById("logout").style.display = "none"; // Hide logout button
  } catch (error) {
    console.error('Error during logout:', error);
  }
};

const callWhoami = async () => {
  try {
    const principalID = await actor.whoami();
    console.log("Principal ID:", principalID);
    document.getElementById("logging").innerText = principalID.toString(); // Display principal ID in the UI

    const urlParams = new URLSearchParams(window.location.search);
    const redirectScheme = urlParams.get('scheme');
    const redirectHost = urlParams.get('host');

    if (result) {
      var delegationString = JSON.stringify(result);

      const encodedDelegation = encodeURIComponent(delegationString);
      window.location.href = `${redirectScheme}://${redirectHost}?del=${encodedDelegation}&status=true`;
    }
  } catch (error) {
    console.error("Error fetching principal ID:", error);
  }
};


// Example event listener for a button to call whoami
document.getElementById("getData").onclick = async (e) => {
  e.preventDefault();
  await callWhoami(); // Then call whoami
};

document.getElementById("authorize").onclick = async (e) => {
  e.preventDefault();
  await setupAuth(); // Ensure authentication is set up first
};

const logoutButton = document.getElementById("logout");
logoutButton.onclick = async (e) => {
  e.preventDefault();
  await handleLogout(); // Call the handleLogout function to log out
  return false;
};
