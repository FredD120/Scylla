#define evaluation constants
const MAXMATEDEPTH::Int16 = Int16(100)
const INF::Int16 = typemax(Int16)
const MATE::Int16 = INF - MAXMATEDEPTH

"different configurations the engine can run in"
mutable struct Config{C <:Control, Q <:Union{Channel,Nothing}} 
    forcequit::Q
    control::C
    starttime::Float64
    nodes_since_time::UInt32
    quit_now::Bool
    quiescence::Bool 
    debug::Bool
end

function Config(quit::Union{Channel,Nothing},control::Control,debug)
    Config(quit,control,time(),UInt32(0),false,true,debug)
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

#holds all information the engine needs to calculate
mutable struct EngineState
    board::Boardstate
    TT::Union{TranspositionTable, Nothing}
    TT_HashFull::UInt32
    config::Config
    info::SearchInfo
end

max_depth(e::EngineState) = e.config.control.maxdepth

"Constructor for enginestate given TT size in Mb and boardstate"
function EngineState(FEN::AbstractString=startFEN, verbose=false;
        sizeMb=TT_DEFAULT_MB, sizePO2=nothing, TT_type=TT_ENTRY_TYPE,
        comms::Union{Channel,Nothing}=nothing, control::Control=Time()) 

    board = Boardstate(FEN)
    TT = TranspositionTable(verbose; size=sizePO2, sizeMb=sizeMb, type=TT_type)
    config = Config(comms, control, verbose)
    info = SearchInfo(config.control.maxdepth)
    return EngineState(board, TT, UInt32(0), config, info)
end

"assign a TT to an engine"
function assign_TT!(E::EngineState;
    sizeMb=TT_DEFAULT_MB, sizePO2=nothing, TT_type=TT_ENTRY_TYPE)
    E.TT = TranspositionTable(E.config.debug,
    sizeMb=sizeMb, size=sizePO2, type=TT_type)
    E.TT_HashFull = UInt32(0)
end

"Reset entries of engine's TT to default value"
function reset_TT!(E::EngineState)
    reset_TT!(E.TT)
    E.TT_HashFull = UInt32(0)
end

"Reset engine to default boardstate and empty TT"
function reset_engine!(E::EngineState)
    reset_TT!(E)
    E.board = Boardstate(startFEN)
end

"update entry in TT. either greater depth or always replace"
function TT_store!(engine::EngineState, ZHash, depth, score, node_type, best_move)
    if !isnothing(engine.TT)
        TT_view = view_entry(engine.TT, ZHash)
        #correct mate scores in TT
        score = correct_score(score, depth,-1)
        new_data = SearchData(ZHash, depth, score, node_type, best_move)
        if depth >= TT_view[].Depth.depth
            if TT_view[].Depth.type == NONE
              engine.TT_HashFull += 1
            end  
            TT_view[].Depth = new_data
        else
            if TT_view[].Always.type == NONE
              engine.TT_HashFull += 1
            end
            TT_view[].Always = new_data
        end
    end
end

"retrieve TT entry and corrected score, also returning true if retrieval successful"
function TT_retrieve!(engine::EngineState, ZHash, cur_depth)
    bucket = get_entry(engine.TT, ZHash)
    #no point using TT if hash collision
    if bucket.Depth.ZHash == ZHash
        return bucket.Depth, correct_score(bucket.Depth.score, cur_depth,+1)
    elseif bucket.Always.ZHash == ZHash
        return bucket.Always, correct_score(bucket.Always.score, cur_depth,+1)
    else
        return nothing, nothing
    end
end

"return PV as vector of strings"
PV_string(PV::Vector{Move})::Vector{String} = map(m->LONGmove(m), PV)

mutable struct Logger
    best_score::Int16
    pos_eval::Int32
    cum_nodes::Int32
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
eval(::Draw,ply) = Int16(0)
"Constant evaluation of being checkmated (favour quicker mates)"
eval(::Loss,ply) = -INF + Int16(ply)

"Returns score of current position from whites perspective"
function evaluate(board::Boardstate)::Int16
    num_pieces = count_pieces(board.pieces)
    score = board.PSTscore[1]*MGweighting(num_pieces) + board.PSTscore[2]*EGweighting(num_pieces)
    
    return Int16(round(score))
end

