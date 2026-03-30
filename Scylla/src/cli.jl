mutable struct EngineWrapper
    engine::EngineState
    debug::Bool
end

"default constructor for EngineWrapper, assumes no transposition table and engine time restricted"
EngineWrapper() = 
    EngineWrapper(EngineState(comms = Channels(), 
    control = Time(GUI_SAFETY_FACTOR), size_mb = 0, verbose = true),
    debug = false)

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
function run_engine(engine::EngineState)
    best, _ = best_move(engine)
    move_str = "bestmove " * uci_move(engine.board, best)
    put!(engine.channel.info, move_str)
end

"task to continually listen for input and put into listen channel"
function listen(st::CLI_state)
    for input in eachline()
        put!(st.listen, input)
    end
end

"parse time-control info from CLI, return as time + increment in seconds"
function get_time_control(board::BoardState, msg_caps)
    match_colour = whitesmove(board.colour) ? "W" : "B"

    time_ind = get_msg_index(msg_caps, match_colour * "TIME")
    inc_ind = get_msg_index(msg_caps, match_colour * "INC")

    time = if is_valid(time_ind, msg_caps)
        parse(Float64, msg_caps[time_ind + 1])
    else
        DEFAULTTIME * 1000
    end

    increment = if is_valid(inc_ind, msg_caps)
        parse(Float64, msg_caps[inc_ind + 1])
    else
        0.0
    end

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
get_msg_index(msg_array, substr) = findfirst(x -> x==substr, msg_array)

"check if index into message array is valid"
is_valid(ind, msg_array) = !isnothing(ind) && (length(msg_array) > ind)

"put quit message into channel for engine to read and close CLI"
function handle_quit!(wrapper, cli_st, _)
    send_quit_msg!(wrapper.engine.channel)
    cli_st.QUIT = true
    return nothing
end

"reset transposition table if it exists, also boardstate"
function handle_ucinewgame!(wrapper, _, _) 
    reset_engine!(wrapper.engine)
    return nothing
end  

"send standard UCI_OK message to GUI"
handle_uci(_, _, _) = UCI_OK_MESSAGE

"ensure all functions are compiled into memory before first search is executed"
function run_short_search(engine::EngineState{T, C, Q}) where {T, C, Q}
    verbose = engine.config.verbose
    control = engine.config.control

    engine.config.control = C(maxdepth = 4)
    engine.config.verbose = false

    _, _ = best_move(engine)
    engine.config.control = control
    engine.config.verbose = verbose
end

"assign default TT if not previously set, tell GUI we are ready to compute"
function handle_isready!(wrapper, cli_st, _)
    run_short_search(wrapper.engine)
    if !cli_st.TT_SET
        wrapper.engine = assign_tt(wrapper.engine, wrapper.debug)
        cli_st.TT_SET = true
    end
    return "readyok"
end

"set hash table to desired size in Mb if given"
function set_hash_table!(wrapper::EngineWrapper, cli_state, msg_caps)
    ind = get_msg_index(msg_caps, "VALUE")
    if is_valid(ind, msg_caps)
        size = tryparse(Int64, msg_caps[ind+1])
        wrapper.engine = assign_tt(wrapper.engine, wrapper.debug; size_mb = size)
        cli_state.TT_SET = true
    end
end

"dispatch on commands from GUI given by OPTION"
function handle_setoption!(wrapper, cli_state, msg_in)
    msg_caps = uppercase.(msg_in)

    if "CLEAR" in msg_caps && "HASH" in msg_caps
        reset_tt!(wrapper.engine)

    elseif "HASH" in msg_caps
        set_hash_table!(wrapper, cli_state, msg_caps)

    elseif wrapper.debug
        return "info option not recognised"
    end
    return nothing
end

"toggle debug state of CLI"
function handle_debug!(wrapper, _, msg_in)
    msg_caps = uppercase.(msg_in)

    if "ON" in msg_caps
        wrapper.debug = true
        return "info debug on"

    elseif "OFF" in msg_caps
        wrapper.debug = false
    end
    return nothing
end

"set engine control based on GUI message, may change type of control"
function get_control(engine::EngineState, msg_in)
    msg_caps = uppercase.(msg_in)
    control = engine.config.control

    if "MOVETIME" in msg_caps
        ind = get_msg_index(msg_caps, "MOVETIME")
        if is_valid(ind, msg_caps)
            new_time = parse(Float64, msg_in[ind + 1]) / 1000
            actual_time = max(new_time - GUI_SAFETY_FACTOR, GUI_SAFETY_FACTOR)
            control = Time(actual_time, control.maxdepth)
        end
    
    elseif "WTIME" in msg_caps || "BTIME" in msg_caps
        time, increment = get_time_control(engine.board, msg_caps)
        newtime = estimate_movetime(engine, time, increment)
        control = Time(newtime, control.maxdepth)

    elseif "DEPTH" in msg_caps
        ind = get_msg_index(msg_caps, "DEPTH")
        if is_valid(ind, msg_caps)
            new_depth = parse(UInt8, msg_in[ind + 1])
            control = Depth(new_depth)
        end

    elseif "NODES" in msg_caps
        ind = get_msg_index(msg_caps, "NODES")
        if is_valid(ind, msg_caps)
            new_nodecount = parse(UInt64, msg_in[ind + 1])
            control = Nodes(new_nodecount)
        end
    end

    return control
end

