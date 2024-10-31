import IcWebSocket, { generateRandomIdentity } from "ic-websocket-js";
import { createActor, backend } from "../../../declarations/backend"; 
import { HttpAgent } from '@dfinity/agent';

const gatewayUrl = "ws://127.0.0.1:8080";
const icUrl = "http://127.0.0.1:4943";

const identity = generateRandomIdentity();
console.log("Generated Identity:", identity);

// Create an actor instance
const agent = new HttpAgent({ identity });
const actor = createActor(process.env.BACKEND_CANISTER_ID, { agent });

export const ws = new IcWebSocket(gatewayUrl, undefined, {
  canisterId: process.env.BACKEND_CANISTER_ID,
  canisterActor: actor,
  identity: identity,
  networkUrl: icUrl,
});

let isConnected = false;
let messageQueue = [];

export const sendMessage = (message) => {
  if (isConnected) {
    ws.send({ message });
    console.log("Message sent:", message);
  } else {
    messageQueue.push({ message });
    console.log("Message queued:", message);
  }
};

ws.onopen = () => {
  console.log("WebSocket connection opened");
  isConnected = true;
  while (messageQueue.length > 0) {
    sendMessage(messageQueue.shift());
  }
};

ws.onclose = () => {
  console.log("WebSocket connection closed");
  isConnected = false;
};

ws.onerror = (error) => {
  console.error("WebSocket error:", error);
};

ws.onmessage = (event) => {
  try {
    console.log("message data: ", event.data)
    const receivedMessage = event.data;
    console.log("Received message:", receivedMessage);
  } catch (error) {
    console.error("Error receiving message:", error);
  }
};
