const NAME = "Scylla"

mutable struct EngineWrapper
    engine::EngineState
    debug::Bool
end

EngineWrapper(state::EngineState; debug = false) = EngineWrapper(state, debug)

"listen waits for user (CLI) input, worker is a task to run the engine"
mutable struct CLI_state
    QUIT::Bool
    TT_SET::Bool
    listen::Channel{String}
    listener::Union{Task, Nothing}
    worker::Union{Task, Nothing}
end
CLI_state() = CLI_state(false, false, Channel{String}(10), nothing, nothing)

"reset worker thread by deleting it"
function reset_worker!(state::CLI_state)
    state.worker = nothing
end

"task to run best_move and put outputs in channel, then close the task"
function run_engine(engine::EngineState, state::CLI_state)
    best, _ = best_move(engine)
    move_str = "bestmove " * UCImove(engine.board, best)
    put!(engine.channel.info, move_str)
    reset_worker!(state)
end

"task to continually listen for input and put into listen channel"
function listen(st::CLI_state)
    for input in eachline()
        put!(st.listen, input)
    end
end

"parse OPTION command from CLI, dispatch on requests"
function set_option!(wrapper::EngineWrapper, cli_state, msg_vec)::Union{Nothing, String}
    if msg_vec[1] == "CLEAR" && msg_vec[2] == "HASH"
        reset_TT!(wrapper.engine)

    elseif msg_vec[1] == "HASH"
        ind = findfirst(x -> x=="VALUE", msg_vec)
        if !isnothing(ind) && length(msg_vec) > ind
            wrapper.engine = assign_TT(wrapper.engine, sizeMb = tryparse(Int64, msg_vec[ind+1]))
            cli_state.TT_SET = true
        end

    elseif wrapper.debug
        return "info option not recognised"
    end
    return nothing
end

"set board position from a FEN string plus moves"
function set_position!(engine, position_moves)
    ind = get_msg_index(uppercase.(position_moves), "MOVES")
    if uppercase(position_moves[1]) == "STARTPOS"
        engine.board = BoardState(startFEN)
    else
        last_ind = length(position_moves)
        #set last index to index of "MOVES" keyword if it exists
        if !isnothing(ind)
            last_ind = ind
        end
        FEN_string = join(position_moves[2:last_ind], " ")
        engine.board = BoardState(FEN_string)
    end
    #play moves if provided
    if !isnothing(ind)
        for move_str in position_moves[ind + 1:end]
            move = identify_UCImove(engine.board, move_str)
            make_move!(move, engine.board)
        end
    end
end

"parse time-control info from CLI, return as time + increment in seconds"
function get_time_control(e::EngineState, msg_array)
    match_colour = whitesmove(e.board.colour) ? "W" : "B"

    time_ind = get_msg_index(msg_array, match_colour * "TIME")
    inc_ind = get_msg_index(msg_array, match_colour * "INC")

    length(msg_array) > time_ind || error("No move-time given")
    time = parse(Float64, msg_array[time_ind + 1])

    increment = isnothing(inc_ind) ? 0.0 : parse(Float64, msg_array[inc_ind + 1])
    return (time, increment) ./ 1000
end

"estimate the optimal time to spend on the current move given time remaining and increment"
function estimate_movetime(::EngineState, time, increment)
    ESTIMATE_MOVES_REMAINING::Int8 = 25
    return (time / ESTIMATE_MOVES_REMAINING) + increment
end

"send quit message to engine if there is a channel to do so"
send_quit_msg!(channel::Channels) = put!(channel.quit, :quit)
send_quit_msg!(::Nothing) = nothing

"find relevant string within message to look for variables on the right"
get_msg_index(msg_array, substr) = findfirst(x->x==substr, msg_array)

