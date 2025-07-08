using Test
using Scylla

@testset "Setters" begin
    num = UInt64(1)

    num = Scylla.setone(num,1)
    @test num == UInt64(3)

    num = Scylla.setzero(num,0)
    @test num == UInt64(2)
    num = Scylla.setzero(num,1)
    @test num == UInt64(0)

    num2 = UInt64(2)
    @test Scylla.setzero(num2,8) == UInt64(2)
end

@testset "Board Initialise" begin
    board = Scylla.Boardstate(FEN)
    @test Scylla.Whitesmove(board.Colour) == true
    @test board.Data.EnPassant[end] == UInt64(0)
    @test Scylla.ally_pieces(board)[3] != UInt64(0)
    @test Scylla.enemy_pieces(board)[3] != UInt64(0)
    @test Scylla.enemy_pieces(board)[1] == UInt64(1) << 4
    @test Scylla.ally_pieces(board)[1] == UInt64(1) << 60
    @test board.Data.Halfmoves[end] == 0
end

@testset "GUI from Board" begin
    board = Scylla.Boardstate(FEN)
    GUIboard = Scylla.GUIposition(board)
    @test typeof(GUIboard) == typeof(Vector{UInt8}())
    @test length(GUIboard) == 64
    @test GUIboard[5] == 7
end

@testset "Bitboard Union" begin 
    board = Scylla.Boardstate(FEN)
    whte = Scylla.BBunion(Scylla.ally_pieces(board))
    blck = Scylla.BBunion(Scylla.enemy_pieces(board))
    all = Scylla.BBunion(board.pieces)
    compareW = UInt64(0)
    compareB = UInt64(0)

    for i in 0:15
        compareW += UInt64(1) << (63-i)
        compareB += UInt64(1) << i
    end
    @test whte == compareW
    @test blck == compareB
    @test all == compareW | compareB
end

@testset "Rank and File Indices" begin 
    pos = 17
    @test Scylla.rank(pos) == 5
    @test Scylla.file(pos) == 1

    bpos = Scylla.side_index(Scylla.black,pos)
    @test Scylla.rank(bpos) == 2
    @test Scylla.file(bpos) == 1
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

@testset "Iterators" begin 
    board = Scylla.Boardstate(FEN)
    pieces = board.pieces
    @test length(pieces) == 12
    pieces::Vector{UInt64}
    wpieces = Scylla.ally_pieces(board)
    @test length(wpieces) == 6
    bpieces = Scylla.enemy_pieces(board)
    @test length(bpieces) == 6
end

@testset "Identify Locations" begin 
    BB = UInt64(1) << 15 | UInt64(1) << 10
    locs = Scylla.identify_locations(BB)
    @test length(locs) == 2
    @test locs[1] * locs[2] == 150
end

@testset "Moves from Location" begin
    simpleFEN = "8/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Scylla.Boardstate(simpleFEN)
    moves = Vector{UInt32}()
    Scylla.moves_from_location!(Scylla.King,moves,Scylla.enemy_pieces(board),UInt64(3),UInt8(2),false)
    @test length(moves) == 2
    @test Scylla.cap_type(moves[1]) == 0
    @test Scylla.from(moves[2]) == 2
    @test Scylla.pc_type(moves[1]) == 1
end

@testset "Legal Info" begin
    @testset "King Checked by Queen" begin
        simpleFEN = "K7/R7/8/8/8/8/8/r6q w - - 0 1"
        board = Scylla.Boardstate(simpleFEN)    
        info = Scylla.attack_info(board)

        @test info.checks == (UInt64(1)<<63)
        @test info.attack_num == 1
        @test length(info.blocks) == 6
    end

    @testset "Block Queen" begin
        simpleFEN = "K7/7R/8/8/8/8/8/qqk5 w - - 0 1"
        board = Scylla.Boardstate(simpleFEN)  
        info = Scylla.attack_info(board)

        @test length(info.blocks) == 6
    end

    @testset "Bishop Pinned" begin
        simpleFEN = "4k3/8/8/8/4q3/8/4B3/1Q2K3 w - 0 1"
        board = Scylla.Boardstate(simpleFEN)  
        info = Scylla.attack_info(board)

        @test info.blocks == typemax(UInt64)
        @test info.checks == typemax(UInt64)
    end

    @testset "Double Pin" begin
        simpleFEN = "K7/R7/8/8/8/8/8/r6b w - - 0 1"
        board = Scylla.Boardstate(simpleFEN)    
        pinfo = Scylla.attack_info(board)
    
        @test length(pinfo.rookpins) == 7
        @test pinfo.bishoppins == 0
    end

    @testset "No Pin" begin
        simpleFEN = "4k3/8/8/8/4b3/8/4B3/1Q2K3 w - 0 1"
        board = Scylla.Boardstate(simpleFEN)    
        pinfo = Scylla.attack_info(board)

        @test pinfo.rookpins == 0
        @test pinfo.bishoppins == 0
    end
