import Principal "mo:base/Principal";
import IcWebSocketCdk "mo:ic-websocket-cdk";
import IcWebSocketCdkState "mo:ic-websocket-cdk/State";
import IcWebSocketCdkTypes "mo:ic-websocket-cdk/Types";
import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import CanDB "mo:candb/CanDB";
import Error "mo:base/Error";
import HTTP "../utils/Http";
import Entity "mo:candb/Entity";
import Float "mo:base/Float";


actor Main {

  type HttpRequest = HTTP.HttpRequest;
  type HttpResponse = HTTP.HttpResponse;

  type UserData = {
      principalID: Text;
      balance: Float;
      todaysEarnings: Float;
      referralCode: Text;
      totalReferral: Float;
  };

  public shared func dummyAutoScalingHook(_ : Text) : async Text {
    return "";
  };

  let scalingOptions : CanDB.ScalingOptions = {
    autoScalingHook = dummyAutoScalingHook;
    sizeLimit = #count(1000);
  };
 
  stable let userDB = CanDB.init({ pk = "userTable"; scalingOptions = scalingOptions; btreeOrder = null });
  stable let _referralDB = CanDB.init({ pk = "referralTable"; scalingOptions = scalingOptions; btreeOrder = null });
  stable let _tierDB = CanDB.init({ pk = "tierTable"; scalingOptions = scalingOptions; btreeOrder = null });
  stable let _nodeConnectionDB = CanDB.init({ pk = "nodeConnectionTable"; scalingOptions = scalingOptions; btreeOrder = null });
  stable let _balanceDB = CanDB.init({ pk = "balanceTable"; scalingOptions = scalingOptions; btreeOrder = null });

  private func createUserEntity(principalID: Text, balance: Float, todaysEarnings: Float, referralCode: Text, totalReferral: Float) : {
      pk: Text;
      sk: Text;
      attributes: [(Text, Entity.AttributeValue)];
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

  public query func getUserData(principalID: Text) : async Result.Result<UserData, Text> { 
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

  public query func http_request(request: HttpRequest) : async HttpResponse {
    return {
        status_code = 200;
        headers = [("Content-Type", "text/plain")];
        body = Text.encodeUtf8("This is a query response");
        streaming_strategy = null;
        upgrade = ?true;  // This indicates that the request should be upgraded to an update call
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
              case (#ok(userData)){
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
                          "\"totalReferral\":" # Float.toText(userData.totalReferral)
                        )
                      )
                    )
                  ) # "}"
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
      case ("POST", "/registerUser") {
        let authHeader = getHeader(headers, "authorization");
        switch (authHeader) {
          case null { 
            Debug.print("Missing Authorization header ");
            return badRequest("Missing Authorization header"); 
          };
          case (?principalID) {
            switch (await insertUserData(principalID)) {
              case (#ok(_)) {
                return {
                  status_code = 200;
                  headers = [("Content-Type", "text/plain")];
                  body = Text.encodeUtf8("User registered successfully");
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
    null
  };

  public shared query (msg) func whoami() : async Principal {
      return msg.caller;
  };

  // Health check function
  public shared query func backend_health_check() : async Text {
      return "OK"; // Responds with "OK"
  };

   type AppMessage = {
    message : Text;
  };

   // Variable to track if the WebSocket is connected
  var isConnected : Bool = false;

  // Health check function for WebSocket
  public shared query func health_check() : async Text {
      return if (isConnected) {
          "OK"
      } else {
          "Error: WebSocket is not connected."
      };
  };

  /// A custom function to send the message to the client
  func send_app_message(client_principal : IcWebSocketCdk.ClientPrincipal, msg : AppMessage): async () {
    Debug.print("Sending message: " # debug_show (msg));

    // here we call the send from the CDK!!
    switch (await IcWebSocketCdk.send(ws_state, client_principal, to_candid(msg))) {
      case (#Err(err)) {
        Debug.print("Could not send message:" # debug_show (#Err(err)));
      };
      case (_) {};
    };
  };

  func on_open(args : IcWebSocketCdk.OnOpenCallbackArgs) : async () {
    let message : AppMessage = {
      message = "Pong";
    };
    isConnected := true; // Update connection status to true
    await send_app_message(args.client_principal, message);
  };

  /// The custom logic is just a ping-pong message exchange between frontend and canister.
  /// Note that the message from the WebSocket is serialized in CBOR, so we have to deserialize it first

  func on_message(args : IcWebSocketCdk.OnMessageCallbackArgs) : async () {
    let app_msg : ?AppMessage = from_candid(args.message);
    let new_msg: AppMessage = switch (app_msg) {
      case (?msg) { 
        { message = Text.concat(msg.message, " ping") };
      };
      case (null) {
        Debug.print("Could not deserialize message");
        return;
      };
    };

    Debug.print("Received message: " # debug_show (new_msg));

    await send_app_message(args.client_principal, new_msg);
  };

  func on_close(args : IcWebSocketCdk.OnCloseCallbackArgs) : async () {
    isConnected := false; // Update connection status to false
    Debug.print("Client " # debug_show (args.client_principal) # " disconnected");
  };

  let params = IcWebSocketCdkTypes.WsInitParams(null, null);
  let ws_state = IcWebSocketCdkState.IcWebSocketState(params);

  let handlers = IcWebSocketCdkTypes.WsHandlers(
    ?on_open,
    ?on_message,
    ?on_close,
  );

  let ws = IcWebSocketCdk.IcWebSocket(ws_state, params, handlers);

  // method called by the WS Gateway after receiving FirstMessage from the client
  public shared ({ caller }) func ws_open(args : IcWebSocketCdk.CanisterWsOpenArguments) : async IcWebSocketCdk.CanisterWsOpenResult {
    await ws.ws_open(caller, args);
  };

  // method called by the Ws Gateway when closing the IcWebSocket connection
  public shared ({ caller }) func ws_close(args : IcWebSocketCdk.CanisterWsCloseArguments) : async IcWebSocketCdk.CanisterWsCloseResult {
    await ws.ws_close(caller, args);
  };

  // method called by the frontend SDK to send a message to the canister
  public shared ({ caller }) func ws_message(args : IcWebSocketCdk.CanisterWsMessageArguments, msg:? AppMessage) : async IcWebSocketCdk.CanisterWsMessageResult {
    await ws.ws_message(caller, args, msg);
  };

  // method called by the WS Gateway to get messages for all the clients it serves
  public shared query ({ caller }) func ws_get_messages(args : IcWebSocketCdk.CanisterWsGetMessagesArguments) : async IcWebSocketCdk.CanisterWsGetMessagesResult {
    ws.ws_get_messages(caller, args);
  };
};