"can modify either the engine state or the CLI state and launch new worker threads"
function parse_msg!(wrapper::EngineWrapper, cli_st, msg)::Union{Nothing, String}
    msg_in = split(uppercase(msg))
    if "QUIT" in msg_in
        send_quit_msg!(wrapper.engine.channel)
        cli_st.QUIT = true

    elseif "UCINEWGAME" in msg_in
        reset_engine!(wrapper.engine)

    elseif "UCI" in msg_in
        return string("id name ", NAME, "\n",
        "pid author FD\n",
        "option name Hash type spin default $TT_DEFAULT_MB min $TT_MIN_MB max $TT_MAX_MB\n",
        "option name Clear Hash type button\n",
        "uciok")

    elseif "ISREADY" in msg_in
        if !cli_st.TT_SET
            #assign default TT if not previously set
            wrapper.engine = assign_TT(wrapper.engine, wrapper.debug)
            cli_st.TT_SET = true
        end
        return "readyok"
    
    elseif "SETOPTION" in msg_in
        ind = get_msg_index(msg_in, "NAME")
        if !isnothing(ind) && length(msg_in) > ind
            return set_option!(wrapper, cli_st, msg_in[ind+1:end])
        end

    elseif "DEBUG" in msg_in
        ind = get_msg_index(msg_in, "DEBUG")
        if !isnothing(ind) && length(msg_in) > ind
            if msg_in[ind+1] == "ON"
                wrapper.debug = true
                return "info debug on"
            elseif msg_in[ind+1] == "OFF"
                wrapper.debug = false
            end
        end

    elseif "GO" in msg_in
        ind = get_msg_index(msg_in, "GO")
        if !isnothing(ind) && length(msg_in) > ind + 1
            if msg_in[ind+1] == "MOVETIME" && (wrapper.engine.config.control isa Time)
                newtime = parse(Float64, msg_in[ind+2]) / 1000
                wrapper.engine.config.control = Time(newtime, wrapper.engine.config.control.maxdepth)
            
            elseif msg_in[ind+1] == "WTIME"
                newtime = estimate_movetime(wrapper.engine, get_time_control(wrapper.engine, msg_in)...)
                wrapper.engine.config.control = Time(newtime, wrapper.engine.config.control.maxdepth)
           
            end
        end
        
        cli_st.worker = Threads.@spawn run_engine(wrapper.engine, cli_st)

        if wrapper.debug
            return "info calculating best move"
        end

    elseif "POSITION" in msg_in
        ind = get_msg_index(msg_in, "POSITION")
        if !isnothing(ind) && length(msg_in) > ind
            set_position!(wrapper.engine, split(msg)[ind+1:end])
        end

    elseif "STOP" in msg_in && !isnothing(cli_st.worker)
        send_quit_msg!(wrapper.engine.channel)

    elseif wrapper.debug
        return "info command not recognised"
    end
    return nothing
end

"entry point for CLI, uses UCI protocol"
function run_cli()
    cli_state = CLI_state()
    cli_state.listener = Threads.@spawn listen(cli_state)
    wrapper = EngineWrapper(
        EngineState(comms = Channels(), 
        control = Time(5), sizeMb = 0, verbose = true),
        debug = false)

    while !cli_state.QUIT
        if isready(cli_state.listen)
            instruction = take!(cli_state.listen)
            return_msg = parse_msg!(wrapper, cli_state, instruction)
            if return_msg isa String
                println(return_msg)
            end
        end
        if isready(wrapper.engine.channel.quit)
            info_str = take!(wrapper.engine.channel.info)
            println(info_str)
        end
        flush(stdout)
        sleep(0.05)
    end
    cli_state.listener = nothing
end

"try to match given UCI move to a legal move. return null move otherwise"
function identify_UCImove(B::BoardState, UCImove::AbstractString)
    moves, _ = generate_moves(B)
    num_from = algebraic_to_numeric(UCImove[1:2])
    num_to = algebraic_to_numeric(UCImove[3:4])
    num_promote = NOFLAG
    kingsmove = num_from == locate_king(B, B.colour)

    if length(UCImove) > 4
        num_promote = promote_id(Char(UCImove[5]))
    end

    for move in moves
        flg = flag(move)
        if from(move) == num_from && to(move) == num_to
            if num_promote == NOFLAG || num_promote == flg
                return move
            end
        #check for castling if the king is moving
        elseif kingsmove
            if (flg == KCASTLE && num_to == Kcastle_shift(num_from)) ||
                (flg == QCASTLE && num_to == Qcastle_shift(num_from))
                return move 
            end
        end
    end
    return NULLMOVE
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