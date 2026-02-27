#define evaluation constants
const MAXMATEDEPTH::Int16 = Int16(100)
const INF::Int16 = typemax(Int16)
const MATE::Int16 = INF - MAXMATEDEPTH

"channel for passing info to and from CLI"
struct Channels
    quit::Channel{Symbol}
    info::Channel{String}
end

"default constructor for Channels, quit channel is smaller as it doesn't need to buffer any data"
Channels() = Channels(Channel{Symbol}(1), Channel{String}(100))

"different configurations the engine can run in"
mutable struct Config{C<:Control}
    control::C
    starttime::Float64
    nodes_since_time::UInt32
    quit_now::Bool
    quiescence::Bool
    verbose::Bool
end

function Config(control::Control, verbose)
    Config(control, time(), UInt32(0), false, true, verbose)
end

mutable struct SearchInfo
    #Record best moves from root to leaves for move ordering
    PV::Vector{Move}
    PV_len::UInt8
    Killers::Vector{Killer}
end

"Constructor for search info struct"
function SearchInfo(depth)
    triangular_PV = nulls(triangle_number(depth))
    killers = [Killer() for _ in 1:depth]
    SearchInfo(triangular_PV, 0, killers)
end

"holds all information the engine needs to calculate"
mutable struct EngineState{T<:Union{TranspositionTable, Nothing}, C<:Control, Q<:Union{Channels, Nothing}}
    board::BoardState
    TT::T
    TT_HashFull::UInt32
    config::Config{C}
    channel::Q
    info::SearchInfo
end

max_depth(e::EngineState) = e.config.control.maxdepth

"Constructor for enginestate given TT size in Mb and boardstate"
function EngineState(FEN::AbstractString=startFEN; verbose=false,
        sizeMb=TT_DEFAULT_MB, sizePO2=nothing, TT_type=TT_ENTRY_TYPE,
        comms::Union{Channels, Nothing}=nothing, control::Control=Time()) 

    board = BoardState(FEN)
    TT = TranspositionTable(verbose; size=sizePO2, sizeMb=sizeMb, type=TT_type)
    config = Config(control, verbose)
    info = SearchInfo(config.control.maxdepth)
    return EngineState(board, TT, UInt32(0), config, comms, info)
end

"return a new engine with a transposition table"
function assign_TT(engine::EngineState{Nothing, C, Q}, debug=false;
    sizeMb=TT_DEFAULT_MB, sizePO2=nothing, TT_type=TT_ENTRY_TYPE) where {C, Q}

    TT = TranspositionTable(debug,
    sizeMb=sizeMb, size=sizePO2, type=TT_type)

    return EngineState(engine.board, TT, UInt32(0), 
           engine.config, engine.channel, engine.info)
end

"modify transposition table if it already exists"
function assign_TT(engine::EngineState{<:TranspositionTable, C, Q}, debug=false;
    sizeMb = TT_DEFAULT_MB, sizePO2=nothing, TT_type=TT_ENTRY_TYPE) where {C, Q}

    engine.TT = TranspositionTable(debug,
    sizeMb=sizeMb, size=sizePO2, type=TT_type)
    return engine
end

"Reset entries of engine's TT to default value"
function reset_TT!(engine::EngineState{<:TranspositionTable, C, Q}) where {C, Q}
    reset_TT!(engine.TT)
    engine.TT_HashFull = UInt32(0)
end

"fallback if transposition table doesn't exist"
reset_TT!(::EngineState{Nothing, C, Q}) where {C, Q} = nothing

"Reset engine to default boardstate and empty TT"
function reset_engine!(engine::EngineState)
    reset_TT!(engine)
    engine.board = BoardState(startFEN)
end

"update entry in transposition table. either greater depth or always replace. return true if successfull"
function store!(table::TranspositionTable{Bucket}, zobrist_hash, depth, score, node_type, best_move)::Bool
    TT_view = view_entry(table, zobrist_hash)
    store_success = false
    #correct mate scores in TT
    score = correct_score(score, depth, -1)
    new_data = SearchData(zobrist_hash, depth, score, node_type, best_move)
    if depth >= TT_view[].Depth.depth
        if TT_view[].Depth.type == NONE
            store_success = true
        end  
        TT_view[].Depth = new_data
    else
        if TT_view[].Always.type == NONE
            store_success = true
        end
        TT_view[].Always = new_data
    end
    return store_success
end

