#=
CURRENT CAPABILITIES
-> Evaluate positions based on piece value and piece square tables
-> Minimax with alpha beta pruning tree search
-> Iterative deepening
-> Move ordering: 
    -PV
    -MVV-LVA 
    -Killer moves
-> Quiescence search
-> Check extension
-> Transposition table

TO-DO (engine)
-> Null move pruning
-> Delta/futility pruning
-> PVS
-> Texel tuned PSTs
-> LMR + history
-> NNUE

TO-DO (general)

-> Implement UCI protocol
-> Unit tests for UCI protocol
-> Convert all files to JLD2, combine mid and endgame tables in one file for each piece

TO THINK ABOUT
#When adding extensions, eg.for checks, we will exceed PV triangular ply and Killer ply
#Need to check for FIDE draws like KNk,KBk as well as unforcable draws like KNkb
=#

module Scylla

using StaticArrays
using JLD2
using Random
using ArgParse

include("bitboard.jl")
include("defs.jl")
include("pst.jl")
include("board.jl")
include("magics.jl")
include("logic.jl")
include("move.jl")
include("transposition.jl")
include("moveordering.jl")
include("engine.jl")
include("perft.jl")
include("precompile.jl")
include("cli.jl")

export Boardstate,
       BitBoard,
       make_move!,
       unmake_move!,
       perft,
       generate_moves,
       gameover!,
       best_move,
       run_cli,
       EngineState,
       reset_engine!

end #module