using Test
using Scylla

const expensive = false
const verbose = false

const FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

function test_setters()
    num = UInt64(1)

    num = Scylla.setone(num,1)
    @assert num == UInt64(3)

    num = Scylla.setzero(num,0)
    @assert num == UInt64(2)
    num = Scylla.setzero(num,1)
    @assert num == UInt64(0)

    num2 = UInt64(2)
    @assert Scylla.setzero(num2,8) == UInt64(2)
end
test_setters()

function test_boardinit()
    board = Boardstate(FEN)
    @assert Whitesmove(board.Colour) == true
    @assert board.Data.EnPassant[end] == UInt64(0)
    @assert Scylla.ally_pieces(board)[3] != UInt64(0)
    @assert Scylla.enemy_pieces(board)[3] != UInt64(0)
    @assert Scylla.enemy_pieces(board)[1] == UInt64(1) << 4
    @assert Scylla.ally_pieces(board)[1] == UInt64(1) << 60
    @assert board.Data.Halfmoves[end] == 0
end
test_boardinit()

function test_GUIboard()
    board = Boardstate(FEN)
    GUIboard = GUIposition(board)
    @assert typeof(GUIboard) == typeof(Vector{UInt8}())
    @assert length(GUIboard) == 64
    @assert GUIboard[5] == 7
end
test_GUIboard()

function test_BitboardUnion()
    board = Boardstate(FEN)
    white = Scylla.BBunion(Scylla.ally_pieces(board))
    black = Scylla.BBunion(Scylla.enemy_pieces(board))
    all = Scylla.BBunion(board.pieces)
    compareW = UInt64(0)
    compareB = UInt64(0)

    for i in 0:15
        compareW += UInt64(1) << (63-i)
        compareB += UInt64(1) << i
    end
    @assert white == compareW
    @assert black == compareB
    @assert all == compareW | compareB
end
test_BitboardUnion()

function test_index()
    pos = 17
    @assert rank(pos) == 5
    @assert file(pos) == 1

    bpos = side_index(black,pos)
    @assert rank(bpos) == 2 "Mirrored about the x axis"
    @assert file(bpos) == 1
end
test_index()

function test_Move()
    pc = UInt8(1)
    from = UInt8(10)
    to = UInt8(11)
    cap = UInt8(3)
    flag = UInt8(1)
    mv = Move(pc,from,to,cap,flag)

    P,F,T,C,Fl = Scylla.unpack_move(mv)
    @assert P == pc
    @assert F == from
    @assert T == to
    @assert C == cap
    @assert Fl == flag
end
test_Move()

function test_moveBB()
    movestruct = Scylla.Move_BB()
    @assert length(movestruct.knight) == 64
    @assert movestruct.king[1] == UInt64(770)
end
test_moveBB()

function test_iterators()
    board = Boardstate(FEN)
    pieces = board.pieces
    @assert length(pieces) == 12
    pieces::Vector{UInt64}
    wpieces = Scylla.ally_pieces(board)
    @assert length(wpieces) == 6
    bpieces = Scylla.enemy_pieces(board)
    @assert length(bpieces) == 6
end
test_iterators()

function test_identifylocs()
    BB = UInt64(1) << 15 | UInt64(1) << 10
    locs = identify_locations(BB)
    @assert length(locs) == 2
    @assert locs[1] * locs[2] == 150
end
test_identifylocs()

function test_movfromloc()
    simpleFEN = "8/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(simpleFEN)
    moves = Vector{UInt32}()
    Scylla.moves_from_location!(Scylla.King,moves,Scylla.enemy_pieces(board),UInt64(3),UInt8(2),false)
    @assert length(moves) == 2
    @assert cap_type(moves[1]) == 0
    @assert from(moves[2]) == 2
    @assert pc_type(moves[1]) == 1
end
test_movfromloc()

