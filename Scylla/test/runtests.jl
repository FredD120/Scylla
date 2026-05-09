using Scylla
using Test
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
        @testset "Moves" begin
            include("test_move.jl")
        end

        @testset "Transposition Table" begin
            include("test_transposition.jl")
        end

        @testset "Move Ordering" begin
            include("test_moveordering.jl")
        end
        
        @testset "Logic Tests" begin
            include("test_logic.jl")
        end

        @testset "Engine Tests" begin
            include("test_engine.jl")
        end

        @testset "CLI Tests" begin
            include("test_cli.jl")
        end
    end
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

        "--expensive", "-e"
            help = "Run expensive engine tests from difficult test suite and run perft on over 100 tricky positions"
            action = :store_true
    end
    return parse_args(s)
end

args = test_args()
const perft_extra::Bool = args["perft_extra"]
const verbose::Bool = args["verbose"]
const expensive::Bool = args["expensive"]
run_tests()