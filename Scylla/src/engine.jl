#define evaluation constants
const MAXMATEDEPTH::Int16 = Int16(100)
const INF::Int16 = typemax(Int16)
const MATE::Int16 = INF - MAXMATEDEPTH

#maximum search depth
const MAXDEPTH::UInt8 = UInt8(32)
const MINDEPTH::UInt8 = UInt8(0)
const DEFAULTDEPTH::UInt8 = UInt8(20)
const DEFAULTTIME::Float64 = Float64(1.5)
const DEFAULTNODES::UInt32 = UInt32(1e8)
#check for out of time/quit message every x nodes
const CHECKNODES::UInt32 = UInt32(1000)

abstract type Control end

struct Time <: Control
    maxtime::Float64
    maxdepth::UInt8
end

Time() = Time(DEFAULTTIME,DEFAULTDEPTH)
Time(max_t) = Time(max_t,DEFAULTDEPTH)

struct Depth <: Control
    maxdepth::UInt8
end

Depth() = Depth(MAXDEPTH)

struct Nodes <: Control
    maxnodes::UInt64
    maxdepth::UInt8
end

Nodes() = Nodes(DEFAULTNODES,DEFAULTDEPTH)
Nodes(nodes) = Nodes(nodes,DEFAULTDEPTH)

struct Mate <: Control
    maxdepth::UInt8
end

Mate() = Mate(DEFAULTDEPTH)

"different configurations the engine can run in"
mutable struct Config{C <:Control, Q <:Union{Channel,Nothing}} 
    forcequit::Q
    control::C
    starttime::Float64
    nodes_since_time::UInt16
    quit_now::Bool
    quiescence::Bool 
    usingTT::Bool
    debug::Bool
end

function Config(quit::Union{Channel,Nothing},control::Control,usingTT,debug)
    Config(quit,control,time(),UInt16(0),false,true,usingTT,debug)
end

mutable struct SearchInfo
    #Record best moves from root to leaves for move ordering
    PV::Vector{UInt32}
    PV_len::UInt8
    Killers::Vector{Killer}
end

"Constructor for search info struct"
function SearchInfo(depth)
    triangular_PV = NULLMOVE*ones(UInt32,triangle_number(depth))
    killers = [Killer() for _ in 1:depth]
    SearchInfo(triangular_PV,0,killers)
end

#holds all information the engine needs to calculate
mutable struct EngineState{C <:Control, Q <:Union{Channel,Nothing}} 
    board::Boardstate
    TT::Union{TranspositionTable,Nothing}
    config::Config{C,Q}
    info::SearchInfo
end

max_depth(e::EngineState) = e.config.control.maxdepth

const TT_ENTRY_TYPE = Bucket

"Constructor for enginestate given TT size in Mb and boardstate"
function EngineState(FEN::AbstractString=startFEN,verbose=false;
        sizePO2=nothing,sizeMb=nothing,
        comms::Union{Channel,Nothing}=nothing,control::Control=Time()) 

    board = Boardstate(FEN)
    TT = set_TT(verbose;sizePO2=sizePO2,sizeMb=sizeMb)
    config = Config(comms,control,!isnothing(TT),verbose)
    info = SearchInfo(config.control.maxdepth)
    config.starttime = time()
    return EngineState(board,TT,config,info)
end

"set a new TT. by default size in powers of two is unspecified so the default constructor is used"
function set_TT(verbose=false;sizePO2=nothing,sizeMb=nothing)
    if !isnothing(sizeMb)
        return TranspositionTable(TT_ENTRY_TYPE,verbose,sizeMb=sizeMb)
    else
        return TranspositionTable(TT_ENTRY_TYPE,verbose,size=sizePO2)
    end
end

"Reset engine to default boardstate and empty TT"
function reset_engine!(E::EngineState)
    reset_TT!(E)
    E.board = Boardstate(startFEN)
end

"return PV as vector of strings"
PV_string(info::SearchInfo)::Vector{String} = map(m->LONGmove(m), info.PV[1:info.PV_len])

mutable struct Logger
    best_score::Int16
    pos_eval::Int32
    cum_nodes::Int32
    nodes::Int32
    Qnodes::Int32
    cur_depth::UInt8
    stopmidsearch::Bool
    PV::Vector{String}
    seldepth::UInt8
    TT_cut::Int32
    TT_total::Int32
    hashfull::UInt32
    δt::Float32
end

Logger(TT_entries) = Logger(0,0,0,0,0,0,false,String[],0,0,TT_entries,0,0.0)

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
function quiescence(engine::EngineState,player::Int8,α,β,ply,logger::Logger)
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
        best_score = player*evaluate(engine.board)
        if best_score > α
            if best_score >= β
                return β
            end
            α = best_score
        end
        moves = generate_attacks(engine.board,legal_info)
        score_moves!(moves)

        for i in eachindex(moves)
            next_best!(moves,i)
            move = moves[i]

            make_move!(move,engine.board)
            score = -quiescence(engine,-player,-β,-α,ply+1,logger)
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
        moves = generate_moves(engine.board,legal_info)
        score_moves!(moves)

        for i in eachindex(moves)
            next_best!(moves,i)
            move = moves[i]

            make_move!(move,engine.board)
            score = -quiescence(engine,-player,-β,-α,ply+1,logger)
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