function test_legalinfo()
    simpleFEN = "K7/R7/8/8/8/8/8/r6q w - - 0 1"
    board = Boardstate(simpleFEN)    
    info = Scylla.attack_info(board)

    @assert info.checks == (UInt64(1)<<63) "only bishop attacks king"
    @assert info.attack_num == 1
    @assert length(info.blocks) == 6 "6 squares blocking bishop"

    simpleFEN = "K7/7R/8/8/8/8/8/qq6 w - - 0 1"
    board = Boardstate(simpleFEN)    
    @assert length(info.blocks) == 6 "6 squares blocking queen attack"

    simpleFEN = "4k3/8/8/8/4q3/8/4B3/1Q2K3 w - 0 1"
    board = Boardstate(simpleFEN)  
    info = Scylla.attack_info(board)

    @assert info.blocks == typemax(UInt64)
    @assert info.checks == typemax(UInt64)

    simpleFEN = "K7/R7/8/8/8/8/8/r6b w - - 0 1"
    board = Boardstate(simpleFEN)    
    pinfo = Scylla.attack_info(board)

    @assert length(pinfo.rookpins) == 7
    @assert pinfo.bishoppins == 0

    simpleFEN = "4k3/8/8/8/4b3/8/4B3/1Q2K3 w - 0 1"
    board = Boardstate(simpleFEN)    
    pinfo = Scylla.attack_info(board)

    @assert pinfo.rookpins == 0
    @assert pinfo.bishoppins == 0
end
test_legalinfo()

function test_castle()
    cFEN = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
    board = Boardstate(cFEN)
    moves = generate_moves(board)

    Kcount = 0
    Qcount = 0
    for m in moves 
        if flag(m) == KCASTLE
            Kcount +=1
        elseif flag(m) == QCASTLE
            Qcount +=1
        elseif (from(m) == 63) & (cap_type(m) == Rook)
            make_move!(m,board)
        end
    end
    @assert Kcount == 1 "Should be able to castle kingside"
    @assert Qcount == 1 "Should be able to castle queenside"
    @assert board.Castle == Int(0b1010) "Both sides have lost kingside castling"

    bmoves = generate_moves(board)
    Kcount = 0
    Qcount = 0
    for m in bmoves 
        if flag(m) == KCASTLE
            Kcount +=1
        elseif flag(m) == QCASTLE
            Qcount +=1
        elseif to(m) == 12
            make_move!(m,board)
        end
    end
    @assert Kcount + Qcount == 0 "Should not be able to castle"

    moves = generate_moves(board)
    Kcount = 0
    Qcount = 0
    for m in moves 
        if flag(m) == KCASTLE
            Kcount +=1
        elseif flag(m) == QCASTLE
            Qcount +=1
        end
    end
    @assert Kcount == 0 "Should not be able to castle kingside"
    @assert Qcount == 1 "Should be able to castle queenside"
    @assert length(board.Data.Castling) == 3

    cFEN = "r3k2r/8/8/8/8/8/8/RB2K2R w KQkq - 0 1"
    board = Boardstate(cFEN)
    moves = generate_moves(board)
    @assert all(i -> (flag(i) != QCASTLE), moves) "cannot castle queenside when piece in the way"
end
test_castle()

function test_pawns()
    pFEN = "8/8/8/8/8/2b5/PPP5/K7 w - - 0 1"
    board = Boardstate(pFEN)
    moves = generate_moves(board)

    @assert count(i->(pc_type(i)==Pawn),moves) == 3 "Pinned/blocked by bishop"
    @assert count(i->(cap_type(i)==Bishop),moves) == 1 "Capture bishop along pin"

    promFEN = "K3r4/1r2P3/8/8/8/8/8/8 w - - 0 1"
    board = Boardstate(promFEN)
    moves = generate_moves(board)
    @assert length(findall(i->flag(i)==PROMQUEEN,moves)) == 1 "One of each promote type Q"
    @assert length(findall(i->flag(i)==PROMROOK,moves)) == 1 "One of each promote type R"
    @assert length(findall(i->flag(i)==PROMBISHOP,moves)) == 1 "One of each promote type B"
    @assert length(findall(i->flag(i)==PROMKNIGHT,moves)) == 1 "One of each promote type N"
    @assert length(findall(i->cap_type(i)==Rook,moves)) == 4 "Must capture rook" 

    checkFEN = "8/8/R7/pppppppk/5R1R/8/8/7K b - - 1 1"
    board = Boardstate(checkFEN)
    moves = generate_moves(board)
    @assert length(moves) == 1
    @assert pc_type(moves[1]) == Pawn "only pawn can capture"
end
test_pawns()