"set engine control type to time/depth/nodes based on GUI request and launch worker thread to calculate"
function handle_go!(wrapper, cli_st, msg_in)
    new_control = get_control(wrapper.engine, msg_in)
    wrapper.engine = assign_control(wrapper.engine, new_control)

    cli_st.worker = Threads.@spawn run_engine(wrapper.engine)

    if wrapper.debug
        return "info calculating best move"
    end
    return nothing
end

"set position sent from GUI, either the starting position or a specified FEN. must use lower case message for FEN string"
function set_position!(engine::EngineState, msg_in, msg_caps)
    if "STARTPOS" in msg_caps
        engine.board = BoardState(START_FEN)
    
    elseif "FEN" in msg_caps
        start_ind = get_msg_index(msg_caps, "FEN") + 1
        last_ind = get_msg_index(msg_caps, "MOVES")
        if isnothing(last_ind)
            last_ind = length(msg_caps)
        end

        FEN_string = join(msg_in[start_ind:last_ind], " ")
        engine.board = BoardState(FEN_string)
    end
end

"play moves given by GUI onto the board if they are legal"
function set_moves!(engine::EngineState, msg_in, msg_caps)
    ind = get_msg_index(msg_caps, "MOVES")
    if is_valid(ind, msg_caps)
        for move_str in msg_in[ind + 1:end]
            move = identify_uci_move(engine.board, move_str)
            make_move!(move, engine.board)
        end
    end
end

"GUI sends a new position to CLI, set board position from a FEN string plus moves"
function handle_position!(wrapper, _, msg_in)
    msg_caps = uppercase.(msg_in)
    set_position!(wrapper.engine, msg_in, msg_caps)

    if "MOVES" in msg_caps
        set_moves!(wrapper.engine, msg_in, msg_caps)
    end

    if wrapper.debug
        return "info position set"
    end
    return nothing
end

"if worker is running, put message in channel to stop it"
function handle_stop!(wrapper, cli_st, _)
    if !isnothing(cli_st.worker)
        send_quit_msg!(wrapper.engine.channel)
    end
    return nothing
end

"define all functions that can be dispatched by CLI message parser"
const UCI_COMMANDS = Dict{String, Function}(
    "QUIT"       => handle_quit!,
    "UCINEWGAME" => handle_ucinewgame!,
    "UCI"        => handle_uci,
    "ISREADY"    => handle_isready!,
    "SETOPTION"  => handle_setoption!,
    "DEBUG"      => handle_debug!,
    "GO"         => handle_go!,
    "POSITION"   => handle_position!,
    "STOP"       => handle_stop!,
)

"can modify either the engine state or the CLI state and launch new worker threads"
function parse_msg!(wrapper::EngineWrapper, cli_state, msg)
    msg_in = split(msg)

    for token in uppercase.(msg_in)
        if haskey(UCI_COMMANDS, token)
            return UCI_COMMANDS[token](wrapper, cli_state, msg_in)
        end
    end

    if wrapper.debug
        return "info command not recognised"
    end
    return nothing
end

"check if there is a command from the GUI and execute"
function fetch_command!(wrapper::EngineWrapper, cli::CLI_state)
    if isready(cli.listen)
        instruction = take!(cli.listen)
        return_msg = parse_msg!(wrapper, cli, instruction)
        if return_msg isa String
            println(return_msg)
        end
    end
end

"check if engine progress info is in buffer and dump to stdout"
function fetch_engine_info!(info_channel::Channel{String})
    while isready(info_channel)
        info_str = take!(info_channel)
        println(info_str)
    end
end

"check for crashed engine and print error message"
function fetch_error!(cli::CLI_state)
    if !isnothing(cli.worker) && istaskfailed(cli.worker)
        try
            fetch(cli.worker)
        catch e
            showerror(stdout, e, catch_backtrace())
            println()
        end
        cli.worker = nothing
    end
end

"entry point for CLI, uses UCI protocol"
function run_cli()
    cli_state = CLI_state()
    cli_state.listener = Threads.@spawn listen(cli_state)
    wrapper = EngineWrapper()

    while !cli_state.QUIT
        fetch_command!(wrapper, cli_state)
        fetch_engine_info!(wrapper.engine.channel.info)
        fetch_error!(cli_state)

        flush(stdout)
        sleep(0.001)
    end
    cli_state.listener = nothing
end

"try to match given UCI move to a legal move. return null move otherwise"
function identify_uci_move(board::BoardState, uci_move::AbstractString)
    moves, move_count = generate_legal_moves(board)
    num_from = algebraic_to_numeric(uci_move[1:2])
    num_to = algebraic_to_numeric(uci_move[3:4])
    num_promote = NOFLAG
    kingsmove = num_from == locate_king(board)
    gui_move = NULLMOVE

    if length(uci_move) > 4
        num_promote = promote_id(Char(uci_move[5]))
    end

    for move in moves
        flg = flag(move)
        if from(move) == num_from && to(move) == num_to
            if num_promote == NOFLAG || num_promote == flg
                gui_move = move
                break
            end
        #check for castling if the king is moving
        elseif kingsmove
            if (flg == KING_CASTLE && num_to == king_castle_shift(num_from)) ||
                (flg == QUEEN_CASTLE && num_to == queen_castle_shift(num_from))
                gui_move = move
                break
            end
        end
    end
    clear_current_moves!(board.move_vector, move_count)
    return gui_move
end

"entry point for PackageCompiler.jl"
function julia_main()::Cint
    run_cli()
    return 0
end