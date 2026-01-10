using Scylla
using Test

@testset "Create and Access" begin
    
    @testset "Unit" begin
        TT = Scylla.TranspositionTable(verbose, type=Scylla.SearchData)
        sz = Scylla.TT_size(TT)
        @test sz <= Scylla.TT_DEFAULT_MB
        @test sz > Scylla.TT_DEFAULT_MB / 2

        size = 16
        TT = Scylla.TranspositionTable(verbose, type=Scylla.SearchData, size=size)
        @test length(TT.HashTable) == 2 ^ size
    end

    @testset "Use TT" begin
        TT = Scylla.TranspositionTable(verbose, size=4, type=Scylla.PerftData)
        @testset "Initialise" begin
            for Data in TT.HashTable
                @test Data.ZHash == 0
                @test Data.depth == 0
                @test Data.leaves == 0
            end    
        end

        @testset "Two Similar Hashes" begin
            Z1 = BitBoard(2^61+2^62+2^10) 
            Z2 = BitBoard(2^61+2^62+2^11) 

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
end
