module Scylla

using StaticArrays
using JLD2
using Random
using ArgParse

include("logic.jl")
include("engine.jl")
include("cli.jl")

export Boardstate,
       make_move!,
       unmake_move!,
       perft,
       generate_moves,
       gameover!,
       best_move,
       run_cli

end #module