"Search available (move-ordered) captures until we reach quiet positions to evaluate"
function quiescence(engine::EngineState, player::Int8, α, β, ply, logger::Logger)
    if stop_early(engine.config)
        logger.stopmidsearch = true
        return α 
    end 

    logger.nodes += 1
    logger.Qnodes += 1
    logger.seldepth = max(logger.seldepth,ply)

    #still need to check for terminal nodes in qsearch
    legal_info = gameover!(engine.board)
    if engine.board.State != Neutral()
        return eval(engine.board.State,ply)
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
        moves = generate_attacks(engine.board, legal_info)
        score_moves!(moves)

        for i in eachindex(moves)
            next_best!(moves,i)
            move = moves[i]

            make_move!(move,engine.board)
            score = -quiescence(engine, -player, -β, -α, ply+1, logger)
            unmake_move!(engine.board)

            if score > α
                if score >= β
                    return β
                end
                α = score
            end
            if score > best_score
                best_score = score
            end
        end
        return best_score

    #in check, must search all legal moves (check extension)
    else
        moves = generate_moves(engine.board, legal_info)
        score_moves!(moves)

        for i in eachindex(moves)
            next_best!(moves,i)
            move = moves[i]

            make_move!(move,engine.board)
            score = -quiescence(engine, -player, -β, -α, ply+1, logger)
            unmake_move!(engine.board)

            if score > α
                if score >= β
                    return β
                end
                α = score
            end
        end
        return α
    end
end

"returns true if we have run out of time"
check_time(config,safety_factor) = (time() - config.starttime) > (config.control.maxtime * safety_factor)

"return true if channel contains FORCEQUIT message"
check_quit(config::Config{C,Q}) where {C<:Control,Q<:Channel} = 
    isready(config.forcequit) && take!(config.forcequit) == FORCEQUIT()

"return false if channel doesn't exist"
check_quit(::Config{C,Q}) where {C<:Control,Q<:Nothing} = false

function stop_early(config::Config{C}, safety_factor=0.98; bypass_check=false) where C<:Time
    if config.quit_now
        return true
    end

    #reduce number of sys calls
    config.nodes_since_time += 1
    if bypass_check || config.nodes_since_time > CHECKNODES
        config.nodes_since_time = 0
        config.quit_now = check_quit(config) || check_time(config,safety_factor)
        
        #=
        if config.quit_now
            println("Quitting")
        end=#
    end
    return config.quit_now
end

"returns true if score is a mate score"
mate_found(score) = abs(score) >= INF - MAXMATEDEPTH

"minimax algorithm, tries to maximise own eval and minimise opponent eval"
function minimax(engine::EngineState, player::Int8, α, β, depth, ply, onPV::Bool, logger::Logger)
    if stop_early(engine.config)
        logger.stopmidsearch = true
        return α 
    end 
    logger.nodes += 1

    #Evaluate whether we are in a terminal node
    legal_info = gameover!(engine.board)
    if engine.board.State != Neutral()
        logger.pos_eval += 1
        return eval(engine.board.State, ply)
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
        TT_data, TT_score = TT_retrieve!(engine, engine.board.ZHash, depth)
        if !isnothing(TT_data)
            #don't try to cutoff if depth of TT entry is too low
            if TT_data.depth >= depth 
                if TT_data.type == EXACT
                    logger.TT_cut += 1
                    return TT_score
                elseif TT_data.type == BETA && TT_score >= β
                    logger.TT_cut += 1
                    return β
                elseif TT_data.type == ALPHA && TT_score <= α 
                    logger.TT_cut += 1
                    return α
                end
            end
            #we can only use the move stored if we found BETA or EXACT node
            #otherwise it will be a NULLMOVE so won't match in move scoring
            best_move = TT_data.move
        end
    end

    #figure out type of current node for use in TT and best move
    node_type = ALPHA
    cur_best_move = NULLMOVE   

    moves = generate_moves(engine.board, legal_info)
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
                    new_killer!(engine.info.Killers,ply,move)
                end

                if move == best_move
                    logger.TT_cut += 1
                end

                TT_store!(engine,engine.board.ZHash,depth,score,BETA,move)
                return β
            end
            node_type = EXACT
            cur_best_move = move
            α = score
            #exact score found, must copy up PV from further down the tree
            copy_PV!(engine.info.PV, ply, engine.info.PV_len, max_depth(engine), move)
        end
    end

    TT_store!(engine, engine.board.ZHash, depth, α, node_type, cur_best_move)
    return α
