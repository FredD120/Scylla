using Scylla
using Profile
using Revise
 
engine = Scylla.EngineState(verbose = true, control = Time(10), sizeMb = 0)

@time move, logger = best_move(engine)
Scylla.print_log(logger)

#@time best, logger = Scylla.best_move(engine) #3.5 Mnps during TT search

#Scylla.print_log(logger)
#@time Scylla.perft(engine.board, 7) #28.84 seconds (7 allocations: 416 bytes)

#=
board = Scylla.Boardstate(Scylla.startFEN)

count = 1000
allocs = @allocated begin
    for _ in 1:count
        Scylla.generate_moves(board)
    end
end

println("Allocations: $(allocs/count) bytes")
=#

#=
α = -Scylla.INF
β = Scylla.INF
player::Int8 = Scylla.sgn(engine.board.colour)
ply = 0
onPV = true 
depth = 2
logger = Logger(0)
@code_warntype Scylla.minimax(engine, -player, -β, -α, depth-1, ply+1, onPV, logger)
=#