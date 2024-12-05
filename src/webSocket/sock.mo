import Principal "mo:base/Principal";
import TrieMap "mo:base/TrieMap";
import Time "mo:base/Time";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Buffer "mo:base/Buffer";
import CertifiedData "mo:base/CertifiedData";
import Hash "mo:base/Hash";
import Option "mo:base/Option";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import SHA256 "mo:sha2/SHA256";
import Encoder "mo:cbor/Encoder";
import Decoder "mo:cbor/Decoder";
import Types "mo:cbor/Types";
import Debug "mo:base/Debug";

actor {
    let LABEL_WEBSOCKET : [Nat8] = [119, 101, 98, 115, 111, 99, 107, 101, 116]; // "websocket" in ASCII
    let MSG_TIMEOUT : Nat64 = 5 * 60 * 1000000000; // 5 minutes in nanoseconds
    let MAX_NUMBER_OF_RETURNED_MESSAGES : Nat = 50;
    private let CERT_TREE = TrieMap.TrieMap<Text, Blob>(Text.equal, Text.hash);

    type PublicKey = Blob;

    type KeyGatewayTime = {
        key : Text;
        gateway : Text;
        time : Nat64;
    };

    type CertMessages = {
        messages : [EncodedMessage];
        cert : [Nat8];
        tree : [Nat8];
    };

    type EncodedMessage = {
        client_id : Nat64;
        key : Text;
        val : Blob;
    };

    type WebsocketMessage = {
        client_id : Nat64;
        sequence_num : Nat64;
        timestamp : Nat64;
        message : Blob;
    };

    var nextClientId : Nat64 = 16;
    var nextMessageNonce : Nat64 = 16;

    // Custom hash function for Nat64
    private func hashNat64(n : Nat64) : Hash.Hash {
        let bytes : [Nat8] = [
            Nat8.fromNat(Nat64.toNat((n >> 56) & 255)),
            Nat8.fromNat(Nat64.toNat((n >> 48) & 255)),
            Nat8.fromNat(Nat64.toNat((n >> 40) & 255)),
            Nat8.fromNat(Nat64.toNat((n >> 32) & 255)),
            Nat8.fromNat(Nat64.toNat((n >> 24) & 255)),
            Nat8.fromNat(Nat64.toNat((n >> 16) & 255)),
            Nat8.fromNat(Nat64.toNat((n >> 8) & 255)),
            Nat8.fromNat(Nat64.toNat(n & 255))
        ];
        var hash : Nat32 = 5381;
        for (byte in bytes.vals()) {
            hash := ((hash << 5) +% hash) +% Nat32.fromNat(Nat8.toNat(byte));
        };
        hash
    };

    private var clientCallerMap : TrieMap.TrieMap<Nat64, Text> = TrieMap.TrieMap<Nat64, Text>(Nat64.equal, hashNat64);
    private var clientPublicKeyMap : TrieMap.TrieMap<Nat64, PublicKey> = TrieMap.TrieMap<Nat64, PublicKey>(Nat64.equal, hashNat64);
    private var clientGatewayMap : TrieMap.TrieMap<Nat64, Text> = TrieMap.TrieMap<Nat64, Text>(Nat64.equal, hashNat64);
    private var clientMessageNumMap : TrieMap.TrieMap<Nat64, Nat64> = TrieMap.TrieMap<Nat64, Nat64>(Nat64.equal, hashNat64);
    private var clientIncomingNumMap : TrieMap.TrieMap<Nat64, Nat64> = TrieMap.TrieMap<Nat64, Nat64>(Nat64.equal, hashNat64);
    private var GATEWAY_MESSAGES_MAP : TrieMap.TrieMap<Text, Blob> = TrieMap.TrieMap<Text, Blob>(Text.equal, Text.hash);
    private var MESSAGE_DELETE_QUEUE : TrieMap.TrieMap<Text, KeyGatewayTime> = TrieMap.TrieMap<Text, KeyGatewayTime>(Text.equal, Text.hash);

    // Note: Certification in Motoko is handled differently, so we don't need an exact equivalent of CERT_TREE

    public func wipe() : async () {
        nextClientId := 16;
        nextMessageNonce := 16;
        clientCallerMap := TrieMap.TrieMap<Nat64, Text>(Nat64.equal, hashNat64);
        clientPublicKeyMap := TrieMap.TrieMap<Nat64, PublicKey>(Nat64.equal, hashNat64);
        clientGatewayMap := TrieMap.TrieMap<Nat64, Text>(Nat64.equal, hashNat64);
        clientMessageNumMap := TrieMap.TrieMap<Nat64, Nat64>(Nat64.equal, hashNat64);
        clientIncomingNumMap := TrieMap.TrieMap<Nat64, Nat64>(Nat64.equal, hashNat64);
        GATEWAY_MESSAGES_MAP := TrieMap.TrieMap<Text, Blob>(Text.equal, Text.hash);
        MESSAGE_DELETE_QUEUE := TrieMap.TrieMap<Text, KeyGatewayTime>(Text.equal, Text.hash);
        // Reset certified data
        CertifiedData.set(Blob.fromArray([]));
    };

    public func next_client_id() : async Nat64 {
        nextClientId += 1;
        nextClientId - 1
    };

    public func next_message_nonce() : async Nat64 {
        nextMessageNonce += 1;
        nextMessageNonce - 1
    };

    public func put_client_public_key(clientId : Nat64, clientKey : PublicKey) : async () {
        clientPublicKeyMap.put(clientId, clientKey);
    };

    public func get_client_public_key(clientId : Nat64) : async ?PublicKey {
        clientPublicKeyMap.get(clientId)
    };

    public shared(msg) func put_client_caller(clientId : Nat64) : async () {
        clientCallerMap.put(clientId, Principal.toText(msg.caller));
    };

    public shared(msg) func put_client_gateway(clientId : Nat64) : async () {
        clientGatewayMap.put(clientId, Principal.toText(msg.caller));
    };

    public func get_client_gateway(clientId : Nat64) : async ?Text {
        clientGatewayMap.get(clientId)
    };

    public func next_client_message_num(clientId : Nat64) : async Nat64 {
        switch (clientMessageNumMap.get(clientId)) {
            case (null) {
                clientMessageNumMap.put(clientId, 0);
                0
            };
            case (?num) {
                let nextNum = num + 1;
                clientMessageNumMap.put(clientId, nextNum);
                nextNum
            };
        }
    };

    public func get_client_incoming_num(clientId : Nat64) : async Nat64 {
        switch (clientIncomingNumMap.get(clientId)) {
            case (null) { 0 };
            case (?num) { num };
        }
    };

    public func put_client_incoming_num(clientId : Nat64, num : Nat64) : async () {
        clientIncomingNumMap.put(clientId, num);
    };

    public func delete_client(clientId : Nat64) : async () {
        clientCallerMap.delete(clientId);
        clientPublicKeyMap.delete(clientId);
        clientGatewayMap.delete(clientId);
        clientMessageNumMap.delete(clientId);
        clientIncomingNumMap.delete(clientId);
    };

   public shared(msg) func get_cert_messages(nonce : Nat64) : async CertMessages {
        let gateway = Principal.toText(msg.caller);
        
        // Get or create gateway messages
        let gatewayMessages : [EncodedMessage] = switch (GATEWAY_MESSAGES_MAP.get(gateway)) {
            case null { [] };
            case (?messagesBlob) {
                switch (Decoder.decode(messagesBlob)) {
                    case (#ok(#majorType4(values))) {
                        Array.mapFilter<Types.Value, EncodedMessage>(values, decodeEncodedMessage);
                    };
                    case _ { [] };
                };
            };
        };

        let smallestKey = gateway # "_" # padLeft(Nat64.toText(nonce), '0', 20);
        
        // Find start index
        let startIndex = Array.foldLeft<EncodedMessage, Nat>(
            gatewayMessages, 
            0, 
            func(acc, x) { if (x.key < smallestKey) { acc + 1 } else { acc } }
        );

        // Calculate end index
        let endIndex = Nat.min(
            startIndex + MAX_NUMBER_OF_RETURNED_MESSAGES,
            gatewayMessages.size()
        );

        // Get messages slice
        let messages : [EncodedMessage] = Array.subArray<EncodedMessage>(
            gatewayMessages, 
            startIndex, 
            endIndex - startIndex
        );

        Debug.print("Messages to return: " # debug_show(messages));

        // Return CertMessages structure
        if (messages.size() > 0) {
            let firstKey = messages[0].key;
            let lastKey = messages[messages.size() - 1].key;
            let (cert, tree) = await get_cert_for_range(firstKey, lastKey);
            {
                messages = Array.map<EncodedMessage, EncodedMessage>(
                    messages,
                    func(m) : EncodedMessage {
                        {
                            client_id = m.client_id;
                            key = m.key;
                            val = m.val;
                        }
                    }
                );
                cert = Blob.toArray(cert);
                tree = Blob.toArray(tree);
            }
        } else {
            {
                messages = [];
                cert = [];
                tree = [];
            }
        }
    };

    private func delete_message(messageInfo : KeyGatewayTime) {
        switch (GATEWAY_MESSAGES_MAP.get(messageInfo.gateway)) {
            case (?existingBlob) {
                // Decode existing messages
                let existingMessages = switch (Decoder.decode(existingBlob)) {
                    case (#ok(#majorType4(values))) {
                        Array.mapFilter<Types.Value, EncodedMessage>(values, decodeEncodedMessage);
                    };
                    case _ { [] };
                };

                // Remove the first message if there are any
                if (existingMessages.size() > 0) {
                    let updatedMessages = Array.subArray(existingMessages, 1, existingMessages.size() - 1);

                    // Encode updated messages using the encodeCBORMessages helper function
                    let cborValue = encodeCBORMessages(updatedMessages);

                    switch (Encoder.encode(cborValue)) {
                        case (#ok(bytes)) {
                            GATEWAY_MESSAGES_MAP.put(messageInfo.gateway, Blob.fromArray(bytes));
                        };
                        case (#err(e)) {
                            Debug.print("Error encoding CBOR: " # debug_show(e));
                        };
                    };
                };
            };
            case null { /* Do nothing */ };
        };
        CERT_TREE.delete(messageInfo.key);
    };

    public func send_message_from_canister(client_id : Nat64, msg : Blob) : async () {
        let gateway = switch (await get_client_gateway(client_id)) {
            case null { return };
            case (?gw) { gw };
        };

        let time = Time.now();
        nextMessageNonce += 1;
        let key = gateway # "_" # padLeft(Nat64.toText(nextMessageNonce), '0', 20);

        // Add to message delete queue and cleanup old messages
        let queueItem : KeyGatewayTime = {
            key = key;
            gateway = gateway;
            time = Nat64.fromNat(Int.abs(time));
        };
        MESSAGE_DELETE_QUEUE.put(key, queueItem);

        // Check and cleanup old messages (similar to Rust's front check)
        let currentTime = Nat64.fromNat(Int.abs(time));
        for ((_, item) in MESSAGE_DELETE_QUEUE.entries()) {
            if (currentTime - item.time > MSG_TIMEOUT) {
                delete_message(item);
                MESSAGE_DELETE_QUEUE.delete(item.key);
            };
        };

        let input : WebsocketMessage = {
            client_id = client_id;
            sequence_num = await next_client_message_num(client_id);
            timestamp = Nat64.fromNat(Int.abs(time));
            message = msg;
        };

        let cborValue = encodeCBORWebsocketMessage(input);
        let data = switch (Encoder.encode(cborValue)) {
            case (#ok(bytes)) { Blob.fromArray(bytes) };
            case (#err(e)) { 
                Debug.print("Error encoding CBOR: " # debug_show(e));
                return;
            };
        };

        await put_cert_for_message(key, data);

        // Update GATEWAY_MESSAGES_MAP
        switch (GATEWAY_MESSAGES_MAP.get(gateway)) {
            case null {
                let messages = [{
                    client_id = client_id;
                    key = key;
                    val = data;
                }];
                let cborValue = encodeCBORMessages(messages);
                switch (Encoder.encode(cborValue)) {
                    case (#ok(bytes)) {
                        GATEWAY_MESSAGES_MAP.put(gateway, Blob.fromArray(bytes));
                    };
                    case (#err(e)) {
                        Debug.print("Error encoding CBOR: " # debug_show(e));
                        return;
                    };
                };
            };
            case (?existingBlob) {
                let existingMessages = switch (Decoder.decode(existingBlob)) {
                    case (#ok(#majorType4(values))) {
                        Array.mapFilter<Types.Value, EncodedMessage>(values, decodeEncodedMessage);
                    };
                    case _ { [] };
                };
                
                let updatedMessages = Array.append(existingMessages, [{
                    client_id = client_id;
                    key = key;
                    val = data;
                }]);
                
                let cborValue = encodeCBORMessages(updatedMessages);
                switch (Encoder.encode(cborValue)) {
                    case (#ok(bytes)) {
                        GATEWAY_MESSAGES_MAP.put(gateway, Blob.fromArray(bytes));
                    };
                    case (#err(e)) {
                        Debug.print("Error encoding CBOR: " # debug_show(e));
                        return;
                    };
                };
            };
        };
    };

    public func put_cert_for_message(key : Text, value : Blob) : async () {
        Debug.print("put_cert_for_message");
        Debug.print("key: " # key);
        Debug.print("value: " # debug_show (value));
        let hash = SHA256.fromBlob(#sha256, value);
        
        CERT_TREE.put(key, hash);
        
        let rootHash = labeledHash(LABEL_WEBSOCKET, treeRootHash());
        CertifiedData.set(rootHash);
    };

    public func get_cert_for_message(key : Text) : async (Blob, Blob) {
        let witness = createWitness(key);
        let tree = labeled(LABEL_WEBSOCKET, witness);
        
        // CBOR encoding of the blob
        let cborTree = encodeCBORBlob(tree);
        
        let treeBlob = switch (Encoder.encode(cborTree)) {
            case (#ok(bytes)) { Blob.fromArray(bytes) };
            case (#err(e)) { 
                Debug.print("Error encoding CBOR tree: " # debug_show(e));
                Blob.fromArray([]); // Return an empty Blob in case of error
            };
        };

        switch (CertifiedData.getCertificate()) {
            case (?cert) {
                (cert, treeBlob)
            };
            case null {
                // Handle the case where no certificate is available
                (Blob.fromArray([]), treeBlob)
            };
        }
    };

    public func get_cert_for_range(first : Text, last : Text) : async (Blob, Blob) {
        let witness = createRangeWitness(first, last);
        let tree = labeled(LABEL_WEBSOCKET, witness);
        
        // CBOR encoding of the tree
        let cborTree = encodeCBORBlob(tree);
        
        let treeBlob = switch (Encoder.encode(cborTree)) {
            case (#ok(bytes)) { Blob.fromArray(bytes) };
            case (#err(e)) { 
                Debug.print("Error encoding CBOR tree: " # debug_show(e));
                Blob.fromArray([]); // Return an empty Blob in case of error
            };
        };
        
        switch (CertifiedData.getCertificate()) {
            case (?cert) {
                (cert, treeBlob)
            };
            case null {
                // Handle the case where no certificate is available
                // You might want to return an empty Blob or handle this case differently
                (Blob.fromArray([]), treeBlob)
            };
        }
    };

    // Helper functions
    private func labeledHash(labelData : [Nat8], data : Blob) : Blob {
        let combined = Array.append(labelData, Blob.toArray(data));
        SHA256.fromArray(#sha256, combined)
    };

    private func treeRootHash() : Blob {
        let allHashes = Array.map<(Text, Blob), Blob>(
            Iter.toArray(CERT_TREE.entries()), 
            func((_, v)) { v }
        );
        SHA256.fromArray(#sha256, Array.flatten(Array.map(allHashes, Blob.toArray)))
    };

    private func createWitness(key : Text) : Blob {
        let buffer = Buffer.Buffer<Nat8>(0);
        
        // Add the key-value pair
        addKeyValueToBuffer(buffer, key, CERT_TREE.get(key));
        
        // Add the proof for other branches
        for ((k, v) in CERT_TREE.entries()) {
            if (k != key) {
                addHashToBuffer(buffer, textToHash(k));
            };
        };
        
        Blob.fromArray(Buffer.toArray(buffer))
    };

    private func createRangeWitness(first : Text, last : Text) : Blob {
        let buffer = Buffer.Buffer<Nat8>(0);
        
        // Add all key-value pairs in the range
        for ((k, v) in CERT_TREE.entries()) {
            if (k >= first and k <= last) {
                addKeyValueToBuffer(buffer, k, ?v);
            } else {
                addHashToBuffer(buffer, textToHash(k));
            };
        };
        
        Blob.fromArray(Buffer.toArray(buffer))
    };

    private func labeled(labelData : [Nat8], data : Blob) : Blob {
        let buffer = Buffer.Buffer<Nat8>(0);
        
        // Add labelData length (as a single byte)
        buffer.add(Nat8.fromNat(labelData.size()));
        
        // Add labelData
        for (byte in labelData.vals()) {
            buffer.add(byte);
        };
        
        // Add data
        for (byte in Blob.toArray(data).vals()) {
            buffer.add(byte);
        };
        
        Blob.fromArray(Buffer.toArray(buffer))
    };

    // Helper functions
    private func addKeyValueToBuffer(buffer : Buffer.Buffer<Nat8>, key : Text, value : ?Blob) {
        // Add key length (as a 16-bit big-endian integer)
        let keyBytes = Text.encodeUtf8(key);
        let keySize = Nat32.fromNat(keyBytes.size());
        buffer.add(Nat8.fromNat(Nat32.toNat((keySize >> 8) & 0xFF)));
        buffer.add(Nat8.fromNat(Nat32.toNat(keySize & 0xFF)));
        
        // Add key
        for (byte in keyBytes.vals()) {
            buffer.add(byte);
        };
        
        // Add value or empty hash if value is null
        switch (value) {
            case (?v) {
                for (byte in Blob.toArray(v).vals()) {
                    buffer.add(byte);
                };
            };
            case null {
                for (byte in Array.freeze(Array.init<Nat8>(32, 0)).vals()) {
                    buffer.add(byte);
                };
            };
        };
    };

    private func addHashToBuffer(buffer : Buffer.Buffer<Nat8>, hash : [Nat8]) {
        for (byte in hash.vals()) {
            buffer.add(byte);
        };
    };

    private func textToHash(text : Text) : [Nat8] {
        Blob.toArray(SHA256.fromBlob(#sha256, Text.encodeUtf8(text)))
    };

    private func padLeft(text : Text, pad : Char, len : Nat) : Text {
        let textLen = Text.size(text);
        if (textLen >= len) {
            return text;
        };
        let padLen = len - textLen;
        let padText = Text.join("", Iter.map(Iter.range(0, padLen - 1), func(_ : Nat) : Text { Text.fromChar(pad) }));
        padText # text
    };

    type Tree = {
        #empty;
        #pruned : [Nat8];
        #fork : (Tree, Tree);
        #labeled : (Text, Tree);
        #leaf : [Nat8];
    };

    // Helper function to encode a Blob to CBOR
    func encodeCBORBlob(blob : Blob) : Types.Value {
        #majorType2(Blob.toArray(blob))
    };

    // Helper function to decode a single EncodedMessage from CBOR
    func decodeEncodedMessage(value : Types.Value) : ?EncodedMessage {
        switch (value) {
            case (#majorType5(fields)) {
                var client_id : ?Nat64 = null;
                var key : ?Text = null;
                var val : ?Blob = null;

                for ((k, v) in fields.vals()) {
                    switch (k, v) {
                        case (#majorType3("client_id"), #majorType0(id)) { 
                            // Convert from Nat to Nat64 during decoding
                            client_id := ?id;
                        };
                        case (#majorType3("key"), #majorType3(k)) { 
                            key := ?k 
                        };
                        case (#majorType3("val"), #majorType2(v)) { 
                            val := ?Blob.fromArray(v) 
                        };
                        case _ {};
                    };
                };

                switch (client_id, key, val) {
                    case (?cId, ?k, ?v) { 
                        ?{ 
                            client_id = cId;  // Now cId is already Nat64
                            key = k; 
                            val = v 
                        } 
                    };
                    case _ { null };
                };
            };
            case _ { null };
        };
    };
    // Helper function to encode EncodedMessage array to CBOR
    func encodeCBORMessages(messages : [EncodedMessage]) : Types.Value {
        #majorType4(Array.map(messages, func (m : EncodedMessage) : Types.Value {
            #majorType5([
                (#majorType3("client_id"), #majorType0(m.client_id)),  // Remove Nat64.toNat conversion
                (#majorType3("key"), #majorType3(m.key)),
                (#majorType3("val"), #majorType2(Blob.toArray(m.val)))
            ])
        }))
    };

    private func encodeCBORWebsocketMessage(msg : WebsocketMessage) : Types.Value {
        #majorType5([
            (#majorType3("client_id"), #majorType0(msg.client_id)),  // Use msg.clientId directly
            (#majorType3("sequence_num"), #majorType0(msg.sequence_num)),  // Use msg.sequence_num directly
            (#majorType3("timestamp"), #majorType0(msg.timestamp)),  // Use msg.timestamp directly
            (#majorType3("message"), #majorType2(Blob.toArray(msg.message)))
        ])
    };

    private func encodeKeyGatewayTime(kgt : KeyGatewayTime) : Types.Value {
        #majorType5([
            (#majorType3("key"), #majorType3(kgt.key)),
            (#majorType3("gateway"), #majorType3(kgt.gateway)),
            (#majorType3("time"), #majorType0(kgt.time))
        ])
    };

    private func decodeKeyGatewayTime(value : Types.Value) : ?KeyGatewayTime {
        switch (value) {
            case (#majorType5(fields)) {
                var key : ?Text = null;
                var gateway : ?Text = null;
                var time : ?Nat64 = null;

                for ((k, v) in fields.vals()) {
                    switch (k, v) {
                        case (#majorType3("key"), #majorType3(k)) { key := ?k };
                        case (#majorType3("gateway"), #majorType3(g)) { gateway := ?g };
                        case (#majorType3("time"), #majorType0(t)) { time := ?t };
                        case _ {};
                    };
                };

                switch (key, gateway, time) {
                    case (?k, ?g, ?t) {
                        ?{
                            key = k;
                            gateway = g;
                            time = t;
                        }
                    };
                    case _ { null };
                };
            };
            case _ { null };
        };
    };

    // Add helper function to get queue size
    public func get_delete_queue_size() : async Nat {
        Iter.size(MESSAGE_DELETE_QUEUE.entries())
    };

    // Add helper function to get queue items
    public func get_delete_queue_items() : async [KeyGatewayTime] {
        Iter.toArray(Iter.map(MESSAGE_DELETE_QUEUE.entries(), func (entry : (Text, KeyGatewayTime)) : KeyGatewayTime { entry.1 }))
    };

    // Helper function to encode CertMessages to CBOR
    func encodeCertMessages(certMessages : CertMessages) : Blob {
        let cborValue : Types.Value = #majorType5([
            (#majorType3("messages"), encodeCBORMessages(certMessages.messages)),
            (#majorType3("cert"), #majorType2(certMessages.cert)),
            (#majorType3("tree"), #majorType2(certMessages.tree))
        ]);

        switch (Encoder.encode(cborValue)) {
            case (#ok(bytes)) { Blob.fromArray(bytes) };
            case (#err(e)) {
                Debug.print("Error encoding CBOR: " # debug_show(e));
                Blob.fromArray([]) // Return an empty Blob in case of error
            };
        };
    };
}