end

@testset "Castling Rights" begin
    cFEN = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
    board = Scylla.Boardstate(cFEN)
    moves = Scylla.generate_moves(board)

    Kcount = 0
    Qcount = 0
    for m in moves 
        if Scylla.flag(m) == Scylla.KCASTLE
            Kcount +=1
        elseif Scylla.flag(m) == Scylla.QCASTLE
            Qcount +=1
        elseif (Scylla.from(m) == 63) & (Scylla.cap_type(m) == Scylla.Rook)
            Scylla.make_move!(m,board)
        end
    end

    @testset "King/Queen-side" begin
        @test Kcount == 1
        @test Qcount == 1
        @test board.Castle == Int(0b1010)
    end

    bmoves = Scylla.generate_moves(board)
    Kcount = 0
    Qcount = 0
    for m in bmoves 
        if Scylla.flag(m) == Scylla.KCASTLE
            Kcount +=1
        elseif Scylla.flag(m) == Scylla.QCASTLE
            Qcount +=1
        elseif Scylla.to(m) == 12
            Scylla.make_move!(m,board)
        end
    end

    @testset "No Castle" begin
        @test Kcount + Qcount == 0
    end

    moves = Scylla.generate_moves(board)
    Kcount = 0
    Qcount = 0
    for m in moves 
        if Scylla.flag(m) == Scylla.KCASTLE
            Kcount +=1
        elseif Scylla.flag(m) == Scylla.QCASTLE
            Qcount +=1
        end
    end

    @testset "Only Queenside" begin
        @test Kcount == 0
        @test Qcount == 1
        @test length(board.Data.Castling) == 3
    end

    @testset "Castling Blocked" begin
        cFEN = "r3k2r/8/8/8/8/8/8/RB2K2R w KQkq - 0 1"
        board = Scylla.Boardstate(cFEN)
        moves = Scylla.generate_moves(board)
        @test all(i -> (Scylla.flag(i) != Scylla.QCASTLE), moves) 
    end
end

