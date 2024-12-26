import Blob "mo:base/Blob";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Ed25519 "mo:ed25519";
import Sock "canister:sock";
import Canister "canister:webSocketCanister";
import rpcCanister "canister:rpcCanister";
import Debug "mo:base/Debug";
import Decoder "mo:cbor/Decoder";
import Http "mo:http-parser";
import Error "mo:base/Error";
import JSON "mo:json/JSON";
import Int "mo:base/Int";
import Nat16 "mo:base/Nat16";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import DatabaseOps "../nodeCanister/modules/database_ops";
import HttpHandler "../nodeCanister/modules/http_handler";

actor {

    type HttpRequest = HttpHandler.HttpRequest;
    type HttpResponse = HttpHandler.HttpResponse;

    // Type definitions
    public type WebsocketMessage = {
        client_id : Nat64;
        sequence_num : Nat64;
        timestamp : Nat64;
        message : Blob;
    };

    public type EncodedMessage = {
        client_id : Nat64;
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
        client_id : Nat64;
        canister_id : Text;
        user_principal_id : Text;
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
    public shared func ws_register(publicKey : Blob) : async Nat64 {

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
    public shared func ws_open(msg : Blob, sig : Blob) : async Text {

        Debug.print("msg: " # debug_show (msg));
        Debug.print("sig: " # debug_show (sig));

        let decoded : FirstMessage = switch (Decoder.decode(msg)) {
            case (#ok(#majorType6 { value = #majorType5(fields) })) {
                var client_id : ?Nat64 = null;
                var canister_id : ?Text = null;
                var user_principal_id : ?Text = null;

                for ((key, val) in fields.vals()) {
                    switch (key, val) {
                        case (#majorType3("client_id"), #majorType0(id)) {
                            client_id := ?id;
                        };
                        case (#majorType3("canister_id"), #majorType3(id)) {
                            canister_id := ?id;
                        };
                        case (#majorType3("user_principal_id"), #majorType3(id)) {
                            user_principal_id := ?id;
                        };
                        case _ {};
                    };
                };

                switch (client_id, canister_id, user_principal_id) {
                    case (?cId, ?cName, ?uPrincipal) {
                        { client_id = cId; canister_id = cName; user_principal_id = uPrincipal };
                    };
                    case _ {
                        Debug.print("Missing or invalid client_id/canister_id/user_principal_id");
                        { 
                            client_id = 0;
                            canister_id = "Missing fields";
                            user_principal_id = "Missing fields"
                        };
                    };
                };
            };
            case _ {
                Debug.print("Invalid CBOR message format");
                { 
                    client_id = 0;
                    canister_id = "Invalid CBOR message format";
                    user_principal_id = "Invalid CBOR message format"
                }
            };
        };

        let client_id = decoded.client_id;
        let clientKey = switch (await Sock.get_client_public_key(client_id)) {
            case (?key) { key };
            case null { 
                Debug.print("Client key not found");
                // Return empty blob to indicate error
                Blob.fromArray([]);
            };
        };

        // Then check for empty blob
        if (Blob.toArray(clientKey).size() == 0) {
            return "{" #
                "\"status\": \"error\"," #
                "\"message\": \"Client key not found\"" #
            "}";
        };

        let userPrincipalID = decoded.user_principal_id;

        let publicKeyBytes = Blob.toArray(clientKey);
        let signatureBytes = Blob.toArray(sig);
        let messageBytes = Blob.toArray(msg);

        let valid = Ed25519.ED25519.verify(signatureBytes, messageBytes, publicKeyBytes);

        if (valid) {
            // Remember this gateway will get the messages for this client_id.
            await Sock.put_client_gateway(client_id);

             let canisterResponse = await Canister.ws_on_open(client_id, userPrincipalID);
             switch (canisterResponse) {
                case (#ok(jsonResponse)) {
                    jsonResponse  // Pass through the JSON response directly
                };
                case (#err(error)) {
                    "{" #
                        "\"status\": \"error\"," #
                        "\"message\": \"" # error # "\"" #
                    "}"
                };
            };
        } else {
            "{" #
                "\"status\": \"error\"," #
            "}"
        }
    };

    // Close the websocket connection.
    public func ws_close(clientId : Nat64) : async () {
        await Sock.delete_client(clientId);
    };

    public func requestAuth(client_id: Nat64) : async Bool {
        
        let rpcCanisterIdPrincipal = await rpcCanister.getRpcCanisterID();
        let rpcCanisterID = Principal.toText(rpcCanisterIdPrincipal);
        let rpcCanisterIDURL = rpcCanisterID # ".localhost:4943";
        Debug.print("rpcCanisterID: " # rpcCanisterID);
        
        let url = "http://" # rpcCanisterIDURL # "/requestAuth" # "&requestMethod=requestAuth";
        let headers = Http.Headers([("Authorization", Nat64.toText(client_id))]);

        let request : Http.HttpRequest = {
            url = url;
            method = "GET";
            headers = headers.original;
            body = "";
        };

        let ic : actor {
            http_request_update : Http.HttpRequest -> async Http.HttpResponse;
        } = actor (rpcCanisterID);

        try {
            let response = await ic.http_request_update(request);
            
            switch (Text.decodeUtf8(response.body)) {
                case (?body) {
                    Debug.print("Response body: " # body);
                    return true;
                };
                case null {
                    return false;
                };
            };
        } catch (error) {
            let errorMessage = Error.message(error);
            Debug.print("Error calling target canister: " # errorMessage);
            return false;
        };
    };

    public func responseAuth() : async Bool {
        let rpcCanisterIdPrincipal = await rpcCanister.getRpcCanisterID();
        let rpcCanisterID = Principal.toText(rpcCanisterIdPrincipal);
        let rpcCanisterIDURL = rpcCanisterID # ".localhost:4943";
        Debug.print("rpcCanisterID: " # rpcCanisterID);
        //call RPC canister via http request
        let url = "http://" # rpcCanisterIDURL # "/responseAuth" # "&requestMethod=responseAuth";
        let headers = Http.Headers([("Authorization", "success")]);

        // Prepare the HTTP request (method GET, URL, headers)
        let request : Http.HttpRequest = {
            url = url;
            method = "GET";
            headers = headers.original;
            body = "";
        };

        let ic : actor {
            http_request_update : Http.HttpRequest -> async Http.HttpResponse;
        } = actor (rpcCanisterID);

        try {
            let response = await ic.http_request_update(request);
            
            // Check if the status code is 200 (OK)
            if (response.status_code == 200) {
                switch (Text.decodeUtf8(response.body)) {
                    case (?body) {
                        Debug.print("Response body: " # body);
                        
                        // Parse the JSON body
                        switch (JSON.parse(body)) {
                            case (?parsed) {
                                switch (parsed) {
                                    case (#Object(fields)) {
                                        for ((key, value) in fields.vals()) {
                                            if (key == "status" and value == #String("OK")) {
                                                return true;
                                            };
                                        };
                                    };
                                    case _ {};
                                };
                            };
                            case null {
                                Debug.print("Failed to parse JSON response");
                            };
                        };
                    };
                    case null {
                        Debug.print("Failed to decode response body");
                    };
                };
            } else {
                Debug.print("HTTP status code is not 200: " # Nat.toText(Nat16.toNat(response.status_code)));
            };
        } catch (error) {
            let errorMessage = Error.message(error);
            Debug.print("Error calling target canister: " # errorMessage);
        };

        return false;
    };

    // Gateway calls this method to pass on the message from the client to the canister.
    public func ws_message(msg : Blob) : async Text {
        Debug.print("Inside ws_message(), msg: " # debug_show (msg));

        let decoded : ClientMessage = switch (Decoder.decode(msg)) {
            case (#ok(#majorType6 { value = #majorType5(fields) })) {
                var val : ?Blob = null;
                var sig : ?Blob = null;

                for ((key, value) in fields.vals()) {
                    switch (key, value) {
                        case (#majorType3("val"), #majorType2(v)) { val := ?Blob.fromArray(v) };
                        case (#majorType3("sig"), #majorType2(s)) { sig := ?Blob.fromArray(s) };
                        case _ {};
                    };
                };

                switch (val, sig) {
                    case (?v, ?s) { { val = v; sig = s } };
                    case _ {
                        Debug.print("Missing or invalid val/sig in ClientMessage");
                        return "{" #
                            "\"status\": \"error\"," #
                            "\"message\": \"Missing or invalid val/sig in ClientMessage\"" #
                        "}";
                    };
                };
            };
            case _ {
                Debug.print("Invalid CBOR message format for ClientMessage");
                return "{" #
                    "\"status\": \"error\"," #
                    "\"message\": \"Invalid CBOR message format for ClientMessage\"" #
                "}";
            };
        };

        let content : WebsocketMessage = switch (Decoder.decode(decoded.val)) {
            case (#ok(#majorType6 { value = #majorType5(fields) })) {
                var client_id : ?Nat64 = null;
                var sequence_num : ?Nat64 = null;
                var timestamp : ?Nat64 = null;
                var message : ?Blob = null;

                for ((key, value) in fields.vals()) {
                    switch (key, value) {
                        case (#majorType3("client_id"), #majorType0(id)) { 
                            client_id := ?id;
                        };
                        case (#majorType3("sequence_num"), #majorType0(num)) { 
                            sequence_num := ?num;
                        };
                        case (#majorType3("timestamp"), #majorType0(ts)) { 
                            timestamp := ?ts;
                        };
                        case (#majorType3("message"), #majorType2(msg)) { 
                            message := ?Blob.fromArray(msg);
                        };
                        case _ {};
                    };
                };

                switch (client_id, sequence_num, timestamp, message) {
                    case (?cId, ?sNum, ?ts, ?msg) { 
                        { 
                            client_id = cId;
                            sequence_num = sNum;
                            timestamp = ts;
                            message = msg;
                        };
                    };
                    case _ {
                        Debug.print("Missing or invalid fields in WebsocketMessage");
                        return "{" #
                            "\"status\": \"error\"," #
                            "\"message\": \"Missing or invalid fields in WebsocketMessage\"" #
                        "}";
                    };
                };
            };
            case _ {
                Debug.print("Invalid CBOR message format for WebsocketMessage");
                return "{" #
                    "\"status\": \"error\"," #
                    "\"message\": \"Invalid CBOR message format for WebsocketMessage\"" #
                "}";
            };
        };

        let clientId = content.client_id;

        let checkAuth = await requestAuth(clientId);
        if (checkAuth){
            Debug.print("requestAuth() success");
            // Verify the signature
            let clientKey = switch (await Sock.get_client_public_key(clientId)) {
                case (?key) { key };
                case null { 
                    Debug.print("Client key not found");
                    return "{" #
                        "\"status\": \"error\"," #
                        "\"message\": \"Client key not found\"" #
                    "}";
                };
            };

            let publicKeyBytes = Blob.toArray(clientKey);
            let signatureBytes = Blob.toArray(decoded.sig);
            let messageBytes = Blob.toArray(decoded.val);

            let valid = Ed25519.ED25519.verify(signatureBytes, messageBytes, publicKeyBytes);

            if (valid) {
                // Verify the message sequence number
                let clientIncomingNum = await Sock.get_client_incoming_num(clientId);
                if (content.sequence_num == clientIncomingNum) {
                    await Sock.put_client_incoming_num(clientId, content.sequence_num + 1);
                    
                    // Create a new object with the expected structure
                    let adjustedContent = {
                        client_id = content.client_id;
                        message = content.message;
                    };

                    let checkForResponseAuth = await responseAuth();
                    if (checkForResponseAuth) {
                        Debug.print("Response Authentication Success");
                        let canisterResponse = await Canister.ws_on_message(adjustedContent);
                        switch (canisterResponse) {
                            case (#ok(jsonResponse)) {
                                jsonResponse;  // Pass through the JSON response directly
                            };
                            case (#err(error)) {
                                "{" #
                                    "\"status\": \"error\"," #
                                    "\"message\": \"" # error # "\"" #
                                "}";
                            };
                        };
                    } else {
                        Debug.print("Response Authentication failed");
                        "{" #
                            "\"status\": \"error\"," #
                            "\"message\": \"Response Authentication failed\"" #
                        "}";
                    };
                } else {
                    Debug.print("Invalid sequence number");
                    "{" #
                        "\"status\": \"error\"," #
                        "\"message\": \"Invalid sequence number\"" #
                    "}";
                };
            } else {
                Debug.print("Signature verification failed");
                "{" #
                    "\"status\": \"error\"," #
                    "\"message\": \"Signature verification failed\"" #
                "}";
            };
        }else{
            Debug.print("Authentication failed");
            "{" #
                "\"status\": \"error\"," #
                "\"message\": \"Authentication failed\"" #
            "}";
        }
    };

    // Gateway polls this method to get messages for all the clients it serves.
    public func ws_get_messages(nonce : Nat64) : async CertMessages {
        Debug.print("ws_get_messages called with nonce: " # debug_show(nonce));
        let response = await Sock.get_cert_messages(nonce);
        Debug.print("Response from Sock: " # debug_show(response));
        
        // Convert Blob fields to [Nat8]
        {
            messages = response.messages;
            cert = Blob.toArray(response.cert);
            tree = Blob.toArray(response.tree);
        }
    };
}