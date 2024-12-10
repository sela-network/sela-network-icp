import Blob "mo:base/Blob";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Debug "mo:base/Debug";
import WebSocket "canister:sock";
import Decoder "mo:cbor/Decoder";
import Types "mo:cbor/Types";
import Encoder "mo:cbor/Encoder";

actor {
    // Define the AppMessage type
    type AppMessage = {
        text : Text;
        data : Text;
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
            data = "testdataping";  
        };
        await ws_send_app_message(client_id, msg);
    };

    // Function to handle incoming WebSocket messages
    public func ws_on_message(content : WebsocketMessage) : async () {
        Debug.print("message: " # debug_show (content.message));

        let decoded = switch (Decoder.decode(content.message)) {
            case (#ok(#majorType6 { value = #majorType5(fields) })) {
                var text : ?Text = null;
                var data : ?Text = null;

                for ((key, value) in fields.vals()) {
                    switch (key, value) {
                        case (#majorType3("text"), #majorType3(t)) { text := ?t };
                        case (#majorType3("data"), #majorType3(d)) { data := ?d };
                        case _ {};
                    };
                };

                // Return both text and data in a tuple
                switch (text, data) {
                    case (?t, ?d) { 
                        { text = t; data = d } 
                    };
                    case _ {
                        Debug.print("Missing or invalid fields in AppMessage");
                        return;
                    };
                };
            };
            case _ {
                Debug.print("Invalid CBOR message format for AppMessage");
                return;
            };
        };

        let new_msg : AppMessage = {
            text = decoded.text # " ping";
            data = decoded.data;  // Use the original data
        };
        Debug.print("Sending message: " # debug_show(new_msg));
        await ws_send_app_message(content.client_id, new_msg);
    };

    // Function to send an AppMessage over WebSocket
    public func ws_send_app_message(client_id : Nat64, msg : AppMessage) : async () {
        let cborValue : Types.Value = #majorType5([
            (#majorType3("text"), #majorType3(msg.text)),
            (#majorType3("data"), #majorType3(msg.data))
        ]);

        let msg_cbor = switch (Encoder.encode(cborValue)) {
            case (#ok(bytes)) { Blob.fromArray(bytes) };
            case (#err(e)) { 
                Debug.print("Error encoding CBOR: " # debug_show(e));
                return; // Exit the function if encoding fails
            };
        };

        Debug.print("client_id: " # debug_show(client_id));
        Debug.print("msg: " # debug_show(msg));
        Debug.print("msg_cbor: " # debug_show(msg_cbor));

        await WebSocket.send_message_from_canister(client_id, msg_cbor);
    };
}