function testEP()
    EPfen = "8/3p4/7R/k6R/P6R/8/8/8 b - a3 0 1"
    board = Boardstate(EPfen)
    moves = generate_moves(board)

    @assert length(moves) == 1 "Only one legal move, pawn double push"
    @assert flag(moves[1]) == DPUSH

    make_move!(moves[1],board)
    @assert board.EnPass == UInt64(1) << 19 "En-passant square created by double push"

    EPfen = "8/8/7k/8/Pp6/8/8/K b - a3 0 1"
    board = Boardstate(EPfen)
    moves = generate_moves(board)
    @assert length(findall(i->flag(i)==EPFLAG,moves)) == 1 "Can en-passant"
    kingmv = findfirst(i->pc_type(i)==King,moves)
    make_move!(moves[kingmv],board)
    @assert board.EnPass == 0 "Should clear EP bitboard"

    newFEN = "8/8/8/7k/ppppppP1/8/8/7K b - g3 1 1"
    board = Boardstate(newFEN)
    moves = generate_moves(board)
    @assert length(moves) == 6
    @assert length(findall(i->flag(i)==EPFLAG,moves)) == 1 "Can EP capture out of check"

    newFEN = "K7/8/8/2pP4/8/8/8/7b w - c6 1 1"
    board = Boardstate(newFEN)
    moves = generate_moves(board)
    @assert length(moves) == 4
    @assert length(findall(i->flag(i)==EPFLAG,moves)) == 1 "Can EP along bishop pin"

    newFEN = "k6R/8/8/8/ppppppP1/8/8/7K b - g3 1 1"
    board = Boardstate(newFEN)
    moves = generate_moves(board)
    @assert length(findall(i->pc_type(i)==Pawn,moves)) == 0 "Can't EP when in check"

    newFEN = "8/8/8/K1pPr/8/8/8/8 w - c6 1 1"
    board = Boardstate(newFEN)
    moves = generate_moves(board)
    @assert length(findall(i->flag(i)==EPFLAG,moves)) == 0 "Can't EP as pinned by rook"
end
testEP()

function test_attckpcs()
    simpleFEN = "8/p2n4/1K5r/8/8/8/8/6b1 w - - 0 1"
    board = Boardstate(simpleFEN)    
    all_pcs = Scylla.BBunion(board.pieces)
    kingpos = LSB(board.pieces[King])

    checkers = Scylla.attack_pcs(Scylla.enemy_pieces(board),all_pcs,kingpos,true)
    @assert checkers == (UInt64(1)<<8)|(UInt64(1)<<11)|(UInt64(1)<<23)|(UInt64(1)<<62) "2 sliding piece attacks, a knight and a pawn"
end
test_attckpcs()

function test_allposs()
    simpleFEN = "R1R1R1R1/8/8/8/8/8/8/1R1R1R1R b - - 0 1"
    board = Boardstate(simpleFEN) 
    all_pcs = Scylla.BBunion(board.pieces)  
    attkBB = Scylla.all_poss_moves(Scylla.enemy_pieces(board),all_pcs,Whitesmove(board.Colour))

    @assert attkBB == typemax(UInt64) "rooks are covering all squares"
end
test_allposs()

function test_movegetters()
    simpleFEN = "8/8/4nK2/8/8/8/8/8 w - - 0 1"
    board = Boardstate(simpleFEN)
    moves = generate_moves(board)

    attks = 0
    quiets = 0
    for m in moves 
        if cap_type(m) > 0 
            attks+=1
        else 
            quiets+=1
        end
    end
    @assert attks == 1
    @assert quiets == 5
end
test_movegetters()

function test_gameover()
    simpleFEN = "8/8/4nK2/8/8/8/8/8 w - - 0 1"
    board = Boardstate(simpleFEN)
    board.Data.Halfmoves[end] = 100
    legal = gameover!(board)
    @assert board.State == Draw()

    #WKing stalemated in corner
    slidingFEN = "K7/7r/8/8/8/8/8/1r4k1 w - 0 1"
    board = Boardstate(slidingFEN)
    legal = gameover!(board)
    @assert board.State == Draw() "White king not stalemated"

    #WKing checkmated by queen and 2 rooks, unless bishop blocks
    slidingFEN = "1R4B1/RK6/7r/8/8/8/8/r1r3kq w - 0 1"
    board = Boardstate(slidingFEN)
    legal = gameover!(board)
    @assert board.State == Neutral() "King moves backwards into check?"

    #Wking is checkmated as bishop cannot capture rook because pinned by queen
    slidingFEN = "K5Nr/8/8/3B4/8/8/r7/1r5q w - 0 1"
    board = Boardstate(slidingFEN)
    legal = gameover!(board)
    @assert board.State == Loss() "White bishop cannot block"
end
test_gameover()

