using Scylla
using Test

@testset "Triangular Table" begin
    PVtable = zeros(Scylla.triangle_number(Scylla.MAXDEPTH))
    PV_len = Scylla.MAXDEPTH
    new_move = 1
    tri_count = 0

    for ply in Scylla.MAXDEPTH-1:-1:0
        tri_count += 1
        Scylla.copy_PV!(PVtable,ply,PV_len,Scylla.MAXDEPTH,new_move)
        @test sum(PVtable) == Scylla.triangle_number(tri_count)
    end
end

@testset "MVV-LVA Scoring" begin
    eFEN = "8/8/8/8/8/8/q1r5/1K6 w - - 0 1"
    board = Scylla.Boardstate(eFEN)
    moves = Scylla.generate_moves(board)

    Scylla.score_moves!(moves)
    
    for move in moves
        if Scylla.cap_type(move) == Scylla.Queen
            @test Scylla.score(move) == maximum(scores)
            @test Scylla.score(move) > Scylla.MINCAPSCORE
        elseif Scylla.cap_type(move) == Scylla.NULL_PIECE
            @test Scylla.score(move) == minimum(scores)
            @test Scylla.score(move) < Scylla.MINCAPSCORE
        end
    end
end

@testset "Incremental Ordering" begin
    moves = [Scylla.NULLMOVE for _ in 1:3]

    for i in eachindex(moves)
        moves[i] = Scylla.set_score(moves[i],UInt8(i))
    end

    for i in eachindex(moves)
        Scylla.next_best!(moves,i)
        @test Scylla.score(moves[i]) == 4-i
    end
end

@testset "Score Killers" begin
    killer_vec = [Scylla.Killer() for _ in 1:3]
    ply = 2

    killer_vec[ply+1] = Scylla.Killer(Move(1),Move(2))
    moves = [Move(3),Move(5),Move(2)]

    Scylla.score_moves!(moves,killer_vec[ply+1])
    @test Scylla.score(moves[3]) > Scylla.score(moves[2]) 
    @test Scylla.score(moves[3]) > Scylla.score(moves[1]) 
end

@testset "Update Killers" begin 
    killer_vec = [Scylla.Killer() for _ in 1:3]
    ply = 1

    for i in 1:10
        move = Move(i)
        Scylla.new_killer!(killer_vec, ply, move)
    end
    @test killer_vec[ply+1].First == Move(10) 
    @test killer_vec[ply+1].Second == Move(9) 

    Scylla.new_killer!(killer_vec, ply, Move(10))
    @test killer_vec[ply+1].First != killer_vec[ply+1].Second
end