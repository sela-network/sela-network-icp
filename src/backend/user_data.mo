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
    scalingOptions : CanDB.ScalingOptions;
}) {
    type UserData = {
        principalID: Text;
        balance: Float;
        todaysEarnings: Float;
        referralCode: Text;
        totalReferral: Float;
    };

    // stable let db = CanDB.init({
    //     pk = userTable;
    //     scalingOptions = scalingOptions;
    //     btreeOrder = null; // Set btreeOrder to null explicitly
    // });

    stable let userDB = CanDB.init({ pk = "userTable"; scalingOptions = scalingOptions; btreeOrder = null });
    stable let referralDB = CanDB.init({ pk = "referralTable"; scalingOptions = scalingOptions; btreeOrder = null });
    stable let tierDB = CanDB.init({ pk = "tierTable"; scalingOptions = scalingOptions; btreeOrder = null });
    stable let nodeConnectionDB = CanDB.init({ pk = "nodeConnectionTable"; scalingOptions = scalingOptions; btreeOrder = null });
    stable let balanceDB = CanDB.init({ pk = "balanceTable"; scalingOptions = scalingOptions; btreeOrder = null });

    // Helper function to create an entity with hardcoded sk
    private func createUserEntity(principalID: Text, balance: Float, todaysEarnings: Float, referralCode: Text, totalReferral: Float) : {
        pk: Text;
        sk: Text;
        attributes: [(Text, Entity.AttributeValue)];
    } {
        Debug.print("Attempting to create entity: ");
        {
            pk = "userTable";
            sk = principalID; // Set sk as hardcoded value
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
    public shared func insertUserData(principalID: Text) : async Result.Result<(), Text> {
        Debug.print("Attempting to insert user with principalID: " # principalID);
        
        if (Text.size(principalID) == 0) {
            return #err("Invalid input: principalID must not be empty");
        };

        try {

            //let newReferralCode = generateReferralCode();
            //Debug.print("newReferralCode: " # newReferralCode);
            // First, check if the user already exists
            let existingUser = CanDB.get(userDB, { pk = "userTable"; sk = principalID });
            
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
                    let entity = createUserEntity(principalID, 0.0, 0.0, "referralCode", 0.0);
                    Debug.print("Entity creation done ");
                    await* CanDB.put(userDB, entity);
                    Debug.print("Entity inserted successfully for principalID: " # principalID);
                    return #ok();
                };
            };
        } catch (error) {
            Debug.print("Error caught in insert: " # Error.message(error));
            return #err("Failed to insert: " # Error.message(error));
        }
    };

    public shared func getUserData(principalID: Text) : async Result.Result<UserData, Text> {
        Debug.print("Attempting to get user with principalID: " # principalID);

        try {
            let result = CanDB.get(userDB, { pk = "userTable"; sk = principalID });

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

    // Insert Referral Data
    // public shared func insertReferralData(principalID: Text, referredBy: Text) : async Result.Result<(), Text> {
    //     let referralEntity = createReferralEntity(principalID, referredBy);
    //     try {
    //         await* CanDB.put(referralDB, referralEntity);
    //         return #ok();
    //     } catch {
    //         return #err("Failed to insert referral data");
    //     }
    // };

    // private func createReferralEntity(principalID: Text, referredBy: Text) : {
    //     pk: Text;
    //     sk: Text;
    //     attributes: [(Text, Entity.AttributeValue)];
    // } {
    //     {
    //         pk = principalID;
    //         sk = "REFERRAL";
    //         attributes = [
    //             ("principalID", #text(principalID)),
    //             ("referredBy", #text(referredBy))
    //         ];
    //     }
    // };

    // // Insert Tier Data
    // public shared func insertTierData(principalID: Text, tierLevel: Int) : async Result.Result<(), Text> {
    //     let tierEntity = createTierEntity(principalID, tierLevel);
    //     try {
    //         await* CanDB.put(tierDB, tierEntity);
    //         return #ok();
    //     } catch {
    //         return #err("Failed to insert tier data");
    //     }
    // };

    // private func createTierEntity(principalID: Text, tierLevel: Int) : {
    //     pk: Text;
    //     sk: Text;
    //     attributes: [(Text, Entity.AttributeValue)];
    // } {
    //     {
    //         pk = principalID;
    //         sk = "TIER";
    //         attributes = [
    //             ("principalID", #text(principalID)),
    //             ("tierLevel", #int(tierLevel))
    //         ];
    //     }
    // };

    // // Insert Node Connection Data
    // public shared func insertNodeConnectionData(nodeID: Text, connectedNodeID: Text) : async Result.Result<(), Text> {
    //     let nodeConnectionEntity = createNodeConnectionEntity(nodeID, connectedNodeID);
    //     try {
    //         await* CanDB.put(nodeConnectionDB, nodeConnectionEntity);
    //         return #ok();
    //     } catch {
    //         return #err("Failed to insert node connection data");
    //     }
    // };

    // private func createNodeConnectionEntity(nodeID: Text, connectedNodeID: Text) : {
    //     pk: Text;
    //     sk: Text;
    //     attributes: [(Text, Entity.AttributeValue)];
    // } {
    //     {
    //         pk = nodeID;
    //         sk = "CONNECTION";
    //         attributes = [
    //             ("nodeID", #text(nodeID)),
    //             ("connectedNodeID", #text(connectedNodeID))
    //         ];
    //     }
    // };

    // // Insert Balance Data
    // public shared func insertBalanceData(principalID: Text, currentBalance: Float) : async Result.Result<(), Text> {
    //     let balanceEntity = createBalanceEntity(principalID, currentBalance);
    //     try {
    //         await* CanDB.put(balanceDB, balanceEntity);
    //         return #ok();
    //     } catch {
    //         return #err("Failed to insert balance data");
    //     }
    // };

    // private func createBalanceEntity(principalID: Text, currentBalance: Float) : {
    //     pk: Text;
    //     sk: Text;
    //     attributes: [(Text, Entity.AttributeValue)];
    // } {
    //     {
    //         pk = principalID;
    //         sk = "BALANCE";
    //         attributes = [
    //             ("principalID", #text(principalID)),
    //             ("currentBalance", #float(currentBalance))
    //         ];
    //     }
    // };

    // private func generateReferralCode() : Text {
    //     let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    //     let codeLength = 6;
        
    //     func getRandomChar() : Char {
    //         let randomIndex = Nat.fromIntWrap(Int.abs(Time.now())) % characters.size();
    //         characters[randomIndex]
    //     };

    //     let referralCode = Text.join("", Iter.map(Iter.range(0, codeLength - 1), func (_: Nat) : Text {
    //         Text.fromChar(getRandomChar())
    //     }));

    //     referralCode
    // };
}