@testset "Pawn Moves" begin
    @testset "Pinned Pawns" begin
        pFEN = "8/8/8/8/8/2b5/PPP5/K7 w - - 0 1"
        board = Scylla.Boardstate(pFEN)
        moves = Scylla.generate_moves(board)

        @test count(i->(Scylla.pc_type(i)==Scylla.Pawn),moves) == 3
        @test count(i->(Scylla.cap_type(i)==Scylla.Bishop),moves) == 1
    end

    @testset "Forced Promotion" begin
        promFEN = "K3r4/1r2P3/8/8/8/8/8/8 w - - 0 1"
        board = Scylla.Boardstate(promFEN)
        moves = Scylla.generate_moves(board)
        @test length(findall(i->Scylla.flag(i)==Scylla.PROMQUEEN,moves)) == 1
        @test length(findall(i->Scylla.flag(i)==Scylla.PROMROOK,moves)) == 1
        @test length(findall(i->Scylla.flag(i)==Scylla.PROMBISHOP,moves)) == 1
        @test length(findall(i->Scylla.flag(i)==Scylla.PROMKNIGHT,moves)) == 1
        @test length(findall(i->Scylla.cap_type(i)==Scylla.Rook,moves)) == 4
    end

    @testset "Forced Capture" begin
        checkFEN = "8/8/R7/pppppppk/5R1R/8/8/7K b - - 1 1"
        board = Scylla.Boardstate(checkFEN)
        moves = Scylla.generate_moves(board)
        @test length(moves) == 1
        @test Scylla.pc_type(moves[1]) == Scylla.Pawn
    end

    @testset "En-Passant" begin 
        @testset "Double Push" begin
            EPfen = "8/3p4/7R/k6R/P6R/8/8/8 b - a3 0 1"
            board = Scylla.Boardstate(EPfen)
            moves = Scylla.generate_moves(board)

            @test length(moves) == 1
            @test Scylla.flag(moves[1]) == Scylla.DPUSH

            Scylla.make_move!(moves[1],board)
            @test board.EnPass == UInt64(1) << 19
        end

        @testset "Rules" begin
            EPfen = "8/8/7k/8/Pp6/8/8/K b - a3 0 1"
            board = Scylla.Boardstate(EPfen)
            moves = Scylla.generate_moves(board)
            @test length(findall(i->Scylla.flag(i)==Scylla.EPFLAG,moves)) == 1
            kingmv = findfirst(i->Scylla.pc_type(i)==Scylla.King,moves)
            Scylla.make_move!(moves[kingmv],board)
            @test board.EnPass == 0
        end

        @testset "Out of Check" begin
            newFEN = "8/8/8/7k/ppppppP1/8/8/7K b - g3 1 1"
            board = Scylla.Boardstate(newFEN)
            moves = Scylla.generate_moves(board)
            @test length(moves) == 6
            @test length(findall(i->Scylla.flag(i)==Scylla.EPFLAG,moves)) == 1
        end

        @testset "Bishop Pin" begin
            newFEN = "K7/8/8/2pP4/8/8/8/7b w - c6 1 1"
            board = Scylla.Boardstate(newFEN)
            moves = Scylla.generate_moves(board)
            @test length(moves) == 4
            @test length(findall(i->Scylla.flag(i)==Scylla.EPFLAG,moves)) == 1
        end

        @testset "Illegal due to Check" begin
            newFEN = "k6R/8/8/8/ppppppP1/8/8/7K b - g3 1 1"
            board = Scylla.Boardstate(newFEN)
            moves = Scylla.generate_moves(board)
            @test length(findall(i->Scylla.pc_type(i)==Scylla.Pawn,moves)) == 0 
        end

        @testset "Illegal due to Pin" begin
            newFEN = "8/8/8/K1pPr/8/8/8/8 w - c6 1 1"
            board = Scylla.Boardstate(newFEN)
            moves = Scylla.generate_moves(board)
            @test length(findall(i->Scylla.flag(i)==Scylla.EPFLAG,moves)) == 0
        end
    end
end

@testset "Attack Pieces" begin
    simpleFEN = "8/p2n4/1K5r/8/8/8/8/6b1 w - - 0 1"
    board = Scylla.Boardstate(simpleFEN)    
    all_pcs = Scylla.BBunion(board.pieces)
    kingpos = Scylla.LSB(board.pieces[Scylla.King])

    checkers = Scylla.attack_pcs(Scylla.enemy_pieces(board),all_pcs,kingpos,true)
    @test checkers == (UInt64(1)<<8)|(UInt64(1)<<11)|(UInt64(1)<<23)|(UInt64(1)<<62)
end

@testset "All Possible Moves" begin
    simpleFEN = "R1R1R1R1/8/8/8/8/8/8/1R1R1R1R b - - 0 1"
    board = Scylla.Boardstate(simpleFEN) 
    all_pcs = Scylla.BBunion(board.pieces)  
    attkBB = Scylla.all_poss_moves(Scylla.enemy_pieces(board),all_pcs,Scylla.Whitesmove(board.Colour))

    @test attkBB == typemax(UInt64)
end

@testset "Move Getters" begin
    simpleFEN = "8/8/4nK2/8/8/8/8/8 w - - 0 1"
    board = Scylla.Boardstate(simpleFEN)
    moves = Scylla.generate_moves(board)

    attks = 0
    quiets = 0
    for m in moves 
        if Scylla.cap_type(m) > 0 
            attks+=1
        else 
            quiets+=1
        end
    end
    @test attks == 1
    @test quiets == 5
