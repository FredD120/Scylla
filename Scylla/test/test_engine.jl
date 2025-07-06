using Scylla
using Test

const profil = false
const MAXTIME = 0.5
const expensive = false

function test_eval()
    FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    board = Boardstate(FEN)
    ev = evaluate(board)

    @assert ev == 0 "Start pos should be neutral"

    FEN = "8/P6k/K7/8/8/8/8/8 w - - 0 1"
    board = Boardstate(FEN)
    ev = evaluate(board)

    @assert ev >= 100 "Position is worth at least 100 centipawns to white"
end
test_eval()

function test_weighting()
    FEN = "4k3/ppppppp1/8/8/8/8/PPP5/R3K3 w Qkq - 0 1"
    board = Boardstate(FEN)
    num_pcs = count_pieces(board.pieces)

    @assert MGweighting(num_pcs) > EGweighting(num_pcs) "At 13 pieces, weighted towards midgame"

    num_pcs = 10
    @assert MGweighting(num_pcs) < EGweighting(num_pcs) "At 10 pieces, weighted towards endgame"
end
test_weighting()

function test_triangular()
    PVtable = zeros(triangle_number(MAXDEPTH))
    PV_len = MAXDEPTH
    new_move = 1
    tri_count = 0

    for ply in MAXDEPTH-1:-1:0
        tri_count += 1
        copy_PV!(PVtable,ply,PV_len,MAXDEPTH,new_move)
        @assert sum(PVtable) == triangle_number(tri_count)
    end
end
test_triangular()

function test_MVVLVA()
    FEN = "8/8/8/8/8/8/q1r5/1K6 w - - 0 1"
    board = Boardstate(FEN)
    moves = generate_moves(board)

    score_moves!(moves,Killer())
    
    for move in moves
        if cap_type(move) == Queen
            @assert score(move) == maximum(scores)
            @assert score(move) > MINCAPSCORE
        elseif cap_type(move) == logic.NULL_PIECE
            @assert score(move) == minimum(scores)
            @assert score(move) < MINCAPSCORE
        end
    end
end
test_MVVLVA()

function test_positional()
    FEN = "1n2k1n1/8/8/8/8/8/8/4K3 b KQkq - 0 1"
    board = Boardstate(FEN)
    ev1 = -evaluate(board)

    FEN = "4k3/8/8/3n4/8/4n3/8/4K3 b KQkq - 0 1"
    board = Boardstate(FEN)
    ev2 = -evaluate(board)

    @assert ev2 > ev1 "Knights encouraged to be central"

    FEN = "4k3/pppppppp/8/8/PP4PP/8/2PPPP2/4K3 w KQkq - 0 1"
    board = Boardstate(FEN)
    ev1 = evaluate(board)

    FEN = "4k3/pppppppp/8/8/2PPPP2/8/PP4PP/4K3 w KQkq - 0 1"
    board = Boardstate(FEN)
    ev2 = evaluate(board)

    @assert ev2 > ev1 "Push central pawns first"

    FEN = "4k3/pppppppp/8/8/8/8/PPPPPPPP/R3K3 w Qkq - 0 1"
    board = Boardstate(FEN)
    ev1 = evaluate(board)

    FEN = "4k3/pppppppp/8/8/8/8/PPPPPPPP/2KR4 w KQkq - 0 1"
    board = Boardstate(FEN)
    ev2 = evaluate(board)

    @assert ev2 > ev1 "Castling is positionally favourable"
end
test_positional()

function test_ordering()
    moves = [NULLMOVE,NULLMOVE,NULLMOVE]

    for i in eachindex(moves)
        moves[i] = set_score(moves[i],UInt8(i))
    end

    for i in eachindex(moves)
        next_best!(moves,i)
        @assert score(moves[i]) == 4-i
    end
end
test_ordering()

function test_killer_score()
    killer_vec = [Killer() for _ in 1:3]
    ply = 2

    killer_vec[ply+1] = Killer(UInt32(1),UInt32(2))
    moves = [UInt32(3),UInt32(5),UInt32(2)]

    score_moves!(moves,killer_vec[ply+1])
    @assert score(moves[3]) > score(moves[2]) "Move in killer table should be ranked highest"
    @assert score(moves[3]) > score(moves[1]) "Move in killer table should be ranked highest"
end
test_killer_score()

function test_update_killer()
    killer_vec = [Killer() for _ in 1:3]
    ply = 1

    for move in UInt32(1):UInt32(10)
        new_killer!(killer_vec,ply,move)
    end
    @assert killer_vec[ply+1].First == UInt32(10) 
    @assert killer_vec[ply+1].Second == UInt32(9) 

    new_killer!(killer_vec,ply,UInt32(10))
    @assert killer_vec[ply+1].First != killer_vec[ply+1].Second "Can't have same move twice in killer table at same ply"
end
test_update_killer()

function test_best()
    FEN = "K6Q/8/8/8/8/8/8/b6k b - - 0 1"
    board = Boardstate(FEN)
    best,log = best_move(board,MAXTIME)

    @assert LONGmove(best) == "Ba1xh8" "Bishop should capture queen as black"

    FEN = "k6q/8/8/8/8/8/8/B6K w - - 0 1"
    board = Boardstate(FEN)
    best,log = best_move(board,MAXTIME)

    @assert LONGmove(best) == "Ba1xh8" "Bishop should capture queen as white"

    FEN = "k7/8/8/8/8/8/5K2/7q b - - 0 1"
    board = Boardstate(FEN)
    best,log = best_move(board,MAXTIME)

    @assert LONGmove(best) == "Qh1-e4" "Queen should not allow itself to be captured"
end
test_best()

function test_mate()
    #mate in 2
    for FEN in ["K7/R7/R7/8/8/8/8/7k w - - 0 1","k7/r7/r7/8/8/8/8/7K b - - 0 1"]
        board = Boardstate(FEN)
        best,log = best_move(board,MAXTIME)
        #rook moves to cut off king
        make_move!(best,board)
        moves = generate_moves(board)
        #king response doesn't matter
        make_move!(moves[1],board)
        best,log = best_move(board,MAXTIME)
        make_move!(best,board)
        gameover!(board)
        
        @assert board.State == Loss() "Checkmate in 2 moves"
    end
end
test_mate()

function profile()
    positions = readlines("$(dirname(@__DIR__))/test/test_positions.txt")

    #slow position
    FEN = split(split(positions[12],";")[1],"- bm")[1]*"0"
    board = Boardstate(FEN)

    best,log = best_move(board,MAXTIME)

    @profile best_move(board,MAXTIME*10)
    Profile.print()
end
if profil 
    profile()
end

function test_positions()
    count_correct = 0
    positions = readlines("$(dirname(@__DIR__))/test/test_positions.txt")

    for pos in positions
        FEN_move = split(split(pos,";")[1],"- bm ")
        FEN = FEN_move[1]*"0"
        board = Boardstate(FEN)
        correct_mv = FEN_move[2]

        println("Testing FEN: $FEN")
        best,log = best_move(board,2.0)

        if SHORTmove(best) == correct_mv
            count_correct += 1
        else
            println("Failed to find best move. Move found = $(SHORTmove(best)), best move = $correct_mv")
        end
    end
    println("Total Correct: $count_correct/111")
end

if expensive
    test_positions()
end

println("All tests passed")

