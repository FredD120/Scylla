"channel for passing info to and from CLI"
struct Channels
    quit::Channel{Symbol}
    info::Channel{String}
end

"default constructor for Channels, quit channel is smaller as it doesn't need to buffer any data"
Channels() = Channels(Channel{Symbol}(1), Channel{String}(100))

mutable struct Control 
    maxtime::Float64
    maxnodes::UInt64
    maxdepth::UInt8
    stoppable::Bool
end

"default keyword argument constructor for engine control struct. enforces MAXDEPTH during construction"
Control(; maxtime=Inf64, maxnodes=typemax(UInt64), maxdepth=MAXDEPTH) =
    Control(maxtime, maxnodes, min(maxdepth, MAXDEPTH), false)

"convenience constructor for control with finite time limit"
TimeControl(t=DEFAULTTIME; maxdepth=MAXDEPTH) = Control(maxtime=t, maxdepth=maxdepth)

"convenience constructor for control with finite node limit"
NodesControl(n=DEFAULTNODES; maxdepth=MAXDEPTH) = Control(maxnodes=n, maxdepth=maxdepth)

"convenience constructor for control with finite depth limit"
DepthControl(d=MAXDEPTH) = Control(maxdepth=d)

"different configurations the engine can run in"
mutable struct SearchConfig
    control::Control
    starttime::Float64
    nodes_since_check::UInt64
    nodes::UInt64
    quit_now::Bool
end

SearchConfig() = SearchConfig(TimeControl(), time(), UInt64(0), UInt64(0), false)

"reset all temporary counters/trackers in config struct"
function reset_search_config!(config)
    config.quit_now = false
    config.nodes_since_check = UInt64(0)
    config.nodes = UInt64(0)
end

"holds all information the engine needs to calculate"
mutable struct EngineState{T <: Union{TranspositionTable, Nothing}}
    board::BoardState
    table::T
    tt_hashfull::UInt32
    config::SearchConfig
    channel::Channels
    info::SearchInfo
    verbose::Bool
end

"constructor for enginestate given TT size in Mb and boardstate"
function EngineState(FEN::AbstractString=START_FEN; verbose=false, size_mb=TT_DEFAULT_MB)
    board = BoardState(FEN)
    TT = TranspositionTable(verbose; size_mb=size_mb)
    return EngineState(board, TT, UInt32(0), SearchConfig(), Channels(), SearchInfo(), verbose)
end

"construct a new engine state from an existing one with a different transposition table"
new_engine(e::EngineState, table) = EngineState(e.board, table, UInt32(0), e.config, e.channel, e.info, e.verbose)

"return a new engine with a transposition table"
function assign_tt(engine::EngineState{T}, debug=false; size_mb=TT_DEFAULT_MB) where {T}
    table = TranspositionTable(debug, size_mb=size_mb)

    if table isa T
        engine.table = table
        return engine
    else
        return new_engine(engine, table)
    end
end

"Reset entries of engine's TT to default value"
function reset_tt!(engine::EngineState{<:TranspositionTable})
    reset_tt!(engine.table)
    engine.tt_hashfull = UInt32(0)
end

"fallback if transposition table doesn't exist"
reset_tt!(::EngineState{Nothing})= nothing

"Reset engine to default boardstate and empty TT"
function reset_engine!(engine::EngineState)
    reset_tt!(engine)
    reset_search_info!(engine.info)
    engine.board = BoardState()
end

"return PV as vector of strings"
pv_string(pv::Vector{Move})::Vector{String} = map(m -> long_move(m), pv)

mutable struct Logger
    best_score::Int16
    nodes::UInt64
    q_nodes::UInt64
    cur_depth::UInt8
    stopmidsearch::Bool
    pv::Vector{Move}
    seldepth::UInt8
    tt_total::Int32
    hashfull::UInt32
    δt::Float32
end

Logger(TT_entries) = Logger(0, 0, 0, 0, false, Move[], 0, TT_entries, 0, 0.0)