end

@testset "Game Over" begin
    simpleFEN = "8/8/4nK2/8/8/8/8/8 w - - 0 1"
    board = Scylla.Boardstate(simpleFEN)
    board.Data.Halfmoves[end] = 100
    legal = Scylla.gameover!(board)
    @test board.State == Scylla.Draw()

    @testset "Stalemate" begin
        slidingFEN = "K7/7r/8/8/8/8/8/1r4k1 w - 0 1"
        board = Scylla.Boardstate(slidingFEN)
        legal = Scylla.gameover!(board)
        @test board.State == Scylla.Draw()
    end

    @testset "King X-ray" begin
        slidingFEN = "1R4B1/RK6/7r/8/8/8/8/r1r3kq w - 0 1"
        board = Scylla.Boardstate(slidingFEN)
        legal = Scylla.gameover!(board)
        @test board.State == Scylla.Neutral()
    end

    @testset "Blocked and Pinned" begin
        slidingFEN = "K5Nr/8/8/3B4/8/8/r7/1r5q w - 0 1"
        board = Scylla.Boardstate(slidingFEN)
        legal = Scylla.gameover!(board)
        @test board.State == Scylla.Loss()
    end
end

@testset "Make Move" begin
    @testset "One Piece" begin
        basicFEN = "K7/8/8/8/8/8/8/8 w - - 0 1"
        board = Scylla.Boardstate(basicFEN)
        moves = Scylla.generate_moves(board)

        @test Scylla.ally_pieces(board)[1] == UInt64(1)

        for m in moves
            if Scylla.to(m) == 1
                Scylla.make_move!(m,board)
            end
        end

        @test Scylla.Whitesmove(board.Colour) == false
        @test board.Data.Halfmoves[end] == UInt8(1)
        @test Scylla.enemy_pieces(board)[1] == UInt64(2)
    end

    @testset "Non-Capture" begin
        basicFEN = "Kn6/8/8/8/8/8/8/7k w - 0 1"
        board = Scylla.Boardstate(basicFEN)
        moves = Scylla.generate_moves(board)

        for m in moves
            if Scylla.to(m) == 8
                Scylla.make_move!(m,board)
            end
        end
        @test sum(Scylla.ally_pieces(board)[2:end])  == UInt64(1) << 1
        @test Scylla.enemy_pieces(board)[1] == UInt64(1) << 8
        @test length(generate_moves(board)) == 6
    end

    @testset "Black Move" begin
        basicFEN = "1n6/K7/8/8/8/8/8/7k b - - 0 1"
        board = Scylla.Boardstate(basicFEN)
        moves = Scylla.generate_moves(board)
        @test Scylla.Whitesmove(board.Colour) == false
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
        board = Scylla.Boardstate(basicFEN)
        moves = Scylla.generate_moves(board)
        @test length(moves) == 12
        
        for m in moves
            if (Scylla.from(m) == 56) & (Scylla.to(m) == 41)
                Scylla.make_move!(m,board)
            end
        end
        @test Scylla.Whitesmove(board.Colour) == false
        @test sum(Scylla.ally_pieces(board)[2:end]) == 0

        GUI = Scylla.GUIposition(board)
        @test GUI[42] == 5
    end
end

@testset "Captures" begin
    @testset "King Takes Knight" begin
        basicFEN = "Kn6/8/8/8/8/8/8/7k w - - 0 1"
        board = Scylla.Boardstate(basicFEN)
        moves = Scylla.generate_moves(board)

        @test sum(Scylla.enemy_pieces(board)) > 0

        for m in moves
            if Scylla.cap_type(m) > 0
                Scylla.make_move!(m,board)
            end
        end

        @test sum(Scylla.ally_pieces(board)[2:end]) == 0
        @test Scylla.enemy_pieces(board)[1] == UInt64(2)

        @test length(generate_moves(board)) == 3

        GUI = Scylla.GUIposition(board)
        @test GUI[2] == 1
        @test sum(GUI) == 8
    end
