function run_cli()
    println("Scylla")
end

function test_args()
    s = ArgParseSettings(description="Run chess engine tests with optional extra tests.")

    @add_arg_table! s begin
        "--perft_extra", "-p"
            help = "Run more expensive perft tests to validate move generation and incremental updates"
            action = :store_true

        "--verbose", "-v"
            help = "Verbose output"
            action = :store_true

        "--TT_perft", "-t"
            help = "Run perft from start position with bulk counting and hash table"
            action = :store_true
            
        "--engine", "-e"
            help = "Run expensive engine tests from difficult test suite"
            action = :store_true

        "--profile", "-f"
            help = "Profile engine on a slow position"
            action = :store_true 
            
        "--maxtime", "-m"
            help = "Maximum time the engine will spend on a move during testing" 
            arg_type = Float64
            default = 0.5
    end
    return parse_args(s)
end