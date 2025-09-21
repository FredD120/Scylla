const NAME = "Scylla"

mutable struct CLI_state
    QUIT::Bool
    TT_SET::Bool
    listen::Channel
    worker::Union{Task,Nothing}
    chnnlOUT::Union{Channel,Nothing}
end
CLI_state() = CLI_state(false,false,Channel{String}(1),nothing,nothing)

"reset worker thread and associated channels"
function reset_worker!(st::CLI_state)
    st.worker = nothing
    st.chnnlOUT = nothing
end

"task to run best_move and put outputs in channel"
function run_engine(E::EngineState,ch_out::Channel)
    best, logger = best_move(E)
    put!(ch_out,(best,logger))
end

"task to continually listen for input and put into listen channel"
function listen(st::CLI_state)
    for input in eachline()
        put!(st.listen, input)
    end
end

"parse OPTION command from CLI, dispatch on requests"
function set_option!(engine::EngineState,cli_state,msg_vec)
    if msg_vec[1] == "CLEAR" && msg_vec[2] == "HASH"
        reset_TT!(engine)

    elseif msg_vec[1] == "HASH"
        ind = findfirst(x->x=="VALUE",msg_vec)
        if !isnothing(ind) && length(msg_vec) > ind
            assign_TT!(engine,sizeMb=tryparse(Int64,msg_vec[ind+1]))
            cli_state.TT_SET = true
        end

    elseif engine.config.debug
        println("info option not recognised")
    end
end

"can modify either the engine state or the CLI state and launch new worker threads"
function parse_msg!(engine,cli_st,msg)
    msg_in = split(uppercase(msg))
    if "QUIT" in msg_in
        cli_st.QUIT = true

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
        if !cli_st.TT_SET
            #assign default TT if not previously set
            engine.TT = TranspositionTable(engine.config.debug)
            cli_st.TT_SET = true
        end
        println("readyok\n")
    
    elseif "SETOPTION" in msg_in
        ind = findfirst(x->x=="NAME",msg_in)
        if !isnothing(ind) && length(msg_in) > ind
            set_option!(engine,cli_st,msg_in[ind+1:end])
        end

    elseif "DEBUG" in msg_in
        ind = findfirst(x->x=="DEBUG",msg_in)
        if !isnothing(ind) && length(msg_in) > ind
            if msg_in[ind+1] == "ON"
                engine.config.debug = true
            elseif msg_in[ind+1] == "OFF"
                engine.config.debug = false
            end
        end

    elseif "GO" in msg_in
        cli_st.chnnlOUT = Channel{Tuple{UInt32,Logger}}(1)
        cli_st.worker = Threads.@spawn run_engine(engine,cli_st.chnnlOUT)

    elseif "STOP" in msg_in && !isnothing(cli_st.worker)
        put!(engine.config.forcequit,FORCEQUIT())

    elseif engine.config.debug
        println("info command not recognised")
    end
end

"entry point for CLI, uses UCI protocol"
function run_cli()
    cli_state = CLI_state()
    listener = Threads.@spawn listen(cli_state)
    engine = EngineState(
        comms=Channel{FORCEQUIT}(1),control=Time(10),sizeMb=0)

    while !cli_state.QUIT
        if isready(cli_state.listen)
            parse_msg!(engine,cli_state,take!(cli_state.listen))
        end
        if !isnothing(cli_state.worker) && isready(cli_state.chnnlOUT)
            output = take!(cli_state.chnnlOUT)
            print_log(output[2])
            reset_worker!(cli_state)
        end
        sleep(0.05)
    end
    reset_worker!(cli_state)
    listener = nothing
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