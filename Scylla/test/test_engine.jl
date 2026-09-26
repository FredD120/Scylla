using Scylla
using Test

@testset "Basic Evaluation" begin 
    @testset "Start Position" begin
        eFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        board = Scylla.BoardState(eFEN)
        evw = Scylla.evaluate(board)

        eFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1"
        board = Scylla.BoardState(eFEN)
        evb = Scylla.evaluate(board)
        @test evw == evb
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
        eFEN = "r2qk2r/pppppppp/8/8/PP4PP/8/2PPPP2/R2QK2R w KQkq - 0 1"
        board = Scylla.BoardState(eFEN)
        ev1 = Scylla.evaluate(board)

        eFEN = "r2qk2r/pppppppp/8/8/2PPPP2/8/PP4PP/R2QK2R w KQkq - 0 1"
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

    @testset "Mate in 1" begin
        engine.board = Scylla.BoardState("6k1/5ppp/8/8/8/8/8/3R2K1 w - - 0 1")
        best, _ = Scylla.best_move(engine)
        @test lowercase(Scylla.long_move(best)) == "rd1-d8"
    end

    @testset "Capture Hanging Queen" begin
        engine.board = Scylla.BoardState("k6q/8/8/8/8/8/8/B6K w - - 0 1")
        best, _ = Scylla.best_move(engine)
        @test lowercase(Scylla.long_move(best)) == "ba1xh8"

        # colour swap
        engine.board = BoardState("K6Q/8/8/8/8/8/8/b6k b - - 0 1")
        best, log = Scylla.best_move(engine)

        @test Scylla.long_move(best) == "Ba1xh8"
    end

    @testset "Pawn Promotion" begin
        engine.board = Scylla.BoardState("8/4P1k1/8/8/8/8/8/6K1 w - - 0 1")
        best, _ = Scylla.best_move(engine)
        @test lowercase(Scylla.long_move(best)) == "pe7-e8q"
    end

    @testset "En Passant" begin
        engine.board = Scylla.BoardState("8/8/8/4Pp2/8/8/8/4K2k w - f6 0 1")
        best, _ = Scylla.best_move(engine)
        @test lowercase(Scylla.long_move(best)) == "pe5xf6"
    end

    @testset "Defend Against Mate" begin
        engine.board = Scylla.BoardState("r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR b KQkq - 0 1")
        best, _ = Scylla.best_move(engine)
        @test lowercase(Scylla.long_move(best)) in ["ng8-f6", "qd8-f6", "qd8-e7"]
    end

    @testset "Knight Fork" begin
        engine.board = Scylla.BoardState("r3k3/8/8/3N4/8/8/8/4K3 w - - 0 1")
        best, _ = Scylla.best_move(engine)
        @test lowercase(Scylla.long_move(best)) == "nd5-c7"
    end

    @testset "Discovered Attack" begin
        engine.board = Scylla.BoardState("4k3/4q3/8/8/4B3/8/8/4R1K1 w - - 0 1")
        best, _ = Scylla.best_move(engine)
        @test startswith(lowercase(Scylla.long_move(best)), "be4-")
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

if expensive::Bool
    result = @testset "Difficult Engine Tests" begin
        test_positions()
    end
    if verbose
        Test.print_test_results(result)
    end
end