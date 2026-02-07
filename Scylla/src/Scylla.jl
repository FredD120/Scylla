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
-> SEE move ordering
-> LMR + history
-> NNUE

TO-DO (general)
-> Implement UCI protocol
 - Add time estimate for time controls
 - Fix issue with inconsistant quitting
 - Enable searching to depth/mate/nodes
-> Convert Move to its own type
-> Convert all files to HDF5, combine mid and endgame tables in one file for each piece
-> Check type stability of mutable structs such as EngineState (TT could be nothing)

TO THINK ABOUT
#When adding extensions, eg.for checks, we will exceed PV triangular ply and Killer ply
#Need to check for FIDE draws like KNk, KBk as well as unforcable draws like KNkb
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

export BitBoard,Boardstate,
       make_move!,unmake_move!,
       generate_moves,gameover!,
       best_move,perft,
       Logger,print_log,
       run_cli,assign_TT!,reset_engine!,
       Control,Time,Depth,Nodes,Mate,
       FORCEQUIT, estimate_movetime,
       EngineState,Config
end #module