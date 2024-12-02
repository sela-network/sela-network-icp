import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Sock "canister:sock";
import Result "mo:base/Result";
import Error "mo:base/Error";

actor canister {
    type AppMessage = {
        text : Text;
    };

    type WebsocketMessage = {
        client_id: Text;
        sequence_num: Nat;
        timestamp: Int;
        message: [Nat8];
    };

    public func handle_new_client(client_id : Text) : async Result.Result<Text, Text> {
        try {
            await Sock.register_client(client_id);
            let msg_array = Text.encodeUtf8("Client registered");
            await Sock.send_message_from_canister(client_id, msg_array);
            #ok("Client registered and initial message sent")
        } catch (e) {
            #err("Failed to register client: " # Error.message(e))
        }
    };

    public func ws_send_app_message(client_id : Text, msg : AppMessage) : async Result.Result<Text, Text> {
        try {
            let msg_array = Text.encodeUtf8(msg.text);
            await Sock.send_message_from_canister(client_id, msg_array);
            #ok("Message sent successfully")
        } catch (e) {
            #err("Failed to send message: " # Error.message(e))
        }
    };

    public func ws_on_open(client_id : Text) : async Result.Result<Text, Text> {
        let msg : AppMessage = {
            text = "ping";
        };
        await ws_send_app_message(client_id, msg)
    };

    public func ws_on_message(content : WebsocketMessage) : async Result.Result<Text, Text> {
        let message_blob = Blob.fromArray(content.message);
        switch (Text.decodeUtf8(message_blob)) {
            case (null) {
                Debug.print("Failed to decode message");
                #err("Failed to decode message")
            };
            case (?decoded_text) {
                let app_msg : AppMessage = { text = decoded_text };
                let new_msg : AppMessage = {
                    text = app_msg.text # " ping";
                };
                await ws_send_app_message(content.client_id, new_msg)
            };
        };
    };
};