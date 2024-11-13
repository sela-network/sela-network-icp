import Time "mo:base/Time";
import Timer "mo:base/Timer";
import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Iter "mo:base/Iter";

actor polling {

    // Represents a client with ID, lastAlive timestamp, and state
    type Client = {
        id : Text;
        var lastAlive : Time.Time;
        var state : Text;  // Possible states: "alive", "dead", "working"
    };

    // HashMap to store clients
    private var clients = HashMap.HashMap<Text, Client>(10, Text.equal, Text.hash);

    // For stable storage
    private stable var clientEntries : [(Text, Client)] = [];

    // Timeout thresholds
    let aliveTimeout : Int = 5_000_000_000; // 5000ms in nanoseconds
    let pollInterval : Int = 1_000_000_000; // 1000ms for the polling interval

    // Add or update client alive signal
    public func clientAlive(clientId: Text) : async Text {
        switch (clients.get(clientId)) {
            case (?client) {
                // Update the 'lastAlive' timestamp to show client is still alive
                client.lastAlive := Time.now();
                client.state := "alive"; // Mark client as alive
                "Client is alive"
            };
            case null {
                // New client, add it to the HashMap
                let newClient : Client = {
                    id = clientId;
                    var lastAlive = Time.now();
                    var state = "alive";
                };
                clients.put(clientId, newClient);
                "New client added and marked alive"
            };
        }
    };

    // Monitor clients for timeout (5000ms) and update state to "dead"
    private func checkClientTimeout() : async () {
        let currentTime = Time.now();
        for ((id, client) in clients.entries()) {
            if (currentTime - client.lastAlive > aliveTimeout) {
                // Mark client as dead if it's been too long since last 'alive' signal
                client.state := "dead";
            };
        }
    };

    // Assign a job to an available client who is not working
    public func assignJob() : async Text {
        for ((id, client) in clients.entries()) {
            if (client.state == "alive") {
                // Mark the client as working and assign the job
                client.state := "working";
                return "Job assigned to client: " # id;
            };
        };
        return "No available client to assign job";
    };

    // Simulate job completion and update the client state
    public func jobCompleted(clientId: Text) : async Text {
        switch (clients.get(clientId)) {
            case (?client) {
                // Mark client as "alive" again after job completion
                client.state := "alive";
                "Job completed, client " # clientId # " is alive"
            };
            case null {
                "Client not found"
            };
        }
    };

    // Handle long polling by returning the client status or job availability
    public func longPoll(clientId: Text) : async Text {
        // Wait for the client to become alive or a job to be available
        let maxWaitTime = 5_000_000_000;  // 5000ms
        let startTime = Time.now();
        
        while (Time.now() - startTime < maxWaitTime) {
            switch (clients.get(clientId)) {
                case (?client) {
                    if (client.state == "alive") {
                        return "Client is alive, ready for job";
                    } else if (client.state == "working") {
                        return "Client is working, please wait";
                    } else {
                        return "Client is dead";
                    };
                };
                case null {
                    return "Client not found";
                };
            };
            await delay(1_000_000_000); // Wait for 1 second
        };
        
        // If no update in 5000ms, mark the client as dead
        switch (clients.get(clientId)) {
            case (?client) {
                client.state := "dead";
                return "Client marked as dead due to inactivity";
            };
            case null {
                return "Client not found";
            };
        }
    };

    public func delay(duration: Nat) : async () {
        let start = Time.now();
        var current = start;
        while (current - start < duration) {
            current := Time.now();
        };
    };

    // Set up the recurring timer to check for client timeouts
    ignore Timer.recurringTimer<system>(#seconds 1, checkClientTimeout);

    // For canister upgrades
    system func preupgrade() {
        clientEntries := Iter.toArray(clients.entries());
    };

    system func postupgrade() {
        clients := HashMap.fromIter<Text, Client>(clientEntries.vals(), 10, Text.equal, Text.hash);
        clientEntries := [];
    };
}
