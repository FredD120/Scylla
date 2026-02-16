using Scylla
using Profile
using Revise

engine = Scylla.EngineState(control = Time(10))

#@time move, logger = best_move(engine)
#Scylla.print_log(logger)

@profview Scylla.best_move(engine) 
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