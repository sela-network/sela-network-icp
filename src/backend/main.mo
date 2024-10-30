import Principal "mo:base/Principal";
import Text "mo:base/Text";
import HashMap "mo:base/HashMap";

actor {

  let validIdentities = HashMap.HashMap<Principal, Bool>(10, Principal.equal, Principal.hash);

  public shared(msg) func verifyIdentity(principalText : Text) : async Bool {
    let principal = Principal.fromText(principalText);
    switch (validIdentities.get(principal)) {
      case (null) { false };
      case (?isValid) { isValid };
    };
  };

  public shared query (msg) func whoami() : async Principal {
      return msg.caller;
  };
};