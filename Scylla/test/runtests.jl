using Scylla
using Test
using Profile
using ArgParse
using InteractiveUtils

#=
To check generated code:
@code_llvm
@code_native
@code_warntype
=#

const FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

function run_tests()
    @testset "Chess Engine Tests" begin
        @testset "Logic Tests" begin
            include("test_logic.jl")
        end

        @testset "Engine Tests" begin
            include("test_engine.jl")
        end
    end
end

function get_args()
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

args = get_args()
const perft_extra::Bool = args["perft_extra"]
const verbose::Bool = args["verbose"]
const TT_perft::Bool = args["TT_perft"]
const engine_hard::Bool = args["engine"]
const profile_engine::Bool = args["profile"]
const MAXTIME::Float64 = args["maxtime"]

run_tests()
println("Tests Complete")

