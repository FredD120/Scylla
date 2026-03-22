"channel for passing info to and from CLI"
struct Channels
    quit::Channel{Symbol}
    info::Channel{String}
end

"default constructor for Channels, quit channel is smaller as it doesn't need to buffer any data"
Channels() = Channels(Channel{Symbol}(1), Channel{String}(100))

"different configurations the engine can run in"
mutable struct Config{C <: Control}
    control::C
    starttime::Float64
    nodes_since_time::UInt32
    nodes::UInt32
    quit_now::Bool
    quiescence::Bool
    verbose::Bool
end

function Config(control::Control, verbose)
    Config(control, time(), UInt32(0), UInt32(0), false, true, verbose)
end

"reset all temporary counters/trackers in config struct"
function reset_config!(config)
    config.quit_now = false
    config.nodes_since_time = UInt32(0)
    config.nodes = UInt32(0)
end

mutable struct SearchInfo
    #Record best moves from root to leaves for move ordering
    pv::Vector{Move}
    pv_len::UInt8
    Killers::Vector{Killer}
end

"Constructor for search info struct"
function SearchInfo(depth)
    triangular_pv = nulls(triangle_number(depth))
    killers = [Killer() for _ in 1:depth]
    SearchInfo(triangular_pv, 0, killers)
end

"holds all information the engine needs to calculate"
mutable struct EngineState{T <: Union{TranspositionTable, Nothing}, C <: Control, Q <: Union{Channels, Nothing}}
    board::BoardState
    table::T
    tt_hashfull::UInt32
    config::Config{C}
    channel::Q
    info::SearchInfo
end

max_depth(e::EngineState) = e.config.control.maxdepth

"Constructor for enginestate given TT size in Mb and boardstate"
function EngineState(FEN::AbstractString=START_FEN; verbose=false,
        size_mb=TT_DEFAULT_MB, sizePO2=nothing, TT_type=TT_ENTRY_TYPE,
        comms::Union{Channels, Nothing}=nothing, control::Control=Time()) 

    board = BoardState(FEN)
    TT = TranspositionTable(verbose; size=sizePO2, size_mb=size_mb, type=TT_type)
    config = Config(control, verbose)
    info = SearchInfo(config.control.maxdepth)
    return EngineState(board, TT, UInt32(0), config, comms, info)
end

"return a new engine with a new type of control assigned to it"
function assign_control(engine::EngineState{T, C, Q}, new_control) where {T, C, Q}
    if new_control isa C 
        engine.config.control = new_control
        return engine
    else
        new_config = Config(new_control,
        engine.config.starttime,
        engine.config.nodes_since_time,
        engine.config.nodes,
        engine.config.quit_now,
        engine.config.quiescence,
        engine.config.verbose,)  

        return EngineState(engine.board, engine.table, 
        engine.tt_hashfull, new_config,
        engine.channel, engine.info)
    end
end

"return a new engine with a transposition table"
function assign_tt(engine::EngineState{Nothing, C, Q}, debug=false;
    size_mb=TT_DEFAULT_MB, sizePO2=nothing, TT_type=TT_ENTRY_TYPE) where {C, Q}

    TT = TranspositionTable(debug,
    size_mb=size_mb, size=sizePO2, type=TT_type)

    return EngineState(engine.board, TT, UInt32(0), 
           engine.config, engine.channel, engine.info)
end

"modify transposition table if it already exists"
function assign_tt(engine::EngineState{<:TranspositionTable, C, Q}, debug=false;
    size_mb = TT_DEFAULT_MB, sizePO2=nothing, TT_type=TT_ENTRY_TYPE) where {C, Q}

    engine.table = TranspositionTable(debug,
    size_mb=size_mb, size=sizePO2, type=TT_type)
    return engine
end

"Reset entries of engine's TT to default value"
function reset_tt!(engine::EngineState{<:TranspositionTable, C, Q}) where {C, Q}
    reset_tt!(engine.table)
    engine.tt_hashfull = UInt32(0)
end

"fallback if transposition table doesn't exist"
reset_tt!(::EngineState{Nothing, C, Q}) where {C, Q} = nothing

