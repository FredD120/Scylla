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

args = Scylla.test_args()
const perft_extra::Bool = args["perft_extra"]
const verbose::Bool = args["verbose"]
const TT_perft::Bool = args["TT_perft"]
const engine_hard::Bool = args["engine"]
const profile_engine::Bool = args["profile"]
const MAXTIME::Float64 = args["maxtime"]

run_tests()