using Scylla
using Test

@testset "Create and Access" begin
    
    @testset "Unit" begin
        TT = Scylla.TranspositionTable(verbose, type=Scylla.SearchData)
        sz = Scylla.tt_size(TT)
        @test sz <= Scylla.TT_DEFAULT_MB
        @test sz > Scylla.TT_DEFAULT_MB / 2

        size = 16
        TT = Scylla.TranspositionTable(Scylla.SearchData, size, verbose)
        @test length(TT.hash_table) == 2 ^ size
    end

    @testset "Use TT" begin
        TT = Scylla.TranspositionTable(Scylla.PerftData, 4, verbose)
        @testset "Initialise" begin
            for Data in TT.hash_table
                @test Data.zobrist_hash == 0
                @test Data.depth == 0
                @test Data.leaves == 0
            end    
        end

        @testset "Two Similar Hashes" begin
            Z1 = BitBoard(2^61 + 2^62 + 2^10) 
            Z2 = BitBoard(2^61 + 2^62 + 2^11) 

            new_data = Scylla.PerftData(Z1, UInt8(5), UInt128(1))

            Scylla.set_entry!(TT, new_data)
            TT_entry1 = Scylla.get_entry(TT,Z1)
            TT_entry2 = Scylla.get_entry(TT,Z2)

            @test TT_entry1 == new_data 
            @test TT_entry1 == TT_entry2 
            @test TT_entry2.zobrist_hash == Z1
            @test TT_entry2.zobrist_hash != Z2 
        end
    end
end

@testset "SearchData" begin
    board = BoardState()
    moves, _ = generate_legal_moves(board)

    zobrist = board.zobrist_hash
    depth = UInt8(1)
    score = Int16(100)
    type = Scylla.ALPHA
    move = Scylla.strip_move(moves[1])

    d = Scylla.SearchData(zobrist, depth, score, type, move)

    @test Scylla.get_zobrist(d) == zobrist
    @test Scylla.get_depth(d) == depth
    @test Scylla.get_score(d) == score
    @test Scylla.get_type(d) == type
    @test Scylla.get_age(d) == UInt8(0)
    @test Scylla.get_move(d) == move

    new = Scylla.increment_age(d)
    @test Scylla.get_age(new) == UInt8(1)
end