const NAME = "Scylla"

mutable struct CLI_state
    QUIT::Bool
    TT_SET::Bool
    DEBUG::Bool
end

CLI_state() = CLI_state(false,false,false)

"can modify either the engine state or the CLI state"
function parse_msg!(engine,cli_state,msg)
    msg_in = split(uppercase(msg))
    if "QUIT" in msg_in
        cli_state.QUIT = true

    elseif "UCINEWGAME" in msg_in
        reset_engine!(engine)

    elseif "UCI" in msg_in
        println("id name "*NAME*"\n")
        println("id author FD\n")
        #needs to be parameterised for different options and Hash sizes in MB
        println("option name Hash type spin default $TT_DEFAULT_MB min $TT_MIN_MB max $TT_MAX_MB\n")
        println("option name Clear Hash type button\n")
        println("uciok\n")   

    elseif "ISREADY" in msg_in
        if !cli_state.TT_SET
            engine.TT = set_TT()
            cli_state.TT_SET = true
        end
        println("readyok\n")
    
    elseif "SETOPTION" in msg_in
        ind = findfirst(x->x=="NAME",msg_in)
        if !isnothing(ind) && length(msg_in) > ind
            set_option!(engine,cli_state,msg_in[ind+1:end])
        end

    elseif "DEBUG" in msg_in
        ind = findfirst(x->x=="DEBUG",msg_in)
        if !isnothing(ind) && length(msg_in) > ind
            if msg_in[ind+1] == "ON"
                cli_state.DEBUG = true
            elseif msg_in[ind+1] == "OFF"
                cli_state.DEBUG = false
            end
        end
    elseif cli_state.DEBUG
        println("info command not recognised")
    end
end

function run_cli()
    cli_state = CLI_state()
    engine = EngineState(sizeMb=0)

    while !cli_state.QUIT
        parse_msg!(engine,cli_state,readline())
    end
end

function set_hash!(engine::EngineState,msg_vec)
    val = tryparse(Int64,msg_vec[1])
    engine.TT = set_TT(sizeMb=val)
end

function set_option!(engine::EngineState,cli_state,msg_vec)
    if msg_vec[1] == "CLEAR" && msg_vec[2] == "HASH"
        reset_TT!(engine)

    elseif msg_vec[1] == "HASH"
        ind = findfirst(x->x=="VALUE",msg_vec)
        if !isnothing(ind) && length(msg_vec) > ind
            set_hash!(engine,msg_vec[ind+1:end])
        end

    elseif cli_state.DEBUG
        println("info option not recognised")
    end
end

function test_args()
    s = ArgParseSettings(description="Run chess engine tests with optional extra tests.")

    @add_arg_table! s begin
        "--perft_extra", "-p"
            help = "Run more expensive perft tests to validate move generation and incremental updates"
            action = :store_true

        "--verbose", "-v"
            help = "Verbose output"
            action = :store_true

        "--TT_perft", "-t"
            help = "Run perft from start position with bulk counting and hash table"
            action = :store_true
            
        "--engine", "-e"
            help = "Run expensive engine tests from difficult test suite"
            action = :store_true

        "--profile", "-f"
            help = "Profile engine on a slow position"
            action = :store_true 
            
        "--maxtime", "-m"
            help = "Maximum time the engine will spend on a move during testing" 
            arg_type = Float64
            default = 0.5
    end
    return parse_args(s)
end