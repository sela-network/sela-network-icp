import TrieMap "mo:base/TrieMap";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Time "mo:base/Time";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Int "mo:base/Int";

actor sock {
    // Initialize state inside actor
    private let CLIENT_MAP = TrieMap.TrieMap<Text, Nat>(Text.equal, Text.hash);

    type KeyClientTime = {
        key: Text;
        client_id: Text;
        time: Int;
    };

    type WebsocketMessage = {
        client_id: Text;
        sequence_num: Nat;
        timestamp: Int;
        message: Blob;
    };

    var MESSAGE_DELETE_QUEUE = Buffer.Buffer<KeyClientTime>(0);
    var NEXT_MESSAGE_NONCE : Nat = 0;

    // Function to register a new client
    public func register_client(client_id : Text) : async () {
        CLIENT_MAP.put(client_id, 0);
    };

    
    // Send a WebSocket message to the client
    public func send_message_from_canister(client_id : Text, msg : Blob) : async () {
        switch (CLIENT_MAP.get(client_id)) {
            case (?_) {}; // Client exists, continue
            case null {
                Debug.print("Client not registered: " # client_id);
                return;
            };
        };

        let time = Time.now();
        let key = client_id # "_" # Nat.toText(next_message_nonce());

        MESSAGE_DELETE_QUEUE.add({
            key = key;
            client_id = client_id;
            time = time;
        });

        let input : WebsocketMessage = {
            client_id = client_id;
            sequence_num = await next_client_message_num(client_id);
            timestamp = time;
            message = msg;
        };

        // Placeholder for the actual sending of the message (e.g., add to a message queue)
        Debug.print(debug_show(input));
    };

    // Helper function to get the next message nonce
    func next_message_nonce() : Nat {
        NEXT_MESSAGE_NONCE += 1;
        NEXT_MESSAGE_NONCE
    };

    // Helper function to get the next client message number (placeholder implementation)
    public func next_client_message_num(client_id : Text) : async Nat {
        switch (CLIENT_MAP.get(client_id)) {
            case (null) {
                CLIENT_MAP.put(client_id, 1);
                0
            };
            case (?num) {
                let next_num = num + 1;
                CLIENT_MAP.put(client_id, next_num);
                next_num
            };
        }
    };
}