"Reset engine to default boardstate and empty TT"
function reset_engine!(engine::EngineState)
    reset_tt!(engine)
    engine.board = BoardState()
end

"return PV as vector of strings"
pv_string(pv::Vector{Move})::Vector{String} = map(m -> long_move(m), pv)

mutable struct Logger
    best_score::Int16
    nodes::Int32
    q_nodes::Int32
    cur_depth::UInt8
    stopmidsearch::Bool
    pv::Vector{Move}
    seldepth::UInt8
    tt_total::Int32
    hashfull::UInt32
    δt::Float32
end

Logger(TT_entries) = Logger(0, 0, 0, 0, 
                     false, Move[], 0, 
                     TT_entries, 0, 0.0)

"calculate logging values that are not automatically updated during minimax"
function update_logger!(engine::EngineState, logger::Logger, bestscore)
    logger.δt = time() - engine.config.starttime
    logger.hashfull = engine.tt_hashfull
    logger.nodes = engine.config.nodes
    
    #PV table + position score is only valid after an exhaustive search of a given depth
    if !logger.stopmidsearch
        logger.pv = engine.info.pv[1:engine.info.pv_len]
        logger.best_score = bestscore
    end
end

"report state of engine at current depth if verbose"
function report_progress(engine::EngineState{T, C, Nothing}, logger::Logger) where {T, C}
    println("Searched depth $(logger.cur_depth) in $(round(time() - engine.config.starttime, sigdigits=4))s. ",
    "Current maxdepth = $(logger.seldepth). ",
    "PV so far: ", pv_string(logger.pv))
end

"report state of engine at current depth if using UCI protocol in verbose mode"
function report_progress(engine::EngineState{T, C, Channels}, logger::Logger) where {T, C}
    if length(logger.pv) > 0 
        buffer = IOBuffer()

        best = begin score = logger.best_score
            if mate_found(score)
                dist = Int((INF - abs(score)) ÷ 2)
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

        print(buffer, 
        "nodes $(logger.nodes) ",
        "nps $(round(Int64, logger.nodes/logger.δt)) ",
        "qnodes $(logger.q_nodes) ",
        "depth $(logger.cur_depth) ",
        "seldepth $(logger.seldepth) ",
        TT_msg,
        "time $(round(Int64, logger.δt * 1000)) ",
        "pv ")

        for move in logger.pv
            print(buffer, uci_move(engine.board, move), " ")
        end

        put!(engine.channel.info, String(take!(buffer)))
    else
        put!(engine.channel.info, "info no move found")
    end
    yield()
end

"print all logging info to StdOut"
function print_log(logger::Logger)
    if length(logger.pv) > 0
        best = "$(logger.best_score)"
        if mate_found(logger.best_score)
            dist = Int((INF - abs(logger.best_score)) ÷ 2)
            best = logger.best_score > 0 ? "Engine Mate in $dist" : "Opponent Mate in $dist"
        end

        TT_msg = ""
        if logger.hashfull > 0 
            TT_msg = "Hash full = $(round(logger.hashfull*100/logger.tt_total, sigdigits=3))%."
        end

        println("Best = $(long_move(logger.pv[1])). \
        Score = "*best*". \
        Nodes = $(logger.nodes) ($(round(logger.nodes/logger.δt,sigdigits=4)) nps). \
        Quiescent nodes = $(logger.q_nodes) ($(round(100*logger.q_nodes/logger.nodes,sigdigits=3))%). \
        Depth = $((logger.cur_depth)). \
        Max ply = $(logger.seldepth). "
        *TT_msg*
        " Time = $(round(logger.δt,sigdigits=6))s.")

        if logger.stopmidsearch
            println("Search exited early.")
        end
        println("#"^100)
    else 
        println("Failed to find move better than null move")
    end
end

"returns true if we have run out of time"
@inline check_time(config, safety_factor) = (time() - config.starttime) > (config.control.maxtime * safety_factor)

"return true if channel contains :quit message"
@inline check_quit(channel::Channels) = 
    isready(channel.quit) && take!(channel.quit) == :quit

"return false if channel doesn't exist"
@inline check_quit(::Nothing) = false

