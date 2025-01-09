import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import Error "mo:base/Error";
import Entity "mo:candb/Entity";
import Float "mo:base/Float";
import Option "mo:base/Option";
import DBTypes "./types/types";
import database_ops "./modules/database_ops";
import HTTP "../common/Http";
import Random "../common/utils";

shared(installer) actor class canister(dbCanisterId: Principal) = this {

  type HttpRequest = HTTP.HttpRequest;
  type HttpResponse = HTTP.HttpResponse;

  let db : DBTypes.DBInterface = actor(Principal.toText(dbCanisterId));

  public func getNodeCanisterID() : async Principal {
        return Principal.fromActor(this);
    };

    public func findAndAssignJob() : async ?{user_principal_id : Text; client_id : Int; downloadSpeed : Float} {
      let optimalNode = await db.findAndAssignJob();
      return optimalNode;
   };

   public func createNewJob(jobType : Text, url : Text, ) : async Result.Result<Text, Text>  {
      let data = await db.addJobToDB(jobType, url);
      return data;
   };

   public func assignJobToClient(user_principal_id : Text, client_id : Int) : async Result.Result<Text, Text>  {
      let data = await db.assignJobToClient(user_principal_id, client_id);
      return data;
   };

   public func updateJobComplete(user_principal_id : Text, client_id : Int, result: Text) : async Result.Result<Text, Text>  {
      let data = await db.updateJobCompleted(user_principal_id, client_id, result);
      return data;
   };

  public func handleRequestAuth(user_principal_id : Text) : async Result.Result<Text, Text> {
    //check in DB if prinicpal ID is present
    Debug.print("Inside handleRequestAuth");
    return await db.clientAuthorization(user_principal_id);
  };

  private func login(user_principal_id : Text) : async Result.Result<database_ops.ClientStruct, Text> {
    //check in DB if prinicpal ID is present
    Debug.print("Inside login");
    return await db.login(user_principal_id);
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
    let body = req.body;

    Debug.print("path: " # debug_show (path));
    Debug.print("method: " # debug_show (method));
    Debug.print("body: " # debug_show (body));
    Debug.print("headers: " # debug_show (headers));

    // Extract the base path and query parameters
    let parts = Text.split(path, #text "&");
    let basePath = Option.get(parts.next(), "/");
    let queryParams = Option.get(parts.next(), "");

    // Check if the query parameter contains "requestMethod=requestAuth"
    let isRequestAuth = Text.contains(queryParams, #text "requestMethod=requestAuth");

    Debug.print("isRequestAuth: " # debug_show (isRequestAuth));
    Debug.print("queryParams: " # debug_show (queryParams));
    Debug.print("basePath: " # debug_show (basePath));

    switch (method, path, isRequestAuth) {
      case ("GET", "/getUserData", _) {
        let authHeader = getHeader(headers, "authorization");
        switch (authHeader) {
          case null {
            Debug.print("Missing Authorization header ");
            return badRequest("Missing Authorization header");
          };
          case (?principalID) {
            switch (await login(principalID)) {
              case (#ok(userData)) {
                // Constructing the JSON manually
                let jsonBody = "{" #
                    "\"function\": \"Get Data\"," #
                    "\"message\": \"Getting client data\"," #
                    "\"user_principal_id\": \"" # userData.user_principal_id # "\"," #
                    "\"balance\": \"" # Float.toText(userData.balance) # "\"," #
                    "\"todaysEarnings\": \"" # Float.toText(userData.latestReward) # "\"," #
                    "\"referralCode\": \"" # userData.referralCode # "\"," #
                    "\"state\": \"waiting\"," #
                    "\"status\": \"OK\"," #
                    "\"jobAssigned\": false" #
                "}";

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
      case ("GET", _, true) {   
          Debug.print("Inside requestAuth API");
          let authHeader = getHeader(headers, "Authorization");
          switch (authHeader) {
            case null {
              Debug.print("Missing Authorization header ");
              return badRequest("Missing Authorization header");
            };
            case (?principalID) {
              switch (await handleRequestAuth(principalID)) {
                case (#ok(_)) {
                  Debug.print("RequestAuth OK");
                  // Constructing the JSON manually
                  let jsonBody = "{\"status\": \"RequestAuth OK\"}";
                  Debug.print("JSON response: " # jsonBody);
                  return {
                    status_code = 200;
                    headers = [("Content-Type", "application/json"), ("X-Auth-Status", "OK")];
                    body = Text.encodeUtf8(jsonBody);
                    streaming_strategy = null;
                    upgrade = null;
                  };
                };
                case (#err(errorMsg)) {
                   Debug.print("RequestAuth ERROR");
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
