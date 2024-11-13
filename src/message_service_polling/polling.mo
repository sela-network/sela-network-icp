import Time "mo:base/Time";
import Timer "mo:base/Timer";
import Buffer "mo:base/Buffer";

actor {
  type Update = {
    id : Nat;
    data : Text;
    timestamp : Time.Time;
  };

  var updates = Buffer.Buffer<Update>(0);
  var nextId : Nat = 0;

  // Function to add new data (this would be called by your internal processes)
  public func addUpdate(data : Text) : async () {
    nextId += 1;
    let update : Update = {
      id = nextId;
      data = data;
      timestamp = Time.now();
    };
    updates.add(update);
  };

  // Long polling function
   public func longPollUpdates(lastKnownId : Nat) : async [Update] {
    let startTime = Time.now();
    let timeout = 30_000_000_000; // 30 seconds in nanoseconds

    func checkUpdates() : [Update] {
      let newUpdates = Buffer.Buffer<Update>(0);
      for (update in updates.vals()) {
        if (update.id > lastKnownId) {
          newUpdates.add(update);
        };
      };
      Buffer.toArray(newUpdates)
    };

    var result = checkUpdates();

    if (result.size() == 0) {
      // If no immediate updates, use a promise to implement a delay
      let delay = 2_000_000_000; // 2 seconds in nanoseconds
      let futureTime = Time.now() + delay;
      
      await async {
        while (Time.now() < futureTime) {
          // This loop will keep the canister busy until the delay has passed
        };
      };

      result := checkUpdates(); // Check again after the delay
    };

    // Check if we've exceeded the timeout
    if (Time.now() - startTime >= timeout) {
      return [];
    };

    result
  };
}