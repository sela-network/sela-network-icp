import Blob "mo:base/Blob";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Debug "mo:base/Debug";
import WebSocket "canister:sock";
import Decoder "mo:cbor/Decoder";
import Types "mo:cbor/Types";
import Encoder "mo:cbor/Encoder";
import Result "mo:base/Result";

actor {
    // Define the AppMessage type
    type AppMessage = {
        text : Text;
        data : Text;
        user_principal_id : Text;
        ws_type : Text;
    };

    // Define the WebsocketMessage type
    type WebsocketMessage = {
        client_id : Nat64;
        message : Blob;
    };

    // Function to handle WebSocket open event
    public func ws_on_open(client_id : Nat64, userPrincipalID : Text) : async Result.Result<Text, Text> {
        let msg = {
            text = "ping";
            data = "testdataping"; 
            user_principal_id = userPrincipalID;
            ws_type = "open";
        };
        let wsResponse = await ws_send_app_message(client_id, msg);
        Debug.print("wsResponse from ws_send_app_message in ws_on_open(): " # debug_show(wsResponse));
        switch (wsResponse) {
            case (#ok(jsonResponse)) {
                #ok(jsonResponse)  // Wrap response in #ok variant
            };
            case (#err(error)) {
                #err(error)
            };
        };
    };

    // Function to handle incoming WebSocket messages
    public func ws_on_message(content : WebsocketMessage) : async Result.Result<Text, Text> {
        Debug.print("message: " # debug_show (content.message));

        let decoded = switch (Decoder.decode(content.message)) {
            case (#ok(#majorType6 { value = #majorType5(fields) })) {
                var text : ?Text = null;
                var data : ?Text = null;
                var user_principal_id : ?Text = null;

                for ((key, value) in fields.vals()) {
                    switch (key, value) {
                        case (#majorType3("text"), #majorType3(t)) { text := ?t };
                        case (#majorType3("data"), #majorType3(d)) { data := ?d };
                        case (#majorType3("user_principal_id"), #majorType3(u)) { user_principal_id := ?u };
                        case _ {};
                    };
                };

                // Return both text and data in a tuple
                switch (text, data, user_principal_id) {
                    case (?t, ?d, ?u) { 
                        { text = t; data = d; user_principal_id = u } 
                    };
                    case _ {
                        Debug.print("Missing or invalid fields in AppMessage");
                        return #err("Missing or invalid fields in AppMessage");
                    };
                };
            };
            case _ {
                Debug.print("Invalid CBOR message format for AppMessage");
                return #err("Invalid CBOR message format for AppMessage");
            };
        };

        Debug.print("decoded data: " # debug_show(decoded.data));

        let new_msg : AppMessage = {
            text = decoded.text # " ping";
            data = decoded.data;  // Use the original data
            user_principal_id = decoded.user_principal_id;
            ws_type = "message";
        };
        Debug.print("Sending message: " # debug_show(new_msg));
        let wsResponse = await ws_send_app_message(content.client_id, new_msg);
        switch (wsResponse) {
            case (#ok(jsonResponse)) {
                #ok(jsonResponse)  // Wrap response in #ok variant
            };
            case (#err(error)) {
                #err(error)
            };
        };
    };

    // Function to send an AppMessage over WebSocket
    public func ws_send_app_message(client_id : Nat64, msg : AppMessage) : async Result.Result<Text, Text> {
        let cborValue : Types.Value = #majorType5([
            (#majorType3("text"), #majorType3(msg.text)),
            (#majorType3("data"), #majorType3(msg.data)),
            (#majorType3("user_principal_id"), #majorType3(msg.user_principal_id)),
            (#majorType3("ws_type"), #majorType3(msg.ws_type))
        ]);

        let msg_cbor = switch (Encoder.encode(cborValue)) {
            case (#ok(bytes)) { Blob.fromArray(bytes) };
            case (#err(e)) { 
                Debug.print("Error encoding CBOR: " # debug_show(e));
                return #err("Error encoding CBOR: " # debug_show(e));
            };
        };

        Debug.print("client_id: " # debug_show(client_id));
        Debug.print("msg: " # debug_show(msg));
        Debug.print("msg_cbor: " # debug_show(msg_cbor));

        let wsResponse = await WebSocket.send_message_from_canister(client_id, msg_cbor, msg.user_principal_id, msg.ws_type, msg.data);
        switch (wsResponse) {
            case (#ok(jsonResponse)) {
                #ok(jsonResponse)  // Wrap response in #ok variant
            };
            case (#err(error)) {
                #err(error)
            };
        };
    };
}
