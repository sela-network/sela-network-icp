import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Crypto "ic:aaaaa-aa";
import Ed25519 "mo:ed25519";
import Sock "canister:sock";
import Canister "canister:webSocketCanister";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Types "mo:cbor/Types";
import Decoder "mo:cbor/Decoder";
import Iter "mo:base/Iter";

actor {
    // Type definitions
    public type WebsocketMessage = {
        clientId : Nat64;
        sequenceNum : Nat64;
        timestamp : Nat64;
        message : Blob;
    };

    public type EncodedMessage = {
        clientId : Nat64;
        key : Text;
        val : Blob;
    };

    public type CertMessages = {
        messages : [EncodedMessage];
        cert : [Nat8];
        tree : [Nat8];
    };

    // Type definition for FirstMessage
    public type FirstMessage = {
        clientId : Nat64;
        canisterId : Text;
    };

    // Type definition for ClientMessage
    public type ClientMessage = {
        val : Blob;
        sig : Blob;
    };

    // Debug method. Wipes all data in the canister.
    public func wsWipe() : async () {
        await Sock.wipe();
    };

    // Client submits its public key and gets a new client_id back.
    public shared (msg) func ws_register(publicKey : Blob) : async Nat64 {

        let clientId = await Sock.next_client_id();
        
        // Store the client key.
        await Sock.put_client_public_key(clientId, publicKey);
        
        // The identity (caller) used in this update call will be associated with this client_id. Remember this identity.
        await Sock.put_client_caller(clientId);

        clientId;
    };

    // A method for the gateway to get the client's public key and verify the signature of the first websocket message.
    public func ws_get_client_key(clientId : Nat64) : async Blob {
        let clientKeyOpt = await Sock.get_client_public_key(clientId);
        switch (clientKeyOpt) {
            case (?key) { key };
            case null { 
                // Handle error: client key not found
                Blob.fromArray([]);
            };
        }
    };

    // Open the websocket connection.
    public shared func ws_open(msg : Blob, sig : Blob) : async Bool {

        Debug.print("msg: " # debug_show (msg));
        Debug.print("sig: " # debug_show (sig));

        let decoded : FirstMessage = switch (Decoder.decode(msg)) {
            case (#ok(#majorType6 { value = #majorType5(fields) })) {
                var clientId : ?Nat64 = null;
                var canisterId : ?Text = null;

                for ((key, val) in fields.vals()) {
                    switch (key, val) {
                        case (#majorType3("client_id"), #majorType0(id)) {
                            clientId := ?id;
                        };
                        case (#majorType3("canister_id"), #majorType3(id)) {
                            canisterId := ?id;
                        };
                        case _ {};
                    };
                };

                switch (clientId, canisterId) {
                    case (?cId, ?cName) {
                        { clientId = cId; canisterId = cName };
                    };
                    case _ {
                        Debug.print("Missing or invalid client_id/canister_id");
                        return false;
                    };
                };
            };
            case _ {
                Debug.print("Invalid CBOR message format");
                return false;
            };
        };

        let clientId = decoded.clientId;
        let clientKey = switch (await Sock.get_client_public_key(clientId)) {
            case (?key) { key };
            case null { 
                // Handle error: client key not found
                return false;
            };
        };

        let publicKeyBytes = Blob.toArray(clientKey);
        let signatureBytes = Blob.toArray(sig);
        let messageBytes = Blob.toArray(msg);

        let valid = Ed25519.ED25519.verify(signatureBytes, messageBytes, publicKeyBytes);

        if (valid) {
            // Remember this gateway will get the messages for this client_id.
            await Sock.put_client_gateway(clientId);

            await Canister.ws_on_open(clientId);
            true
        } else {
            false
        }
    };

    // Close the websocket connection.
    public func ws_close(clientId : Nat64) : async () {
        await Sock.delete_client(clientId);
    };

    // Gateway calls this method to pass on the message from the client to the canister.
    public func ws_message(msg : Blob) : async Bool {
        let decoded = switch (from_candid(msg) : ?ClientMessage) {
            case (?value) { value };
            case null { 
                // Handle decoding error
                return false;
            };
        };

        let content = switch (from_candid(decoded.val) : ?WebsocketMessage) {
            case (?value) { value };
            case null { 
                // Handle decoding error
                return false;
            };
        };

        let clientId = content.clientId;

        // Verify the signature.
        let clientKey = switch (await Sock.get_client_public_key(clientId)) {
            case (?key) { key };
            case null { 
                // Handle error: client key not found
                return false;
            };
        };

        let publicKeyBytes = Blob.toArray(clientKey);
        let signatureBytes = Blob.toArray(decoded.sig);
        let messageBytes = Blob.toArray(decoded.val);

        let valid = Ed25519.ED25519.verify(signatureBytes, messageBytes, publicKeyBytes);

        if (valid) {
            // Verify the message sequence number.
            let clientIncomingNum = await Sock.get_client_incoming_num(clientId);
            if (content.sequenceNum == clientIncomingNum) {
                await Sock.put_client_incoming_num(clientId, content.sequenceNum + 1);
                // Create a new object with the expected structure
                let adjustedContent = {
                    client_id = content.clientId;
                    message = content.message;
                };
                
                await Canister.ws_on_message(adjustedContent);
                true
            } else {
                false
            }
        } else {
            false
        }
    };

    // Gateway polls this method to get messages for all the clients it serves.
    public func ws_get_messages(nonce : Nat64) : async CertMessages {
        await Sock.get_cert_messages(nonce);
    };
}