"calculate logging values that are not automatically updated during minimax"
function update_logger!(engine::EngineState, logger::Logger, bestscore)
    logger.δt = time() - engine.config.starttime
    logger.hashfull = engine.tt_hashfull
    logger.nodes = engine.config.nodes
    
    # PV table + position score is only valid after an exhaustive search of a given depth
    if !logger.stopmidsearch
        logger.pv = engine.info.pv[1:engine.info.pv_len[1]]
        logger.best_score = bestscore
    end
end

"report state of engine at current depth if in verbose mode, putting all output into info Channel"
function report_progress(engine::EngineState, logger::Logger)
    buffer = IOBuffer()

    best = begin score = logger.best_score
        if mate_found(score)
            mate_ply = INF - abs(score)
            dist = (mate_ply + 1) ÷ 2
            score > 0 ? "mate $dist" : "mate -$dist"
        else
            "cp $score"
        end
    end
    print(buffer, "info score ", best, " ")
    
    TT_msg = begin
        if logger.hashfull == 0 
            "" 
        else
            hashfull = round(Int64, logger.hashfull*1000 / logger.tt_total)
            "hashfull $(hashfull) "
        end
    end

    nps_msg = begin
        if logger.δt == 0.0
            ""
        else
            "nps $(round(Int64, logger.nodes/logger.δt)) "
        end
    end

    print(buffer, 
    "nodes $(logger.nodes) ",
    nps_msg,
    "qnodes $(logger.q_nodes) ",
    "depth $(logger.cur_depth) ",
    "seldepth $(logger.seldepth) ",
    TT_msg,
    "time $(round(Int64, logger.δt * 1000)) ",
    "pv ")
    
    for move in logger.pv
        print(buffer, uci_move(move), " ")
    end

    put!(engine.channel.info, String(take!(buffer)))
end

"print all logging info collected during search to StdOut"
print_search_log(engine::EngineState) = print_channel(engine.channel.info)

"returns true if we have run out of time"
@inline check_time(config, safety_factor) = (time() - config.starttime) > (config.control.maxtime * safety_factor)

"return true if channel contains :quit message"
@inline check_quit(channel::Channels) = isready(channel.quit) && take!(channel.quit) == :quit

@inline function stop_early(config::SearchConfig, channel::Channels; safety_factor=1.0, always_check=false)
    if config.quit_now
        return true
    end

    if !config.control.stoppable
        return false
    end

    config.nodes_since_check += 1
    if always_check || config.nodes_since_check > CHECKNODES 
        config.nodes_since_check = 0
        config.quit_now = check_quit(channel) || 
                          check_time(config, safety_factor) || 
                          (config.nodes >= config.control.maxnodes)
    end
    return config.quit_now    
end

"returns true if score is a mate score"
mate_found(score) = abs(score) >= INF - MAXMATEDEPTH

"Constant evaluation of stalemate"
@inline evaluate(::Draw, ply) = Int16(0)
"Constant evaluation of being checkmated (favour quicker mates)"
@inline evaluate(::Loss, ply) = -INF + Int16(ply)

"Returns score of current position from whites perspective"
@inline function evaluate(board::BoardState)::Int16
    weight = phase(count_pieces(board))
    score = board.pst_score[1] * weight +
            board.pst_score[2] * endgame_phase(weight)
    
    return Int16(score >> QUANTISATION_SHIFT)
end

"retrieve information from transposition table and tell main engine whether to cut and return precalculated score"
@inline function retrieve_from_table(engine::EngineState{<:TranspositionTable}, α, β, depth, ply)
    transposition_data, transposition_score = retrieve(engine.table, engine.board.zobrist_hash, ply)
    if !isnothing(transposition_data)
        # don't try to cutoff if depth of TT entry is too low
        if transposition_data.depth >= depth 
            if (transposition_data.type == EXACT) ||
               (transposition_data.type == BETA && transposition_score >= β) ||
               (transposition_data.type == ALPHA && transposition_score <= α)
                return transposition_data.move, transposition_score, true
            end
        end
        # we can only use the move stored if we found BETA or EXACT node
        # otherwise it will be a NULLMOVE so won't match in move scoring
        return transposition_data.move, α, false
    end
    return NULLMOVE, α, false
