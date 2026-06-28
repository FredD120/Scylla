using Scylla
using Test

@testset "Triangular Table" begin
    @testset "Perfect PV" begin
        info = Scylla.SearchInfo(4)
        move = Move(1)
        
        for ply in 2:-1:0
            Scylla.copy_pv!(info, ply, move)
        end

        @test info.pv_len[1] == 3
        @test info.pv_len[2] == 2
        @test info.pv_len[3] == 1
        @test info.pv_len[4] == 0
        @test all(map(m -> m == move, info.pv[1:3]))
    end

    @testset "Cut PV" begin
        info = Scylla.SearchInfo(4)
        move = Move(1)
        
        for ply in 2:-2:0
            Scylla.copy_pv!(info, ply, move)
        end

        @test info.pv_len[1] == 1
        @test info.pv_len[2] == 0
        @test info.pv_len[3] == 1
        @test info.pv_len[4] == 0
        @test all(info.pv[1] == move)
    end
end

@testset "MVV-LVA Scoring" begin
    eFEN = "7k/8/8/8/8/8/Q1r5/1K6 b - - 0 1"
    board = Scylla.BoardState(eFEN)
    moves, move_count = Scylla.generate_legal_moves(board)

    Scylla.score_moves!(moves)
    max_score = maximum(m -> Scylla.score(m), moves)
    min_score = minimum(m -> Scylla.score(m), moves)
    
    for move in moves
        if Scylla.is_piecetype(Scylla.cap_type(move), Scylla.QUEEN)    
            @test Scylla.score(move) == max_score
            @test Scylla.score(move) > 0
        elseif Scylla.is_piecetype(Scylla.cap_type(move), Scylla.NULL_PIECE) 
            @test Scylla.score(move) == min_score
            @test Scylla.score(move) == 0
        end
    end
end

@testset "Incremental Ordering" begin
    moves = [Scylla.NULLMOVE for _ in 1:3]

    for i in eachindex(moves)
        moves[i] = Scylla.set_score(moves[i], UInt8(i))
    end

    for i in eachindex(moves)
        Scylla.swap_next_move!(moves,i)
        @test Scylla.score(moves[i]) == 4-i
    end
end

@testset "Update Killers" begin 
    killer_vec = [Scylla.Killer() for _ in 1:3]
    ply = 1

    for i in 1:10
        move = Move(i)
        Scylla.new_killer!(killer_vec, ply, move)
    end
    @test killer_vec[ply+1].first == Move(10) 
    @test killer_vec[ply+1].second == Move(9) 

    Scylla.new_killer!(killer_vec, ply, Move(10))
    @test killer_vec[ply+1].first != killer_vec[ply+1].second
end

@testset "Possible Quiet Move" begin
    test_FEN = "r3k2r/p1P1bp1p/n4np1/qp1p1b2/2BB4/5N2/P1PPQPPP/RN2K2R b kq - 0 12"
    board = BoardState(test_FEN)
    moves, len = generate_pseudolegal_moves(board)

    for m in moves
        if !Scylla.is_capture(m)
            @test Scylla.is_quiet_move_possible(m, board)

            if !Scylla.is_quiet_move_possible(m, board)
                println(Scylla.long_move(m))
            end
        end
    end
end

@testset "Impossible Quiet Move" begin
    blocked_board = BoardState("r2qk1nr/pp2pppp/8/n5b1/P7/1Bp1P3/1PP2PPP/RNQ1K1NR w KQkq - 0 1")
    unblocked_board = BoardState("r2qk1nr/pp2pppp/8/8/8/8/1PP2PPP/RNQNK2R w KQkq - 0 1")

    blocked_moves, _ = generate_pseudolegal_moves(blocked_board)
    unblocked_moves, _ = generate_pseudolegal_moves(unblocked_board)

    possible_moves = Move[]
    impossible_moves = Move[]
    for move in unblocked_moves
        if !Scylla.is_capture(move)
            if any(map(b -> move == b, blocked_moves))
                push!(possible_moves, move)
            else
                push!(impossible_moves, move)
            end
        end
    end

    for m in possible_moves
        @test Scylla.is_quiet_move_possible(m, blocked_board)
    end
    for m in impossible_moves
        @test !Scylla.is_quiet_move_possible(m, blocked_board)
    end
end

@testset "Possible Colour Swapped Move" begin
    white_board = BoardState("4k3/6P1/3N4/8/1P6/3rR3/2B2P2/4K3 w - - 1 1")
    black_board = BoardState("4K3/6p1/3n4/8/1p6/3Rr3/2b2p2/4k3 w - - 1 1")

    white_moves, _ = generate_pseudolegal_moves(white_board)

    for move in white_moves
         if !Scylla.is_capture(move)
            @test !Scylla.is_quiet_move_possible(move, black_board)
        end
    end
end