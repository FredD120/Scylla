using Scylla
using Test
using Profile
using BenchmarkTools
using ArgParse

@testset "Chess Engine Tests" begin

    @testset "Logic Tests" begin
        include(test_logic.jl)
    end

    @testset "Engine Tests" begin
        include(test_engine.jl)
    end

end