import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Int "mo:base/Int";
import JSON "mo:json/JSON";
import Result "mo:base/Result";
import Http "mo:http-parser";
import DatabaseOps "../nodeCanister/modules/database_ops";
import HttpHandler "../nodeCanister/modules/http_handler";

actor{

    type HttpRequest = HttpHandler.HttpRequest;
    type HttpResponse = HttpHandler.HttpResponse;

    var sockCanisterIDURL = "by6od-j4aaa-aaaaa-qaadq-cai.localhost:4943";
    var sockCanisterID = "by6od-j4aaa-aaaaa-qaadq-cai";

    public shared func webSocketRequestForUserData(user_principal_id : Text) : async Result.Result<Text, Text> {
        
        #ok("ok")
    };

    public query func http_request() : async HttpResponse {
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

        switch (method, path) {
            case ("GET", "/ping") {
                let jsonBody = "{" #
                    "\"status\": \"OK\"," #
                "}";
                return {
                  status_code = 200;
                  headers = [("Content-Type", "application/json")];
                  body = Text.encodeUtf8(jsonBody);
                  streaming_strategy = null;
                  upgrade = null;
                };
            };

            case ("GET", "/requestAuth") {                
                let jsonBody = "{" #
                    "\"status\": \"OK\"," #
                "}";
                return {
                  status_code = 200;
                  headers = [("Content-Type", "application/json")];
                  body = Text.encodeUtf8(jsonBody);
                  streaming_strategy = null;
                  upgrade = null;
                };
            };

            case ("GET", "/responseAuth") {       
                let authHeader = getHeader(headers, "authorization");
                switch (authHeader) {
                    case (?value) {
                        if (value == "success") {
                            let jsonBody = "{" #
                                "\"status\": \"OK\"," #
                                "\"message\": \"Authorization successful\"" #
                            "}";
                            return {
                                status_code = 200;
                                headers = [("Content-Type", "application/json")];
                                body = Text.encodeUtf8(jsonBody);
                                streaming_strategy = null;
                                upgrade = null;
                            };
                        } else {
                            let jsonBody = "{" #
                                "\"status\": \"Unauthorized\"," #
                                "\"message\": \"Invalid authorization\"" #
                            "}";
                            return {
                                status_code = 401;
                                headers = [("Content-Type", "application/json")];
                                body = Text.encodeUtf8(jsonBody);
                                streaming_strategy = null;
                                upgrade = null;
                            };
                        }
                    };
                    case null {
                        let jsonBody = "{" #
                            "\"status\": \"Bad Request\"," #
                            "\"message\": \"Missing authorization header\"" #
                        "}";
                        return {
                            status_code = 400;
                            headers = [("Content-Type", "application/json")];
                            body = Text.encodeUtf8(jsonBody);
                            streaming_strategy = null;
                            upgrade = null;
                        };
                    };
                };
            };

            
            case ("POST", "/requestScrape") {
                let jsonBody = "{" #
                    "\"status\": \"OK\"," #
                    "\"message\": \"ok\"" #
                "}";
                return {
                    status_code = 200;
                    headers = [("Content-Type", "application/json")];
                    body = Text.encodeUtf8(jsonBody);
                    streaming_strategy = null;
                    upgrade = null;
                };


                // let authHeader = getHeader(headers, "authorization");
                
                // // Decode and parse request body
                // let bodyText = switch (Text.decodeUtf8(req.body)) {
                //     case (null) { return badRequest("Invalid UTF-8 in request body") };
                //     case (?v) { v };
                // };

                // Debug.print("Decoded body: " # bodyText);

                // switch (JSON.parse(bodyText)) {
                //     case (null) { return badRequest("Invalid JSON in request body") };
                //     case (?jsonObj) {
                //         switch (jsonObj) {
                //             case (#Object(fields)) {
                //                 var client_id : Int = 0;
                                
                //                 // Extract client_id from request body
                //                 for ((key, value) in fields.vals()) {
                //                     switch (key, value) {
                //                         case ("client_id", #Number(v)) { 
                //                             client_id := v;
                //                         };
                //                         case _ {};
                //                     };
                //                 };

                //                 if (client_id == 0) {
                //                     return badRequest("Missing or invalid client_id in request body");
                //                 };

                //                 switch (authHeader) {
                //                     case null {
                //                         Debug.print("Missing Authorization header ");
                //                         return badRequest("Missing Authorization header");
                //                     };
                //                     case (?user_principal_id) {
                //                         let result = await clientConnect(user_principal_id, client_id);
                //                         switch (result) {
                //                             case (#ok(response)) {
                //                                 return {
                //                                     status_code = 200;
                //                                     headers = [("Content-Type", "application/json")];
                //                                     body = Text.encodeUtf8(response);
                //                                     streaming_strategy = null;
                //                                     upgrade = null;
                //                                 };
                //                             };
                //                             case (#err(error)) {
                //                                 return badRequest(error);
                //                             };
                //                         };
                //                     };
                //                 };
                //             };
                //             case _ { return badRequest("Invalid JSON format") };
                //         };
                //     };
                // };
             };
            case _ {
                return notFound();
            };
        };
    };

    // Helper functions for HTTP responses
    func badRequest(msg : Text) : HttpResponse {
        HttpHandler.badRequest(msg)
    };

    func notFound() : HttpResponse {
        HttpHandler.notFound()
    };

    // Helper function to get header value
    func getHeader(headers : [(Text, Text)], name : Text) : ?Text {
        HttpHandler.getHeader(headers, name)
    };

    private func createJsonResponse(status : Text, message : Text, user_principal_id : Text, state : Text) : Text {
        HttpHandler.createJsonResponse(status, message, user_principal_id, state)
    };
}

