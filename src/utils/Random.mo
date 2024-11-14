import Nat = "mo:base/Nat";
import Nat8 = "mo:base/Nat8";
import Random = "mo:base/Random";
import Blob "mo:base/Blob";
import Text "mo:base/Text";
import Array "mo:base/Array";
import Iter "mo:base/Iter";

module {
  public func new() : { next : () -> async Text } =
    object {
      public func next() : async Text {
        let randomBytes = await Random.blob();
        let randomNat = bytesToNat(Blob.toArray(randomBytes));
        let trimmedNat = randomNat % 1000000; // This will give a number between 0 and 999999
        "job" # padWithZeros(Nat.toText(trimmedNat), 6)
      };
    };

  private func bytesToNat(bytes: [Nat8]) : Nat {
    var n : Nat = 0;
    for (byte in bytes.vals()) {
      n := n * 256 + Nat8.toNat(byte);
    };
    n
  };

  private func padWithZeros(s: Text, desiredLength: Nat) : Text {
    let currentLength = s.size();
    if (currentLength >= desiredLength) {
      s
    } else {
      var padded = s;
      for (i in Iter.range(0, desiredLength - currentLength - 1)) {
        padded := "0" # padded;
      };
      padded
    }
  };
};