"don't need to handle quitting on depth exept through channel, since it is dealt with in iterative_deepening"
@inline function stop_early(engine::EngineState{T, Depth, Q}; kwargs...) where {T, Q} 
    if engine.config.quit_now
        return true
    end

    engine.config.quit_now = check_quit(engine.channel)
    return engine.config.quit_now
end

"stop when we have reached the limit of positions to evaluate"
@inline function stop_early(engine::EngineState{T, Nodes, Q}; kwargs...) where {T, Q}
    if engine.config.quit_now
        return true
    end

    if check_quit(engine.channel) || (engine.config.nodes >= engine.config.control.maxnodes)
        engine.config.quit_now = true
    end

    return engine.config.quit_now
end

"check if we have run out of time to continue searching, safety_factor ensures we don't run over due to overhead"
@inline function stop_early(engine::EngineState{T, Time, Q}; safety_factor=0.97, bypass_check=false) where {T, Q}
    if engine.config.quit_now
        return true
    end

    #reduce number of sys calls
    engine.config.nodes_since_time += 1
    if bypass_check || engine.config.nodes_since_time > CHECKNODES
        engine.config.nodes_since_time = 0
        engine.config.quit_now = check_quit(engine.channel) || check_time(engine.config, safety_factor)
    end
    return engine.config.quit_now
end

"returns true if score is a mate score"
mate_found(score) = abs(score) >= INF - MAXMATEDEPTH

"Constant evaluation of stalemate"
@inline evaluate(::Draw, ply) = Int16(0)
"Constant evaluation of being checkmated (favour quicker mates)"
@inline evaluate(::Loss, ply) = -INF + Int16(ply)

"Returns score of current position from whites perspective"
@inline function evaluate(board::BoardState)::Int16
    num_pieces = count_pieces(board.pieces)
    score = board.pst_score[1] * midgame_weighting(num_pieces) +
            board.pst_score[2] * endgame_weighting(num_pieces)
    
    return Int16(round(score))
end

"retrieve information from transposition table and tell main engine whether to cut and return precalculated score"
@inline function retrieve_from_table(engine::EngineState{<:TranspositionTable}, α, β, depth)
    transposition_data, transposition_score = retrieve(engine.table, engine.board.zobrist_hash, depth)
    if !isnothing(transposition_data)
        #don't try to cutoff if depth of TT entry is too low
        if transposition_data.depth >= depth 
            if transposition_data.type == EXACT
                return NULLMOVE, transposition_score, true

            elseif transposition_data.type == BETA && transposition_score >= β
                return NULLMOVE, β, true

            elseif transposition_data.type == ALPHA && transposition_score <= α 
                return NULLMOVE, α, true
                
            end
        end
        #we can only use the move stored if we found BETA or EXACT node
        #otherwise it will be a NULLMOVE so won't match in move scoring
        best_move = transposition_data.move
        return best_move, Int16(0), false
    end
    return NULLMOVE, α, false
end

@inline retrieve_from_table(::EngineState{Nothing}, α, β, depth) = (NULLMOVE, α, false)

"store position with depth, score and best move in transposition table, logging if successful"
@inline function store_in_table!(engine::EngineState{<:TranspositionTable}, depth, score, node_type, move)
    success = store!(engine.table, engine.board.zobrist_hash, depth, score, node_type, move)
    if success
        engine.tt_hashfull += 1
    end
end

@inline store_in_table!(::EngineState{Nothing}, _, _, _, _) = nothing

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
    if stop_early(engine)
        logger.stopmidsearch = true
        return α
    end 

    engine.config.nodes += 1
    logger.q_nodes += 1
    logger.seldepth = max(logger.seldepth, ply)

    #still need to check for draws in qsearch
    if draw_state(engine.board)
        return evaluate(DRAW, ply)
    end

    is_check = in_check(engine.board)
    #not in check, continue quiescence
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

    #in check, must search all legal moves (check extension)
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
        score = -minimax(engine, -player, -β, -α, depth - 1, ply + 1, is_principal, logger)
        unmake_move!(engine.board)

        #only first search is on PV
        is_principal = false
        move_made = true

        best_score = max(score, best_score)
        #update alpha (lower bound) when better score is found
        if score > α
            #cut when upper bound exceeded
            if score >= β
                #update killers if exceed β
                if !is_capture(move)
                    new_killer!(engine.info.Killers, ply, move)
                end

                node_type = BETA
                best_move = move
                break
            end
            node_type = EXACT
            best_move = move
            α = score
            #exact score found, must copy up PV from further down the tree
            copy_pv!(engine.info.pv, ply, engine.info.pv_len, max_depth(engine), move)
        end
    end

    #no moves made, either stalemate or checkmate
    if !move_made
        node_type = EXACT
        if !in_check(engine.board)
            best_score = evaluate(DRAW, ply)
        end
    end

    store_in_table!(engine, depth, best_score, node_type, best_move)
    return best_score
