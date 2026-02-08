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
-> UCI protocol
 - Improve time estimate for time controls
 - Fix issue with inconsistant quitting
 - Enable searching to depth/mate/nodes
 - Print log at intermediate stages in computation
-> Convert all files to HDF5
-> Check type stability of mutable structs such as EngineState (TT could be nothing)
-> Reduce allocations (currently 3.8 Gb for a single 10 second search)
 - Create 64 length vector containing information about locations of pieces 
   for identify_piecetype (avoid allocating enemy_pcs in generate moves)
 - Search for allocations in engine.jl

Code Clarity
-> Consistent naming conventions of variables, functions, constants
-> Separate out make_move and unmake_move into more functions
-> Put all constants in one place

TO THINK ABOUT
#When adding extensions, eg.for checks, we will exceed PV triangular ply and Killer ply
#Need to check for FIDE draws like KNk, KBk as well as unforcable draws like KNkb
=#

module Scylla

using StaticArrays
using JLD2
using HDF5
using Random
using ArgParse

include("bitboard.jl")
include("defs.jl")
include("pst.jl")
include("move.jl")
include("board.jl")
include("magics.jl")
include("logic.jl")
include("transposition.jl")
include("moveordering.jl")
include("engine.jl")
include("perft.jl")
include("precompile.jl")
include("cli.jl")

export BitBoard, Boardstate,
       make_move!, unmake_move!,
       generate_moves, gameover!,
       best_move, Move, perft,
       Logger, print_log,
       run_cli, assign_TT!, reset_engine!,
       Control, Time, Depth, Nodes, Mate,
       FORCEQUIT, estimate_movetime,
       EngineState, Config
end #module