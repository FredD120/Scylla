using Scylla
using Test

@testset "Phase" begin
    @test Scylla.phase(32) == Scylla.QUANTISATION
    @test Scylla.phase(0) == 0

    @test Scylla.endgame_phase(Scylla.phase(32)) == 0
    @test Scylla.endgame_phase(Scylla.phase(0)) == Scylla.QUANTISATION
end

@testset "PST Weighting" begin 
    eFEN = "4k3/8/8/8/8/8/8/R3K3 w Qkq - 0 1"
    board = Scylla.BoardState(eFEN)
    phase = Scylla.phase(Scylla.count_pieces(board))
    eg_phase = Scylla.endgame_phase(phase)

    @test board.pst_score[1] > 0
    @test board.pst_score[2] > 0

    score = board.pst_score[1] * phase + board.pst_score[2] * eg_phase
    @test score > 0
    @test score << Scylla.QUANTISATION_SHIFT > 0
end

@testset "Basic Evaluation" begin 
    @testset "Start Position" begin
        eFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        board = Scylla.BoardState(eFEN)
        ev = Scylla.evaluate(board)

        @test ev == 0
    end

    @testset "Up a Pawn" begin
        eFEN = "8/P6k/K7/8/8/8/8/8 w - - 0 1"
        board = Scylla.BoardState(eFEN)
        ev = Scylla.evaluate(board)

        @test ev >= 100
    end
end

@testset "Positional Evaluation" begin
    @testset "Central Knights" begin
        eFEN = "1n2k1n1/8/8/8/8/8/8/4K3 b KQkq - 0 1"
        board = Scylla.BoardState(eFEN)
        ev1 = -Scylla.evaluate(board)

        eFEN = "4k3/8/8/3n4/8/4n3/8/4K3 b KQkq - 0 1"
        board = Scylla.BoardState(eFEN)
        ev2 = -Scylla.evaluate(board)

        @test ev2 > ev1
    end

    @testset "Central Pawns" begin
        eFEN = "4k3/pppppppp/8/8/PP4PP/8/2PPPP2/4K3 w KQkq - 0 1"
        board = Scylla.BoardState(eFEN)
        ev1 = Scylla.evaluate(board)

        eFEN = "4k3/pppppppp/8/8/2PPPP2/8/PP4PP/4K3 w KQkq - 0 1"
        board = Scylla.BoardState(eFEN)
        ev2 = Scylla.evaluate(board)

        @test ev2 > ev1
    end

    @testset "Castling" begin
        eFEN = "4k3/pppppppp/8/8/8/8/PPPPPPPP/R3K3 w Qkq - 0 1"
        board = Scylla.BoardState(eFEN)
        ev1 = Scylla.evaluate(board)

        eFEN = "4k3/pppppppp/8/8/8/8/PPPPPPPP/2KR4 w KQkq - 0 1"
        board = Scylla.BoardState(eFEN)
        ev2 = Scylla.evaluate(board)

        @test ev2 > ev1
    end
end

@testset "Easy Best Move" begin
    engine = Scylla.EngineState()
    engine.config.control = Scylla.DepthControl(4)

    @testset "Bxq" begin
        eFEN = "K6Q/8/8/8/8/8/8/b6k b - - 0 1"
        engine.board = BoardState(eFEN)
        best, log = Scylla.best_move(engine)

        @test Scylla.long_move(best) == "Ba1xh8"
    end

    @testset "bxQ" begin
        eFEN = "k6q/8/8/8/8/8/8/B6K w - - 0 1"
        engine.board = BoardState(eFEN)
        best, log = Scylla.best_move(engine)

        @test Scylla.long_move(best) == "Ba1xh8"
    end

    @testset "Queen Evade Capture" begin
        eFEN = "k7/8/8/8/8/8/5K2/7q b - - 0 1"
        engine.board = BoardState(eFEN)
        best, log = Scylla.best_move(engine)

        @test Scylla.long_move(best) == "Qh1-e4"
    end
end

@testset "Mate in 2" begin
    #mate in 2
    for eFEN in ["K7/R7/R7/8/8/8/8/7k w - - 0 1", "k7/r7/r7/8/8/8/8/7K b - - 0 1"]
        engine = Scylla.EngineState(eFEN)
        engine.config.control = Scylla.DepthControl(6)

        best,log = Scylla.best_move(engine)
        #rook moves to cut off king
        make_move!(best,engine.board)
        moves, move_count = generate_legal_moves(engine.board)
        #king response doesn't matter
        make_move!(moves[1], engine.board)
        best, log = Scylla.best_move(engine)
        make_move!(best, engine.board)
        
        moves, move_length = generate_legal_moves(engine.board)
        @test move_length == 0
        @test Scylla.in_check(engine.board)
        Scylla.clear_current_moves!(engine.board.move_vector, move_length)
    end
end

function test_positions()
    count_correct = 0
    positions = readlines("$(dirname(@__DIR__))/test/test_positions.txt")

    for pos in positions
        FEN_move = split(split(pos,";")[1],"- bm ")
        eFEN = FEN_move[1] * "0"

        engine = EngineState(eFEN; control = Time(2))
        correct_mv = FEN_move[2]

        if verbose
            println("Testing FEN: $eFEN")
        end
        best, log = best_move(engine)

        if Scylla.short_move(best) == correct_mv
            @test true
            printstyled("Pass \n"; color=:green)
        else
            @test_broken false
            if verbose
                println("Fail. Found: $(Scylla.short_move(best)) - Best: $correct_mv")
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



