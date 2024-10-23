import Principal "mo:base/Principal";

actor {
  // Greeting function
  public query func greet(name : Text) : async Text {
    return "Hello, " # name # "!";
  };

   // A shared function that returns the principal of the caller as text
    public shared(msg) func whoami() : async Text {
        return Principal.toText(msg.caller);  // 'msg.caller' provides the caller's principal
    };

  // Function to handle delegation data
  public func handleDelegation(delegation : Text) : async Text {
    // Process the delegation data
    return "Delegation processed: " # delegation;
  };
};