"fallback for transposition table store if table doesn't exist"
store!(::Nothing, _, _, _, _, _)::Bool = false

"retrieve transposition table entry and corrected score, returning nothing if unsuccessful"
function retrieve(table::TranspositionTable{Bucket}, zobrist_hash, cur_depth)
    bucket = get_entry(table, zobrist_hash)
    #no point using TT if hash collision
    if bucket.Depth.zobrist_hash == zobrist_hash
        return bucket.Depth, correct_score(bucket.Depth.score, cur_depth, +1)
    elseif bucket.Always.zobrist_hash == zobrist_hash
        return bucket.Always, correct_score(bucket.Always.score, cur_depth, +1)
    else
        return nothing, nothing
    end
end

"retrieve function barrier in case transposition table doesn't exist, returning nothing"
retrieve(::Nothing, _, _) = (nothing, nothing)

"return PV as vector of strings"
PV_string(PV::Vector{Move})::Vector{String} = map(m -> LONGmove(m), PV)

mutable struct Logger
    best_score::Int16
    pos_eval::Int32
    cumulative_nodes::Int32
    nodes::Int32
    Qnodes::Int32
    cur_depth::UInt8
    stopmidsearch::Bool
    PV::Vector{Move}
    seldepth::UInt8
    TT_cut::Int32
    TT_total::Int32
    hashfull::UInt32
    δt::Float32
end

Logger(TT_entries) = Logger(0, 0, 0, 0, 0, 0, 
                     false, Move[], 0, 0, 
                     TT_entries, 0, 0.0)

"Constant evaluation of stalemate"
eval(::Draw, ply) = Int16(0)
"Constant evaluation of being checkmated (favour quicker mates)"
eval(::Loss, ply) = -INF + Int16(ply)

"Returns score of current position from whites perspective"
function evaluate(board::BoardState)::Int16
    num_pieces = count_pieces(board.pieces)
    score = board.PSTscore[1] * MGweighting(num_pieces) +
            board.PSTscore[2] * EGweighting(num_pieces)
    
    return Int16(round(score))
end

"Search available (move-ordered) captures until we reach quiet positions to evaluate"
function quiescence(engine::EngineState, player::Int8, α, β, ply, logger::Logger)
    if stop_early(engine)
        logger.stopmidsearch = true
        return α 
    end 

    logger.nodes += 1
    logger.Qnodes += 1
    logger.seldepth = max(logger.seldepth,ply)

    #still need to check for terminal nodes in qsearch
    legal_info = gameover!(engine.board)
    if engine.board.state != Neutral()
        return eval(engine.board.state, ply)
    end

    #not in check, continue quiescence
    if legal_info.attack_num == 0
        best_score = player * evaluate(engine.board)
        if best_score > α
            if best_score >= β
                return β
            end
            α = best_score
        end
        moves, attack_count = generate_attacks(engine.board, legal_info)
        score_moves!(moves)

        for i in eachindex(moves)
            next_best!(moves,i)
            move = moves[i]

            make_move!(move,engine.board)
            score = -quiescence(engine, -player, -β, -α, ply+1, logger)
            unmake_move!(engine.board)

            if score > α
                if score >= β
                    clear_current_moves!(engine.board.move_vector, attack_count)
                    return β
                end
                α = score
            end
            if score > best_score
                best_score = score
            end
        end
        clear_current_moves!(engine.board.move_vector, attack_count)
        return best_score

    #in check, must search all legal moves (check extension)
    else
        moves, move_length = generate_moves(engine.board, legal_info)
        score_moves!(moves)

        for i in eachindex(moves)
            next_best!(moves,i)
            move = moves[i]

            make_move!(move,engine.board)
            score = -quiescence(engine, -player, -β, -α, ply+1, logger)
            unmake_move!(engine.board)

            if score > α
                if score >= β
                    clear_current_moves!(engine.board.move_vector, move_length)
                    return β
                end
                α = score
            end
        end
        clear_current_moves!(engine.board.move_vector, move_length)
        return α
    end
end

"returns true if we have run out of time"
check_time(config, safety_factor) = (time() - config.starttime) > (config.control.maxtime * safety_factor)

"return true if channel contains FORCEQUIT message"
check_quit(channel::Channels) = 
    isready(channel.quit) && take!(channel.quit) == :quit

"return false if channel doesn't exist"
check_quit(::Nothing) = false

