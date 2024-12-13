import Result "mo:base/Result";

module {
    public type DBInterface = actor {
        clientConnect : shared (Text, Int) -> async Result.Result<Text, Text>;
        clientDisconnect : shared (Int) -> async Text;
        updateJobCompleted : shared (Text, Int, Text) -> async Result.Result<Text, Text>;
    };
}