end

"minimax algorithm, tries to maximise eval while constrained by opponent trying to minimise eval"
function minimax(engine::EngineState, player::Int8, α, β, depth, ply, is_principal::Bool, logger::Logger)
    # stop if out of time/nodes or receive quit message
    if stop_early(engine)
        logger.stopmidsearch = true
        return α
    end 
    engine.config.nodes += 1

    # enter quiescence search if at leaf node
    if depth <= MINDEPTH
        if engine.config.quiescence
            return quiescence(engine, player, α, β, ply, logger)
        else 
            # evaluate whether we are in a terminal node
            gameover!(engine.board)
            return evaluate(engine.board)
        end
    end

    #check for draw by FIDE rules
    if draw_state(engine.board)
        return evaluate(DRAW, ply)
    end

    best_move = NULLMOVE
    # dont use TT if on PV (still save result of PV search in TT)
    if is_principal
        best_move = engine.info.pv[ply + 1]
    else
        best_move, score, return_early = retrieve_from_table(engine, α, β, depth)

        if return_early
            return score
        end
    end   

    moves, move_length = generate_legal_moves(engine.board)
    score_moves!(moves, engine.info.Killers[ply + 1], best_move)
    score = search_moves(engine, moves, player, α, β, depth, ply, is_principal, logger)

    clear_current_moves!(engine.board.move_vector, move_length)
    return score
end

"root of minimax search"
function root(engine::EngineState, moves, depth, logger::Logger)
    #whites current best score
    α = -INF
    #whites current worst score (blacks best score)
    β = INF
    #white is +1, black is -1. this ensures score is always from side-to-moves perspective
    player::Int8 = sgn(engine.board.colour)
    ply = 0
    #search PV first, only if it exists
    is_principal = true 

    #root node is always on PV
    score_moves!(moves, engine.info.Killers[ply + 1], engine.info.pv[ply + 1])

    for i in eachindex(moves)
        next_best!(moves, i)
        move = moves[i]

        make_move!(move, engine.board)
        score = -minimax(engine, -player, -β, -α, depth - 1, ply + 1, is_principal, logger)
        unmake_move!(engine.board)

        if stop_early(engine)
            logger.stopmidsearch = true
            break
        end

        if score > α
            copy_pv!(engine.info.pv, ply, engine.info.pv_len, max_depth(engine), move)
            α = score
        end
        is_principal = false
    end
    return α
end

"Run minimax search to fixed depth then increase depth until time runs out"
function iterative_deepening(engine::EngineState)
    moves, _ = generate_legal_moves(engine.board)
    depth = 0
    logger = Logger(num_entries(engine.table))
    bestscore = 0

    #Quit early if we or opponent have mate or if we run out of time
    while (depth < max_depth(engine)) &&  
        !(mate_found(bestscore)) &&
        !(stop_early(engine, safety_factor = 0.5, bypass_check=true))

        depth += 1
        logger.cur_depth = depth
        engine.info.pv_len = depth
        bestscore = root(engine, moves, depth, logger)

        update_logger!(engine, logger, bestscore)

        if engine.config.verbose && (time() - engine.config.starttime > GUI_SAFETY_FACTOR)
            report_progress(engine, logger)
        end
    end
    clear!(engine.board.move_vector)
    return engine.info.pv[1], logger
end

"Evaluates the position to return the best move"
function best_move(engine::EngineState)
    engine.config.starttime = time()
    best_move, logger = iterative_deepening(engine)

    reset_config!(engine.config)
    return best_move, logger
end
