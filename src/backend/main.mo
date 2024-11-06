import Principal "mo:base/Principal";
import IcWebSocketCdk "mo:ic-websocket-cdk";
import IcWebSocketCdkState "mo:ic-websocket-cdk/State";
import IcWebSocketCdkTypes "mo:ic-websocket-cdk/Types";
import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import CanDB "mo:candb/CanDB";
import DatabaseActor "canister:database";

actor Main {

  type UserData = {
    principalID: Text;
    randomID: Text;
  };

  let database = actor(Principal.toText(Principal.fromActor(DatabaseActor))) : actor {
      insert : shared (Text, Text) -> async Result.Result<(), Text>;
      get : shared query (Text) -> async Result.Result<UserData, Text>;
      update : shared (Text, Text) -> async Result.Result<(), Text>;
      delete : shared (Text) -> async Result.Result<(), Text>;
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

  public shared(msg) func storeUserData(principalID:Text, randomID: Text) : async Result.Result<(), Text> {
    await database.insert(principalID, randomID);
  };

  public shared(msg) func getUserData(principalID:Text) : async Result.Result<UserData, Text> {
      await database.get(principalID);
  };

  public shared(msg) func updateUserData(principalID:Text, newRandomID: Text) : async Result.Result<(), Text> {
      await database.update(principalID, newRandomID);
  };

//  public shared(msg) func getAllUsers(limit: Nat, skUpperBound : Text, ascending: ?Bool) : async async Result.Result<CanDB.ScanResult, Text> {
//     Debug.print("Attempting to get all users with limit: " # debug_show(limit));
    
//     try {
//         let result = await Database.scanAllUsers(limit, skUpperBound, ascending);
        
//         switch (result) {
//             case (#ok(scanResult)) {
//                 Debug.print("Successfully retrieved users.");
//                 return #ok(scanResult); // Returning the scan result
//             };
//             case (#err(errorMessage)) {
//                 Debug.print("Error retrieving users: " # errorMessage);
//                 return #err("Failed to retrieve user data: " # errorMessage);
//             };
//         }
//     } catch (error) {
//         Debug.print("Unexpected error in getAllUsers: " # Error.message(error));
//         return #err("Unexpected error: " # Error.message(error));
//     }
//   };
};