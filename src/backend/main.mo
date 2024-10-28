import Principal "mo:base/Principal";

actor {
  // Function to return the caller's Principal ID as Text
  public query(message) func whoami() : async Text {
    return Principal.toText(message.caller); // Returns the Principal ID of the caller
  };
};