end

"root of minimax search"
function root(engine::EngineState,moves,depth,logger::Logger)
    #whites current best score
    α = -INF 
    #whites current worst score (blacks best score)
    β = INF
    player::Int8 = sgn(engine.board.Colour)
    ply = 0
    #search PV first, only if it exists
    onPV = true 

    #root node is always on PV
    score_moves!(moves, engine.info.Killers[ply+1], engine.info.PV[ply+1])

    for i in eachindex(moves)
        next_best!(moves,i)
        move = moves[i]

        make_move!(move, engine.board)
        score = -minimax(engine, -player, -β, -α, depth-1, ply+1, onPV, logger)
        unmake_move!(engine.board)

        if stop_early(engine.config)
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

function report_progress(engine::EngineState, logger::Logger)
    if engine.config.debug && (time() - engine.config.starttime > 0.05)
        println("Searched depth $(logger.cur_depth) in $(round(time()-engine.config.starttime,sigdigits=4))s. ",
        "Current maxdepth = $(logger.seldepth). ",
        "PV so far: ", PV_string(logger.PV))
    end
end

"Run minimax search to fixed depth then increase depth until time runs out"
function iterative_deepening(engine::EngineState)
    moves = generate_moves(engine.board)
    depth = 0
    logger = Logger(num_entries(engine.TT))
    bestscore = 0

    #Quit early if we or opponent have mate or if we run out of time
    while (depth < max_depth(engine)) &&  
        !(mate_found(bestscore)) &&
        !(stop_early(engine.config, 0.5, bypass_check=true))

        depth += 1
        logger.cur_depth = depth
        engine.info.PV_len = depth
        bestscore = root(engine, moves, depth, logger)

        logger.PV = engine.info.PV[1:engine.info.PV_len]
        report_progress(engine, logger)
        
        #If we stopped midsearch, we still want to add to total nodes and nps (but not when calculating branching factor)
        if !logger.stopmidsearch
            logger.cum_nodes += logger.pos_eval
            logger.pos_eval = 0 
            logger.best_score = bestscore
        end
    end
    return engine.info.PV[1], logger
end

"print all logging info to StdOut"
function print_log(logger::Logger)
    if length(logger.PV) > 0
        best ="$(logger.best_score)"
        if mate_found(logger.best_score)
            dist = Int((INF - abs(logger.best_score)) ÷ 2)
            best = logger.best_score > 0 ? "Engine Mate in $dist" : "Opponent Mate in $dist"
        end

        TT_msg = logger.hashfull == 0 ? "" : "TT cuts = $(logger.TT_cut).\
         Hash full = $(round(logger.hashfull*100/logger.TT_total,sigdigits=3))%."

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

"print results of search, formatted for UCI protocol"
function UCI_log(logger::Logger, board::Boardstate)
    if length(logger.PV) > 0
        best = begin score = logger.best_score
            if mate_found(score)
                dist = Int((INF - abs(score))÷2)
                score > 0 ? "mate $dist" : "mate -$dist"
            else
                "cp $score"
            end
        end

        TT_msg = begin
            if logger.hashfull == 0 
                "" 
            else
                hashfull = round(Int64, logger.hashfull*1000 / logger.TT_total)
                "tthits $(logger.TT_cut) hashfull $(hashfull) "
            end
        end

        print("info score " * best * " ",
        "nodes $(logger.nodes) ",
        "nps $(round(Int64, logger.nodes/logger.δt)) ",
        "qnodes $(logger.Qnodes) ",
        "depth $(logger.cur_depth) ",
        "seldepth $(logger.seldepth) ",
        TT_msg,
        "time $(round(Int64, logger.δt * 1000)) ",
        "pv ")

        for move in logger.PV
            print(UCImove(board, move), " ")
        end

        println("")
    else
        error("Failed to find move")
    end
end

"Evaluates the position to return the best move"
function best_move(engine::EngineState)
    engine.config.starttime = time()
    best_move, logger = iterative_deepening(engine)

    logger.δt = time() - engine.config.starttime
    logger.hashfull = engine.TT_HashFull

    engine.config.quit_now = false
    engine.config.nodes_since_time = UInt32(0)

    return best_move, logger
end