function test_makemove()
    #Test making a move with only one piece on the board
    basicFEN = "K7/8/8/8/8/8/8/8 w - - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)

    @assert Scylla.ally_pieces(board)[1] == UInt64(1)

    for m in moves
        if to(m) == 1
            make_move!(m,board)
        end
    end

    @assert Whitesmove(board.Colour) == false
    @assert board.Data.Halfmoves[end] == UInt8(1)
    @assert Scylla.enemy_pieces(board)[1] == UInt64(2)

    #Test making a non-capture with three pieces on the board
    basicFEN = "Kn6/8/8/8/8/8/8/7k w - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)

    for m in moves
        if to(m) == 8
            make_move!(m,board)
        end
    end
    @assert sum(Scylla.ally_pieces(board)[2:end])  == UInt64(1) << 1
    @assert Scylla.enemy_pieces(board)[1] == UInt64(1) << 8
    @assert length(generate_moves(board)) == 6

    #Test a black move
    basicFEN = "1n6/K7/8/8/8/8/8/7k b - - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)
    @assert Whitesmove(board.Colour) == false
    @assert length(moves) == 6

    for m in moves
        if to(m) == 11
            make_move!(m,board)
        end
    end
    @assert sum(Scylla.enemy_pieces(board)[2:end]) == 1<<11
    GUI = GUIposition(board)
    @assert GUI[12] == 11

    #Test 3 pieces on the board
    basicFEN = "k7/8/8/8/8/8/8/NNN4K w - - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)
    @assert length(moves) == 12
    
    for m in moves
        if (from(m) == 56) & (to(m) == 41)
            make_move!(m,board)
        end
    end
    @assert Whitesmove(board.Colour) == false
    @assert sum(Scylla.ally_pieces(board)[2:end]) == 0

    GUI = GUIposition(board)
    @assert GUI[42] == 5
end
test_makemove()

function test_capture()
    #WKing captures BKnight
    basicFEN = "Kn6/8/8/8/8/8/8/7k w - - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)

    @assert sum(Scylla.enemy_pieces(board)) > 0

    for m in moves
        if cap_type(m) > 0
            make_move!(m,board)
        end
    end

    @assert sum(Scylla.ally_pieces(board)[2:end]) == 0
    @assert Scylla.enemy_pieces(board)[1] == UInt64(2)

    @assert length(generate_moves(board)) == 3

    GUI = GUIposition(board)
    @assert GUI[2] == 1
    @assert sum(GUI) == 8
end
test_capture()

function test_legal()
    knightFEN = "K7/8/1nnn4/8/N7/8/8/8 w - 0 1"
    board = Boardstate(knightFEN)

    moves = generate_moves(board)
    @assert length(moves) == 1 "Wknight must capture knight"
    @assert cap_type(moves[1]) > 0
    @assert pc_type(moves[1]) == Knight

    #WKing stalemated in corner
    slidingFEN = "K7/7r/8/8/8/8/8/1r4k1 w - 0 1"
    board = Boardstate(slidingFEN)
    moves = generate_moves(board)
    @assert length(moves) == 0 "White king not stalemated"

    #WKing checkmated by queen and 2 rooks, unless bishop blocks
    slidingFEN = "1R4B1/RK6/7r/8/8/8/8/r1r3kq w - 0 1"
    board = Boardstate(slidingFEN)
    moves = generate_moves(board)
    @assert length(moves) == 1 "King moves backwards into check?"
    @assert pc_type(moves[1]) == Bishop

    #Wking is checkmated as bishop cannot capture rook because pinned by queen
    slidingFEN = "K5Nr/8/8/3B4/8/8/r7/1r5q w - 0 1"
    board = Boardstate(slidingFEN)
    moves = generate_moves(board)
    @assert length(moves) == 0 "White bishop cannot block"

    #Only legal move is to block with rook
    slidingFEN = "K5Nr/8/8/3B4/7R/8/q7/1r5q w - 0 1"
    board = Boardstate(slidingFEN)
    moves = generate_moves(board)
    @assert length(moves) == 1 "White rook must block"
end
test_legal()

function test_identifyID()
    basicFEN = "1N7/8/8/8/8/8/8/8 w - - 0 1"
    board = Boardstate(basicFEN)
    ID = Scylla.identify_piecetype(Scylla.ally_pieces(board),1)
    @assert ID == 5

    ID = Scylla.identify_piecetype(Scylla.ally_pieces(board),2)
    @assert ID == 0
end
test_identifyID()

