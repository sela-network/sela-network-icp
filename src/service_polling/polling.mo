import Time "mo:base/Time";
import Timer "mo:base/Timer";
import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Iter "mo:base/Iter";
import Result "mo:base/Result";
import CanDB "mo:candb/CanDB";
import Error "mo:base/Error";
import HTTP "../utils/Http";
import Random "../utils/Random";
import Entity "mo:candb/Entity";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Nat = "mo:base/Nat";

actor polling {

    type HttpRequest = HTTP.HttpRequest;
    type HttpResponse = HTTP.HttpResponse;

    type ClientStruct = {
        clientID : Text;
        state : Text;  // Possible states: "alive", "dead", "working"
        jobID : Text;
    };

    type JobStruct = {
        jobID: Text;
        jobType: Text;
        target: Text;
        state: Text; // 'complete', 'pending', 'reject', 'ongoing'
        result: Text;
        clientId: Text;
        assignedAt: Int;
        completeAt: Int;
    };

    public shared func dummyAutoScalingHook(_ : Text) : async Text {
        return "";
    };

    let scalingOptions : CanDB.ScalingOptions = {
        autoScalingHook = dummyAutoScalingHook;
        sizeLimit = #count(1000);
    };

    stable let clientDB = CanDB.init({ pk = "clientTable"; scalingOptions = scalingOptions; btreeOrder = null });
    stable let jobDB = CanDB.init({ pk = "jobTable"; scalingOptions = scalingOptions; btreeOrder = null });

    // Timeout thresholds
    let aliveTimeout : Int = 5_000_000_000; // 5000ms in nanoseconds
    let pollInterval : Int = 1_000_000_000; // 1000ms for the polling interval

    private func createClientEntity(clientID: Text, state: Text) : {
        pk: Text;
        sk: Text;
        attributes: [(Text, Entity.AttributeValue)];
    } {
        Debug.print("Attempting to create client entity: ");
        {
            pk = "clientTable";
            sk = clientID;
            attributes = [
                ("clientID", #text(clientID)),
                ("state", #text(state)),
                ("jobID", #text(""))
            ];
        }
    };

    private func createJobEntity(jobId: Text, jobType: Text, target: Text) : {
        pk: Text;
        sk: Text;
        attributes: [(Text, Entity.AttributeValue)];
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

    public shared func addClientToDB(clientID: Text) : async Result.Result<Text, Text> {
        Debug.print("Attempting to insert client with clientID: " # clientID);
        
        if (Text.size(clientID) == 0) {
            return #err("Invalid input: clientID must not be empty");
        };

        try {
            // First, check if the user already exists
            let existingClient = CanDB.get(clientDB, { pk = "clientTable"; sk = clientID });
            
            switch (existingClient) {
                case (?_) {
                    // Job already exists, return an error
                    Debug.print("Client already exists for clientID: " # clientID);
                    return #err("Client already exists");
                };
                case null {
                    // Job doesn't exist, proceed with insertion
                    Debug.print("New client");
                    let entity = createClientEntity(clientID, "new");
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
                };
            };
        } catch (error) {
            Debug.print("Error caught in job insertion: " # Error.message(error));
            return #err("Failed to job insertion: " # Error.message(error));
        }
    };

    public shared func addJobToDB(jobType: Text, target: Text) : async Result.Result<Text, Text> {
        let randomGenerator = Random.new();
        let jobId = await randomGenerator.next();
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
        }
    };

    public shared func updateJobCompleted(jobID: Text, result: Text) : async Result.Result<Text, Text> {
        Debug.print("Attempting to update job with jobID: " # jobID);

        if (Text.size(jobID) == 0) {
            return #err("Invalid input: jobId must not be empty");
        };

        try {
            // First, check if the job exists in CanDB
            let existingJob = CanDB.get(jobDB, { pk = "jobTable"; sk = jobID });

            switch (existingJob) {
                case (?jobEntity) {
                    Debug.print("Job found in DB with jobID: " # jobID);
                    // Convert Text to Blob
                    //let jsonBlob = Text.encodeUtf8(jsonText);
                    
                    // Prepare the updated attributes for the job
                    let updatedAttributes = [
                        ("state", #text("complete")), // Mark the job as completed
                        ("result", #text(result)),    // Attach the result (blob)
                        ("completeAt", #int(Time.now())) // Set the completion time
                    ];

                    // Define the update function to update the job attributes
                    func updateAttributes(attributeMap : ?Entity.AttributeMap) : Entity.AttributeMap {
                        switch (attributeMap) {
                            case null {
                                Entity.createAttributeMapFromKVPairs(updatedAttributes);
                            };
                            case (?map) {
                                Entity.updateAttributeMapWithKVPairs(map, updatedAttributes);
                            };
                        }
                    };

                    let updated = switch (
                        CanDB.update(
                            jobDB,
                            {
                                pk = "jobTable";
                                sk = jobID;
                                updateAttributeMapFunction = updateAttributes;
                            },
                        ),
                    ) {
                        case null { 
                            Debug.print("Failed to update job: " # jobID);
                            return #err("Failed to update job");
                         };
                        case (?updatedEntity) {
                            let jobDetails = Entity.extractKVPairsFromAttributeMap(updatedEntity.attributes);
                            let jsonResponse = "{" #
                                "\"status\": \"success\"," #
                                "\"message\": \"Job completed successfully\"," #
                                "\"jobId\": \"" # updatedEntity.sk # "\"," #
                            "}";
                            return #ok(jsonResponse);
                        };
                    };
                };
                case null {
                    // Job doesn't exist in the database, return error
                    Debug.print("Job does not exist with jobID: " # jobID);
                    return #err("Job does not exist");
                };
            };
        } catch (error) {
            Debug.print("Error caught in job update: " # Error.message(error));
            return #err("Failed to update job: " # Error.message(error));
        }
    };

    public query func getJobWithID(jobID: Text) : async Result.Result<JobStruct, Text> { 
        Debug.print("Attempting to get job with jobID: " # jobID);

        try {
            let existingJob = CanDB.get(jobDB, { pk = "jobTable"; sk = jobID });

            switch(existingJob) {
                case null {
                    Debug.print("Job not found for jobID: " # jobID);
                    #err("Job not found")
                };
                case (?entity) {
                    switch(unwrapJobEntity(entity)) {
                        case (?jobStruct) {
                            #ok(jobStruct)
                        };
                        case null {
                            #err("Error unwrapping job data")
                        };
                    }
                };
            }
        } catch (error) {
            Debug.print("Error in get function: " # Error.message(error));
            #err("Failed to get user: " # Error.message(error))
        }
    };

    public shared query func getClientWithID(clientID: Text) : async Result.Result<ClientStruct, Text> { 
        Debug.print("Attempting to get client with clientID: " # clientID);

        try {
            let existingClient = CanDB.get(clientDB, { pk = "clientTable"; sk = clientID });

            switch(existingClient) {
                case null {
                    Debug.print("Client not found for clientID: " # clientID);
                    #err("Client not found")
                };
                case (?entity) {
                    switch(unwrapClientEntity(entity)) {
                        case (?clientStruct) {
                            #ok(clientStruct)
                        };
                        case null {
                            #err("Error unwrapping client data")
                        };
                    }
                };
            }
        } catch (error) {
            Debug.print("Error in get function: " # Error.message(error));
            #err("Failed to get user: " # Error.message(error))
        }
    };

    public shared query func getPendingJobs(clientID: Text) : async Result.Result<Text, Text> {
        Debug.print("Received request to fetch pending jobs: ");
       
        let skLowerBound = "job";  // Start of the range for client keys
        let skUpperBound = "job~"; // End of the range for client keys
        let limit = 1000;  // Limit number of records to scan
        let ascending = null;  // Not specifying order

        // Use CanDB.scan to retrieve job records
        let { entities; nextKey } = CanDB.scan(
            jobDB,
            {
                skLowerBound = skLowerBound;
                skUpperBound = skUpperBound;
                limit = limit;
                ascending = ascending;
            }
        );

        Debug.print("Total entities: " # debug_show(entities.size()));
        for (entity in entities.vals()) {
            Debug.print("Entity: " # debug_show(entity));
        };

        let pendingJobs = Array.filter(entities, func (entity : {attributes : Entity.AttributeMap; pk : Text; sk : Text}) : Bool {
            switch (Entity.getAttributeMapValueForKey(entity.attributes, "state")) {
                case (?(#text(state))) {
                    Text.equal(state, "pending")
                };
                case _ { false };
            }
        });

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
        }
    };

    // public shared func clientOn(clientID: Text) : async Result.Result<Text, Text> {
    //     Debug.print("Received client ON request with clientID: " # clientID);

    //     if (Text.size(clientID) == 0) {
    //         return #err("Invalid input: clientID must not be empty");
    //     };

    //     try {
    //         let existingClient = CanDB.get(clientDB, { pk = "clientTable"; sk = clientID });

    //         switch(existingClient) {
    //             case null {
    //                 Debug.print("Client not found for clientID: " # clientID);
    //                 #err("Client not found")
    //             };
    //             case (?entity) {
                    
    //             };
    //         }
    //     } catch (error) {
    //         Debug.print("Error in get function: " # Error.message(error));
    //         #err("Failed to get user: " # Error.message(error))
    //     }
    // };

    public shared func assignJobToClient(clientID: Text) : async Result.Result<Text, Text> {
        Debug.print("Received client is alive with clientID: " # clientID);

        if (Text.size(clientID) == 0) {
            return #err("Invalid input: clientID must not be empty");
        };

        let skLowerBound = "job";  // Start of the range for client keys
        let skUpperBound = "job~"; // End of the range for client keys
        let limit = 1000;  // Limit number of records to scan
        let ascending = null;  // Not specifying order

        // Use CanDB.scan to retrieve job records
        let { entities; nextKey } = CanDB.scan(
            jobDB,
            {
                skLowerBound = skLowerBound;
                skUpperBound = skUpperBound;
                limit = limit;
                ascending = ascending;
            }
        );

        let pendingJobs = Array.filter(entities, func (entity : {attributes : Entity.AttributeMap; pk : Text; sk : Text}) : Bool {
            switch (Entity.getAttributeMapValueForKey(entity.attributes, "state")) {
                case (?(#text(state))) {
                    Text.equal(state, "pending")
                };
                case _ { false };
            }
        });
        //simply return if no job
        if (Array.size(pendingJobs) == 0) {
            let jsonResponse = "{" #
                "\"status\": \"success\"," #
                "\"message\": \"No pending jobs available\"" #
            "}";
            return #ok(jsonResponse);
        };
        try{
            switch (Array.find(pendingJobs, func (job: {attributes : Entity.AttributeMap; pk : Text; sk : Text}) : Bool { true })) {
                case (?job) {
                    Debug.print("Job found in DB with jobID: " # job.sk);
                    let updatedAttributes = [
                        ("state", #text("assigned")),
                        ("clientId", #text(clientID)),   
                        ("assignedAt", #int(Time.now()))
                    ];
                    func updateAttributes(attributeMap : ?Entity.AttributeMap) : Entity.AttributeMap {
                        switch (attributeMap) {
                            case null {
                                Entity.createAttributeMapFromKVPairs(updatedAttributes);
                            };
                            case (?map) {
                                Entity.updateAttributeMapWithKVPairs(map, updatedAttributes);
                            };
                        }
                    };
                    let updated = switch (
                        CanDB.update(
                            jobDB,
                            {
                                pk = "jobTable";
                                sk = job.sk;
                                updateAttributeMapFunction = updateAttributes;
                            },
                        ),
                    ) {
                        case null { 
                            Debug.print("Failed to update job: " # job.sk);
                            return #err("Failed to update job");
                        };
                        case (?updatedEntity) {
                            let jobDetails = Entity.extractKVPairsFromAttributeMap(updatedEntity.attributes);
                            let jsonResponse = "{" #
                                "\"status\": \"success\"," #
                                "\"message\": \"Job assigned successfully\"," #
                                "\"jobId\": \"" # updatedEntity.sk # "\"," #
                            "}";
                            return #ok(jsonResponse);
                        };
                    };
                }
            }
        }catch (error) {
            Debug.print("Error caught in job update: " # Error.message(error));
            return #err("Failed to update job: " # Error.message(error));
        }
    };

    func unwrapJobEntity(entity: Entity.Entity): ?JobStruct {
        let attributes = entity.attributes;

        let jobID = switch (Entity.getAttributeMapValueForKey(attributes, "jobID")) {
            case (?(#text(value))) { value };
            case _ { return null; };
        };

        let jobType = switch (Entity.getAttributeMapValueForKey(attributes, "jobType")) {
            case (?(#text(value))) { value };
            case _ { return null; };
        };

        let target = switch (Entity.getAttributeMapValueForKey(attributes, "target")) {
            case (?(#text(value))) { value };
            case _ { return null; };
        };

        let state = switch (Entity.getAttributeMapValueForKey(attributes, "state")) {
            case (?(#text(value))) { value };
            case _ { return null; };
        };

        let result = switch (Entity.getAttributeMapValueForKey(attributes, "result")) {
            case (?(#text(value))) { value };
            case _ { return null; };
        };

        let clientId = switch (Entity.getAttributeMapValueForKey(attributes, "clientId")) {
            case (?(#text(value))) { value };
            case _ { return null; };
        };

        let assignedAt = switch (Entity.getAttributeMapValueForKey(attributes, "assignedAt")) {
            case (?(#int(value))) { value };
            case _ { return null; };
        };

        let completeAt = switch (Entity.getAttributeMapValueForKey(attributes, "completeAt")) {
            case (?(#int(value))) { value };
            case _ { return null; };
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
        }
    };

    func unwrapClientEntity(entity: Entity.Entity): ?ClientStruct {
        let attributes = entity.attributes;

        let clientID = switch (Entity.getAttributeMapValueForKey(attributes, "clientID")) {
            case (?(#text(value))) { value };
            case _ { return null; };
        };

        let state = switch (Entity.getAttributeMapValueForKey(attributes, "state")) {
            case (?(#text(value))) { value };
            case _ { return null; };
        };

        let jobID = switch (Entity.getAttributeMapValueForKey(attributes, "jobID")) {
            case (?(#text(value))) { value };
            case _ { return null; };
        };

        ?{
            clientID;
            state;
            jobID;
        }
    };
}