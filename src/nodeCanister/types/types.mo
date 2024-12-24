import Text "mo:base/Text";
import Result "mo:base/Result";
import HTTP "../../utils/Http";

module {
	public type HttpRequest = HTTP.HttpRequest;
	public type HttpResponse = HTTP.HttpResponse;

	public type ClientStruct = {
		user_principal_id : Text; 
		client_id : Int;
		jobID : Text;
		jobStatus : Text;
		wsConnect : Int;
		wsDisconnect : Int;
	};

	public type JobStruct = {
		jobID : Text;
		jobType : Text;
		target : Text;
		state : Text;
		result : Text;
		user_principal_id : Text;
		assignedAt : Int;
		completeAt : Int;
	};

	public type DatabaseError = {
		#NotFound;
		#AlreadyExists;
		#UpdateFailed;
		#InvalidInput;
		#DatabaseError;
		#Unknown : Text;
	};

	public type EntityResult<T> = {
		#ok : T;
		#err : DatabaseError;
	};

	public type JobState = {
		#pending;
		#ongoing;
		#completed;
		#failed;
	};

	public type ClientState = {
		#working;
		#notWorking;
		#disconnected;
	};

	public type DBInterface = actor {
        clientConnect : shared (Text, Int) -> async Result.Result<Text, Text>;
        clientDisconnect : shared (Int) -> async Text;
        updateJobCompleted : shared (Text, Int, Text) -> async Result.Result<Text, Text>;
        updateClientInternetSpeed : shared (Text, Text) -> async Result.Result<Text, Text>;
    };
}