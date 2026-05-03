using Scylla
using Test

@testset "Move Representations" begin
        
    @testset "UCI Move" begin
        cFEN = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
        board = Scylla.BoardState(cFEN)
        moves, move_count = generate_legal_moves(board)

        move = Scylla.Move(UInt8(1),UInt8(2),UInt8(54),UInt8(0),UInt8(0))
        @test Scylla.uci_move(move) == "c8g2"

        kcastle = moves[findfirst(m->Scylla.flag(m)==Scylla.KING_CASTLE, moves)]
        @test Scylla.uci_move(kcastle) == "e1g1"
        qcastle = moves[findfirst(m->Scylla.flag(m)==Scylla.QUEEN_CASTLE, moves)]
        @test Scylla.uci_move(qcastle) == "e1c1"

        cFEN = "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1"
        board = Scylla.BoardState(cFEN)
        moves, move_count = generate_legal_moves(board)
        kcastle = moves[findfirst(m->Scylla.flag(m)==Scylla.KING_CASTLE, moves)]
        @test Scylla.uci_move(kcastle) == "e8g8"
        qcastle = moves[findfirst(m->Scylla.flag(m)==Scylla.QUEEN_CASTLE, moves)]
        @test Scylla.uci_move(qcastle) == "e8c8"

        promFEN = "K3r3/2r2P3/8/8/8/8/8/8 w - - 0 1"
        board = Scylla.BoardState(promFEN)
        moves, move_count = generate_legal_moves(board)
        move = moves[findfirst(m->Scylla.flag(m)==Scylla.PROMQUEEN, moves)]
        @test Scylla.uci_move(move) == "f7e8q"
    end

    @testset "Convert Algebraic <--> Numeric" begin
        @test Scylla.algebraic_to_numeric("a8") == 0
        @test Scylla.algebraic_to_numeric("h1") == 63

        @test Scylla.uci_pos(0) == "a8"
        @test Scylla.uci_pos(63) == "h1"

        promFEN = "K3r3/2r2P3/8/8/8/8/8/8 w - - 0 1"
        board = Scylla.BoardState(promFEN)
        moves, move_count = generate_legal_moves(board)

        for move in moves 
            uci = Scylla.uci_move(move)
            @test Scylla.identify_uci_move(board,uci) == move
        end
    end

    @testset "UCI to Internal" begin
        board = BoardState("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
        kmove = Scylla.identify_uci_move(board, "e8g8")
        @test Scylla.flag(kmove) == Scylla.KING_CASTLE
        qmove = Scylla.identify_uci_move(board, "e8c8")
        @test Scylla.flag(qmove) == Scylla.QUEEN_CASTLE
    end

    @testset "Move Sequence Input" begin
        board = BoardState("r1bqkb1r/pp2pp1p/2np1np1/8/2PNP3/2N5/PP2BPPP/R1BQK2R b KQkq - 0 1")
        moves = ["c6d4", "d1d4", "e7e5", "d4d3", "c8e6", "c1g5", "a8c8", "b2b3", 
                 "c8c6", "a1d1", "a7a5", "c3d5", "f8g7", "f2f4", "h7h6", "f4e5", 
                 "h6g5", "e5f6", "g7f6", "g2g4", "f6e5", "h2h3", "e8g8", "e1g1"]
    
        for m in moves 
            move = Scylla.identify_uci_move(board, m)
            @test Scylla.uci_move(move) == m
            make_move!(move, board)
        end

        final_board = BoardState("3q1rk1/1p3p2/2rpb1p1/p2Nb1p1/2P1P1P1/1P1Q3P/P3B3/3R1RK1 b - - 2 13")
        @test board.pieces == final_board.pieces
    end

    @testset "Long UCI Move" begin 
        move = Scylla.Move(UInt8(1),UInt8(2),UInt8(54),UInt8(2),UInt8(0))
        mvstr = Scylla.long_move(move)
        @test mvstr == "Kc8xg2"
    end

end

@testset "Move Struct" begin 
    pc = UInt8(1)
    from = UInt8(10)
    to = UInt8(11)
    cap = UInt8(3)
    flag = UInt8(1)
    mv = Scylla.Move(pc,from,to,cap,flag)

    P,F,T,C,Fl = Scylla.unpack_move(mv)
    @test P == pc
    @test F == from
    @test T == to
    @test C == cap
    @test Fl == flag
end

@testset "Move Bitboard" begin 
    movestruct = Scylla.Move_BB()
    @test length(movestruct.knight) == 64
    @test movestruct.king[1] == UInt64(770)
end

@testset "Make Move" begin
    @testset "One Piece" begin
        basicFEN = "K7/8/8/8/8/8/8/8 w - - 0 1"
        board = Scylla.BoardState(basicFEN)
        moves, move_count = Scylla.generate_legal_moves(board)

        @test Scylla.ally_pieces(board)[1] == UInt64(1)

        for m in moves
            if Scylla.to(m) == 1
                Scylla.make_move!(m,board)
            end
        end

        @test Scylla.whitesmove(board.colour) == false
        @test board.data.half_moves[end] == UInt8(1)
        @test Scylla.enemy_pieces(board)[1] == UInt64(2)
    end

    @testset "Non-Capture" begin
        basicFEN = "Kn6/8/8/8/8/8/8/7k w - 0 1"
        board = Scylla.BoardState(basicFEN)
        moves, move_count = Scylla.generate_legal_moves(board)

        for m in moves
            if Scylla.to(m) == 8
                Scylla.make_move!(m,board)
            end
        end
        @test sum(Scylla.ally_pieces(board)[2:end])  == UInt64(1) << 1
        @test Scylla.enemy_pieces(board)[1] == UInt64(1) << 8
        @test length(generate_legal_moves(board)[1]) == 6
    end

    @testset "Black Move" begin
        basicFEN = "1n6/K7/8/8/8/8/8/7k b - - 0 1"
        board = Scylla.BoardState(basicFEN)
        moves, move_count = Scylla.generate_legal_moves(board)
        @test Scylla.whitesmove(board.colour) == false
        @test length(moves) == 6

        for m in moves
            if Scylla.to(m) == 11
                Scylla.make_move!(m,board)
            end
        end
        @test sum(Scylla.enemy_pieces(board)[2:end]) == 1<<11
        GUI = Scylla.GUIposition(board)
        @test GUI[12] == 11
    end

    @testset "Multiple Pieces" begin
        basicFEN = "k7/8/8/8/8/8/8/NNN4K w - - 0 1"
        board = Scylla.BoardState(basicFEN)
        moves, move_count = Scylla.generate_legal_moves(board)
        @test length(moves) == 12
        
        for m in moves
            if (Scylla.from(m) == 56) & (Scylla.to(m) == 41)
                Scylla.make_move!(m,board)
            end
        end
        @test Scylla.whitesmove(board.colour) == false
        @test sum(Scylla.ally_pieces(board)[2:end]) == 0

        GUI = Scylla.GUIposition(board)
        @test GUI[42] == 5
    end
end


@testset "Unmake Move" begin
    basicFEN = "Kn6/8/8/8/8/8/8/7k w - - 0 1"
    board = Scylla.BoardState(basicFEN)
    moves, move_count = Scylla.generate_legal_moves(board)

    @testset "Single Make/Unmake" begin
        for m in moves
            if Scylla.cap_type(m) > 0
                Scylla.make_move!(m,board)
            end
        end
        Scylla.unmake_move!(board)

        @test Scylla.whitesmove(board.colour) == true
        @test Scylla.ally_pieces(board)[1] == UInt64(1)
        @test Scylla.enemy_pieces(board)[5] == UInt64(2)
    end

    @testset "Triple Make/Unmake" begin
        moves, move_count = Scylla.generate_legal_moves(board)
        for m in moves
            if Scylla.to(m) == 8
                Scylla.make_move!(m,board)
            end
        end
        @test Scylla.enemy_pieces(board)[1] == UInt(1) << 8
        moves, move_count = Scylla.generate_legal_moves(board)
        for m in moves
            if Scylla.to(m) == 16
                Scylla.make_move!(m,board)
            end
        end
        @test Scylla.enemy_pieces(board)[5] == UInt(1) << 16
        moves, move_count = Scylla.generate_legal_moves(board)
        for m in moves
            if Scylla.cap_type(m) == 5
                Scylla.make_move!(m, board)
            end
        end
        @test Scylla.ally_pieces(board)[5] == 0
        @test length(board.data.half_moves) == 2
        Scylla.unmake_move!(board)
        Scylla.unmake_move!(board)
        Scylla.unmake_move!(board)

        @test Scylla.whitesmove(board.colour) == true
        @test Scylla.ally_pieces(board)[1] == UInt64(1)
        @test Scylla.enemy_pieces(board)[5] == UInt64(2)
        @test length(board.data.half_moves) == 1
    end
end