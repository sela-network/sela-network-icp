import CanDB "mo:candb/CanDB";
import Entity "mo:candb/Entity";
import Text "mo:base/Text";
import Result "mo:base/Result";
import Error "mo:base/Error";
import Debug "mo:base/Debug";

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
        btreeOrder = null;
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

  private func isDatabaseReady() : Bool {
    return db.count >= 0; // This assumes that `db.count` is always available and non-negative
  };

    // Insert function
  public shared func insert(principalID: Text, randomID: Text) : async Result.Result<(), Text> {
    if (not isDatabaseReady()) {
      Debug.print("Database not initialized");
      return #err("Database not initialized");
    };
    
    if (Text.size(principalID) == 0 or Text.size(randomID) == 0) {
      Debug.print("Invalid input: principalID or randomID is empty");
      return #err("Invalid input: principalID and randomID must not be empty");
    };

    Debug.print("Database is ready. Proceeding with insert operation.");
    
    try {
        let entity = createEntity(principalID, randomID);
        Debug.print("Entity created. Attempting to insert into database.");
        await* CanDB.put(db, entity);
        Debug.print("Insert operation successful");
        #ok()
    } catch (error) {
        Debug.print("Error caught in insert: " # Error.message(error));
        #err("Failed to insert: " # Error.message(error))
    }
  };

    // Get function
    public shared query func get(principalID: Text) : async Result.Result<UserData, Text> {
        let result = CanDB.get(db, { pk = principalID; sk = "" });
        switch (result) {
            case (null) { #err("User not found") };
            case (?entity) {
                #ok({
                    principalID = entity.pk;
                    randomID = entity.sk;
                })
            };
        }
    };

    // Update function
    public shared func update(principalID: Text, newRandomID: Text) : async Result.Result<(), Text> {
      let existingEntity = CanDB.get(db, { pk = principalID; sk = "" });
      switch (existingEntity) {
          case (null) { #err("User not found") };
          case (_) {
              let updatedEntity = createEntity(principalID, newRandomID);
              try {
                  await* CanDB.put(db, updatedEntity);
                  #ok()
              } catch (error) {
                  #err("Failed to update: " # Error.message(error))
              }
          };
      };
  };

    // Delete function
    public shared func delete(principalID: Text) : async Result.Result<(), Text> {
      try {
          let _result = CanDB.remove(db, { pk = principalID; sk = "" });
          #ok()
      } catch (error) {
          #err("Failed to delete: " # Error.message(error))
      }
  };
}