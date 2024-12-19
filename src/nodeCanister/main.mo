import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import CanDB "mo:candb/CanDB";
import Error "mo:base/Error";
import HTTP "../utils/Http";
import Entity "mo:candb/Entity";
import Float "mo:base/Float";
import Random "../utils/Random";

actor Main {

  type HttpRequest = HTTP.HttpRequest;
  type HttpResponse = HTTP.HttpResponse;

  type UserData = {
    principalID : Text;
    balance : Float;
    todaysEarnings : Float;
    referralCode : Text;
    totalReferral : Float;
  };

  public shared func dummyAutoScalingHook(_ : Text) : async Text {
    return "";
  };

  let scalingOptions : CanDB.ScalingOptions = {
    autoScalingHook = dummyAutoScalingHook;
    sizeLimit = #count(1000);
  };

  stable let userDB = CanDB.init({
    pk = "userTable";
    scalingOptions = scalingOptions;
    btreeOrder = null;
  });
  stable let _referralDB = CanDB.init({
    pk = "referralTable";
    scalingOptions = scalingOptions;
    btreeOrder = null;
  });
  stable let _tierDB = CanDB.init({
    pk = "tierTable";
    scalingOptions = scalingOptions;
    btreeOrder = null;
  });
  stable let _nodeConnectionDB = CanDB.init({
    pk = "nodeConnectionTable";
    scalingOptions = scalingOptions;
    btreeOrder = null;
  });
  stable let _balanceDB = CanDB.init({
    pk = "balanceTable";
    scalingOptions = scalingOptions;
    btreeOrder = null;
  });

  private func createUserEntity(principalID : Text, balance : Float, todaysEarnings : Float, referralCode : Text, totalReferral : Float) : {
    pk : Text;
    sk : Text;
    attributes : [(Text, Entity.AttributeValue)];
  } {
    Debug.print("Attempting to create entity: ");
    {
      pk = "userTable";
      sk = principalID;
      attributes = [
        ("principalID", #text(principalID)),
        ("balance", #float(balance)),
        ("todaysEarnings", #float(todaysEarnings)),
        ("referralCode", #text(referralCode)),
        ("totalReferral", #float(totalReferral)),
      ];
    };
  };

  // Insert function to add user data
  public shared func insertUserData(principalID : Text) : async Result.Result<(), Text> {
    Debug.print("Attempting to insert user with principalID: " # principalID);

    if (Text.size(principalID) == 0) {
      return #err("Invalid input: principalID must not be empty");
    };

    try {
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
          let randomGenerator = Random.new();
          let referralCode_ =  await randomGenerator.next();
          let referralCode = "#ref" # referralCode_;
          Debug.print("New user");
          let entity = createUserEntity(principalID, 0.0, 0.0, referralCode, 0.0);
          Debug.print("Entity creation done ");
          await* CanDB.put(userDB, entity);
          Debug.print("Entity inserted successfully for principalID: " # principalID);
          return #ok();
        };
      };
    } catch (error) {
      Debug.print("Error caught in insert: " # Error.message(error));
      return #err("Failed to insert: " # Error.message(error));
    };
  };

  public func getUserData(principalID : Text) : async Result.Result<UserData, Text> {
    Debug.print("Attempting to get user with principalID: " # principalID);

    try {
      let result = CanDB.get(userDB, { pk = "userTable"; sk = principalID });

      switch (result) {
        case null {
          Debug.print("User not found for principalID: " # principalID);
          let insertResult = await insertUserData(principalID);
          switch (insertResult) {
            case (#ok()) {
              // User inserted successfully, now try to get the user data again
              let newResult = CanDB.get(userDB, { pk = "userTable"; sk = principalID });
              switch (newResult) {
                case (?entity) {
                  switch (unwrapUser(entity)) {
                    case (?userData) {
                      #ok(userData);
                    };
                    case null {
                      #err("Error unwrapping user data after insertion");
                    };
                  };
                };
                case null {
                  #err("User not found after insertion");
                };
              };
            };
            case (#err(errorMsg)) {
              #err("Failed to insert user: " # errorMsg);
            };
          };
        };
        case (?entity) {
          switch (unwrapUser(entity)) {
            case (?userData) {
              #ok(userData);
            };
            case null {
              #err("Error unwrapping user data");
            };
          };
        };
      };
    } catch (error) {
      Debug.print("Error in get function: " # Error.message(error));
      #err("Failed to get user: " # Error.message(error));
    };
  };

  func unwrapUser(entity : Entity.Entity) : ?UserData {
    let attributes = entity.attributes;

    let principalID = switch (Entity.getAttributeMapValueForKey(attributes, "principalID")) {
      case (?(#text(value))) { value };
      case _ { return null };
    };

    let balance = switch (Entity.getAttributeMapValueForKey(attributes, "balance")) {
      case (?(#float(value))) { value };
      case _ { return null };
    };

    let todaysEarnings = switch (Entity.getAttributeMapValueForKey(attributes, "todaysEarnings")) {
      case (?(#float(value))) { value };
      case _ { return null };
    };

    let referralCode = switch (Entity.getAttributeMapValueForKey(attributes, "referralCode")) {
      case (?(#text(value))) { value };
      case _ { return null };
    };

    let totalReferral = switch (Entity.getAttributeMapValueForKey(attributes, "totalReferral")) {
      case (?(#float(value))) { value };
      case _ { return null };
    };

    ?{
      principalID;
      balance;
      todaysEarnings;
      referralCode;
      totalReferral;
    };
  };

  public query func http_request(_request : HttpRequest) : async HttpResponse {
    return {
      status_code = 200;
      headers = [("Content-Type", "text/plain")];
      body = Text.encodeUtf8("This is a query response");
      streaming_strategy = null;
      upgrade = ?true; // This indicates that the request should be upgraded to an update call
    };
  };

  public func http_request_update(req : HttpRequest) : async HttpResponse {
    let path = req.url;
    let method = req.method;
    let headers = req.headers;

    Debug.print("path: " # debug_show (path));
    Debug.print("method: " # debug_show (method));
    Debug.print("headers: " # debug_show (headers));

    switch (method, path) {
      case ("GET", "/getUserData") {
        let authHeader = getHeader(headers, "authorization");
        switch (authHeader) {
          case null {
            Debug.print("Missing Authorization header ");
            return badRequest("Missing Authorization header");
          };
          case (?principalID) {
            switch (await getUserData(principalID)) {
              case (#ok(userData)) {
                // Constructing the JSON manually
                let jsonBody = Text.concat(
                  "{",
                  Text.concat(
                    "\"principalID\":\"" # userData.principalID # "\",",
                    Text.concat(
                      "\"balance\":" # Float.toText(userData.balance) # ",",
                      Text.concat(
                        "\"todaysEarnings\":" # Float.toText(userData.todaysEarnings) # ",",
                        Text.concat(
                          "\"referralCode\":\"" # userData.referralCode # "\",",
                          "\"totalReferral\":" # Float.toText(userData.totalReferral),
                        ),
                      ),
                    ),
                  ) # "}",
                );
                Debug.print("JSON response: " # jsonBody);
                return {
                  status_code = 200;
                  headers = [("Content-Type", "application/json")];
                  body = Text.encodeUtf8(jsonBody);
                  streaming_strategy = null;
                  upgrade = null;
                };
              };
              case (#err(errorMsg)) {
                return badRequest(errorMsg);
              };
            };
          };
        };
      };
      case _ {
        return notFound();
      };
    };
  };

  // Helper functions for HTTP responses
  func badRequest(msg : Text) : HttpResponse {
    {
      status_code = 400;
      headers = [("Content-Type", "text/plain")];
      body = Text.encodeUtf8(msg);
      streaming_strategy = null;
      upgrade = null;
    };
  };

  func notFound() : HttpResponse {
    {
      status_code = 404;
      headers = [("Content-Type", "text/plain")];
      body = Text.encodeUtf8("Not Found");
      streaming_strategy = null;
      upgrade = null;
    };
  };

  // Helper function to get header value
  func getHeader(headers : [(Text, Text)], name : Text) : ?Text {
    for ((key, value) in headers.vals()) {
      if (Text.equal(key, name)) {
        return ?value;
      };
    };
    null;
  };

  public shared query (msg) func whoami() : async Principal {
    return msg.caller;
  };

  // Health check function
  public shared query func backend_health_check() : async Text {
    return "OK"; // Responds with "OK"
  };
};
