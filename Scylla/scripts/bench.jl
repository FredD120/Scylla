using Scylla

engine = Scylla.EngineState(control = Time(10))
#@time move, logger = best_move(engine)
#Scylla.print_log(logger)

@time Scylla.perft(engine.board, 7) #49.003617 seconds (986.96 M allocations: 48.943 GiB)

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
#generate moves allocates 400 bytes
#make/unmake allocates 48 bytes

###NOT###
#EP edge case