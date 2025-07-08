using Scylla
using Test

@testset "Basic Evaluation" begin 
    @testset "Start Position" begin
        eFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        board = Scylla.Boardstate(eFEN)
        ev = Scylla.evaluate(board)

        @test ev == 0
    end

    @testset "Up a Pawn" begin
        eFEN = "8/P6k/K7/8/8/8/8/8 w - - 0 1"
        board = Scylla.Boardstate(eFEN)
        ev = Scylla.evaluate(board)

        @test ev >= 100
    end
end

@testset "PST Weighting" begin 
    eFEN = "4k3/ppppppp1/8/8/8/8/PPP5/R3K3 w Qkq - 0 1"
    board = Scylla.Boardstate(eFEN)
    num_pcs = Scylla.count_pieces(board.pieces)

    @test Scylla.MGweighting(num_pcs) > Scylla.EGweighting(num_pcs)

    num_pcs = 10
    @test Scylla.MGweighting(num_pcs) < Scylla.EGweighting(num_pcs)
end

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

@testset "Positional Evaluation" begin
    @testset "Central Knights" begin
        eFEN = "1n2k1n1/8/8/8/8/8/8/4K3 b KQkq - 0 1"
        board = Scylla.Boardstate(eFEN)
        ev1 = -Scylla.evaluate(board)

        eFEN = "4k3/8/8/3n4/8/4n3/8/4K3 b KQkq - 0 1"
        board = Scylla.Boardstate(eFEN)
        ev2 = -Scylla.evaluate(board)

        @test ev2 > ev1
    end

    @testset "Central Pawns" begin
        eFEN = "4k3/pppppppp/8/8/PP4PP/8/2PPPP2/4K3 w KQkq - 0 1"
        board = Scylla.Boardstate(eFEN)
        ev1 = Scylla.evaluate(board)

        eFEN = "4k3/pppppppp/8/8/2PPPP2/8/PP4PP/4K3 w KQkq - 0 1"
        board = Scylla.Boardstate(eFEN)
        ev2 = Scylla.evaluate(board)

        @test ev2 > ev1
    end

    @testset "Castling" begin
        eFEN = "4k3/pppppppp/8/8/8/8/PPPPPPPP/R3K3 w Qkq - 0 1"
        board = Scylla.Boardstate(eFEN)
        ev1 = Scylla.evaluate(board)

        eFEN = "4k3/pppppppp/8/8/8/8/PPPPPPPP/2KR4 w KQkq - 0 1"
        board = Scylla.Boardstate(eFEN)
        ev2 = Scylla.evaluate(board)

        @test ev2 > ev1
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

    killer_vec[ply+1] = Scylla.Killer(UInt32(1),UInt32(2))
    moves = [UInt32(3),UInt32(5),UInt32(2)]

    Scylla.score_moves!(moves,killer_vec[ply+1])
    @test Scylla.score(moves[3]) > Scylla.score(moves[2]) 
    @test Scylla.score(moves[3]) > Scylla.score(moves[1]) 
end

@testset "Update Killers" begin 
    killer_vec = [Scylla.Killer() for _ in 1:3]
    ply = 1

    for move in UInt32(1):UInt32(10)
        Scylla.new_killer!(killer_vec,ply,move)
    end
    @test killer_vec[ply+1].First == UInt32(10) 
    @test killer_vec[ply+1].Second == UInt32(9) 

    Scylla.new_killer!(killer_vec,ply,UInt32(10))
    @test killer_vec[ply+1].First != killer_vec[ply+1].Second
end

@testset "Easy Best Move" begin
    @testset "Bxq" begin
        eFEN = "K6Q/8/8/8/8/8/8/b6k b - - 0 1"
        board = Scylla.Boardstate(eFEN)
        best,log = Scylla.best_move(board,MAXTIME)

        @test Scylla.LONGmove(best) == "Ba1xh8"
    end

    @testset "bxQ" begin
        eFEN = "k6q/8/8/8/8/8/8/B6K w - - 0 1"
        board = Scylla.Boardstate(eFEN)
        best,log = Scylla.best_move(board,MAXTIME)

        @test Scylla.LONGmove(best) == "Ba1xh8"
    end

    @testset "Queen Evade Capture" begin
        eFEN = "k7/8/8/8/8/8/5K2/7q b - - 0 1"
        board = Boardstate(eFEN)
        best,log = best_move(board,MAXTIME)

        @test Scylla.LONGmove(best) == "Qh1-e4"
    end
end

@testset "Mate in 2" begin
    #mate in 2
    for eFEN in ["K7/R7/R7/8/8/8/8/7k w - - 0 1","k7/r7/r7/8/8/8/8/7K b - - 0 1"]
        board = Boardstate(eFEN)
        best,log = best_move(board,MAXTIME)
        #rook moves to cut off king
        make_move!(best,board)
        moves = generate_moves(board)
        #king response doesn't matter
        make_move!(moves[1],board)
        best,log = best_move(board,MAXTIME)
        make_move!(best,board)
        gameover!(board)
        
        @test board.State == Scylla.Loss()
    end
end

function profile()
    positions = readlines("$(dirname(@__DIR__))/test/test_positions.txt")

    #slow position
    eFEN = split(split(positions[12],";")[1],"- bm")[1]*"0"
    board = Boardstate(eFEN)

    best,log = best_move(board,MAXTIME)

    @profile best_move(board,MAXTIME*10)
    Profile.print()
end
if profile_engine::Bool
    profile()
end

function test_positions()
    count_correct = 0
    positions = readlines("$(dirname(@__DIR__))/test/test_positions.txt")

    for pos in positions
        FEN_move = split(split(pos,";")[1],"- bm ")
        eFEN = FEN_move[1]*"0"
        board = Boardstate(eFEN)
        correct_mv = FEN_move[2]

        if verbose
            println("Testing FEN: $eFEN")
        end
        best,log = best_move(board,MAXTIME)

        if Scylla.SHORTmove(best) == correct_mv
            @test true
            printstyled("Pass \n";color=:green)
        else
            @test_broken false
            if verbose
                println("Fail. Found: $(Scylla.SHORTmove(best)) - Best: $correct_mv")
            end
        end
    end
end
if engine_hard::Bool
    result = @testset "Difficult Engine Tests" begin
        test_positions()
    end
    if verbose
        Test.print_test_results(result)
    end
end