end

@testset "Legal Info" begin
    @testset "Forced Capture" begin
        knightFEN = "K7/8/1nnn4/8/N7/8/8/8 w - 0 1"
        board = Scylla.Boardstate(knightFEN)

        moves = Scylla.generate_moves(board)
        @test length(moves) == 1
        @test Scylla.cap_type(moves[1]) > 0
        @test Scylla.pc_type(moves[1]) == Scylla.Knight
    end

    @testset "Stalemate" begin
        slidingFEN = "K7/7r/8/8/8/8/8/1r4k1 w - 0 1"
        board = Scylla.Boardstate(slidingFEN)
        moves = Scylla.generate_moves(board)
        @test length(moves) == 0
    end

    @testset "Bishop Must Block" begin
        slidingFEN = "1R4B1/RK6/7r/8/8/8/8/r1r3kq w - 0 1"
        board = Scylla.Boardstate(slidingFEN)
        moves = Scylla.generate_moves(board)
        @test length(moves) == 1
        @test Scylla.pc_type(moves[1]) == Scylla.Bishop 
    end

    @testset "Checkmate" begin
        slidingFEN = "K5Nr/8/8/3B4/8/8/r7/1r5q w - 0 1"
        board = Scylla.Boardstate(slidingFEN)
        moves = Scylla.generate_moves(board)
        @test length(moves) == 0
    end

    #Only legal move is to block with rook
    @testset "Rook Must Block" begin
        slidingFEN = "K5Nr/8/8/3B4/7R/8/q7/1r5q w - 0 1"
        board = Scylla.Boardstate(slidingFEN)
        moves = Scylla.generate_moves(board)
        @test length(moves) == 1
    end
end

@testset "Identify Piecetype" begin
    basicFEN = "1N7/8/8/8/8/8/8/8 w - - 0 1"
    board = Scylla.Boardstate(basicFEN)
    ID = Scylla.identify_piecetype(Scylla.ally_pieces(board),1)
    @test ID == 5

    ID = Scylla.identify_piecetype(Scylla.ally_pieces(board),2)
    @test ID == 0
end

@testset "Unmake Move" begin
    basicFEN = "Kn6/8/8/8/8/8/8/7k w - - 0 1"
    board = Scylla.Boardstate(basicFEN)
    moves = Scylla.generate_moves(board)

    @testset "Single Make/Unmake" begin
        for m in moves
            if Scylla.cap_type(m) > 0
                Scylla.make_move!(m,board)
            end
        end
        Scylla.unmake_move!(board)

        @test Scylla.Whitesmove(board.Colour) == true
        @test Scylla.ally_pieces(board)[1] == UInt64(1)
        @test Scylla.enemy_pieces(board)[5] == UInt64(2)
    end

    @testset "Triple Make/Unmake" begin
        moves = Scylla.generate_moves(board)
        for m in moves
            if Scylla.to(m) == 8
                Scylla.make_move!(m,board)
            end
        end
        @test Scylla.enemy_pieces(board)[1] == UInt(1) << 8
        moves = Scylla.generate_moves(board)
        for m in moves
            if Scylla.to(m) == 16
                Scylla.make_move!(m,board)
            end
        end
        @test Scylla.enemy_pieces(board)[5] == UInt(1) << 16
        moves = Scylla.generate_moves(board)
        for m in moves
            if Scylla.cap_type(m) == 5
                Scylla.make_move!(m,board)
            end
        end
        @test Scylla.ally_pieces(board)[5] == 0
        @test length(board.Data.Halfmoves) == 2
        Scylla.unmake_move!(board)
        Scylla.unmake_move!(board)
        Scylla.unmake_move!(board)

        @test Scylla.Whitesmove(board.Colour) == true
        @test Scylla.ally_pieces(board)[1] == UInt64(1)
        @test Scylla.enemy_pieces(board)[5] == UInt64(2)
        @test length(board.Data.Halfmoves) == 1
    end
end

