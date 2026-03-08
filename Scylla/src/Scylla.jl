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
-> PVS/aspiration windows
-> Texel tuned PSTs
-> SEE move ordering
-> LMR + history
-> NNUE

TO-DO (general)
-> UCI protocol
 - Enable searching to depth/mate/nodes
 - Better time estimation - use movestogo if provided
-> Add pseudolegal move generation
 - Squares attacked by enemy must be generated during make move (and stored in BoardState)
 - New functionality to make move and unmake if illegal
 - Test using perft
-> Optimise memory allocations of board data in make and rollback in unmake
-> Add check for FIDE draws like KNk, KBk

Code Clarity
-> Separate out functions for readability in:
 - generatemoves.jl
 - makemove.jl
 - cli.jl
 - engine.jl
-> Unify white/black distinction, ensuring same speed
 - Three types of indexing: true/false, 0/1, 0/6
-> Make castling purely a king's move and calculate rook position during makemove

TO THINK ABOUT
# When adding extensions, eg.for checks, we will exceed PV triangular ply and Killer ply
# What to do about unforcable draws like KNkb
=#

module Scylla

using StaticArrays
using HDF5
using Random
using ArgParse

include("bitboard.jl")
include("defs.jl")
include("pst.jl")
include("move.jl")
include("board.jl")
include("magics.jl")
include("generatemoves.jl")
include("makemove.jl")
include("transposition.jl")
include("moveordering.jl")
include("engine.jl")
include("perft.jl")
#include("precompile.jl")
include("cli.jl")

export BitBoard, BoardState, setzero, setone,
       make_move!, unmake_move!,
       generate_legal_moves, gameover!,
       best_move, Move, perft,
       Logger, print_log,
       run_cli, assign_tt!, reset_engine!,
       Control, Time, Depth, Nodes, Mate,
       estimate_movetime,
       EngineState, Config
end #module