function stop_early(config::Config{C},safety_factor=0.98;bypass_check=false) where C<:Time
    if config.quit_now
        return true
    end
    #reduce number of sys calls
    config.nodes_since_time += 1
    if bypass_check || config.nodes_since_time > CHECKNODES
        config.nodes_since_time = 0
        #If we run out of time, return lower bound on score
        config.quit_now = (time() - config.starttime) > (config.control.maxtime*safety_factor)
    end
    return config.quit_now
end

"minimax algorithm, tries to maximise own eval and minimise opponent eval"
function minimax(engine::EngineState,player::Int8,α,β,depth,ply,onPV::Bool,logger::Logger)
    if stop_early(engine.config)
        logger.stopmidsearch = true
        return α 
    end 
    logger.nodes += 1

    #Evaluate whether we are in a terminal node
    legal_info = gameover!(engine.board)
    if engine.board.State != Neutral()
        logger.pos_eval += 1
        value = eval(engine.board.State,ply)
        return value
    end

    #enter quiescence search if at leaf node
    if engine.config.quiescence && depth <= MINDEPTH 
        logger.pos_eval += 1
        return quiescence(engine,player,α,β,ply,logger)
    end

    best_move = NULLMOVE
    #dont use TT if on PV (still save result of PV search in TT)
    if onPV
        best_move = engine.info.PV[ply+1]
    else
        TT_data,TT_score = TT_retrieve!(engine.TT,engine.board.ZHash,depth)
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

    moves = generate_moves(engine.board,legal_info)
    score_moves!(moves,engine.info.Killers[ply+1],best_move)

    for i in eachindex(moves)
        next_best!(moves,i)
        move = moves[i]

        make_move!(move,engine.board)
        score = -minimax(engine,-player,-β,-α,depth-1,ply+1,onPV,logger)
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

                TT_store!(engine.TT,engine.board.ZHash,depth,score,BETA,move,logger)
                return β
            end
            node_type = EXACT
            cur_best_move = move
            α = score
            #exact score found, must copy up PV from further down the tree
            copy_PV!(engine.info.PV,ply,engine.info.PV_len,max_depth(engine),move)
        end
    end

    TT_store!(engine.TT,engine.board.ZHash,depth,α,node_type,cur_best_move,logger)
    return α
end

"Root of minimax search. Deals in moves not scores"
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
    score_moves!(moves,engine.info.Killers[ply+1],engine.info.PV[ply+1])

    for i in eachindex(moves)
        next_best!(moves,i)
        move = moves[i]

        make_move!(move,engine.board)
        score = -minimax(engine,-player,-β,-α,depth-1,ply+1,onPV,logger)
        unmake_move!(engine.board)

        if logger.stopmidsearch
            break
        end

        if score > α
            copy_PV!(engine.info.PV,ply,engine.info.PV_len,max_depth(engine),move)
            α = score
        end
        onPV = false
    end
    return α
end

function report_progress(engine::EngineState,logger::Logger)
    if engine.config.debug && (time() - engine.config.starttime > 0.05)
        println("Searched depth $(logger.cur_depth) in $(round(time()-engine.config.starttime,sigdigits=4))s. Current maxdepth = $(logger.seldepth). PV so far: $(logger.PV)")
    end
end

"Run minimax search to fixed depth then increase depth until time runs out"
function iterative_deepening(engine::EngineState)
    moves = generate_moves(engine.board)
    depth = 0
    logger = Logger(num_entries(engine.TT))
    bestscore = 0

    #Quit early if we or opponent have M1 or if we run out of time
    while (depth < max_depth(engine)) &&  
        !(abs(logger.best_score)==INF-1 || abs(logger.best_score)==INF-2) &&
        !(stop_early(engine.config,0.2,bypass_check=true))

        depth += 1
        logger.cur_depth = depth
        engine.info.PV_len = depth
        bestscore = root(engine,moves,depth,logger)

        logger.PV = PV_string(engine.info)
        report_progress(engine,logger)
        
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
    best ="$(logger.best_score)"
    if abs(logger.best_score) >= INF - MAXMATEDEPTH
        dist = Int((INF - abs(logger.best_score))÷2)
        best = logger.best_score > 0 ? "Engine Mate in $dist" : "Opponent Mate in $dist"
    end

    println("Best = $(logger.PV[1]). \
    Score = "*best*". \
    Nodes = $(logger.nodes) ($(round(logger.nodes/logger.δt,sigdigits=4)) nps). \
    Quiescent nodes = $(logger.Qnodes) ($(round(100*logger.Qnodes/logger.nodes,sigdigits=3))%). \
    Depth = $((logger.cur_depth)). \
    Max ply = $(logger.seldepth). \
    TT cuts = $(logger.TT_cut). \
    Hash full = $(round(logger.hashfull*100/logger.TT_total,sigdigits=3))%. \
    Time = $(round(logger.δt,sigdigits=6))s.")

    if logger.stopmidsearch
        println("Ran out of time mid search.")
    end
    println("#"^100)
end

"Evaluates the position to return the best move"
function best_move(engine::EngineState)
    println(time()-engine.config.starttime)
    t = time()
    best_move,logger = iterative_deepening(engine)
    logger.δt = time() - t

    best_move != NULLMOVE || error("Failed to find move better than null move")

    return best_move,logger
end
