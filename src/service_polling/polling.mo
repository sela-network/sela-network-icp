import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
import Text "mo:base/Text";
import Int "mo:base/Int";
import Result "mo:base/Result";
import CanDB "mo:candb/CanDB";
import Error "mo:base/Error";
import HTTP "../utils/Http";
import Random "../utils/Random";
import Entity "mo:candb/Entity";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Nat = "mo:base/Nat";
import JSON "mo:json/JSON";

actor polling {

    type HttpRequest = HTTP.HttpRequest;
    type HttpResponse = HTTP.HttpResponse;

    type ClientStruct = {
        clientID : Text;
        state : Text; // Possible states: "alive", "dead"
        jobID : Text;
        jobStatus : Text;
        lastAlive : Int;
    };

    type JobStruct = {
        jobID : Text;
        jobType : Text;
        target : Text;
        state : Text; // 'complete', 'pending', 'reject', 'ongoing'
        result : Text;
        clientId : Text;
        assignedAt : Int;
        completeAt : Int;
    };

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

    private func createClientEntity(clientID : Text, state : Text) : {
        pk : Text;
        sk : Text;
        attributes : [(Text, Entity.AttributeValue)];
    } {
        Debug.print("Attempting to create client entity: ");
        {
            pk = "clientTable";
            sk = clientID;
            attributes = [
                ("clientID", #text(clientID)),
                ("state", #text(state)),
                ("jobID", #text("")),
                ("jobStatus", #text("notWorking")),
                ("lastAlive", #int(0)),
            ];
        };
    };

    private func createJobEntity(jobId : Text, jobType : Text, target : Text) : {
        pk : Text;
        sk : Text;
        attributes : [(Text, Entity.AttributeValue)];
    } {
        // Create a job entity with default values and the passed jobType and target
        Debug.print("Attempting to create job entity: " # jobId);
        return {
            pk = "jobTable"; // CanDB partition key
            sk = jobId; // Unique job ID (can be generated as a timestamp or counter)
            attributes = [
                ("jobID", #text(jobId)), // Job ID
                ("jobType", #text(jobType)), // Job type
                ("target", #text(target)), // Job target (like scrape twitter, etc.)
                ("state", #text("pending")), // Default state is "pending"
                ("result", #text("")), // Empty result initially (empty JSON object)
                ("clientId", #text("")), // Initially, no client is assigned
                ("assignedAt", #int(0)),
                ("completeAt", #int(0)) // Initially, not completed (can use 0 or null)
            ];
        };
    };

    public shared func addClientToDB(clientID : Text) : async Result.Result<Text, Text> {
        Debug.print("Attempting to insert client with clientID: " # clientID);

        try {
           Debug.print("New client");
            let entity = createClientEntity(clientID, "dead");
            Debug.print("Client entity creation done ");
            await* CanDB.put(clientDB, entity);
            Debug.print("Entity inserted successfully for clientID: " # clientID);
            // Create a JSON response
            let jsonResponse = "{" #
            "\"status\": \"success\"," #
            "\"message\": \"Client successfully inserted\"," #
            "\"clientID\": \"" # clientID # "\"" #
            "\"state\": \"" # "new" # "\"" #
            "}";

            return #ok(jsonResponse);
        } catch (error) {
            Debug.print("Error caught in job insertion: " # Error.message(error));
            return #err("Failed to job insertion: " # Error.message(error));
        };
    };

    public shared func addJobToDB(jobType : Text, target : Text) : async Result.Result<Text, Text> {
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
                    let entity = createJobEntity(jobId, jobType, target);
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

    public shared func updateJobCompleted(clientID : Text, jobID : Text, result : Text) : async Result.Result<Text, Text> {
        Debug.print("Attempting to mark job as completed: " # jobID);
        Debug.print("Request sent by clientID: " # clientID);

        try {
            // First, retrieve the job to check its current state
            let jobEntity = CanDB.get(jobDB, { pk = "jobTable"; sk = jobID });

            switch (jobEntity) {
                case (?job) {
                    let currentState = switch (Entity.getAttributeMapValueForKey(job.attributes, "state")) {
                        case (?(#text(s))) s;
                        case _ "unknown";
                    };

                    let assignedAt = switch (Entity.getAttributeMapValueForKey(job.attributes, "assignedAt")) {
                        case (?(#int(t))) t;
                        case _ 0;
                    };

                    if (currentState != "ongoing") {
                        return #err("Job is not in 'ongoing' state");
                    };

                    // Update job state to completed
                    let updatedJobResult = await updateJobState(jobID, clientID, "completed", assignedAt, Time.now());

                    switch (updatedJobResult) {
                        case (#ok()) {
                            // Update client state to idle
                            let updatedClientResult = await updateClientState(clientID, "", "notWorking", "dead", Time.now());

                            switch (updatedClientResult) {
                                case (#ok()) {
                                    let jsonResponse = "{" #
                                    "\"status\": \"success\"," #
                                    "\"message\": \"Job marked as completed successfully\"," #
                                    "\"jobId\": \"" # jobID # "\"," #
                                    "\"clientId\": \"" # clientID # "\"," #
                                    "\"completedAt\": \"" # Int.toText(Time.now()) # "\"" #
                                    "}";
                                    #ok(jsonResponse);
                                };
                                case (#err(errorMsg)) {
                                    // Job is completed, but client state update failed
                                    let jsonResponse = "{" #
                                    "\"status\": \"partial_success\"," #
                                    "\"message\": \"Job completed but failed to update client state: " # errorMsg # "\"," #
                                    "\"jobId\": \"" # jobID # "\"," #
                                    "\"clientId\": \"" # clientID # "\"" #
                                    "}";
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

    public shared query func getClientWithID(clientID : Text) : async Result.Result<ClientStruct, Text> {
        Debug.print("Attempting to get client with clientID: " # clientID);

        try {
            let existingClient = CanDB.get(clientDB, { pk = "clientTable"; sk = clientID });

            switch (existingClient) {
                case null {
                    Debug.print("Client not found for clientID: " # clientID);
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

    public shared query func getPendingJobs(clientID : Text) : async Result.Result<Text, Text> {
        Debug.print("Received request to fetch pending jobs: ");

        let skLowerBound = "job"; // Start of the range for client keys
        let skUpperBound = "job~"; // End of the range for client keys
        let limit = 1000; // Limit number of records to scan
        let ascending = null; // Not specifying order

        // Use CanDB.scan to retrieve job records
        let { entities; nextKey } = CanDB.scan(
            jobDB,
            {
                skLowerBound = skLowerBound;
                skUpperBound = skUpperBound;
                limit = limit;
                ascending = ascending;
            },
        );

        Debug.print("Total entities: " # debug_show (entities.size()));
        for (entity in entities.vals()) {
            Debug.print("Entity: " # debug_show (entity));
        };

        let pendingJobs = Array.filter(
            entities,
            func(entity : { attributes : Entity.AttributeMap; pk : Text; sk : Text }) : Bool {
                switch (Entity.getAttributeMapValueForKey(entity.attributes, "state")) {
                    case (?(#text(state))) {
                        Text.equal(state, "pending");
                    };
                    case _ { false };
                };
            },
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

    public shared func assignJobToClient(clientID : Text) : async Result.Result<Text, Text> {
        Debug.print("Received client is alive with clientID: " # clientID);

        try {
            if (Text.size(clientID) == 0) {
                return #err("Invalid input: clientID must not be empty");
            };

            let skLowerBound = "job"; // Start of the range for client keys
            let skUpperBound = "job~"; // End of the range for client keys
            let limit = 1; // Limit number of records to scan
            let ascending = null; // Not specifying order

            // Create a filter for pending jobs
            let pendingFilter = ?{
                attributeName = "state";
                operator = #equal;
                value = #text("pending");
            };

            // Use CanDB.scan to retrieve job records
            let { entities; nextKey } = CanDB.scan(
                jobDB,
                {
                    skLowerBound = skLowerBound;
                    skUpperBound = skUpperBound;
                    limit = limit;
                    ascending = ascending;
                    filter = pendingFilter;
                },
            );

            switch (entities.size()) {
                case 0 {
                    Debug.print("No pending jobs found");
                    #err("No pending jobs available");
                };
                case _ {
                    let job = entities[0];
                    let jobID = job.sk;

                    // Update job state to ongoing
                    let updatedJobResult = await updateJobState(jobID, clientID, "ongoing", Time.now(), 0);

                    switch (updatedJobResult) {
                        case (#ok()) {
                            // Update client state to working
                            let updatedClientResult = await updateClientState(clientID, jobID, "working", "alive", Time.now());

                            switch (updatedClientResult) {
                                case (#ok()) {
                                    let jsonResponse = "{" #
                                    "\"status\": \"success\"," #
                                    "\"message\": \"Job assigned successfully\"," #
                                    "\"jobId\": \"" # jobID # "\"," #
                                    "\"clientId\": \"" # clientID # "\"" #
                                    "}";
                                    #ok(jsonResponse);
                                };
                                case (#err(errorMsg)) {
                                    // Revert job state if client update fails
                                    ignore updateJobState(jobID, clientID, "pending", 0, 0);
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

    private func updateClientStateToAliveOrDead(clientID : Text, state : Text, lastAlive : Int) : async Result.Result<(), Text> {
        Debug.print("Attempting to update client info with clientId: " # clientID);

        try {

            let updatedAttributes = [
                ("state", #text(state)),
                ("lastAlive", #int(lastAlive)),
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

            let updated = switch (
                CanDB.update(
                    clientDB,
                    {
                        pk = "clientTable";
                        sk = clientID;
                        updateAttributeMapFunction = updateAttributes;
                    },
                )
            ) {
                case null {
                    Debug.print("Failed to update client: " # clientID);
                    #err("Failed to update client");
                };
                case (?updatedEntity) {
                    #ok();
                };
            };
        } catch (error) {
            Debug.print("Error caught in client update: " # Error.message(error));
            #err("Failed to update client: " # Error.message(error));
        };
    };

    private func updateClientState(clientID : Text, jobID : Text, jobStatus : Text, state : Text, lastAlive : Int) : async Result.Result<(), Text> {
        Debug.print("Attempting to update client info with clientId: " # clientID);

        try {
            let existingClient = CanDB.get(clientDB, { pk = "clientTable"; sk = clientID });

            switch (existingClient) {
                case (?clientEntity) {
                    Debug.print("Client found in DB with clientID: " # clientID);

                    let updatedAttributes = [
                        ("state", #text(state)),
                        ("jobID", #text(jobID)),
                        ("jobStatus", #text(jobStatus)),
                        ("lastAlive", #int(lastAlive)),
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

                    let updated = switch (
                        CanDB.update(
                            clientDB,
                            {
                                pk = "clientTable";
                                sk = clientID;
                                updateAttributeMapFunction = updateAttributes;
                            },
                        )
                    ) {
                        case null {
                            Debug.print("Failed to update client: " # clientID);
                            #err("Failed to update client");
                        };
                        case (?updatedEntity) {
                            #ok();
                        };
                    };
                };
                case null {
                    Debug.print("Client does not exist with clientID: " # clientID);
                    #err("Client does not exist");
                };
            };
        } catch (error) {
            Debug.print("Error caught in client update: " # Error.message(error));
            #err("Failed to update client: " # Error.message(error));
        };
    };

    private func updateJobState(jobID : Text, clientID : Text, newState : Text, assignedAt : Int, completeAt : Int) : async Result.Result<(), Text> {
        Debug.print("Attempting to update job info with jobID: " # jobID);

        try {
            let updatedAttributes = [
                ("state", #text(newState)),
                ("assignedAt", #int(assignedAt)),
                ("completeAt", #int(completeAt)),
                ("clientID", #text(clientID)),
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

            let updated = switch (
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
                case (?updatedEntity) {
                    #ok();
                };
            };
        } catch (error) {
            Debug.print("Error caught in client update: " # Error.message(error));
            #err("Failed to update client: " # Error.message(error));
        };
    };

    func unwrapJobEntity(entity : Entity.Entity) : ?JobStruct {
        let attributes = entity.attributes;

        let jobID = switch (Entity.getAttributeMapValueForKey(attributes, "jobID")) {
            case (?(#text(value))) { value };
            case _ { return null };
        };

        let jobType = switch (Entity.getAttributeMapValueForKey(attributes, "jobType")) {
            case (?(#text(value))) { value };
            case _ { return null };
        };

        let target = switch (Entity.getAttributeMapValueForKey(attributes, "target")) {
            case (?(#text(value))) { value };
            case _ { return null };
        };

        let state = switch (Entity.getAttributeMapValueForKey(attributes, "state")) {
            case (?(#text(value))) { value };
            case _ { return null };
        };

        let result = switch (Entity.getAttributeMapValueForKey(attributes, "result")) {
            case (?(#text(value))) { value };
            case _ { return null };
        };

        let clientId = switch (Entity.getAttributeMapValueForKey(attributes, "clientId")) {
            case (?(#text(value))) { value };
            case _ { return null };
        };

        let assignedAt = switch (Entity.getAttributeMapValueForKey(attributes, "assignedAt")) {
            case (?(#int(value))) { value };
            case _ { return null };
        };

        let completeAt = switch (Entity.getAttributeMapValueForKey(attributes, "completeAt")) {
            case (?(#int(value))) { value };
            case _ { return null };
        };

        ?{
            jobID;
            jobType;
            target;
            state;
            result;
            clientId;
            assignedAt;
            completeAt;
        };
    };

    func unwrapClientEntity(entity : Entity.Entity) : ?ClientStruct {
        let attributes = entity.attributes;

        let clientID = switch (Entity.getAttributeMapValueForKey(attributes, "clientID")) {
            case (?(#text(value))) { value };
            case _ { return null };
        };

        let state = switch (Entity.getAttributeMapValueForKey(attributes, "state")) {
            case (?(#text(value))) { value };
            case _ { return null };
        };

        let jobID = switch (Entity.getAttributeMapValueForKey(attributes, "jobID")) {
            case (?(#text(value))) { value };
            case _ { return null };
        };

        let jobStatus = switch (Entity.getAttributeMapValueForKey(attributes, "jobStatus")) {
            case (?(#text(value))) { value };
            case _ { return null };
        };

        let lastAlive = switch (Entity.getAttributeMapValueForKey(attributes, "lastAlive")) {
            case (?(#int(value))) { value };
            case _ { return null };
        };

        ?{
            clientID;
            state;
            jobID;
            jobStatus;
            lastAlive;
        };
    };

    public func clientAlive(clientID : Text) : async Text {
        var jsonResponse : Text = "";

        try {
            // Validate the clientID as a Principal
            //let _ = Principal.fromText(clientID);

            // Check if the client exists in the database
            let existingClient = CanDB.get(clientDB, { pk = "clientTable"; sk = clientID });

            switch (existingClient) {
                case null {
                    // If client is not found, add the client to the DB
                    Debug.print("Client not found for clientID: " # clientID);
                    let registerClient = await addClientToDB(clientID);
                    switch (registerClient) {
                        case (#ok(successMessage)) {
                            Debug.print("Client added to DB for clientID: " # clientID);
                            return createJsonResponse("success", "New Client added to DB, pls call again to make the client alive", clientID, "dead");
                        };
                        case (#err(errorMessage)) {
                            return createJsonResponse("error", "Failed to update client status: " # errorMessage, clientID, "dead");
                        };
                    };
                };
                case (?entity) {
                    // Client found, continue without changes
                    let client : ClientStruct = {
                        clientID = entity.sk;
                        state = switch (Entity.getAttributeMapValueForKey(entity.attributes, "state")) {
                            case (?(#text(s))) s;
                            case _ "unknown";
                        };
                        jobID = switch (Entity.getAttributeMapValueForKey(entity.attributes, "jobID")) {
                            case (?(#text(j))) j;
                            case _ "";
                        };
                        jobStatus = switch (Entity.getAttributeMapValueForKey(entity.attributes, "jobStatus")) {
                            case (?(#text(j))) j;
                            case _ "";
                        };
                        lastAlive = switch (Entity.getAttributeMapValueForKey(entity.attributes, "lastAlive")) {
                            case (?(#int(t))) t;
                            case _ 0;
                        };
                    };

                    Debug.print("Client found for clientID: " # clientID);
                    // Mark the client as "alive"
                    let timeNow = Time.now();
                    let updateResult = await updateClientStateToAliveOrDead(clientID, "alive", timeNow);

                    switch (updateResult) {
                        case (#ok()) {
                            if (client.jobID != "") {
                                // Return the response immediately after marking the client as alive
                                jsonResponse := createJsonResponse("success", "Client is alive and working, waiting for 6 seconds", clientID, "alive");
                            } else{
                                // Return the response immediately after marking the client as alive
                                jsonResponse := createJsonResponse("success", "Client is alive, waiting for 6 seconds", clientID, "alive");
                            };

                            // Run a timer in the background to mark the client as "dead" after 6 seconds
                            ignore Timer.setTimer<system>(#nanoseconds(6_000_000_000), func() : async () {
                                let deadUpdateResult = await updateClientStateToAliveOrDead(clientID, "dead", Time.now());
                                
                                switch (deadUpdateResult) {
                                    case (#ok()) {
                                        Debug.print("Client " # clientID # " marked as dead after 6 seconds");
                                    };
                                    case (#err(errorMsg)) {
                                        Debug.print("Failed to mark client " # clientID # " as dead: " # errorMsg);
                                    };
                                };
                            });

                            return jsonResponse; // Respond immediately
                        };
                        case (#err(errorMsg)) {
                            jsonResponse := createJsonResponse("error", "Failed to update client state: " # errorMsg, clientID, "unknown");
                        };
                    };
                };
            };
        } catch (error) {
            Debug.print("Error in clientAlive: " # Error.message(error));
            jsonResponse := createJsonResponse("error", "An unexpected error occurred", clientID, "unknown");
        };

        return jsonResponse;
    };

    func hourlyJobCheck() : async () {
        Debug.print("Performing hourly job check...");

        let currentTime = Time.now();
        let deadTimeout = 3600_000_000_000; // 1 hour in nanoseconds

        // Scan for jobs
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
            },
        );

        for (jobEntity in jobScanResult.entities.vals()) {
            let job : JobStruct = {
                jobID = jobEntity.sk;
                jobType = switch (Entity.getAttributeMapValueForKey(jobEntity.attributes, "jobType")) {
                    case (?(#text(t))) t;
                    case _ "unknown";
                };
                target = switch (Entity.getAttributeMapValueForKey(jobEntity.attributes, "target")) {
                    case (?(#text(t))) t;
                    case _ "";
                };
                state = switch (Entity.getAttributeMapValueForKey(jobEntity.attributes, "state")) {
                    case (?(#text(s))) s;
                    case _ "unknown";
                };
                result = switch (Entity.getAttributeMapValueForKey(jobEntity.attributes, "result")) {
                    case (?(#text(r))) r;
                    case _ "";
                };
                clientId = switch (Entity.getAttributeMapValueForKey(jobEntity.attributes, "clientId")) {
                    case (?(#text(c))) c;
                    case _ "";
                };
                assignedAt = switch (Entity.getAttributeMapValueForKey(jobEntity.attributes, "assignedAt")) {
                    case (?(#int(t))) t;
                    case _ 0;
                };
                completeAt = switch (Entity.getAttributeMapValueForKey(jobEntity.attributes, "completeAt")) {
                    case (?(#int(t))) t;
                    case _ 0;
                };
            };

            Debug.print("clientId: " # job.clientId);
            Debug.print("job state: " # job.state);

            if (job.state == "ongoing") {
                // Check if the client is dead
                let clientResult = CanDB.get(clientDB, { pk = "clientTable"; sk = job.clientId });

                switch (clientResult) {
                    case (?clientEntity) {
                        let client : ClientStruct = {
                            clientID = clientEntity.sk;
                            state = switch (Entity.getAttributeMapValueForKey(clientEntity.attributes, "state")) {
                                case (?(#text(s))) s;
                                case _ "unknown";
                            };
                            jobID = switch (Entity.getAttributeMapValueForKey(clientEntity.attributes, "jobID")) {
                                case (?(#text(j))) j;
                                case _ "";
                            };
                            jobStatus = switch (Entity.getAttributeMapValueForKey(clientEntity.attributes, "jobStatus")) {
                                case (?(#text(j))) j;
                                case _ "";
                            };
                            lastAlive = switch (Entity.getAttributeMapValueForKey(clientEntity.attributes, "lastAlive")) {
                                case (?(#int(t))) t;
                                case _ 0;
                            };
                        };

                        if (client.state == "dead" and currentTime - client.lastAlive > deadTimeout) {
                            // Update job status to pending
                            let updateJobResult = await updateJobState(job.jobID, "", "pending", 0, 0);

                            switch (updateJobResult) {
                                case (#ok()) {
                                    Debug.print("Job " # job.jobID # " updated: state = pending, assignedAt = 0, completeAt = 0");
                                };
                                case (#err(errorMessage)) {
                                    Debug.print("Error updating job " # job.jobID # ": " # errorMessage);
                                };
                            };
                        };
                    };
                    case (null) {
                        Debug.print("Client not found for job: " # job.jobID);
                        // Update job status to pending
                        let updateJobResult = await updateJobState(job.jobID, "", "pending", 0, 0);

                        switch (updateJobResult) {
                            case (#ok()) {
                                Debug.print("Job " # job.jobID # " updated: state = pending, assignedAt = 0, completeAt = 0");
                            };
                            case (#err(errorMessage)) {
                                Debug.print("Error updating job " # job.jobID # ": " # errorMessage);
                            };
                        };
                    };
                };
            };
        };

        Debug.print("Hourly job check completed.");
    };

    // Set up the recurring timer to check for client timeouts
    //ignore Timer.recurringTimer<system>(#seconds(3600), hourlyJobCheck);

    public query func http_request(request : HttpRequest) : async HttpResponse {
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
            case ("POST", "/clientAlive") {
                let authHeader = getHeader(headers, "authorization");
                switch (authHeader) {
                    case null {
                        Debug.print("Missing Authorization header ");
                        return badRequest("Missing Authorization header");
                    };
                    case (?clientID) {
                        let result = await clientAlive(clientID);
                        return {
                            status_code = 200;
                            headers = [("Content-Type", "application/json")];
                            body = Text.encodeUtf8(result);
                            streaming_strategy = null;
                            upgrade = null;
                        };
                    };
                };
            };
            case ("POST", "/assignJob") {
                let authHeader = getHeader(headers, "authorization");
                switch (authHeader) {
                    case null {
                        Debug.print("Missing Authorization header ");
                        return badRequest("Missing Authorization header");
                    };
                    case (?clientID) {
                        let result = await assignJobToClient(clientID);
                        switch (result) {
                            case (#ok(successMessage)) {
                                return {
                                    status_code = 200;
                                    headers = [("Content-Type", "application/json")];
                                    body = Text.encodeUtf8(successMessage);
                                    streaming_strategy = null;
                                    upgrade = null;
                                };
                            };
                            case (#err(errorMessage)) {
                                return {
                                    status_code = 400;
                                    headers = [("Content-Type", "application/json")];
                                    body = Text.encodeUtf8(errorMessage);
                                    streaming_strategy = null;
                                    upgrade = null;
                                };
                            };
                        };
                    };
                };
            };
            case ("POST", "/updateJobCompleted") {
                let authHeader = getHeader(headers, "authorization");
                switch (authHeader) {
                    case null {
                        Debug.print("Missing Authorization header ");
                        return badRequest("Missing Authorization header");
                    };
                    case (?clientID) {

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
                                        var jobID : Text = "";
                                        var result : Text = "";
                                        
                                        for ((key, value) in fields.vals()) {
                                            switch (key, value) {
                                                case ("jobID", #String(v)) { jobID := v };
                                                case ("result", #String(v)) { result := v };
                                                case _ {};
                                            };
                                        };

                                        if (jobID == "" or result == "") {
                                            return badRequest("Missing or invalid jobID or result");
                                        };

                                        Debug.print("Parsed data - jobID: " # jobID # ", result: " # result);
                                        let updateResult = await updateJobCompleted(clientID, jobID, result);
                                        switch (updateResult) {
                                            case (#ok(successMessage)) {
                                                return {
                                                    status_code = 200;
                                                    headers = [("Content-Type", "application/json")];
                                                    body = Text.encodeUtf8(successMessage);
                                                    streaming_strategy = null;
                                                    upgrade = null;
                                                };
                                            };
                                            case (#err(errorMessage)) {
                                                return badRequest(errorMessage);
                                            };
                                        };
                                    };
                                    case (#Array(_)) {
                                        return badRequest("Unexpected JSON array");
                                    };
                                    case (#Boolean(_)) {
                                        return badRequest("Unexpected JSON boolean");
                                    };
                                    case (#Null) {
                                        return badRequest("Unexpected JSON null");
                                    };
                                    case (#Number(_)) {
                                        return badRequest("Unexpected JSON number");
                                    };
                                    case (#String(_)) {
                                        return badRequest("Unexpected JSON string");
                                    };
                                }
                            }
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

    // Helper function to create JSON response
    private func createJsonResponse(status : Text, message : Text, clientID : Text, state : Text) : Text {
        return "{" #
        "\"status\": \"" # status # "\"," #
        "\"message\": \"" # message # "\"," #
        "\"clientID\": \"" # clientID # "\"," #
        "\"state\": \"" # state # "\"" #
        "}";
    };
};