function stop_early(engine::EngineState{T, Time, Q}, safety_factor=0.97; bypass_check=false) where {T, Q}
    if engine.config.quit_now
        return true
    end

    #reduce number of sys calls
    engine.config.nodes_since_time += 1
    if bypass_check || engine.config.nodes_since_time > CHECKNODES
        engine.config.nodes_since_time = 0
        engine.config.quit_now = check_quit(engine.channel) || check_time(engine.config, safety_factor)
        
        #=
        if config.quit_now
            println("Quitting")
        end=#
    end
    return engine.config.quit_now
end

"returns true if score is a mate score"
mate_found(score) = abs(score) >= INF - MAXMATEDEPTH

"minimax algorithm, tries to maximise own eval and minimise opponent eval"
function minimax(engine::EngineState, player::Int8, α, β, depth, ply, onPV::Bool, logger::Logger)
    if stop_early(engine)
        logger.stopmidsearch = true
        return α 
    end 
    logger.nodes += 1

    #Evaluate whether we are in a terminal node
    legal_info = gameover!(engine.board)
    if engine.board.state != Neutral()
        logger.pos_eval += 1
        return eval(engine.board.state, ply)
    end

    #enter quiescence search if at leaf node
    if depth <= MINDEPTH 
        logger.pos_eval += 1
        if engine.config.quiescence
            return quiescence(engine, player, α, β, ply, logger)
        else 
            return player * evaluate(engine.board)
        end
    end

    best_move = NULLMOVE
    #dont use TT if on PV (still save result of PV search in TT)
    if onPV
        best_move = engine.info.PV[ply+1]
    elseif !isnothing(engine.TT)
        transposition_data, transposition_score = retrieve(engine.TT, engine.board.zobrist_hash, depth)
        if !isnothing(transposition_data)
            #don't try to cutoff if depth of TT entry is too low
            if transposition_data.depth >= depth 
                if transposition_data.type == EXACT
                    logger.TT_cut += 1
                    return transposition_score
                elseif transposition_data.type == BETA && transposition_score >= β
                    logger.TT_cut += 1
                    return β
                elseif transposition_data.type == ALPHA && transposition_score <= α 
                    logger.TT_cut += 1
                    return α
                end
            end
            #we can only use the move stored if we found BETA or EXACT node
            #otherwise it will be a NULLMOVE so won't match in move scoring
            best_move = transposition_data.move
        end
    end

    #figure out type of current node for use in TT and best move
    node_type = ALPHA
    cur_best_move = NULLMOVE   

    moves, move_length = generate_moves(engine.board, legal_info)
    score_moves!(moves, engine.info.Killers[ply+1], best_move)

    for i in eachindex(moves)
        next_best!(moves,i)
        move = moves[i]

        make_move!(move, engine.board)
        score = -minimax(engine, -player, -β, -α, depth-1, ply+1, onPV, logger)
        unmake_move!(engine.board)

        #only first search is on PV
        onPV = false

        #update alpha when better score is found
        if score > α
            #cut when upper bound exceeded
            if score >= β
                #update killers if exceed β
                if !iscapture(move)
                    new_killer!(engine.info.Killers, ply, move)
                end

                if move == best_move
                    logger.TT_cut += 1
                end

                success = store!(engine.TT, engine.board.zobrist_hash, depth, score, BETA, move)
                if success
                    engine.TT_HashFull += 1
                end
                clear_current_moves!(engine.board.move_vector, move_length)
                return β
            end
            node_type = EXACT
            cur_best_move = move
            α = score
            #exact score found, must copy up PV from further down the tree
            copy_PV!(engine.info.PV, ply, engine.info.PV_len, max_depth(engine), move)
        end
    end

    success = store!(engine.TT, engine.board.zobrist_hash, depth, α, node_type, cur_best_move)
    if success
        engine.TT_HashFull += 1
    end
    clear_current_moves!(engine.board.move_vector, move_length)
    return α
end

"root of minimax search"
function root(engine::EngineState, moves, depth, logger::Logger)
    #whites current best score
    α = -INF
    #whites current worst score (blacks best score)
    β = INF
    player::Int8 = sgn(engine.board.colour)
    ply = 0
    #search PV first, only if it exists
    onPV = true 

    #root node is always on PV
    score_moves!(moves, engine.info.Killers[ply+1], engine.info.PV[ply+1])

    for i in eachindex(moves)
        next_best!(moves, i)
        move = moves[i]

        make_move!(move, engine.board)
        score = -minimax(engine, -player, -β, -α, depth-1, ply+1, onPV, logger)
        unmake_move!(engine.board)

        if stop_early(engine)
            logger.stopmidsearch = true
            break
        end

        if score > α
            copy_PV!(engine.info.PV, ply, engine.info.PV_len, max_depth(engine), move)
            α = score
        end
        onPV = false
    end
    return α
