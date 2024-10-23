import { html, render } from 'lit-html';
import { Ed25519KeyIdentity } from '@dfinity/identity';
import { Actor, HttpAgent } from '@dfinity/agent';
import { idlFactory as myCanisterIdl } from 'declarations/cannister_backend';
import { canisterId as myCanisterId } from 'declarations/cannister_backend';
import { AuthClient } from '@dfinity/auth-client';

// State variable to hold the delegation object and agent data
let delegationData = null;
let agentData = null;

// Helper function to convert ArrayBuffer to hex string
const bytesToHex = (buffer) => {
  return Array.from(new Uint8Array(buffer), (byte) =>
    byte.toString(16).padStart(2, '0')
  ).join('');
};

// Template function for rendering the app
const appTemplate = (onLoginClick, onAppClick, isAuthenticated, agentData, delegationData) => html`
  <main>
    <h1>Internet Identity Authentication</h1>
    <button @click="${onLoginClick}" ?disabled=${isAuthenticated}>Login with Internet Identity</button>
    <br /><br />
    <button @click="${onAppClick}" ?disabled=${!isAuthenticated}>Take me to the app</button>
    ${delegationData ? html`<pre>Delegation Data: ${JSON.stringify(delegationData, null, 2)}</pre>` : ""}
    ${agentData ? html`<pre>Agent Data: ${JSON.stringify(agentData, null, 2)}</pre>` : ""}
  </main>
`;

class App {
  constructor() {
    this.isAuthenticated = false;
    this.render();
  }

  // Authenticate the user using Internet Identity
  async loginWithInternetIdentity() {
    try {
      const authClient = await AuthClient.create();

      // Generate a session key
      const newIdentity = await Ed25519KeyIdentity.generate();
      const publicKey = newIdentity.getPublicKey();
      const publicKeyDer = publicKey.toDer();
      const sessionKey = bytesToHex(publicKeyDer);

      console.log("newIdentity: ", newIdentity);
      console.log("publicKey: ", publicKey);
      console.log("publicKeyDer: ", publicKeyDer);
      console.log("session key: ", sessionKey);

      // Start the login process with session key in URL
      authClient.login({
        identityProvider: `https://identity.ic0.app?sessionkey=${sessionKey}`,
        onSuccess: async () => {
          const identity = authClient.getIdentity();
          this.isAuthenticated = true;

          // Fetch the identity principal
          const principal = identity.getPrincipal().toString();

          // Create an authenticated agent and actor to communicate with the backend
          const agent = new HttpAgent({ 
            identity,
            host: 'http://127.0.0.1:4943',
           });
          const actor = Actor.createActor(myCanisterIdl, {
            agent,
            canisterId: myCanisterId,
          });

          console.log("identity: ", identity);
          console.log("agent: ", agent);
          console.log("actor: ", actor);

          // Call the whoami() function to get the caller's principal
          const whoamiResponse = await actor.whoami();
          console.log('Whoami response:', whoamiResponse); // Log the response
          
          // Fetch delegation data if needed
          delegationData = {
            publicKey: principal,
            sessionKey: sessionKey,
            status: true,
            whoami: whoamiResponse // Store the response
          };

          // Save agent data
          agentData = {
            identity: principal,
            agent,
          };

          console.log('Logged in as:', principal, 'Session Key:', sessionKey);

          // Render the updated view
          this.render();
        },
        onError: (error) => {
          console.error('Login failed:', error);
        },
      });
    } catch (error) {
      console.error('Failed to authenticate:', error);
    }
  }

  // Handle the "Take me to the app" button
  takeMeToApp() {
    if (delegationData || agentData) {
      alert('You have successfully authenticated. Check data below.');
    }
  }

  // Render the HTML content
  render() {
    const body = appTemplate(
      () => this.loginWithInternetIdentity(),
      () => this.takeMeToApp(),
      this.isAuthenticated,
      agentData,
      delegationData
    );
    render(body, document.getElementById('root'));
  }
}

// Exporting the App class
export default App;
