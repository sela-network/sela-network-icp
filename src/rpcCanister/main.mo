import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Int "mo:base/Int";
import JSON "mo:json/JSON";
import Result "mo:base/Result";
import HTTP "../common/Http";
import Principal "mo:base/Principal";
import Option "mo:base/Option";
import Nat64 "mo:base/Nat64";
import Float "mo:base/Float";
import nodeCanister "canister:nodeCanister";
import Sock "canister:rpcCanisterSock";
import HttpHandler "../common/http_handler";

shared(installer) actor class canister() = this {

    type HttpRequest = HTTP.HttpRequest;
    type HttpResponse = HTTP.HttpResponse;
    type HeaderField = (Text, Text);

    public shared func webSocketRequestForUserData() : async Result.Result<Text, Text> {
        #ok("ok")
    };

    public func getRpcCanisterID() : async Principal {
        return Principal.fromActor(this);
    };

    private func getOptimalNode(url : Text, scrapeType : Text) : async ?{user_principal_id : Text; client_id : Int; downloadSpeed : Float} {
        let optimalNode = await nodeCanister.findAndAssignJob();
        //send job to client
        switch (optimalNode) {
            case (null) {
                // No optimal node found
                Debug.print("No optimal node found");
                return null;
            };
            case (?node) {
                // Optimal node found, send job to client
                Debug.print("Optimal node found");
                let clientIdNat64 = Nat64.fromNat(Int.abs(node.client_id));
                let _send = await Sock.send_job_to_client(clientIdNat64, node.user_principal_id, url, scrapeType);
                return ?node;
            };
        };
    };

    private func addJobToDB(url : Text, scrapeType : Text) : async Result.Result<Text, Text> {
        let addJob = await nodeCanister.createNewJob(scrapeType, url);
        return addJob;
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

        switch (method, path) {
            case ("GET", "/ping") {
                return handlePing();
            };
            
            case ("POST", "/requestJob") {
                let authHeader = getHeader(headers, "authorization");
                
                // Decode and parse request body
                let bodyText = switch (Text.decodeUtf8(req.body)) {
                    case (null) { return badRequest("Invalid UTF-8 in request body") };
                    case (?v) { v };
                };

                Debug.print("Decoded body: " # bodyText);

                switch (JSON.parse(bodyText)) {
                    case (null) { return badRequest("Invalid JSON in request body") };
                    case (?jsonObj) {
                        switch (jsonObj) {
                            case (#Object(fields)) {
                                var url : Text = "";
                                var scrapeType : Text = "";
                                
                                // Extract url from request body
                                for ((key, value) in fields.vals()) {
                                    switch (key, value) {
                                        case ("url", #String(v)) { url := v };
                                        case ("scrapeType", #String(v)) { scrapeType := v };
                                        case _ {};
                                    };
                                };

                                if (url == "" or scrapeType == "") {
                                    return badRequest("Missing or invalid client_id in request body");
                                };

                                switch (authHeader) {
                                    case null {
                                        Debug.print("Missing Authorization header ");
                                        return badRequest("Missing Authorization header");
                                    };
                                    case (?user_principal_id) {
                                    let addJob = await addJobToDB(url, scrapeType);
                                    switch (addJob) {
                                        case (#ok(_)) {
                                            // Successfully added job
                                            Debug.print("Job added successfully");
                                            // You can return a success response or perform further actions here
                                        };
                                        case (#err(error)) {
                                            // Failed to add job
                                            Debug.print("Failed to add job: " # error);
                                            return badRequest("Failed to add job to DB");
                                        };
                                    };

                                    let result = await getOptimalNode(url, scrapeType);
                                    switch (result) {
                                        case (null) {
                                            return badRequest("No optimal node found");
                                        };
                                        case (?node) {
                                            let jsonResponse = "{" #
                                                "\"function\": \"Notification\"," #
                                                "\"message\": \"Client found, sending job details\"," #
                                                "\"url\": \"" # url # "\"," #
                                                "\"scrapeType\": \"" # scrapeType # "\"," #
                                                "\"user_principal_id\": \"" # node.user_principal_id # "\"," #
                                                "\"client_id\": \"" # Int.toText(node.client_id) # "\"," #
                                                "\"downloadSpeed\": \"" # Float.toText(node.downloadSpeed) # "\"," #
                                                "\"state\": \"assigned\"," #
                                                "\"status\": \"OK\"," #
                                                "\"jobAssigned\": true" #
                                            "}";
                                            return {
                                                status_code = 200;
                                                headers = [("Content-Type", "application/json")];
                                                body = Text.encodeUtf8(jsonResponse);
                                                streaming_strategy = null;
                                                upgrade = null;
                                            };
                                        };
                                    };
                                };
                                };
                            };
                            case _ { return badRequest("Invalid JSON format") };
                        };
                    };
                };
             };
             case _ {
                return {
                    status_code = 404;
                    headers = [("Content-Type", "text/plain")];
                    body = Text.encodeUtf8("Not Found");
                    streaming_strategy = null;
                    upgrade = null;
                };
            };
        };
    };

    func handlePing() : HttpResponse {
        let jsonBody = "{\"status\": \"OK\"}";
        return {
            status_code = 200;
            headers = [("Content-Type", "application/json")];
            body = Text.encodeUtf8(jsonBody);
            streaming_strategy = null;
            upgrade = null;
        };
    };

    func handleRequestAuth() : HttpResponse {
        let jsonBody = "{\"status\": \"RequestAuth OK\"}";
        return {
            status_code = 200;
            headers = [("Content-Type", "application/json")];
            body = Text.encodeUtf8(jsonBody);
            streaming_strategy = null;
            upgrade = null;
        };
    };

    func handleResponseAuth(authHeader: Text) : HttpResponse {
        Debug.print("Inside responseAuth API: ");   
        Debug.print("authHeader: " # debug_show (authHeader));
        
        if (authHeader == "success") {
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
        } else if (authHeader == "") {
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
    func getHeader(headers: [HeaderField], name: Text) : ?Text {
        HttpHandler.getHeader(headers, name)
    };

    private func createJsonResponse(status : Text, message : Text, user_principal_id : Text, state : Text) : Text {
        HttpHandler.createJsonResponse(status, message, user_principal_id, state)
    };
}

