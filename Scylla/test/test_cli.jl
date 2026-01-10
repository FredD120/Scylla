using Test
using Scylla

@testset "Initialise and Quit" begin
    cli_state = Scylla.CLI_state()
    engine = EngineState("K7/8/8/8/8/8/8/7k w - - 0 1",sizeMb=0)

    Scylla.parse_msg!(engine, cli_state, "  ucinewgame  ")
    @test engine.board.pieces == Boardstate(Scylla.startFEN).pieces

    Scylla.parse_msg!(engine, cli_state, "qqq QUIT")
    @test cli_state.QUIT == true

    Scylla.parse_msg!(engine, cli_state, "Debug on")
    @test engine.config.debug == true

    Scylla.parse_msg!(engine, cli_state, "Debug off")
    @test engine.config.debug == false

    @test cli_state.TT_SET == false
    msg = Scylla.parse_msg!(engine, cli_state, "isready")
    @test msg == "readyok"
    @test cli_state.TT_SET == true
end

@testset "Set TranspositionTable" begin
    cli_state = Scylla.CLI_state()
    engine = EngineState(sizeMb=0)

    Scylla.parse_msg!(engine, cli_state, "setoption name hash value 32")
    @test Scylla.TT_size(engine.TT) < 32
    @test Scylla.TT_size(engine.TT) > 16

    Scylla.parse_msg!(engine, cli_state, "setoption name hash value 1")
    engine.TT.HashTable[1].Always = Scylla.SearchData(BitBoard(),UInt8(1),Int16(0),Scylla.NONE,Scylla.NULLMOVE)
    @test engine.TT.HashTable[1].Always.depth == UInt8(1)
    Scylla.parse_msg!(engine, cli_state, "setoption name clear hash")
    @test engine.TT.HashTable[1].Always.depth == UInt8(0)
end

@testset "Set board position" begin
    cli_state = Scylla.CLI_state()
    engine = EngineState(sizeMb=0)
    newFEN = "Kn6/8/8/8/8/8/8/7k w - - 0 1"

    Scylla.parse_msg!(engine, cli_state, "position " * newFEN * "Moves")
    @test engine.board.ZHash == Boardstate(newFEN).ZHash
    Scylla.parse_msg!(engine, cli_state, "position STARTPOS")
    @test engine.board.ZHash == Boardstate(FEN).ZHash
end