using Test
using Scylla

@testset "Initialise and Quit" begin
    cli_state = Scylla.CLI_state()
    wrapper = Scylla.EngineWrapper(EngineState("K7/8/8/8/8/8/8/7k w - - 0 1", sizeMb=0))
    engine = wrapper.engine

    Scylla.parse_msg!(wrapper, cli_state, "  ucinewgame  ")
    @test engine.board.pieces == BoardState(Scylla.startFEN).pieces

    Scylla.parse_msg!(wrapper, cli_state, "qqq QUIT")
    @test cli_state.QUIT == true

    Scylla.parse_msg!(wrapper, cli_state, "Debug on")
    @test wrapper.debug == true

    Scylla.parse_msg!(wrapper, cli_state, "Debug off")
    @test wrapper.debug == false

    @test cli_state.TT_SET == false
    msg = Scylla.parse_msg!(wrapper, cli_state, "isready")
    @test msg == "readyok"
    @test cli_state.TT_SET == true
end

@testset "Set TranspositionTable" begin
    cli_state = Scylla.CLI_state()
    wrapper = Scylla.EngineWrapper(EngineState(sizeMb=0))

    Scylla.parse_msg!(wrapper, cli_state, "setoption name hash value 32")
    @test Scylla.TT_size(wrapper.engine.TT) < 32
    @test Scylla.TT_size(wrapper.engine.TT) > 16

    Scylla.parse_msg!(wrapper, cli_state, "setoption name hash value 1")
    wrapper.engine.TT.HashTable[1].Always = Scylla.SearchData(BitBoard(),UInt8(1),Int16(0),Scylla.NONE,Scylla.NULLMOVE)
    @test wrapper.engine.TT.HashTable[1].Always.depth == UInt8(1)
    Scylla.parse_msg!(wrapper, cli_state, "setoption name clear hash")
    @test wrapper.engine.TT.HashTable[1].Always.depth == UInt8(0)
end

@testset "Set board position" begin
    cli_state = Scylla.CLI_state()
    wrapper = Scylla.EngineWrapper(EngineState(sizeMb=0))
    engine = wrapper.engine
    newFEN = "Kn6/8/8/8/8/8/8/7k w - - 0 1"

    Scylla.parse_msg!(wrapper, cli_state, "position fen " * newFEN * "Moves")
    @test engine.board.zobrist_hash == BoardState(newFEN).zobrist_hash
    Scylla.parse_msg!(wrapper, cli_state, "position STARTPOS")
    @test engine.board.zobrist_hash == BoardState(FEN).zobrist_hash

    Scylla.parse_msg!(wrapper, cli_state, "position STARTPOS Moves c2c4 a7a6")
    moveFEN = "rnbqkbnr/1ppppppp/p7/8/2P5/8/PP1PPPPP/RNBQKBNR w KQkq - 0 2"
    @test engine.board.zobrist_hash == BoardState(moveFEN).zobrist_hash

    castleFEN = "rnbqk2r/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 0"
    Scylla.parse_msg!(wrapper, cli_state, "position fen $castleFEN Moves e8g8")
    afterFEN = "rnbq1rk1/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQ - 0 1"
    @test engine.board.zobrist_hash == BoardState(afterFEN).zobrist_hash
end

@testset "Time Controls" begin
    msg_array = ["WTIME", "10000", "BTIME", "20000", "WINC", "1000", "BINC", "1000"]
    engine = EngineState(sizeMb=0)

    time, increment = Scylla.get_time_control(engine, msg_array)
    @test time == 10.0
    @test increment == 1.0
    
    searchtime = estimate_movetime(engine, time, increment)
    @test searchtime > increment
    @test searchtime < time + increment
end