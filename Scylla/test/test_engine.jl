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

@testset "Easy Best Move" begin
    @testset "Bxq" begin
        eFEN = "K6Q/8/8/8/8/8/8/b6k b - - 0 1"
        engine = Scylla.EngineState(eFEN)
        best,log = Scylla.best_move(engine,max_T=MAXTIME)

        @test Scylla.LONGmove(best) == "Ba1xh8"
    end

    @testset "bxQ" begin
        eFEN = "k6q/8/8/8/8/8/8/B6K w - - 0 1"
        engine = Scylla.EngineState(eFEN)
        best,log = Scylla.best_move(engine,max_T=MAXTIME)

        @test Scylla.LONGmove(best) == "Ba1xh8"
    end

    @testset "Queen Evade Capture" begin
        eFEN = "k7/8/8/8/8/8/5K2/7q b - - 0 1"
        engine = Scylla.EngineState(eFEN)
        best,log = Scylla.best_move(engine,max_T=MAXTIME)

        @test Scylla.LONGmove(best) == "Qh1-e4"
    end
end

@testset "Mate in 2" begin
    #mate in 2
    for eFEN in ["K7/R7/R7/8/8/8/8/7k w - - 0 1","k7/r7/r7/8/8/8/8/7K b - - 0 1"]
        engine = Scylla.EngineState(eFEN)
        best,log = Scylla.best_move(engine,max_T=MAXTIME)
        #rook moves to cut off king
        make_move!(best,engine.board)
        moves = generate_moves(engine.board)
        #king response doesn't matter
        make_move!(moves[1],engine.board)
        best,log = Scylla.best_move(engine,max_T=MAXTIME)
        make_move!(best,engine.board)
        gameover!(engine.board)
        
        @test engine.board.State == Scylla.Loss()
    end
end

function profile()
    positions = readlines("$(dirname(@__DIR__))/test/test_positions.txt")

    #slow position
    eFEN = split(split(positions[12],";")[1],"- bm")[1]*"0"
    engine = Scylla.EngineState(eFEN)
    best,log = Scylla.best_move(engine,max_T=MAXTIME)

    @profile Scylla.best_move(engine,max_T=MAXTIME*10)
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



