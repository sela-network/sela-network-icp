import CanDB "mo:candb/CanDB";
import Entity "mo:candb/Entity";
import Text "mo:base/Text";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Principal "mo:base/Principal"; 
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Error "mo:base/Error";
import Iter "mo:base/Iter";

shared ({ caller = owner }) actor class User_data({
    partitionKey : Text;
    scalingOptions : CanDB.ScalingOptions;
}) {
    type UserData = {
        principalID: Text;
        balance: Float;
        todaysEarnings: Float;
        referralCode: Text;
        totalReferral: Float;
    };

    stable let db = CanDB.init({
        pk = partitionKey;
        scalingOptions = scalingOptions;
        btreeOrder = null; // Set btreeOrder to null explicitly
    });

    // Helper function to create an entity with hardcoded sk
    private func createEntity(principalID: Text, balance: Float, todaysEarnings: Float, referralCode: Text, totalReferral: Float) : {
        pk: Text;
        sk: Text;
        attributes: [(Text, Entity.AttributeValue)];
    } {
        Debug.print("Attempting to create entity: ");
        let hardcodedSk = "USER"; // Hardcoded alphanumeric value for sk
        {
            pk = principalID;
            sk = hardcodedSk; // Set sk as hardcoded value
            attributes = [
                ("principalID", #text(principalID)),
                ("balance", #float(balance)),
                ("todaysEarnings", #float(todaysEarnings)),
                ("referralCode", #text(referralCode)),
                ("totalReferral", #float(totalReferral))
            ];
        }
    };

    // Insert function to add user data
    public shared func insert(principalID: Text) : async Result.Result<(), Text> {
        Debug.print("Attempting to insert user with principalID: " # principalID);
        
        if (Text.size(principalID) == 0) {
            return #err("Invalid input: principalID must not be empty");
        };

        try {
            // First, check if the user already exists
            let existingUser = CanDB.get(db, { pk = principalID; sk = "USER" });
            
            switch (existingUser) {
                case (?_) {
                    // User already exists, return an error
                    Debug.print("User already exists for principalID: " # principalID);
                    return #err("User already exists");
                };
                case null {
                    // User doesn't exist, proceed with insertion
                 //   let referralCode = generateReferralCode();
                    Debug.print("New user");
                    let entity = createEntity(principalID, 0.0, 0.0, "referralCode", 0.0);
                    Debug.print("Entity creation done ");
                    await* CanDB.put(db, entity);
                    Debug.print("Entity inserted successfully for principalID: " # principalID);
                    return #ok();
                };
            };
        } catch (error) {
            Debug.print("Error caught in insert: " # Error.message(error));
            return #err("Failed to insert: " # Error.message(error));
        }
    };

    public shared func get(principalID: Text) : async Result.Result<UserData, Text> {
        Debug.print("Attempting to get user with principalID: " # principalID);

        try {
            let result = CanDB.get(db, { pk = principalID; sk = "USER" });

            switch(result) {
                case null {
                    Debug.print("User not found for principalID: " # principalID);
                    #err("User not found")
                };
                case (?entity) {
                    switch(unwrapUser(entity)) {
                        case (?userData) {
                            #ok(userData)
                        };
                        case null {
                            #err("Error unwrapping user data")
                        };
                    }
                };
            }
        } catch (error) {
            Debug.print("Error in get function: " # Error.message(error));
            #err("Failed to get user: " # Error.message(error))
        }
    };


   func unwrapUser(entity: Entity.Entity): ?UserData {
        let attributes = entity.attributes;

        let principalID = switch (Entity.getAttributeMapValueForKey(attributes, "principalID")) {
            case (?(#text(value))) { value };
            case _ { return null; };
        };

        let balance = switch (Entity.getAttributeMapValueForKey(attributes, "balance")) {
            case (?(#float(value))) { value };
            case _ { return null; };
        };

        let todaysEarnings = switch (Entity.getAttributeMapValueForKey(attributes, "todaysEarnings")) {
            case (?(#float(value))) { value };
            case _ { return null; };
        };

        let referralCode = switch (Entity.getAttributeMapValueForKey(attributes, "referralCode")) {
            case (?(#text(value))) { value };
            case _ { return null; };
        };

        let totalReferral = switch (Entity.getAttributeMapValueForKey(attributes, "totalReferral")) {
            case (?(#float(value))) { value };
            case _ { return null; };
        };

        ?{
            principalID;
            balance;
            todaysEarnings;
            referralCode;
            totalReferral;
        }
    };
}
