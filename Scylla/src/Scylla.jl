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
       EngineState

end #module