@testset "Repetition" begin
    basicFEN = "K7/8/8/8/8/8/8/7k w - - 0 1"
    board = Scylla.Boardstate(basicFEN)

    for i in 1:8
        moves = Scylla.generate_moves(board)
        for m in moves
            pos = -1
            if i%2==1
                pos = 0
            else
                pos = 63
            end
            if (Scylla.from(m) == pos) | (Scylla.to(m) == pos)
                Scylla.make_move!(m,board)
                break
            end
        end
    end
    legal = Scylla.gameover!(board)
    @test board.State == Scylla.Draw()
end

@testset "UCI Move" begin
    str1 = Scylla.UCIpos(0)
    str2 = Scylla.UCIpos(63)
    @test (str1 == "a8") & (str2 == "h1")

    move = Scylla.Move(UInt8(1),UInt8(2),UInt8(54),UInt8(0),UInt8(0))
    mvstr = Scylla.UCImove(move)
    @test mvstr == "c8g2"
end

@testset "Long UCI Move" begin 
    move = Scylla.Move(UInt8(1),UInt8(2),UInt8(54),UInt8(2),UInt8(0))
    mvstr = Scylla.LONGmove(move)
    @test mvstr == "Kc8xg2"
end

@testset "Pseudo-legal Sliding Piece Generation" begin
    slidingFEN = "Q6r/8/2K5/8/8/8/8/b2k3 w - 0 1"
    board = Scylla.Boardstate(slidingFEN)

    moves = Scylla.generate_moves(board)
    @test length(moves) == 23
    @test count(i->(Scylla.cap_type(i) > 0),moves) == 2

    for m in moves
        if Scylla.cap_type(m) == Scylla.Rook
            Scylla.make_move!(m,board)
        end
    end
    newmoves = Scylla.generate_moves(board)
    @test length(newmoves) == 12
    @test count(i->(Scylla.cap_type(i) == Scylla.Queen),newmoves) == 1
end

@testset "Zobrist" begin
    board = Scylla.Boardstate(FEN)
    moves = Scylla.generate_moves(board)
    for move in moves
       if (Scylla.from(move) == 57) & (Scylla.to(move) == 40)
        Scylla.make_move!(move,board)
       end
    end

    newFEN = "rnbqkbnr/pppppppp/8/8/8/N7/PPPPPPPP/R1BQKBNR b KQkq - 1 1"
    newboard = Scylla.Boardstate(newFEN)
    @test board.ZHash == newboard.ZHash

    #should end up back at start position
    moves = Scylla.generate_moves(board)
    for move in moves
       if (Scylla.from(move) == 1) & (Scylla.to(move) == 16)
        Scylla.make_move!(move,board)
       end
    end
    moves = Scylla.generate_moves(board)
    for move in moves
       if (Scylla.from(move) == 40) & (Scylla.to(move) == 57)
        Scylla.make_move!(move,board)
       end
    end
    moves = Scylla.generate_moves(board)
    for move in moves
       if (Scylla.from(move) == 16) & (Scylla.to(move) == 1)
        Scylla.make_move!(move,board)
       end
    end
    @test board.ZHash == board.Data.ZHashHist[1]

    Scylla.unmake_move!(board)
    Scylla.unmake_move!(board)
    Scylla.unmake_move!(board)
    @test board.ZHash == newboard.ZHash
end

@testset "PST Values" begin
    nFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    board = Scylla.Boardstate(nFEN)

    @test board.PSTscore == [0,0]

    nFEN = "8/P6k/K7/8/8/8/8/8 w - - 0 1"
    board = Scylla.Boardstate(nFEN)
    
    @test board.PSTscore[1] >= 100
    @test board.PSTscore[2] >= 100
end


@testset "Cheap Perft" begin 
    basicFEN = "K7/8/8/8/8/8/8/7k w - - 0 1"
    board = Scylla.Boardstate(basicFEN)

    leaves = perft(board,2)
    @test leaves == 9
end