end

"Run minimax search to fixed depth then increase depth until time runs out"
function iterative_deepening(engine::EngineState)
    moves, _ = generate_moves(engine.board)
    depth = 0
    logger = Logger(num_entries(engine.TT))
    bestscore = 0

    #Quit early if we or opponent have mate or if we run out of time
    while (depth < max_depth(engine)) &&  
        !(mate_found(bestscore)) &&
        !(stop_early(engine, 0.5, bypass_check=true))

        depth += 1
        logger.cur_depth = depth
        engine.info.PV_len = depth
        bestscore = root(engine, moves, depth, logger)

        update_logger!(engine, logger, bestscore)

        if engine.config.verbose && (time() - engine.config.starttime > 0.05)
            report_progress(engine, logger)
        end
    end
    clear!(engine.board.move_vector)
    return engine.info.PV[1], logger
end

"calculate logging values that are not automatically updated during minimax"
function update_logger!(engine::EngineState, logger::Logger, bestscore)
    logger.PV = engine.info.PV[1:engine.info.PV_len]
    logger.δt = time() - engine.config.starttime
    logger.hashfull = engine.TT_HashFull
    
    #If we stopped midsearch, we still want to add to total nodes and nps (but not when calculating branching factor)
    if !logger.stopmidsearch
        logger.cumulative_nodes += logger.pos_eval
        logger.pos_eval = 0 
        logger.best_score = bestscore
    end
end

"report state of engine at current depth if verbose"
function report_progress(engine::EngineState{T, C, Nothing}, logger::Logger) where {T, C}
    println("Searched depth $(logger.cur_depth) in $(round(time() - engine.config.starttime,sigdigits=4))s. ",
    "Current maxdepth = $(logger.seldepth). ",
    "PV so far: ", PV_string(logger.PV))
end

"report state of engine at current depth if using UCI protocol in verbose mode"
function report_progress(engine::EngineState{T, C, Channels}, logger::Logger) where {T, C}
    if length(logger.PV) > 0 
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
                hashfull = round(Int64, logger.hashfull*1000 / logger.TT_total)
                "tthits $(logger.TT_cut) hashfull $(hashfull) "
            end
        end

        print(buffer, 
        "nodes $(logger.nodes) ",
        "nps $(round(Int64, logger.nodes/logger.δt)) ",
        "qnodes $(logger.Qnodes) ",
        "depth $(logger.cur_depth) ",
        "seldepth $(logger.seldepth) ",
        TT_msg,
        "time $(round(Int64, logger.δt * 1000)) ",
        "pv ")

        for move in logger.PV
            print(buffer, UCImove(engine.board, move), " ")
        end

        put!(engine.channel.info, String(take!(buffer)))
    else
        put!(engine.channel.info, "info no move found")
    end
    yield()
end

"print all logging info to StdOut"
function print_log(logger::Logger)
    if length(logger.PV) > 0
        best ="$(logger.best_score)"
        if mate_found(logger.best_score)
            dist = Int((INF - abs(logger.best_score)) ÷ 2)
            best = logger.best_score > 0 ? "Engine Mate in $dist" : "Opponent Mate in $dist"
        end

        TT_msg = logger.hashfull == 0 ? "" : "TT cuts = $(logger.TT_cut). \
         Hash full = $(round(logger.hashfull*100/logger.TT_total, sigdigits=3))%."

        println("Best = $(LONGmove(logger.PV[1])). \
        Score = "*best*". \
        Nodes = $(logger.nodes) ($(round(logger.nodes/logger.δt,sigdigits=4)) nps). \
        Quiescent nodes = $(logger.Qnodes) ($(round(100*logger.Qnodes/logger.nodes,sigdigits=3))%). \
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

"Evaluates the position to return the best move"
function best_move(engine::EngineState)
    engine.config.starttime = time()
    best_move, logger = iterative_deepening(engine)

    engine.config.quit_now = false
    engine.config.nodes_since_time = UInt32(0)

    return best_move, logger
end
