import { createActor, backend } from '../../declarations/backend';
import { AuthClient } from '@dfinity/auth-client';
import { HttpAgent } from '@dfinity/agent';
import { fromHexString } from '@dfinity/candid';
import { Ed25519PublicKey } from '@dfinity/identity';
import { IdbStorage } from '@dfinity/auth-client/lib/cjs/storage';

// Initialize the actor with the backend
let actor = backend;
let authClient; // Declare authClient globally
let result;

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
    throw new Error('Not implemented');
  }
}

// Function to handle login and setup authentication
const setupAuth = async () => {
  const url = new URL(window.location.href);
  const sessionKey = url.searchParams.get('sessionkey') ?? ''; // Extract session key from the URL

  let options = { storage: new IdbStorage() };

  if (sessionKey) {
    const derPublicKey = fromHexString(sessionKey);
    const publicKey = Ed25519PublicKey.fromDer(derPublicKey);
    options.identity = new SessionIdentity(publicKey);

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

      const delegations = identity._delegation.delegations.map(
        (delegation) => ({
          delegation: {
            expiration: delegation.delegation.expiration.toString(),
            pubkey: bytesToHex(delegation.delegation.pubkey),
          },
          signature: bytesToHex(delegation.signature),
        })
      );

      const publicKey = bytesToHex(identity._inner.getPublicKey().toDer());

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

// Attach event listeners to buttons
const loginButton = document.getElementById('login');
loginButton.onclick = async (e) => {
  e.preventDefault();
  await setupAuth(); // Call the setupAuth function to handle authentication
  return false;
};

const logoutButton = document.getElementById("logout");
logoutButton.onclick = async (e) => {
  e.preventDefault();
  await handleLogout(); // Call the handleLogout function to log out
  return false;
};
