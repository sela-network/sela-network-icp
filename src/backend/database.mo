import CanDB "mo:candb/CanDB";
import Entity "mo:candb/Entity";
import Text "mo:base/Text";
import Result "mo:base/Result";
import Error "mo:base/Error";
import Debug "mo:base/Debug";
import Principal "mo:base/Principal"; 
import Array "mo:base/Array";

shared ({ caller = owner }) actor class Database({
    partitionKey : Text;
    scalingOptions : CanDB.ScalingOptions;
}) {
    type UserData = {
        principalID: Text;
        randomID: Text;
    };

    stable let db = CanDB.init({
        pk = partitionKey;
        scalingOptions = scalingOptions;
        btreeOrder = null; // Set btreeOrder to null explicitly
    });

    // Helper function to create an entity
    private func createEntity(principalID: Text, randomID: Text) : {
        pk: Text;
        sk: Text;
        attributes: [(Text, Entity.AttributeValue)];
    } {
        {
            pk = principalID;
            sk = randomID;
            attributes = [
                ("principalID", #text(principalID)),
                ("randomID", #text(randomID))
            ];
        }
    };

    // Insert function
    public shared func insert(principalID: Text, randomID: Text) : async Result.Result<(), Text> {
        Debug.print("Inserting user with principalID: " # principalID);
        
        if (Text.size(principalID) == 0 or Text.size(randomID) == 0) {
            return #err("Invalid input: principalID and randomID must not be empty");
        };

        let entity = createEntity(principalID, randomID);
        try {
            await* CanDB.put(db, entity); // Use await* here for async operation
            Debug.print("Entity inserted successfully for principalID: " # principalID);
            return #ok();
        } catch (error) {
            Debug.print("Error caught in insert: " # Error.message(error));
            return #err("Failed to insert: " # Error.message(error));
        }
    };

    // Get function
    public shared func get(principalID: Text) : async Result.Result<?UserData, Text> {
        Debug.print("Attempting to get user with principalID: " # principalID);
        
        try {
            let result = CanDB.get(db, { pk = principalID; sk = "1234" });
            
            switch (result) {
                case null {
                    Debug.print("User not found for principalID: " # principalID);
                    return #err("User not found");
                };
                case (?entity) {
                    let userData : UserData = {
                        principalID = entity.pk; // Actual principal ID
                        randomID = entity.sk; // Assuming sk is randomID
                    };
                    Debug.print("User found: " # principalID);
                    return #ok(?userData);
                };
            };
        } catch (error) {
            Debug.print("Error in get function: " # Error.message(error));
            return #err("Failed to get user: " # Error.message(error));
        }
    };

    // Update function
    public shared func update(principalID: Text, newRandomID: Text) : async Result.Result<(), Text> {
        Debug.print("Updating user with principalID: " # principalID);
        
        // Attempt to retrieve the existing entity for the given principal ID
        let existingEntity = CanDB.get(db, { pk = principalID; sk = "1234" });

        switch (existingEntity) {
            case null {
                Debug.print("User not found for update");
                return #err("User not found");
            };
            case (?entity) {
                // User found, proceed to update the randomID
                let updatedEntity = createEntity(principalID, newRandomID);
                
                // Use CanDB.update to perform the update operation
                let updateResult = switch (
                    CanDB.update(
                        db,
                        {
                            pk = principalID; // Assuming principalID is the partition key
                            sk = entity.sk;   // Keep the existing sort key
                            updateAttributeMapFunction = func(attributeMap : ?Entity.AttributeMap) : Entity.AttributeMap {
                                switch (attributeMap) {
                                    case null {
                                        Entity.createAttributeMapFromKVPairs([("randomID", #text(newRandomID))]);
                                    };
                                    case (?map) {
                                        // Update the randomID in the existing attributes
                                        Entity.updateAttributeMapWithKVPairs(map, [("randomID", #text(newRandomID))]);
                                    };
                                };
                            };
                        },
                    )
                ) {
                    case null {
                        Debug.print("Failed to update user: entity not found in database.");
                        return #err("Update failed: entity not found");
                    };
                    case (?entity) {
                        Debug.print("Update operation successful for principalID: " # principalID);
                        return #ok();
                    };
                };
            };
        };
    };

}
