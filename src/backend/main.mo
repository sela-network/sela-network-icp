import Principal "mo:base/Principal";
import IcWebSocketCdk "mo:ic-websocket-cdk";
import IcWebSocketCdkState "mo:ic-websocket-cdk/State";
import IcWebSocketCdkTypes "mo:ic-websocket-cdk/Types";
import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import CanDB "mo:candb/CanDB";
import User_dataActor "canister:user_data";
import Error "mo:base/Error";
import HTTP "./Http";
import Blob "mo:base/Blob";

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

  let user_database = actor(Principal.toText(Principal.fromActor(User_dataActor))) : actor {
      insertUserData : shared (Text) -> async Result.Result<(), Text>;
      getUserData : shared query (Text) -> async Result.Result<UserData, Text>;
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

  public shared(msg) func registerUser(principalID: Text) : async Result.Result<(), Text> {
    await user_database.insertUserData(principalID);
  };

  public func getUserData(principalID: Text) : async Result.Result<UserData, Text> {
      await user_database.getUserData(principalID);
  };

  public query func http_request(req : HttpRequest) : async HttpResponse {
    let path = req.url;
    let method = req.method;

    switch (method, path) {
      case ("GET", "/getUserData") {
        // Return an upgrade response for GET requests that need async operations
        return {
          status_code = 200;
          headers = [];
          body = Text.encodeUtf8("");
          streaming_strategy = null;
          upgrade = ?true;
        };
      };
      case ("POST", "/registerUser") {
        // Return an upgrade response for POST requests that need async operations
        return {
          status_code = 200;
          headers = [];
          body = Text.encodeUtf8("");
          streaming_strategy = null;
          upgrade = ?true;
        };
      };
      case _ {
        return notFound();
      };
    };
  };

  public func http_request_update(req : HttpRequest) : async HttpResponse {
    let path = req.url;
    let method = req.method;
    let headers = req.headers;

    switch (method, path) {
      case ("GET", "/getUserData") {
        let authHeader = getHeader(headers, "Authorization");
        switch (authHeader) {
          case null { return badRequest("Missing Authorization header"); };
          case (?principalID) {
            switch (await getUserData(principalID)) {
              case (#ok(userData)){
                return {
                  status_code = 200;
                  headers = [("Content-Type", "application/json")];
                  body = Text.encodeUtf8(debug_show(userData));
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
        let authHeader = getHeader(headers, "Authorization");
        switch (authHeader) {
          case null { return badRequest("Missing Authorization header"); };
          case (?principalID) {
            switch (await registerUser(principalID)) {
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
};