import Text "mo:base/Text";
import Result "mo:base/Result";
import HTTP "../../common/Http";

module {
	public type HttpRequest = HTTP.HttpRequest;
	public type HttpResponse = HTTP.HttpResponse;

	public type ClientStruct = {
		user_principal_id : Text; 
		client_id : Int;
		jobID : Text;
		jobStatus : Text;
		downloadSpeed : Float;
		ping : Int;
		wsConnect : Int;
		wsDisconnect : Int;
		jobStartTime : Int;
		jobEndTime : Int;
		todaysEarnings: Float;
		balance: Float;
		referralCode: Text;
		totalReferral: Int;
	};

	public type JobStruct = {
		jobID : Text;
		jobType : Text;
		target : Text;
		state : Text;
		user_principal_id : Text;
		assignedAt : Int;
		completeAt : Int;
		reward: Float;
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
        login : shared (Text) -> async Result.Result<ClientStruct, Text>;
		getUserRewardHistory : shared (Text) -> async Result.Result<[JobStruct], Text>;
        clientConnect : shared (Text, Int) -> async Result.Result<Text, Text>;
        clientDisconnect : shared (Int) -> async Text;
        updateJobCompleted : shared (Text, Int) -> async Result.Result<Text, Text>;
        updateClientInternetSpeed : shared (Text, Text) -> async Result.Result<Text, Text>;
        clientAuthorization : shared (Text) -> async Result.Result<Text, Text>;
        addJobToDB : shared (Text, Text) -> async Result.Result<Text, Text>;
        assignJobToClient : shared (Text, Int) -> async Result.Result<Text, Text>;
		findAndAssignJob : shared () -> async ?{user_principal_id : Text; client_id : Int; downloadSpeed : Float}
    };
}