#=
CURRENT CAPABILITIES
-> Evaluate positions based on piece value and piece square tables
-> Minimax with alpha beta pruning tree search
-> Iterative deepening
-> Principle variation search
-> Move ordering: 
    -PV
    -MVV-LVA 
    -Killer moves
-> Quiescence search
-> Check extension
-> Transposition table

TO-DO (engine)

Pruning
-> Null move pruning
-> SEE in quiescence
-> TT in quiescence
-> PVS/aspiration windows
-> Razoring

Move Ordering
-> Promotion - queen good, underpromote bad
-> SEE
-> LMR (+ history?)

Evaluation
-> Texel tuned PSTs
-> King safety
-> Pawn structure
-> NNUE

TO-DO (general)
-> UCI protocol
 - Better time estimation - use movestogo if provided
-> Transposition table
 - Pack TT entries into 2 UInt64s
 - Age out TT entry whenever its accessed but not used
 - Test accessing TT in quiescence search
 - Enable future multi-threading via shared lock-less transposition table

Known bugs
-> Mate scores in transposition table are wrong (off by one?)

Speed
-> Test whether extensive inlining is necessary
-> Fixed size board history array - reduce allocations
-> Try incrementally updated mailbox for identify_piecetype
-> Test playing TT move immediately if pseudo-legal
-> Test small lookups vs on the fly calculation
-> Faster 3-move repetition detection

TO THINK ABOUT
# What to do about unforcable draws like KNkb
# Do we need to check for FIDE draws like KNk, KBk
=#

module Scylla

using StaticArrays
using HDF5
using Random

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
include("cli.jl")
include("precompile.jl")

export BitBoard, BoardState, print_board, setzero, setone,
       make_move!, unmake_move!,
       generate_legal_moves, generate_pseudolegal_moves,
       best_move, Move, perft,
       Logger, print_search_log,
       run_cli, assign_tt!, reset_engine!,
       Control, TimeControl, DepthControl, NodesControl,
       estimate_movetime,
       EngineState, Config
end #module