end

@inline retrieve_from_table(::EngineState{Nothing}, α, β, depth, ply) = (NULLMOVE, α, false)

"store position with depth, score and best move in transposition table, logging if successful"
@inline function store_in_table!(engine::EngineState{<:TranspositionTable}, depth, ply, score, node_type, move)
    #not safe to store in TT if search is incomplete
    if engine.config.quit_now
        return nothing
    end 
    move = remove_score(move)
    success = store!(engine.table, engine.board.zobrist_hash, depth, ply, score, node_type, move)
    if success
        engine.tt_hashfull += 1
    end
end

@inline store_in_table!(::EngineState{Nothing}, args...) = nothing

"search a set of moves generated during quiescent search. recursively calls quiescence, uses fail-soft"
function search_quiescent_moves(engine::EngineState, moves, best_score, is_check, player::Int8, α, β, ply, logger::Logger)
    for i in eachindex(moves)
        next_best!(moves,i)
        move = moves[i]

        success = make_pseudolegal_move!(move, engine.board, is_check)
        if !success
            continue
        end
        score = -quiescence(engine, -player, -β, -α, ply + 1, logger)
        unmake_move!(engine.board)

        best_score = max(score, best_score)
        if score > α
            if score >= β
                break
            end
            α = score
        end
    end
    
    return best_score
end

"Search available (move-ordered) captures until we reach quiet positions to evaluate"
function quiescence(engine::EngineState, player::Int8, α, β, ply, logger::Logger)
    if stop_early(engine.config, engine.channel)
        logger.stopmidsearch = true
        return α
    end 

    engine.config.nodes += 1
    logger.q_nodes += 1
    logger.seldepth = max(logger.seldepth, ply)

    # still need to check for draws in qsearch
    if draw_state(engine.board)
        return evaluate(DRAW, ply)
    end

    is_check = in_check(engine.board)
    # not in check, continue quiescence
    if !is_check
        # stand-pat evaluation - makes null move assumption
        best_score = player * evaluate(engine.board)
        # either player can choose not to continue trading 
        if best_score > α
            if best_score >= β
                return best_score
            end
            α = best_score
        end

        moves, attack_count = generate_pseudolegal_attacks(engine.board)
        score_moves!(moves)

        score = search_quiescent_moves(engine, moves, best_score, is_check, player, α, β, ply, logger)
        clear_current_moves!(engine.board.move_vector, attack_count)
        return score

    # in check, must search all legal moves (check extension)
    else
        best_score = evaluate(LOSS, ply)
        moves, move_length = generate_legal_moves(engine.board)
        score_moves!(moves)

        score = search_quiescent_moves(engine, moves, best_score, is_check, player, α, β, ply, logger)
        clear_current_moves!(engine.board.move_vector, move_length)
        return score
    end
end

"iterate through all moves and recursively call minimax to evaluate the position. returns a score, node type and best move"
function search_moves(engine::EngineState, moves, player::Int8, α, β, depth, ply, is_principal::Bool, logger::Logger)
    # figure out type of current node for use in TT and best move
    node_type = ALPHA
    best_move = NULLMOVE
    best_score = evaluate(LOSS, ply)
    move_made = false

    for i in eachindex(moves)
        next_best!(moves, i)
        move = moves[i]

        make_move!(move, engine.board)
        score = principle_variation_search(engine, player, α, β, depth, ply, is_principal, logger)
        unmake_move!(engine.board)

        # only first search is on PV
        is_principal = false
        move_made = true

        best_score = max(score, best_score)
        # update alpha (lower bound) when better score is found
        if score > α
            # cut when upper bound exceeded
            if score >= β
                # update killers if exceed β
                if !is_capture(move)
                    new_killer!(engine.info.killers, ply, move)
                end

                node_type = BETA
                best_move = move
                break
            end
            node_type = EXACT
            best_move = move
            α = score
            # exact score found, must copy up PV from further down the tree
            copy_pv!(engine.info, ply, move)
        end
    end

    # no moves made, either stalemate or checkmate
    if !move_made
        node_type = EXACT
        if !in_check(engine.board)
            best_score = evaluate(DRAW, ply)
        end
    end

    store_in_table!(engine, depth, ply, best_score, node_type, best_move)
    return best_score