@testset "Transposition Table" begin
    TT = Scylla.TranspositionTable(4,Scylla.PerftData)
    @testset "Initialise" begin
        for Data in TT.HashTable
            @test Data.ZHash == 0
            @test Data.depth == 0
            @test Data.leaves == 0
        end    
    end

    @testset "Two Similar Hashes" begin
        Z1 = UInt64(2^61+2^62+2^10) 
        Z2 = UInt64(2^61+2^62+2^11) 

        new_data = Scylla.PerftData(Z1,UInt8(5),UInt128(1))

        Scylla.set_entry!(TT,new_data)
        TT_entry1 = Scylla.get_entry(TT,Z1)
        TT_entry2 = Scylla.get_entry(TT,Z2)

        @test TT_entry1 == new_data 
        @test TT_entry1 == TT_entry2 
        @test TT_entry2.ZHash == Z1
        @test TT_entry2.ZHash != Z2 
    end
end

function Testing_perft(board::Boardstate,depth)
    #could also test incremental Zhash updates here
    legal = Scylla.gameover!(board)
    moves = Scylla.generate_moves(board,legal)

    if board.State == Scylla.Neutral()
        @assert length(moves) > 0
    else
        @assert length(moves) == 0
    end
    
    attacks = Scylla.generate_attacks(board)
    num_attacks = count(m->Scylla.cap_type(m)>0,moves)
    @assert length(attacks) == num_attacks "Wrong number of attacks generated. Should be $(num_attacks), got $(length(attacks))."

    if depth > 1
        for move in moves
            Scylla.make_move!(move,board)
            static_eval = zeros(Int32,2)
            Scylla.set_PST!(static_eval,board.pieces)
            @assert board.PSTscore == static_eval "Score doesn't match. Dynamic = $(board.PSTscore), static = $(static_eval). Found on move $(show(move))"
            Testing_perft(board,depth-1)
            Scylla.unmake_move!(board)
        end
    end
end

function test_with_perft()
    #Test that PST values from incremental upadate are not different from static evaluation
    #Also that number of attacks from generate_attacks is the same as fromScylla.generate_moves(all)
    #Also that we can identify terminal nodes without running movegen

    FEN = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
    board = Scylla.Boardstate(FEN)
    Testing_perft(board,4)

    FEN = "n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - 0 1"
    board = Scylla.Boardstate(FEN)
    Testing_perft(board,5)

    FEN = "RPrk/PP6/8/8/8/8/r7/7K b - - 0 26"
    board = Scylla.Boardstate(FEN)
    Testing_perft(board,5)
end

function test_speed()
    FENs = ["nnnnknnn/8/8/8/8/8/8/NNNNKNNN w - 0 1",
    "bbbqknbq/8/8/8/8/8/8/QNNNKBBQ w - 0 1",
    "r3k2r/4q1b1/bn3n2/4N3/8/2N2Q2/3BB3/R3K2R w KQkq -",
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"]
    Depths = [5,4,4,4]
    Targets = [11813050,7466475,7960855,4085603]
    Δt = 0
    leaves = 0
    TT_size = 0

    for (FEN,depth,target) in zip(FENs,Depths,Targets)
        board = Scylla.Boardstate(FEN)
        if verbose
            println("Testing position: $FEN")
        end
        t = time()
        TT = Scylla.TranspositionTable(TT_size,Scylla.PerftData)
        cur_leaves = Scylla.perft(board,depth,TT,verbose)
        println()
        Δt += time() - t
        leaves += cur_leaves

        if target == 0
            println(cur_leaves)
        else
            @assert cur_leaves == target "failed on FEN $FEN, missing $(target-cur_leaves) nodes"
        end
    end
    return leaves,Δt
end

if perft_extra::Bool
    test_with_perft()
    leaves,Δt = test_speed()
    println("Leaves: $leaves. NPS = $(leaves/Δt) nodes/second")
end

function test_TT_perft()
    #best speed = 180 Mnps
    board = Scylla.Boardstate(FEN)
    TT = Scylla.TranspositionTable(24,Scylla.PerftData,verbose)
    t = time()
    @test Scylla.perft(board,7,TT,verbose) == 3195901860
    δt = time()-t
    println("Successfully determined perft 7 in $(round(δt,sigdigits=4))s. $(round(3195901860/(δt*1e6),sigdigits=6)) Mnps")
end
if TT_perft::Bool
    test_TT_perft()
end