function test_unmake()
    #WKing captures BKnight then unmake
    basicFEN = "Kn6/8/8/8/8/8/8/7k w - - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)

    for m in moves
        if cap_type(m) > 0
            make_move!(m,board)
        end
    end
    unmake_move!(board)

    @assert Whitesmove(board.Colour) == true
    @assert Scylla.ally_pieces(board)[1] == UInt64(1)
    @assert Scylla.enemy_pieces(board)[5] == UInt64(2)

    moves = generate_moves(board)
    for m in moves
        if to(m) == 8
            make_move!(m,board)
        end
    end
    @assert Scylla.enemy_pieces(board)[1] == UInt(1) << 8
    moves = generate_moves(board)
    for m in moves
        if to(m) == 16
            make_move!(m,board)
        end
    end
    @assert Scylla.enemy_pieces(board)[5] == UInt(1) << 16
    moves = generate_moves(board)
    for m in moves
        if cap_type(m) == 5
            make_move!(m,board)
        end
    end
    @assert Scylla.ally_pieces(board)[5] == 0
    @assert length(board.Data.Halfmoves) == 2
    unmake_move!(board)
    unmake_move!(board)
    unmake_move!(board)

    @assert Whitesmove(board.Colour) == true
    @assert Scylla.ally_pieces(board)[1] == UInt64(1)
    @assert Scylla.enemy_pieces(board)[5] == UInt64(2)
    @assert length(board.Data.Halfmoves) == 1
end
test_unmake()

function test_repetition()
    basicFEN = "K7/8/8/8/8/8/8/7k w - - 0 1"
    board = Boardstate(basicFEN)

    for i in 1:8
        moves = generate_moves(board)
        for m in moves
            pos = -1
            if i%2==1
                pos = 0
            else
                pos = 63
            end
            if (from(m) == pos) | (to(m) == pos)
                make_move!(m,board)
                break
            end
        end
    end
    legal = gameover!(board)
    @assert board.State == Draw()
end
test_repetition()

function test_UCI()
    str1 = Scylla.UCIpos(0)
    str2 = Scylla.UCIpos(63)
    @assert (str1 == "a8") & (str2 == "h1")

    move = Move(UInt8(1),UInt8(2),UInt8(54),UInt8(0),UInt8(0))
    mvstr = UCImove(move)
    @assert mvstr == "c8g2"
end
test_UCI()

function test_longmv()
    move = Move(UInt8(1),UInt8(2),UInt8(54),UInt8(2),UInt8(0))
    mvstr = LONGmove(move)
    @assert mvstr == "Kc8xg2"
end
test_longmv()

"check all sliding attacks and quiets are generated correctly, not including checks"
function test_sliding()
    slidingFEN = "Q6r/8/2K5/8/8/8/8/b2k3 w - 0 1"
    board = Boardstate(slidingFEN)

    moves = generate_moves(board)
    @assert length(moves) == 23
    @assert count(i->(cap_type(i) > 0),moves) == 2

    for m in moves
        if cap_type(m) == Rook
            make_move!(m,board)
        end
    end
    newmoves = generate_moves(board)
    @assert length(newmoves) == 12
    @assert count(i->(cap_type(i) == Queen),newmoves) == 1
end
test_sliding()

function test_Zobrist()
    board = Boardstate(FEN)
    moves = generate_moves(board)
    for move in moves
       if (from(move) == 57) & (to(move) == 40)
        make_move!(move,board)
       end
    end

    newFEN = "rnbqkbnr/pppppppp/8/8/8/N7/PPPPPPPP/R1BQKBNR b KQkq - 1 1"
    newboard = Boardstate(newFEN)
    @assert board.ZHash == newboard.ZHash

    #should end up back at start position
    moves = generate_moves(board)
    for move in moves
       if (from(move) == 1) & (to(move) == 16)
        make_move!(move,board)
       end
    end
    moves = generate_moves(board)
    for move in moves
       if (from(move) == 40) & (to(move) == 57)
        make_move!(move,board)
       end
    end
    moves = generate_moves(board)
    for move in moves
       if (from(move) == 16) & (to(move) == 1)
        make_move!(move,board)
       end
    end
    @assert board.ZHash == board.Data.ZHashHist[1] "Zhash should be identical to start pos"

    unmake_move!(board)
    unmake_move!(board)
    unmake_move!(board)
    @assert board.ZHash == newboard.ZHash "should be able to recover Zhash after unmaking move"
end
test_Zobrist()

