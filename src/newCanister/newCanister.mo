import Http "mo:http-parser";
import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Error "mo:base/Error";
import Result "mo:base/Result";

actor CallingCanister {

    type UserData = {
        principalID : Text;
        balance : Float;
        todaysEarnings : Float;
        referralCode : Text;
        totalReferral : Float;
    };

    public func callTargetCanister() : async Text {
        let targetCanisterId = "by6od-j4aaa-aaaaa-qaadq-cai.localhost:4943"; // Replace with actual canister ID
        let url = "http://" # targetCanisterId # "/getUserData";

        let headers = Http.Headers([("Authorization", "u1")]);

        // Prepare the HTTP request (method GET, URL, headers)
        let request : Http.HttpRequest = {
            url = url;
            method = "GET";
            headers = headers.original;
            body = "";
        };

        let ic : actor {
            http_request : Http.HttpRequest -> async Http.HttpResponse;
        } = actor ("by6od-j4aaa-aaaaa-qaadq-cai");

        try {
            let response = await ic.http_request(request);
            switch (Text.decodeUtf8(response.body)) {
                case (?body) {
                    Debug.print("Response body: " # body);
                    return body;
                };
                case null {
                    return "Failed to decode response";
                };
            };
        } catch (error) {
            let errorMessage = Error.message(error);
            Debug.print("Error calling target canister: " # errorMessage);
            return "Error calling target canister: " # errorMessage;
        };
    };

    public func callTargetCanisterTest() : async Text {
        let targetCanisterId = Principal.fromText("by6od-j4aaa-aaaaa-qaadq-cai"); // Remove localhost part

        // Actor reference to the target canister
        let targetCanister : actor {
            getUserData : (Text) -> async Result.Result<UserData, Text>;
        } = actor (Principal.toText(targetCanisterId));

        try {
            let result = await targetCanister.getUserData("u1");
            Debug.print("Response: " # debug_show (result));

            switch (result) {
                case (#ok(userData)) {
                    // Handle successful case
                    return "User data retrieved successfully: " # debug_show (userData);
                };
                case (#err(errorMessage)) {
                    // Handle error case
                    return "Error retrieving user data: " # errorMessage;
                };
            };
        } catch (error) {
            let errorMessage = Error.message(error);
            Debug.print("Error calling target canister: " # errorMessage);
            return "Error calling target canister: " # errorMessage;
        };
    };
};