end

"minimax algorithm, tries to maximise eval while constrained by opponent trying to minimise eval"
function minimax(engine::EngineState, player::Int8, α, β, depth, ply, is_principal::Bool, logger::Logger)
    # reset pv length for the current ply
    engine.info.pv_len[ply + 1] = UInt8(0)
    # stop if out of time/nodes or receive quit message
    if stop_early(engine.config, engine.channel)
        logger.stopmidsearch = true
        return α
    end
    
    # enter quiescence search if at leaf node
    if depth <= MINDEPTH
        return quiescence(engine, player, α, β, ply, logger)
    end
    engine.config.nodes += 1

    # check for draw by FIDE rules
    if draw_state(engine.board)
        return evaluate(DRAW, ply)
    end

    best_move, score, return_early = retrieve_from_table(engine, α, β, depth, ply)
    if return_early
        set_pv!(engine.info, ply, best_move)
        return score
    end

    moves, move_length = generate_legal_moves(engine.board)
    score_moves!(moves, engine.info.killers[ply + 1], best_move)
    score = search_moves(engine, moves, player, α, β, depth, ply, is_principal, logger)

    clear_current_moves!(engine.board.move_vector, move_length)
    return score
end

"if not on principle variation, search with a null window. if this fails (score > α), must open window and re-search"
function principle_variation_search(engine, player, α, β, depth, ply, is_principal, logger)
    if !is_principal
        null_window_score = -minimax(engine, -player, -α - 1, -α, depth - 1, ply + 1, is_principal, logger)
        # have we proved that all other moves are worse than PV move
        if null_window_score <= α
            return null_window_score
        end
    end
    return -minimax(engine, -player, -β, -α, depth - 1, ply + 1, is_principal, logger)
end

"root of minimax search, define parameters and return result of fixed depth search"
function root(engine::EngineState, depth, logger::Logger)
    # whites current best score
    α = -INF
    # whites current worst score (blacks best score)
    β = INF
    # white is +1, black is -1. this ensures score is always from side-to-moves perspective
    player::Int8 = sgn(engine.board.colour)
    ply = 0
    is_principal = true

    return minimax(engine, player, α, β, depth, ply, is_principal, logger)
end

"checks escape conditions from iterative deepening search, returns true if none are met"
function continue_deepening(engine::EngineState, depth, bestscore)
    if depth >= engine.config.control.maxdepth
        return false
    elseif mate_found(bestscore)
        return false
    elseif stop_early(engine.config, engine.channel, safety_factor = 0.5, always_check=true)
        return false
    end
    return true
end

"run minimax search to fixed depth then increase depth until time runs out"
function iterative_deepening(engine::EngineState)
    depth = 0
    logger = Logger(num_entries(engine.table))
    bestscore = 0

    while continue_deepening(engine, depth, bestscore)
        depth += 1
        logger.cur_depth = depth
        bestscore = root(engine, depth, logger)

        update_logger!(engine, logger, bestscore)

        if engine.verbose
            report_progress(engine, logger)
        end

        # fully search root node to ensure a move is always found
        engine.config.control.stoppable = true
    end
    return logger
end

"evaluates the position to return the best move"
function best_move(engine::EngineState)
    engine.config.starttime = time()
    logger = iterative_deepening(engine)

    reset_search_config!(engine.config)
    return logger.pv[1], logger
end