function Testing_perft(board::Boardstate,depth)
    #could also test incremental Zhash updates here
    legal = gameover!(board)
    moves = generate_moves(board,legal)

    if board.State == Neutral()
        @assert length(moves) > 0 "Missed gameover state"
    else
        @assert length(moves) == 0 "Incorrectly identified gameover state"
    end
    
    attacks = generate_attacks(board)
    num_attacks = count(m->cap_type(m)>0,moves)
    @assert length(attacks) == num_attacks "Wrong number of attacks generated. Should be $(num_attacks), got $(length(attacks))."

    if depth > 1
        for move in moves
            make_move!(move,board)
            static_eval = zeros(Int32,2)
            Scylla.set_PST!(static_eval,board.pieces)
            @assert board.PSTscore == static_eval "Score doesn't match. Dynamic = $(board.PSTscore), static = $(static_eval). Found on move $(show(move))"
            Testing_perft(board,depth-1)
            unmake_move!(board)
        end
    end
end

function test_with_perft()
    #Test that PST values from incremental upadate are not different from static evaluation
    #Also that number of attacks from generate_attacks is the same as from generate_moves(all)
    #Also that we can identify terminal nodes without running movegen

    FEN = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
    board = Boardstate(FEN)
    Testing_perft(board,4)

    FEN = "n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - 0 1"
    board = Boardstate(FEN)
    Testing_perft(board,5)

    FEN = "RPrk/PP6/8/8/8/8/r7/7K b - - 0 26"
    board = Boardstate(FEN)
    Testing_perft(board,5)
end

function test_PSTeval()
    FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    board = Boardstate(FEN)

    @assert board.PSTscore == [0,0] "Start pos should be neutral"

    FEN = "8/P6k/K7/8/8/8/8/8 w - - 0 1"
    board = Boardstate(FEN)
    
    @assert board.PSTscore[1] >= 100 "Position is worth at least 100 centipawns to white in midgame"
    @assert board.PSTscore[2] >= 100 "Position is worth at least 100 centipawns to white in endgame"
end
test_PSTeval()

function test_perft()
    basicFEN = "K7/8/8/8/8/8/8/7k w - - 0 1"
    board = Boardstate(basicFEN)

    leaves = perft(board,2)
    @assert leaves == 9
end
test_perft()

function test_TT()
    TT = TranspositionTable(4,PerftData)
    for Data in TT.HashTable
        @assert Data.ZHash == 0
        @assert Data.depth == 0
        @assert Data.leaves == 0
    end    

    Z1 = UInt64(2^61+2^62+2^10) 
    Z2 = UInt64(2^61+2^62+2^11) 

    new_data = PerftData(Z1,UInt8(5),UInt128(1))

    set_entry!(TT,new_data)
    TT_entry1 = get_entry(TT,Z1)
    TT_entry2 = get_entry(TT,Z2)

    @assert TT_entry1 == new_data "retrieve data"
    @assert TT_entry1 == TT_entry2 "access same TT entry"
    @assert TT_entry2.ZHash == Z1 "Zkey matches"
    @assert TT_entry2.ZHash != Z2 "key collision"
end
test_TT()

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
        board = Boardstate(FEN)
        if verbose
            println("Testing position: $FEN")
        end
        t = time()
        TT = TranspositionTable(TT_size,PerftData)
        cur_leaves = perft(board,depth,TT,verbose)
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

function benchmarkspeed(leafcount)
    FEN = "nnnnknnn/8/8/8/8/8/8/NNNNKNNN w - 0 1"
    board = Boardstate(FEN)
    depth = 5

    trial = @benchmark perft($board,$depth)
    minimum_time = minimum(trial).time * 1e-9

    println("Benchmarked nps = $(leafcount/minimum_time)")
end

if expensive
    @time test_with_perft()
    leaves,Δt = test_speed()
    println("Leaves: $leaves. NPS = $(leaves/Δt) nodes/second")

    #benchmarkspeed(leaves)
    #best = 6.9e7 nps
end

function test_TT_perft()
    #best speed = 180 Mnps
    board = Boardstate(FEN)
    TT = TranspositionTable(24,PerftData,true)
    t = time()
    @assert perft(board,7,TT,true) == 3195901860
    δt = time()-t
    println("Successfully determined perft 7 in $(round(δt,sigdigits=4))s. $(round(3195901860/(δt*1e6),sigdigits=6)) Mnps")
end
test_TT_perft()

println("All tests passed")
