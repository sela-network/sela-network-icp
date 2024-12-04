import Blob "mo:base/Blob";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import WebSocket "canister:sock";

actor {
    // Define the AppMessage type
    type AppMessage = {
        text : Text;
    };

    // Define the WebsocketMessage type
    type WebsocketMessage = {
        client_id : Nat64;
        message : Blob;
    };

    // Function to handle WebSocket open event
    public func ws_on_open(client_id : Nat64) : async () {
        let msg = {
            text = "ping";
        };
        await ws_send_app_message(client_id, msg);
    };

    // Function to handle incoming WebSocket messages
    public func ws_on_message(content : WebsocketMessage) : async () {
        switch (from_candid(content.message) : ?AppMessage) {
            case (?app_msg) {
                let new_msg : AppMessage = {
                    text = app_msg.text # " ping";
                };
                await ws_send_app_message(content.client_id, new_msg);
            };
            case null {
                Debug.print("Error decoding message");
            };
        };
    };

    // Function to send an AppMessage over WebSocket
    public func ws_send_app_message(client_id : Nat64, msg : AppMessage) : async () {
        let msg_candid = to_candid(msg);
        await WebSocket.send_message_from_canister(client_id, msg_candid);
    };
}