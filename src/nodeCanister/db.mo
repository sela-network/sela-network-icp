import Principal "mo:base/Principal";
import Time "mo:base/Time";
import _Timer "mo:base/Timer";
import Text "mo:base/Text";
import Int "mo:base/Int";
import Result "mo:base/Result";
import CanDB "mo:candb/CanDB";
import Error "mo:base/Error";
import Random "../common/utils";
import Entity "mo:candb/Entity";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Nat = "mo:base/Nat";
import JSON "mo:json/JSON";
import Float "mo:base/Float";
import Char "mo:base/Char";
import Nat32 "mo:base/Nat32";

import DatabaseOps "./modules/database_ops";
import HttpHandler "../common/http_handler";

actor {
    private let DEAD_TIMEOUT : Int = 3_600_000_000_000; // 1 hour in nanoseconds

    type ClientStruct = DatabaseOps.ClientStruct;
    type JobStruct = DatabaseOps.JobStruct;
    type HttpRequest = HttpHandler.HttpRequest;
    type HttpResponse = HttpHandler.HttpResponse;


    public shared func dummyAutoScalingHook(_ : Text) : async Text {
        return "";
    };

    let scalingOptions : CanDB.ScalingOptions = {
        autoScalingHook = dummyAutoScalingHook;
        sizeLimit = #count(1000);
    };

    stable let clientDB = CanDB.init({
        pk = "clientTable";
        scalingOptions = scalingOptions;
        btreeOrder = null;
    });

    stable let jobDB = CanDB.init({
        pk = "jobTable";
        scalingOptions = scalingOptions;
        btreeOrder = null;
    });

    private func createClientEntity(user_principal_id : Text, referralCode: Text) : {
        pk : Text;
        sk : Text;
        attributes : [(Text, Entity.AttributeValue)];
    } {
        Debug.print("Attempting to create client entity: ");
        {
            pk = "clientTable";
            sk = user_principal_id;
            attributes = [
                ("user_principal_id", #text(user_principal_id)),
                ("client_id", #int(0)),
                ("jobID", #text("")),
                ("jobStatus", #text("notWorking")),
                ("downloadSpeed", #float(0.0)),
                ("ping", #int(0)),
                ("wsConnect", #int(Time.now())),
                ("wsDisconnect", #int(0)),
                ("jobStartTime", #int(0)),
                ("jobEndTime", #int(0)),
                ("latestReward", #float(0.0)),
                ("balance", #float(0.0)),
                ("referralCode", #text(referralCode)),
            ];
        };
    };

    private func createJobEntity(jobId : Text, jobType : Text, url : Text) : {
        pk : Text;
        sk : Text;
        attributes : [(Text, Entity.AttributeValue)];
    } {
        // Create a job entity with default values and the passed jobType and url
        Debug.print("Attempting to create job entity: " # jobId);
        return {
            pk = "jobTable"; // CanDB partition key
            sk = jobId; // Unique job ID (can be generated as a timestamp or counter)
            attributes = [
                ("jobID", #text(jobId)), // Job ID
                ("jobType", #text(jobType)), // Job type
                ("url", #text(url)), // Job url (like scrape twitter, etc.)
                ("state", #text("pending")), // Default state is "pending"
                ("result", #text("")), // Empty result initially (empty JSON object)
                ("user_principal_id", #text("")), // Initially, no client is assigned
                ("assignedAt", #int(0)),
                ("completeAt", #int(0)), // Initially, not completed (can use 0 or null)
                ("reward", #float(0.0)),
            ];
        };
    };

    public shared func addClientToDB(user_principal_id : Text, referralCode: Text) : async Result.Result<Text, Text> {
        Debug.print("Attempting to insert client with user_principal_id: " # user_principal_id);

        try {
           Debug.print("New client");
            let entity = createClientEntity(user_principal_id, referralCode);
            Debug.print("Client entity creation done ");
            await* CanDB.put(clientDB, entity);
            Debug.print("Entity inserted successfully for user_principal_id: " # user_principal_id);
            // Create a JSON response
            let jsonResponse = "{" #
            "\"status\": \"success\"," #
            "\"message\": \"Client successfully inserted\"," #
            "\"user_principal_id\": \"" # user_principal_id # "\"" #
            "\"state\": \"" # "new" # "\"" #
            "}";

            return #ok(jsonResponse);
        } catch (error) {
            Debug.print("Error caught in job insertion: " # Error.message(error));
            return #err("Failed to job insertion: " # Error.message(error));
        };
    };

    public shared func addJobToDB(jobType : Text, url : Text) : async Result.Result<Text, Text> {
        let randomGenerator = Random.new();
        let jobId_ = await randomGenerator.next();
        let jobId = "job" # jobId_;
        Debug.print("Attempting to insert job with jobID: " # jobId);

        if (Text.size(jobId) == 0) {
            return #err("Invalid input: jobId must not be empty");
        };

        try {
            // First, check if the user already exists
            let existingjob = CanDB.get(jobDB, { pk = "jobTable"; sk = jobId });

            switch (existingjob) {
                case (?_) {
                    // Job already exists, return an error
                    Debug.print("Job already exists for jobId: " # jobId);
                    return #err("Job already exists");
                };
                case null {
                    // Job doesn't exist, proceed with insertion
                    Debug.print("New job");
                    let entity = createJobEntity(jobId, jobType, url);
                    Debug.print("Job entity creation done ");
                    await* CanDB.put(jobDB, entity);
                    Debug.print("Entity inserted successfully for jobId: " # jobId);
                    // Create a JSON response
                    let jsonResponse = "{" #
                    "\"status\": \"success\"," #
                    "\"message\": \"Job successfully inserted\"," #
                    "\"jobId\": \"" # jobId # "\"" #
                    "}";

                    return #ok(jsonResponse);
                };
            };
        } catch (error) {
            Debug.print("Error caught in job insertion: " # Error.message(error));
            return #err("Failed to job insertion: " # Error.message(error));
        };
    };

    public shared func updateJobCompleted(user_principal_id : Text, client_id : Int, result : Text) : async Result.Result<Text, Text> {
        Debug.print("Request sent by user_principal_id to mark job as completed: " # user_principal_id);
        Debug.print("Attempting to fetch jobID");

        try {
            let clientEntity = CanDB.get(clientDB, { pk = "clientTable"; sk = user_principal_id });
            let jobID = switch (clientEntity) {
                case (?entity) {
                    switch (Entity.getAttributeMapValueForKey(entity.attributes, "jobID")) {
                        case (?(#text(jobID))) jobID;
                        case _ "unknown";
                    };
                };
                case null "unknown";
            };

            let fetchedClientID = switch (clientEntity) {
                case (?entity) {
                    switch (Entity.getAttributeMapValueForKey(entity.attributes, "client_id")) {
                        case (?(#int(clientID))) clientID;
                        case _ 0;
                    };
                };
                case null 0;
            };

            Debug.print("JobID fetched: " # jobID);
            Debug.print("ClientID fetched: " # Int.toText(fetchedClientID));

            if(fetchedClientID != client_id) {
                return #err("ClientID mismatch");
            };

            // First, retrieve the job to check its current state
            let jobEntity = CanDB.get(jobDB, { pk = "jobTable"; sk = jobID });

            switch (jobEntity) {
                case (?job) {
                    let currentState = switch (Entity.getAttributeMapValueForKey(job.attributes, "state")) {
                        case (?(#text(s))) s;
                        case _ "unknown";
                    };

                    let assignedAt = switch (Entity.getAttributeMapValueForKey(job.attributes, "assignedAt")) {
                        case (?(#int(v))) v;
                        case _ 0;
                    };

                    if (currentState != "ongoing") {
                        return #err("Job is not in 'ongoing' state");
                    };

                    // Update job state to completed
                    let updatedJobResult = await updateJobState(jobID, user_principal_id, "completed", assignedAt, Time.now(), result);

                    switch (updatedJobResult) {
                        case (#ok()) {
                            // Update client state to idle
                            let (jobStartTime, balance) = switch (clientEntity) {
                                case (?entity) {
                                    (
                                        switch (Entity.getAttributeMapValueForKey(entity.attributes, "jobStartTime")) {
                                            case (?(#int(v))) v;
                                            case _ 0;
                                        },
                                        switch (Entity.getAttributeMapValueForKey(entity.attributes, "balance")) {
                                            case (?(#float(v))) v;
                                            case _ 0.0;
                                        }
                                    );
                                };
                                case null (0, 0.0);
                            };

                            let endTime = Time.now();

                            // Calculate the points
                            let timeDifferenceNanos : Int = endTime - jobStartTime;
                            let timeDifferenceSeconds : Float = Float.fromInt(timeDifferenceNanos) / 1_000_000_000;
                            let rewardPoints : Float = 0.012 * timeDifferenceSeconds;
                            let totalBalance : Float = balance + rewardPoints;

                            Debug.print("jobStartTime: " # debug_show(jobStartTime));
                            Debug.print("endTime: " # debug_show(endTime));
                            Debug.print("Job duration (seconds): " # debug_show(timeDifferenceSeconds));
                            Debug.print("Reward points: " # debug_show(rewardPoints));
                            Debug.print("New total balance: " # debug_show(totalBalance));

                            let updatedClientResult = await updateClientStateWithRewards(user_principal_id, "", "notWorking", jobStartTime, endTime, rewardPoints, totalBalance);

                            switch (updatedClientResult) {
                                case (#ok()) {
                                    let jsonResponse = "{" #
                                    "\"function\": \"NOTIFICATION\"," #
                                    "\"type\": \"TWITTER_POST\"," #
                                    "\"status\": \"OK\"," #
                                    "\"message\": \"Job marked as completed successfully\"," #
                                    "\"jobId\": \"" # jobID # "\"," #
                                    "\"user_principal_id\": \"" # user_principal_id # "\"," #
                                    "\"client_id\": \"" # Int.toText(client_id) # "\"," #
                                    "\"completedAt\": \"" # Int.toText(Time.now()) # "\"," #
                                    "\"balance\": \"" # Float.toText(totalBalance) # "\"," #
                                    "\"earning\": \"" # Float.toText(rewardPoints) # "\"" #
                                    "}";
                                    Debug.print("jsonResponse: " # debug_show(jsonResponse));
                                    #ok(jsonResponse);
                                };
                                case (#err(errorMsg)) {
                                    // Job is completed, but client state update failed
                                    let jsonResponse = "{" #
                                    "\"function\": \"NOTIFICATION\"," #
                                    "\"type\": \"TWITTER_POST\"," #
                                    "\"status\": \"partial_success\"," #
                                    "\"message\": \"Job completed but failed to update client state: " # errorMsg # "\"," #
                                    "\"jobId\": \"" # jobID # "\"," #
                                    "\"client_id\": \"" # Int.toText(client_id) # "\"," #
                                    "\"user_principal_id\": \"" # user_principal_id # "\"," #
                                    "\"balance\": \"" # Float.toText(totalBalance) # "\"," #
                                    "\"earning\": \"" # Float.toText(rewardPoints) # "\"" #
                                    "}";
                                    Debug.print("jsonResponse: " # debug_show(jsonResponse));
                                    #ok(jsonResponse);
                                };
                            };
                        };
                        case (#err(errorMsg)) {
                            #err("Failed to update job state: " # errorMsg);
                        };
                    };
                };
                case null {
                    #err("Job not found");
                };
            };
        } catch (error) {
            Debug.print("Error in updateJobCompleted: " # Error.message(error));
            #err("An unexpected error occurred: " # Error.message(error));
        };
    };

    public query func getJobWithID(jobID : Text) : async Result.Result<JobStruct, Text> {
        Debug.print("Attempting to get job with jobID: " # jobID);

        try {
            let existingJob = CanDB.get(jobDB, { pk = "jobTable"; sk = jobID });

            switch (existingJob) {
                case null {
                    Debug.print("Job not found for jobID: " # jobID);
                    #err("Job not found");
                };
                case (?entity) {
                    switch (unwrapJobEntity(entity)) {
                        case (?jobStruct) {
                            #ok(jobStruct);
                        };
                        case null {
                            #err("Error unwrapping job data");
                        };
                    };
                };
            };
        } catch (error) {
            Debug.print("Error in get function: " # Error.message(error));
            #err("Failed to get user: " # Error.message(error));
        };
    };

    public shared query func getClientWithID(user_principal_id : Text) : async Result.Result<ClientStruct, Text> {
        Debug.print("Attempting to get client with user_principal_id: " # user_principal_id);

        try {
            let existingClient = CanDB.get(clientDB, { pk = "clientTable"; sk = user_principal_id });

            switch (existingClient) {
                case null {
                    Debug.print("Client not found for user_principal_id: " # user_principal_id);
                    #err("Client not found");
                };
                case (?entity) {
                    switch (unwrapClientEntity(entity)) {
                        case (?clientStruct) {
                            #ok(clientStruct);
                        };
                        case null {
                            #err("Error unwrapping client data");
                        };
                    };
                };
            };
        } catch (error) {
            Debug.print("Error in get function: " # Error.message(error));
            #err("Failed to get user: " # Error.message(error));
        };
    };

    public shared query func clientAuthorization(user_principal_id : Text) : async Result.Result<Text, Text> {
        Debug.print("Attempting to get client with user_principal_id: " # user_principal_id);

        try {
            let existingClient = CanDB.get(clientDB, { pk = "clientTable"; sk = user_principal_id });

            switch (existingClient) {
                case null {
                    Debug.print("Client not found for user_principal_id: " # user_principal_id);
                    #err("Client not found");
                };
                case (?entity) {
                    Debug.print("Client found in DB with user_principal_id: " # user_principal_id);
                    #ok("OK");
                };
            };
        } catch (error) {
            Debug.print("Error in get function: " # Error.message(error));
            #err("Failed to get user: " # Error.message(error));
        };
    };

    public shared query func getPendingJobs() : async Result.Result<Text, Text> {
        Debug.print("Received request to fetch pending jobs: ");

        let skLowerBound = "job"; // Start of the range for client keys
        let skUpperBound = "job~"; // End of the range for client keys
        let limit = 10000; // Limit number of records to scan
        let ascending = null; // Not specifying order

        // Use CanDB.scan to retrieve job records
        let { entities } = CanDB.scan(
            jobDB,
            {
                skLowerBound = skLowerBound;
                skUpperBound = skUpperBound;
                limit = limit;
                ascending = ascending;
            },
        );

        Debug.print("Total entities: " # debug_show (entities.size()));
        
        let pendingJobs = Array.filter(
            entities,
            func(entity : { attributes : Entity.AttributeMap; pk : Text; sk : Text }) : Bool {
                switch (Entity.getAttributeMapValueForKey(entity.attributes, "state")) {
                    case (?(#text(state))) { 
                        Debug.print("Job state: " # state);
                        Text.equal(state, "pending") 
                    };
                    case _ { false };
                };
            }
        );

        if (pendingJobs.size() == 0) {
            let jsonResponse = "{" #
            "\"status\": \"success\"," #
            "\"message\": \"No pending jobs found in the database\"," #
            "\"count\": 0" #
            "}";
            return #ok(jsonResponse);
        } else {
            // Process pending jobs
            let pendingJobsCount = pendingJobs.size();
            let jsonResponse = "{" #
            "\"status\": \"success\"," #
            "\"message\": \"Pending jobs found\"," #
            "\"count\": " # Nat.toText(pendingJobsCount) #
            "}";
            Debug.print("Pending jobs right now: " # debug_show (jsonResponse));
            return #ok(jsonResponse);
        };
    };

    public shared func assignJobToClient(user_principal_id : Text, client_id : Int) : async Result.Result<Text, Text> {
        Debug.print("Received client with user_principal_id: " # user_principal_id);

        try {
            if (Text.size(user_principal_id) == 0) {
                return #err("Invalid input: user_principal_id must not be empty");
            };

            let jobScanResult = CanDB.scan(
                jobDB,
                {
                    skLowerBound = "job";
                    skUpperBound = "job~";
                    limit = 10000;
                    ascending = null;
                    filter = ?{
                        attributeName = "state";
                        operator = #equal;
                        value = #text("pending");
                    };
                }
            );

            // Add explicit filtering after scan
            let pendingJobs = Array.filter(
                jobScanResult.entities,
                func(entity : { attributes : Entity.AttributeMap; pk : Text; sk : Text }) : Bool {
                    switch (Entity.getAttributeMapValueForKey(entity.attributes, "state")) {
                        case (?(#text(state))) { 
                            Debug.print("Job state: " # state);
                            Text.equal(state, "pending") 
                        };
                        case _ { false };
                    };
                }
            );           
            switch (pendingJobs.size()) {
                case 0 {
                    Debug.print("No pending jobs found");
                    #err("No pending jobs available");
                };
                case _ {
                    Debug.print("Job found");
                    let job = pendingJobs[0];
                    let jobID = job.sk;

                    // Update job state to ongoing
                    let updatedJobResult = await updateJobState(jobID, user_principal_id, "ongoing", Time.now(), 0, "");

                    switch (updatedJobResult) {
                        case (#ok()) {
                            // Update client state to working
                            let existingClient = CanDB.get(clientDB, { pk = "clientTable"; sk = user_principal_id });
                            let (currentWsConnect, currentWsDisconnect) = switch (existingClient) {
                                case (?entity) {
                                    (
                                        switch (Entity.getAttributeMapValueForKey(entity.attributes, "wsConnect")) {
                                            case (?(#int(v))) v;
                                            case _ 0;
                                        },
                                        switch (Entity.getAttributeMapValueForKey(entity.attributes, "wsDisconnect")) {
                                            case (?(#int(v))) v;
                                            case _ 0;
                                        }
                                    );
                                };
                                case null (0, 0);
                            };
                            let updatedClientResult = await updateClientState(user_principal_id, client_id, jobID, "working", currentWsConnect, currentWsDisconnect, Time.now(), 0);

                            switch (updatedClientResult) {
                                case (#ok()) {
                                    let jsonResponse = "{" #
                                    "\"status\": \"success\"," #
                                    "\"message\": \"Job assigned successfully\"," #
                                    "\"jobId\": \"" # jobID # "\"," #
                                    "\"user_principal_id\": \"" # user_principal_id # "\"" #
                                    "}";
                                    #ok(jsonResponse);
                                };
                                case (#err(errorMsg)) {
                                    // Revert job state if client update fails
                                    ignore updateJobState(jobID, user_principal_id, "pending", 0, 0, "");
                                    #err("Failed to update client state: " # errorMsg);
                                };
                            };
                        };
                        case (#err(errorMsg)) {
                            #err("Failed to update job state: " # errorMsg);
                        };
                    };
                };
            };
        } catch (error) {
            Debug.print("Error caught in job update: " # Error.message(error));
            return #err("Failed to update job: " # Error.message(error));
        };
    };

    private func updateClientStateWithRewards(
        user_principal_id : Text, 
        jobID : Text, 
        jobStatus : Text, 
        jobStartTime : Int,
        jobEndTime : Int,
        latestRewards : Float,
        balance : Float) : async Result.Result<(), Text> {
        Debug.print("Attempting to update client with rewards info with user_principal_id: " # user_principal_id);

        try {
            let existingClient = CanDB.get(clientDB, { pk = "clientTable"; sk = user_principal_id });

            switch (existingClient) {
                case (?_clientEntity) {
                    Debug.print("Client found in DB with user_principal_id: " # user_principal_id);

                    let updatedAttributes = [
                        ("jobID", #text(jobID)),
                        ("jobStatus", #text(jobStatus)),
                        ("jobStartTime", #int(jobStartTime)),
                        ("jobEndTime", #int(jobEndTime)),
                        ("latestReward", #float(latestRewards)),
                        ("balance", #float(balance)),
                    ];

                    func updateAttributes(attributeMap : ?Entity.AttributeMap) : Entity.AttributeMap {
                        switch (attributeMap) {
                            case null {
                                Entity.createAttributeMapFromKVPairs(updatedAttributes);
                            };
                            case (?map) {
                                Entity.updateAttributeMapWithKVPairs(map, updatedAttributes);
                            };
                        };
                    };

                    let _ = switch (
                        CanDB.update(
                            clientDB,
                            {
                                pk = "clientTable";
                                sk = user_principal_id;
                                updateAttributeMapFunction = updateAttributes;
                            },
                        )
                    ) {
                        case null {
                            Debug.print("Failed to update client with rewards: " # user_principal_id);
                            #err("Failed to update client");
                        };
                        case (?_) {
                            #ok();
                        };
                    };
                };
                case null {
                    Debug.print("Client does not exist with user_principal_id: " # user_principal_id);
                    #err("Client does not exist");
                };
            };
        } catch (error) {
            Debug.print("Error caught in client update: " # Error.message(error));
            #err("Failed to update client: " # Error.message(error));
        };
    };

    private func updateClientState(
        user_principal_id : Text, 
        client_id : Int, 
        jobID : Text, 
        jobStatus : Text, 
        wsConnect : Int, 
        wsDisconnect : Int,
        jobStartTime : Int,
        jobEndTime : Int) : async Result.Result<(), Text> {
        Debug.print("Attempting to update client info with user_principal_id: " # user_principal_id);

        try {
            let existingClient = CanDB.get(clientDB, { pk = "clientTable"; sk = user_principal_id });

            switch (existingClient) {
                case (?_clientEntity) {
                    Debug.print("Client found in DB with user_principal_id: " # user_principal_id);

                    let updatedAttributes = [
                        ("client_id", #int(client_id)),
                        ("jobID", #text(jobID)),
                        ("jobStatus", #text(jobStatus)),
                        ("wsConnect", #int(wsConnect)),
                        ("wsDisconnect", #int(wsDisconnect)),
                        ("jobStartTime", #int(jobStartTime)),
                        ("jobEndTime", #int(jobEndTime)),
                    ];

                    func updateAttributes(attributeMap : ?Entity.AttributeMap) : Entity.AttributeMap {
                        switch (attributeMap) {
                            case null {
                                Entity.createAttributeMapFromKVPairs(updatedAttributes);
                            };
                            case (?map) {
                                Entity.updateAttributeMapWithKVPairs(map, updatedAttributes);
                            };
                        };
                    };

                    let _ = switch (
                        CanDB.update(
                            clientDB,
                            {
                                pk = "clientTable";
                                sk = user_principal_id;
                                updateAttributeMapFunction = updateAttributes;
                            },
                        )
                    ) {
                        case null {
                            Debug.print("Failed to update client: " # user_principal_id);
                            #err("Failed to update client");
                        };
                        case (?_) {
                            #ok();
                        };
                    };
                };
                case null {
                    Debug.print("Client does not exist with user_principal_id: " # user_principal_id);
                    #err("Client does not exist");
                };
            };
        } catch (error) {
            Debug.print("Error caught in client update: " # Error.message(error));
            #err("Failed to update client: " # Error.message(error));
        };
    };

    private func updateJobState(
        jobID : Text, 
        user_principal_id : Text, 
        newState : Text, 
        assignedAt : Int, 
        completeAt : Int, 
        result: Text) : async Result.Result<(), Text> {
        Debug.print("Attempting to update job info with jobID: " # jobID);

        try {
            let updatedAttributes = [
                ("state", #text(newState)),
                ("assignedAt", #int(assignedAt)),
                ("completeAt", #int(completeAt)),
                ("user_principal_id", #text(user_principal_id)),
                ("result", #text(result)),
            ];

            func updateAttributes(attributeMap : ?Entity.AttributeMap) : Entity.AttributeMap {
                switch (attributeMap) {
                    case null {
                        Entity.createAttributeMapFromKVPairs(updatedAttributes);
                    };
                    case (?map) {
                        Entity.updateAttributeMapWithKVPairs(map, updatedAttributes);
                    };
                };
            };

            let _updated = switch (
                CanDB.update(
                    jobDB,
                    {
                        pk = "jobTable";
                        sk = jobID;
                        updateAttributeMapFunction = updateAttributes;
                    },
                )
            ) {
                case null {
                    Debug.print("Failed to update job: " # jobID);
                    #err("Failed to update job");
                };
                case (?_) {
                    #ok();
                };
            };
        } catch (error) {
            Debug.print("Error caught in client update: " # Error.message(error));
            #err("Failed to update client: " # Error.message(error));
        };
    };

    private func updateClientID(user_principal_id : Text, client_id : Int) : async Result.Result<(), Text> {
        Debug.print("Attempting to update client_id for user_principal_id: " # user_principal_id);

        try {
            let existingClient = CanDB.get(clientDB, { pk = "clientTable"; sk = user_principal_id });

            switch (existingClient) {
                case (?_) {
                    Debug.print("Client found, updating client_id");

                    // Only update the client_id attribute
                    let updatedAttributes = [
                        ("client_id", #int(client_id)),
                        ("wsConnect", #int(Time.now())),
                        ("wsDisconnect", #int(0)),
                        ("jobStartTime", #int(0)),
                        ("jobEndTime", #int(0)),
                        ("jobID", #text("")),
                        ("jobStatus", #text("notWorking")),
                    ];

                    func updateAttributes(attributeMap : ?Entity.AttributeMap) : Entity.AttributeMap {
                        switch (attributeMap) {
                            case null {
                                Entity.createAttributeMapFromKVPairs(updatedAttributes);
                            };
                            case (?map) {
                                Entity.updateAttributeMapWithKVPairs(map, updatedAttributes);
                            };
                        };
                    };

                    switch (
                        CanDB.update(
                            clientDB,
                            {
                                pk = "clientTable";
                                sk = user_principal_id;
                                updateAttributeMapFunction = updateAttributes;
                            },
                        )
                    ) {
                        case null {
                            Debug.print("Failed to update client_id for: " # user_principal_id);
                            #err("Failed to update client_id");
                        };
                        case (?_) {
                            Debug.print("Successfully updated client_id");
                            #ok();
                        };
                    };
                };
                case null {
                    Debug.print("Client not found with user_principal_id: " # user_principal_id);
                    #err("Client not found");
                };
            };
        } catch (error) {
            Debug.print("Error updating client_id: " # Error.message(error));
            #err("Failed to update client_id: " # Error.message(error));
        };
    };

    public func updateClientInternetSpeed(user_principal_id : Text, data : Text) : async Result.Result<Text, Text> {
        Debug.print("Attempting to update client internet data with user_principal_id: " # user_principal_id);

        try {
            let existingClient = CanDB.get(clientDB, { pk = "clientTable"; sk = user_principal_id });

            switch (existingClient) {
                case null {
                    Debug.print("Client does not exist with user_principal_id: " # user_principal_id);
                    return #err("Client does not exist");
                };
                case (?_clientEntity) {
                    Debug.print("Client found in DB with user_principal_id: " # user_principal_id);

                    let downloadSpeedText = removeQuotes(extractValue(data, "downloadSpeed\":"));
                    let pingText = removeQuotes(extractValue(data, "ping\":"));

                    var downloadSpeed : Float = textToFloat(downloadSpeedText);
                    var ping : Int = textToInt(pingText);

                    Debug.print("downloadSpeedText: " # debug_show(downloadSpeedText));
                    Debug.print("pingText: " # debug_show(pingText));

                    Debug.print("downloadSpeed: " # debug_show(downloadSpeed));
                    Debug.print("ping: " # Int.toText(ping));

                    Debug.print("data: " # debug_show(data));

                    // If you need a Nat
                    let pingNat : Nat = Int.abs(ping);
                    Debug.print("ping as Nat: " # Nat.toText(pingNat));

                    // Parse the JSON string
                    let parsedData = JSON.parse(data);
                    Debug.print("Parsed Data: " # debug_show(parsedData));

                    let updatedAttributes : [(Text, Entity.AttributeValue)] = [
                        ("downloadSpeed", #float(downloadSpeed)),
                        ("ping", #int(Int.abs(ping)))
                    ];

                    func updateAttributes(attributeMap : ?Entity.AttributeMap) : Entity.AttributeMap {
                        switch (attributeMap) {
                            case null {
                                Entity.createAttributeMapFromKVPairs(updatedAttributes);
                            };
                            case (?map) {
                                Entity.updateAttributeMapWithKVPairs(map, updatedAttributes);
                            };
                        };
                    };


                    let _updateResult = switch (
                        CanDB.update(
                            clientDB,
                            {
                                pk = "clientTable";
                                sk = user_principal_id;
                                updateAttributeMapFunction = updateAttributes;
                            },
                        )
                    ) {
                        case null {
                            Debug.print("Failed to update client internet speed: " # user_principal_id);
                            #err("Failed to update client");
                        };
                        case (?_) {
                            Debug.print("Successfully updated internet speed for user_principal_id: " # user_principal_id);
                            let jsonResponse = "{" #
                                "\"function\": \"Notification\"," #
                                "\"message\": \"Client internet speed updated successfully\"," #
                                "\"user_principal_id\": \"" # user_principal_id # "\"," #
                                "\"state\": \"updated\"," #
                                "\"status\": \"OK\"" #
                            "}";
                            #ok(jsonResponse);
                        };
                    };

                    let jsonResponse = "{" #
                        "\"function\": \"Notification\"," #
                        "\"message\": \"Client internet speed updated successfully\"," #
                        "\"user_principal_id\": \"" # user_principal_id # "\"," #
                        "\"state\": \"updated\"," #
                        "\"status\": \"OK\"" #
                    "}";
                    #ok(jsonResponse);
                };
            };
        } catch (error) {
            Debug.print("Error caught while updating client internet speed: " # Error.message(error));
            return #err("Failed to update client internet speed: " # Error.message(error));
        };
    };

    func textToNumber(t : Text) : (Int, Int, Int) {
        var intPart = 0;
        var fracPart = 0;
        var fracDigits = 0;
        var isNegative = false;
        var seenDot = false;

        for (c in t.chars()) {
            switch (c) {
                case '-' { isNegative := true; };
                case '.' { seenDot := true; };
                case d {
                    let digit = Char.toNat32(d) - 48; // ASCII '0' is 48
                    if (seenDot) {
                        fracPart := fracPart * 10 + Nat32.toNat(digit);
                        fracDigits += 1;
                    } else {
                        intPart := intPart * 10 + Nat32.toNat(digit);
                    };
                };
            };
        };

        let sign = if (isNegative) -1 else 1;
        (sign * intPart, fracPart, fracDigits)
    };

    func textToFloat(t : Text) : Float {
        let (intPart, fracPart, fracDigits) = textToNumber(t);
        let fracValue = Float.fromInt(fracPart) / Float.pow(10, Float.fromInt(fracDigits));
        Float.fromInt(intPart) + (if (intPart < 0) -fracValue else fracValue)
    };

    func textToInt(t : Text) : Int {
        let (intPart, _, _) = textToNumber(t);
        intPart
    };
    
    func extractValue(text : Text, key : Text) : Text {
        let iter = Text.split(text, #text key);
        switch (iter.next()) {
            case null { "" };
            case (?_) {
                switch (iter.next()) {
                    case null { "" };
                    case (?value) {
                        let valueIter = Text.split(value, #text ",");
                        switch (valueIter.next()) {
                            case null { "" };
                            case (?v) {
                                // Remove quotation marks, closing brace, and trim whitespace
                                Text.trim(Text.replace(v, #text "\"", ""), #char '}')
                            };
                        };
                    };
                };
            };
        };
    };

    func removeQuotes(text : Text) : Text {
        Text.replace(text, #text "\"", "")
    };

    private func unwrapJobEntity(entity : Entity.Entity) : ?JobStruct {
        DatabaseOps.unwrapJobEntity(entity)
    };

    private func unwrapClientEntity(entity : Entity.Entity) : ?ClientStruct {
        DatabaseOps.unwrapClientEntity(entity)
    };

    public func login(user_principal_id : Text) : async Result.Result<ClientStruct, Text> {

        try {
            // Validate the user_principal_id as a Principal
            let _ = Principal.fromText(user_principal_id);

            // Check if the client exists in the database
            let existingClient = CanDB.get(clientDB, { pk = "clientTable"; sk = user_principal_id });

            switch (existingClient) {
                case null {
                    // If client is not found, add the client to the DB
                    Debug.print("Client not found for user_principal_id: " # user_principal_id);
                    let randomGenerator = Random.new();
                    let referralCode_ =  await randomGenerator.next();
                    let referralCode = "#ref" # referralCode_;
                    let registerClient = await addClientToDB(user_principal_id, referralCode);
                    switch (registerClient) {
                        case (#ok(_)) {
                            let getClient = CanDB.get(clientDB, { pk = "clientTable"; sk = user_principal_id });
                            switch (getClient) {
                                case (?entity) {
                                    //Client found
                                    Debug.print("Client found for user_principal_id: " # user_principal_id);
                                    switch (unwrapClientEntity(entity)) {
                                        case (?clientStruct) {
                                            #ok(clientStruct);
                                        };
                                        case null {
                                            #err("Error unwrapping client data");
                                        };
                                    };
                                };
                                case null {
                                    #err("Error getting client data");
                                };
                            };
                        };
                        case (#err(errorMessage)) {
                            Debug.print("Failed to create client: " # errorMessage);
                            #err(createJsonResponse("error", "Failed to create client", user_principal_id, "error"));
                        };
                    };
                };
                case (?entity) {
                    //Client found
                    Debug.print("Client found for user_principal_id: " # user_principal_id);
                    switch (unwrapClientEntity(entity)) {
                        case (?clientStruct) {
                            #ok(clientStruct);
                        };
                        case null {
                            #err("Error unwrapping client data");
                        };
                    };
                };
            };
        } catch (error) {
            Debug.print("An unexpected error occurred: " # Error.message(error));
            #err("An unexpected error occurred: " # Error.message(error));
        };
    };

    public func clientConnect(user_principal_id : Text, client_id : Int) : async Result.Result<Text, Text> {

        try {
            // Validate the user_principal_id as a Principal
            let _ = Principal.fromText(user_principal_id);

            // Check if the client exists in the database
            let existingClient = CanDB.get(clientDB, { pk = "clientTable"; sk = user_principal_id });

            switch (existingClient) {
                case null {
                    // If client is not found, return with error
                    let jsonResponse = "{" #
                        "\"function\": \"Notification\"," #
                        "\"message\": \"New client, Please signin first\"," #
                        "\"user_principal_id\": \"" # user_principal_id # "\"," #
                        "\"state\": \"new\"," #
                        "\"status\": \"ERROR\"," #
                    "}";
                    #ok(jsonResponse);
                };
                case (?_) {
                    //Client found, continue without changes
                    Debug.print("Client found for user_principal_id: " # user_principal_id);
                    //update client_id
                    let updateClient = await updateClientID(user_principal_id, client_id);
                    switch (updateClient) {
                        case (#ok()) {
                            let jsonResponse = "{" #
                                "\"function\": \"Notification\"," #
                                "\"message\": \"Client ID updated in DB\"," #
                                "\"user_principal_id\": \"" # user_principal_id # "\"," #
                                "\"state\": \"waiting\"," #
                                "\"status\": \"OK\"," #
                                "\"jobAssigned\": false" #
                            "}";
                            #ok(jsonResponse);
                        };
                        case (#err(errorMessage)) {
                            Debug.print("Failed to update clientID: " # errorMessage);
                            #err(createJsonResponse("error", "Failed to update clientID", user_principal_id, "error"));
                        };
                    };
                };
            };
        } catch (error) {
            Debug.print("An unexpected error occurred: " # Error.message(error));
            #err("An unexpected error occurred: " # Error.message(error));
        };
    };

    public func clientDisconnect(client_id : Int) : async Text {
        Debug.print("Client disconnecting with ID: " # Int.toText(client_id));

        try {
            // Scan clientDB to find entry with matching client_id
            let filter = ?{
                attributeName = "client_id";
                operator = #equal;
                value = #int(client_id);
            };

            let { entities } = CanDB.scan(
                clientDB,
                {
                    skLowerBound = "";
                    skUpperBound = "~";
                    limit = 1;
                    ascending = null;
                    filter = filter;
                },
            );

            switch (entities.size()) {
                case 0 {
                    return createJsonResponse("error", "Client not found", "", "unknown");
                };
                case _ {
                    let entity = entities[0];
                    let user_principal_id = entity.sk;
                    
                    // Get current job status
                    let jobID = switch (Entity.getAttributeMapValueForKey(entity.attributes, "jobID")) {
                        case (?(#text(j))) j;
                        case _ "";
                    };
                    let jobStatus = switch (Entity.getAttributeMapValueForKey(entity.attributes, "jobStatus")) {
                        case (?(#text(j))) j;
                        case _ "";
                    };
                    let wsConnect = switch (Entity.getAttributeMapValueForKey(entity.attributes, "wsConnect")) {
                        case (?(#int(t))) t;
                        case _ 0;
                    };

                    // If client was working on a job, reset it
                    if (jobID != "" and jobStatus == "working") {
                        let jobUpdateResult = await updateJobState(
                            jobID, 
                            "", 
                            "pending",
                            0, 
                            0,
                            ""
                        );

                        let clientUpdateResult = await updateClientState(
                            user_principal_id,
                            client_id,
                            "",
                            "notWorking",
                            wsConnect,
                            Time.now(),
                            0,
                            0
                        );

                        switch (jobUpdateResult, clientUpdateResult) {
                            case (#ok(), #ok()) {
                                Debug.print("Client disconnected and job reset");
                                return createJsonResponse("success", "Client disconnected and job reset", user_principal_id, jobID);
                            };
                            case _ {
                                Debug.print("Failed to update states");
                                return createJsonResponse("error", "Failed to update states", user_principal_id, "error");
                            };
                        };
                    } else {
                        // Just update disconnect time
                        let clientUpdateResult = await updateClientState(
                            user_principal_id,
                            client_id,
                            "",
                            "notWorking",
                            wsConnect,
                            Time.now(),
                            0,
                            0
                        );

                        switch (clientUpdateResult) {
                            case (#ok()) {
                                return createJsonResponse("success", "Client disconnected", user_principal_id, "");
                            };
                            case (#err(error)) {
                                Debug.print("Failed to update client: " # error);
                                return createJsonResponse("error", "Failed to update client", user_principal_id, "error");
                            };
                        };
                    };
                };
            };
        } catch (error) {
            Debug.print("Error in clientDisconnect: " # Error.message(error));
            return createJsonResponse("error", "An unexpected error occurred", "", "unknown");
        };
    };

    public func findAndAssignJob() : async ?{user_principal_id : Text; client_id : Int; downloadSpeed : Float} {
        let optimalNode = await getOptimalNode();
        switch (optimalNode) {
            case (null) {
                Debug.print("No optimal node found");
                null
            };
            case (?node) {
                let assignResult = await assignJobToClient(node.user_principal_id, node.client_id);
                switch (assignResult) {
                    case (#ok(message)) {
                        Debug.print("Optimal node found and job assigned. " # message);
                        ?node
                    };
                    case (#err(error)) {
                        Debug.print("Optimal node found but job assignment failed. " # error);
                        ?node
                    };
                };
            };
        };
    };

    private func getOptimalNode() : async ?{user_principal_id : Text; client_id : Int; downloadSpeed : Float} {
        let skLowerBound = ""; // Start of the range for client keys
        let skUpperBound = "~"; // End of the range for client keys
        let limit = 10000; // Limit number of records to scan
        let ascending = null; // Not specifying order

        // Use CanDB.scan to retrieve job records
        let { entities } = CanDB.scan(
            clientDB,
            {
                skLowerBound = skLowerBound;
                skUpperBound = skUpperBound;
                limit = limit;
                ascending = ascending;
            },
        );

        Debug.print("Total entities: " # debug_show (entities.size()));

        let entityWithMaxSpeed = Array.foldLeft(
            entities,
            null : ?{client_id : Int; downloadSpeed : Float; user_principal_id : Text},
            func(maxEntity : ?{client_id : Int; downloadSpeed : Float; user_principal_id : Text}, currentEntity : { attributes : Entity.AttributeMap; pk : Text; sk : Text }) : ?{client_id : Int; downloadSpeed : Float; user_principal_id : Text} {
                let currentSpeed = switch (Entity.getAttributeMapValueForKey(currentEntity.attributes, "downloadSpeed")) {
                    case (?(#float(speed))) speed;
                    case _ 0.0;
                };
                let currentClientId = switch (Entity.getAttributeMapValueForKey(currentEntity.attributes, "client_id")) {
                    case (?(#int(id))) id;
                    case _ 0;
                };
                let currentUserId = switch (Entity.getAttributeMapValueForKey(currentEntity.attributes, "user_principal_id")) {
                    case (?(#text(id))) id;
                    case _ "";
                };
                
                let wsDisconnect = switch (Entity.getAttributeMapValueForKey(currentEntity.attributes, "wsDisconnect")) {
                    case (?(#int(value))) value;
                    case _ 1; // Default to non-zero if not found or not an int
                };

                let jobStatus = switch (Entity.getAttributeMapValueForKey(currentEntity.attributes, "jobStatus")) {
                    case (?(#text(status))) status;
                    case _ "";
                };
                
                // Only consider this entity if wsDisconnect is 0
                if (wsDisconnect == 0 and jobStatus == "notWorking") {
                    switch (maxEntity) {
                        case (null) ?{client_id = currentClientId; downloadSpeed = currentSpeed; user_principal_id = currentUserId};
                        case (?maxEnt) {
                            if (currentSpeed > maxEnt.downloadSpeed) 
                                ?{client_id = currentClientId; downloadSpeed = currentSpeed; user_principal_id = currentUserId}
                            else 
                                ?maxEnt;
                        };
                    };
                } else {
                    maxEntity; // Keep the current max if this entity's wsDisconnect is not 0
                };
            }
        );

        return entityWithMaxSpeed;
    };

    // =============== Maintenance Tasks ===============
    private func _hourlyJobCheck() : async () {
        Debug.print("Performing hourly job check...");
        let currentTime = Time.now();

        let jobScanResult = CanDB.scan(
            jobDB,
            {
                skLowerBound = "job";
                skUpperBound = "job~";
                limit = 1000;
                ascending = null;
                filter = ?{
                    attributeName = "state";
                    operator = #equal;
                    value = #text("ongoing");
                };
            }
        );

        for (jobEntity in jobScanResult.entities.vals()) {
            switch (unwrapJobEntity(jobEntity)) {
                case null { 
                    Debug.print("Failed to unwrap job entity");
                    // Skip this iteration
                };
                case (?job) {
                    if (job.state == "ongoing") {
                        await checkAndUpdateStaleJob(job, currentTime);
                    };
                };
            };
        };

        Debug.print("Hourly job check completed.");
    };

    private func checkAndUpdateStaleJob(job : JobStruct, currentTime : Int) : async () {
        let clientResult = CanDB.get(clientDB, { pk = "clientTable"; sk = job.user_principal_id });

        switch (clientResult) {
            case (?clientEntity) {
                switch (unwrapClientEntity(clientEntity)) {
                    case (?client) {
                        if (client.wsDisconnect > 0 and currentTime - client.wsDisconnect > DEAD_TIMEOUT) {
                            // Reset job to pending state
                            ignore await DB.updateEntity(
                                jobDB,
                                "jobTable",
                                job.jobID,
                                [
                                    ("state", #text("pending")),
                                    ("user_principal_id", #text("")),
                                    ("assignedAt", #int(0))
                                ]
                            );
                        };
                    };
                    case null {
                        Debug.print("Failed to unwrap client entity");
                    };
                };
            };
            case null {
                // Client not found, reset job
                ignore await DB.updateEntity(
                    jobDB,
                    "jobTable",
                    job.jobID,
                    [
                        ("state", #text("pending")),
                        ("user_principal_id", #text("")),
                        ("assignedAt", #int(0))
                    ]
                );
            };
        };
    };

    // Optional: Uncomment to enable hourly job checking
    // ignore Timer.recurringTimer<system>(#seconds(3600), hourlyJobCheck);

    private func createJsonResponse(status : Text, message : Text, user_principal_id : Text, state : Text) : Text {
        HttpHandler.createJsonResponse(status, message, user_principal_id, state)
    };


    private module DB {
        public func updateEntity(db : CanDB.DB, pk : Text, sk : Text, updates : [(Text, Entity.AttributeValue)]) : async Result.Result<(), Text> {
            try {
                func updateAttributes(attributeMap : ?Entity.AttributeMap) : Entity.AttributeMap {
                    switch (attributeMap) {
                        case null Entity.createAttributeMapFromKVPairs(updates);
                        case (?map) Entity.updateAttributeMapWithKVPairs(map, updates);
                    };
                };

                switch (CanDB.update(db, { pk; sk; updateAttributeMapFunction = updateAttributes })) {
                    case null #err("Failed to update entity");
                    case (?_) #ok();
                };
            } catch (error) {
                Debug.print("Error in entity update: " # Error.message(error));
                #err("Update failed: " # Error.message(error));
            };
        };
    };
};
