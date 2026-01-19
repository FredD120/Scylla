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
function run_engine(E::EngineState, ch_out::Channel)
    best, logger = best_move(E)
    put!(ch_out, (best,logger))
end

"task to continually listen for input and put into listen channel"
function listen(st::CLI_state)
    for input in eachline()
        put!(st.listen, input)
    end
end

"parse OPTION command from CLI, dispatch on requests"
function set_option!(engine::EngineState, cli_state, msg_vec)::Union{Nothing, String}
    if msg_vec[1] == "CLEAR" && msg_vec[2] == "HASH"
        reset_TT!(engine)

    elseif msg_vec[1] == "HASH"
        ind = findfirst(x->x=="VALUE", msg_vec)
        if !isnothing(ind) && length(msg_vec) > ind
            assign_TT!(engine, sizeMb=tryparse(Int64, msg_vec[ind+1]))
            cli_state.TT_SET = true
        end

    elseif engine.config.debug
        return "info option not recognised"
    end
    return nothing
end

"set board position from a FEN string plus moves"
function set_position!(engine, position_moves)
    ind = get_msg_index(uppercase.(position_moves), "MOVES")
    if uppercase(position_moves[1]) == "STARTPOS"
        engine.board = Boardstate(startFEN)
    else
        last_ind = length(position_moves)
        if !isnothing(ind)
            last_ind = ind
        end
        FEN_string = join(position_moves[1:last_ind], " ")
        engine.board = Boardstate(FEN_string)
    end
    #play moves if provided
    if !isnothing(ind)
        for move_str in position_moves[ind + 1:end]
            move = identify_UCImove(engine.board, move_str)
            make_move!(move, engine.board)
        end
    end
end

"send quit message to engine if there is a channel to do so"
send_quit_msg!(channel::Channel) = put!(channel, FORCEQUIT())
send_quit_msg!(::Nothing) = nothing

"find relevant string within message to look for variables on the right"
get_msg_index(msg_array, substr) = findfirst(x->x==substr, msg_array)

"can modify either the engine state or the CLI state and launch new worker threads"
function parse_msg!(engine, cli_st, msg)::Union{Nothing, String}
    msg_in = split(uppercase(msg))
    if "QUIT" in msg_in
        send_quit_msg!(engine.config.forcequit)
        cli_st.QUIT = true

    elseif "UCINEWGAME" in msg_in
        reset_engine!(engine)

    elseif "UCI" in msg_in
        return string("id name ", NAME, "\n",
        "pid author FD\n",
        "option name Hash type spin default $TT_DEFAULT_MB min $TT_MIN_MB max $TT_MAX_MB\n",
        "option name Clear Hash type button\n",
        "uciok")

    elseif "ISREADY" in msg_in
        if !cli_st.TT_SET
            #assign default TT if not previously set
            engine.TT = TranspositionTable(engine.config.debug)
            cli_st.TT_SET = true
        end
        return "readyok"
    
    elseif "SETOPTION" in msg_in
        ind = get_msg_index(msg_in, "NAME")
        if !isnothing(ind) && length(msg_in) > ind
            return set_option!(engine, cli_st, msg_in[ind+1:end])
        end

    elseif "DEBUG" in msg_in
        ind = get_msg_index(msg_in, "DEBUG")
        if !isnothing(ind) && length(msg_in) > ind
            if msg_in[ind+1] == "ON"
                engine.config.debug = true
                return "info debug on"
            elseif msg_in[ind+1] == "OFF"
                engine.config.debug = false
            end
        end

    elseif "GO" in msg_in
        ind = get_msg_index(msg_in, "GO")
        if !isnothing(ind) && length(msg_in) > ind + 1
            if msg_in[ind+1] == "MOVETIME" && (engine.config.control isa Time)
                newtime = parse(Float64, msg_in[ind+2])
                engine.config.control = Time(newtime, engine.config.control.maxdepth)
            end
        end
        
        cli_st.chnnlOUT = Channel{Tuple{UInt32,Logger}}(1)
        cli_st.worker = Threads.@spawn run_engine(engine, cli_st.chnnlOUT)

        if engine.config.debug
            return "info calculating best move"
        end

    elseif "POSITION" in msg_in
        ind = get_msg_index(msg_in, "POSITION")
        if !isnothing(ind) && length(msg_in) > ind
            set_position!(engine, split(msg)[ind+1:end])
        end

    elseif "STOP" in msg_in && !isnothing(cli_st.worker)
        send_quit_msg!(engine.config.forcequit)

    elseif engine.config.debug
        return "info command not recognised"
    end
    return nothing
end

"entry point for CLI, uses UCI protocol"
function run_cli()
    cli_state = CLI_state()
    listener = Threads.@spawn listen(cli_state)
    engine = EngineState(
        comms = Channel{FORCEQUIT}(1), control = Time(5), sizeMb = 0)

    while !cli_state.QUIT
        if isready(cli_state.listen)
            msg = parse_msg!(engine, cli_state, take!(cli_state.listen))
            if msg isa String
                println(msg)
            end
        end
        if !isnothing(cli_state.worker) && isready(cli_state.chnnlOUT)
            output = take!(cli_state.chnnlOUT)
            print_log(output[2])
            println("bestmove ", UCImove(engine.board, output[1]))
            reset_worker!(cli_state)
            #not required by UCI to make a move, usually a GUI will overwrite with a new FEN
            make_move!(output[1], engine.board)
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