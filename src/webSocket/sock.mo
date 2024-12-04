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
        clientId : Nat64;
        key : Text;
        val : Blob;
    };

    type WebsocketMessage = {
        clientId : Nat64;
        sequenceNum : Nat64;
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
    private var GATEWAY_MESSAGES_MAP : TrieMap.TrieMap<Text, Buffer.Buffer<EncodedMessage>> = TrieMap.TrieMap<Text, Buffer.Buffer<EncodedMessage>>(Text.equal, Text.hash);
    private var MESSAGE_DELETE_QUEUE : Buffer.Buffer<KeyGatewayTime> = Buffer.Buffer<KeyGatewayTime>(0);

    // Note: Certification in Motoko is handled differently, so we don't need an exact equivalent of CERT_TREE

    public func wipe() : async () {
        nextClientId := 16;
        nextMessageNonce := 16;
        clientCallerMap := TrieMap.TrieMap<Nat64, Text>(Nat64.equal, hashNat64);
        clientPublicKeyMap := TrieMap.TrieMap<Nat64, PublicKey>(Nat64.equal, hashNat64);
        clientGatewayMap := TrieMap.TrieMap<Nat64, Text>(Nat64.equal, hashNat64);
        clientMessageNumMap := TrieMap.TrieMap<Nat64, Nat64>(Nat64.equal, hashNat64);
        clientIncomingNumMap := TrieMap.TrieMap<Nat64, Nat64>(Nat64.equal, hashNat64);
        GATEWAY_MESSAGES_MAP := TrieMap.TrieMap<Text, Buffer.Buffer<EncodedMessage>>(Text.equal, Text.hash);
        MESSAGE_DELETE_QUEUE := Buffer.Buffer<KeyGatewayTime>(0);
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
        
        let gatewayMessagesBuffer = switch (GATEWAY_MESSAGES_MAP.get(gateway)) {
            case null {
                let newBuffer = Buffer.Buffer<EncodedMessage>(0);
                GATEWAY_MESSAGES_MAP.put(gateway, newBuffer);
                newBuffer
            };
            case (?buffer) { buffer };
        };

        let smallestKey = gateway # "_" # padLeft(Nat64.toText(nonce), '0', 20);
        
        // Use Buffer.partition to split the buffer
        let (leftBuffer, rightBuffer) = Buffer.partition(gatewayMessagesBuffer, func (x : EncodedMessage) : Bool {
            Text.compare(x.key, smallestKey) == #less
        });

        // Create a new buffer with the desired messages
        let messages = Buffer.Buffer<EncodedMessage>(0);
        let iterRight = rightBuffer.vals();
        var count = 0;

        label l loop {
            switch (iterRight.next()) {
                case (?message) {
                    if (count >= MAX_NUMBER_OF_RETURNED_MESSAGES) { break l; };
                    messages.add(message);
                    count += 1;
                };
                case null { break l; };
            };
        };
        
        if (messages.size() > 0) {
            let firstKey = messages.get(0).key;
            let lastKey = messages.get(messages.size() - 1).key;
            let (cert, tree) = await get_cert_for_range(firstKey, lastKey);
            {
                messages = Buffer.toArray(messages);
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
            case (?buffer) {
                if (buffer.size() > 0) {
                    let _ = buffer.remove(0);
                };
            };
            case null { /* Do nothing */ };
        };
        CERT_TREE.delete(messageInfo.key);
    };

    public func send_message_from_canister(clientId : Nat64, msg : Blob) : async () {
        let gateway = switch (await get_client_gateway(clientId)) {
            case null { return };
            case (?gw) { gw };
        };


        let time = Time.now();
        nextMessageNonce += 1;
        let key = gateway # "_" # padLeft(Nat64.toText(nextMessageNonce), '0', 20);

        MESSAGE_DELETE_QUEUE.add({
            key = key;
            gateway = gateway;
            time = Nat64.fromNat(Int.abs(time));
        });

        if (MESSAGE_DELETE_QUEUE.size() > 0) {
            let front = MESSAGE_DELETE_QUEUE.get(0);
            if (Nat64.fromNat(Int.abs(time)) - front.time > MSG_TIMEOUT) {
                delete_message(front);
                ignore MESSAGE_DELETE_QUEUE.remove(0);

                if (MESSAGE_DELETE_QUEUE.size() > 0) {
                    let newFront = MESSAGE_DELETE_QUEUE.get(0);
                    if (Nat64.fromNat(Int.abs(time)) - newFront.time > MSG_TIMEOUT) {
                        delete_message(newFront);
                        ignore MESSAGE_DELETE_QUEUE.remove(0);
                    };
                };
            };
        };

        let input : WebsocketMessage = {
            clientId = clientId;
            sequenceNum = await next_client_message_num(clientId);
            timestamp = Nat64.fromNat(Int.abs(time));
            message = msg;
        };

        let data = to_candid(input);

        await put_cert_for_message(key, data);
        
        switch (GATEWAY_MESSAGES_MAP.get(gateway)) {
            case null {
                let newBuffer = Buffer.Buffer<EncodedMessage>(1);
                newBuffer.add({
                    clientId = clientId;
                    key = key;
                    val = data;
                });
                GATEWAY_MESSAGES_MAP.put(gateway, newBuffer);
            };
            case (?buffer) {
                buffer.add({
                    clientId = clientId;
                    key = key;
                    val = data;
                });
            };
        };
    };

    public func put_cert_for_message(key : Text, value : Blob) : async () {
        let hash = SHA256.fromBlob(#sha256, value);
        
        CERT_TREE.put(key, hash);
        
        let rootHash = labeledHash(LABEL_WEBSOCKET, treeRootHash());
        CertifiedData.set(rootHash);
    };

    public func get_cert_for_message(key : Text) : async (Blob, Blob) {
        let witness = createWitness(key);
        let tree = labeled(LABEL_WEBSOCKET, witness);
        
        let treeBlob = to_candid(tree);
        
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

    public func get_cert_for_range(first : Text, last : Text) : async (Blob, Blob) {
        let witness = createRangeWitness(first, last);
        let tree = labeled(LABEL_WEBSOCKET, witness);
        
        let treeBlob = to_candid(tree);
        
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

    // Add this helper function at the top of your actor or in a separate module
    private func padLeft(text : Text, pad : Char, len : Nat) : Text {
        let textLen = Text.size(text);
        if (textLen >= len) {
            return text;
        };
        let padLen = len - textLen;
        let padText = Text.join("", Iter.map(Iter.range(0, padLen - 1), func(_ : Nat) : Text { Text.fromChar(pad) }));
        padText # text
    };
}