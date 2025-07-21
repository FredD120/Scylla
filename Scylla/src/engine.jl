#=
CURRENT
-> Evaluate positions based on piece value and piece square tables
-> Minimax with alpha beta pruning tree search
-> Iterative deepening
-> Move ordering: 
    -PV
    -MVV-LVA 
    -Killer moves
-> Quiescence search
-> Check extension
-> Transposition table

TO-DO
-> Null move pruning
-> Delta/futility pruning
-> PVS
-> Texel tuned PSTs
-> LMR + history
-> NNUE

TO THINK ABOUT
#When adding extensions, eg.for checks, we will exceed PV triangular ply and Killer ply
#Need to check for FIDE draws like KNk,KBk as well as unforcable draws like KNkb
#making score an Int16 would fit better in TT
=#

#define evaluation constants
const INF::Int16 = typemax(Int16)
const MATE::Int16 = INF - Int16(100)

#maximum search depth
const MAXDEPTH::UInt8 = UInt8(24)
const MINDEPTH::UInt8 = UInt8(0)

mutable struct SearchInfo
    #Break out early with current best score if OOT
    starttime::Float64
    maxtime::Float64
    maxdepth::UInt8
    #Record best moves from root to leaves for move ordering
    PV::Vector{UInt32}
    PV_len::UInt8
    nodes_since_time::UInt16
    Killers::Vector{Killer}
end

"Constructor for search info struct"
function SearchInfo(t_max,maxdepth=MAXDEPTH)
    triangular_PV = NULLMOVE*ones(UInt32,triangle_number(maxdepth))
    killers = [Killer() for _ in 1:maxdepth]
    SearchInfo(time(),t_max,maxdepth,triangular_PV,0,0,killers)
end

"return PV as string"
PV_string(info::SearchInfo) = "$([LONGmove(m) for m in info.PV[1:info.PV_len]])"

mutable struct Logger
    best_score::Int16
    pos_eval::Int32
    cum_nodes::Int32
    nodes::Int32
    Qnodes::Int32
    cur_depth::UInt8
    stopmidsearch::Bool
    PV::String
    seldepth::UInt8
    TT_cut::Int32
    hashfull::UInt32
end

Logger() = Logger(0,0,0,0,0,0,false,"",0,0,0)

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
function quiescence(board::Boardstate,player::Int8,α,β,ply,info::SearchInfo,logger::Logger)
    info.nodes_since_time += 1
    if info.nodes_since_time > 500 
        #If we run out of time, return lower bound on score
        if (time() - info.starttime) > info.maxtime*0.95
            logger.stopmidsearch = true
            return α     
        end
        info.nodes_since_time = 0
    end
    
    logger.nodes += 1
    logger.Qnodes += 1
    logger.seldepth = max(logger.seldepth,ply)

    #still need to check for terminal nodes in qsearch
    legal_info = gameover!(board)
    if board.State != Neutral()
        return eval(board.State,ply)
    end

    if legal_info.attack_num == 0
        best_score = player*evaluate(board)
        if best_score > α
            if best_score >= β
                return β
            end
            α = best_score
        end
        moves = generate_attacks(board,legal_info)
        score_moves!(moves)

        for i in eachindex(moves)
            next_best!(moves,i)
            move = moves[i]

            make_move!(move,board)
            score = -quiescence(board,-player,-β,-α,ply+1,info,logger)
            unmake_move!(board)

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

    else
        moves = generate_moves(board,legal_info)
        score_moves!(moves)

        for i in eachindex(moves)
            next_best!(moves,i)
            move = moves[i]

            make_move!(move,board)
            score = -quiescence(board,-player,-β,-α,ply+1,info,logger)
            unmake_move!(board)

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

"minimax algorithm, tries to maximise own eval and minimise opponent eval"
function minimax(board::Boardstate,player::Int8,α,β,depth,ply,onPV::Bool,info::SearchInfo,logger::Logger)
    #reduce number of sys calls
    info.nodes_since_time += 1
    if info.nodes_since_time > 500
        #If we run out of time, return lower bound on score
        if (time() - info.starttime) > (info.maxtime*0.98) #allow for small overhead
            logger.stopmidsearch = true
            return α     
        end
        info.nodes_since_time = 0
    end
    logger.nodes += 1

    #Evaluate whether we are in a terminal node
    legal_info = gameover!(board)
    if board.State != Neutral()
        logger.pos_eval += 1
        value = eval(board.State,ply)
        return value
    end

    #enter quiescence search if at leaf node
    if depth <= MINDEPTH
        logger.pos_eval += 1
        return quiescence(board,player,α,β,ply,info,logger)
    end

    best_move = NULLMOVE
    #dont use TT if on PV (still save result of PV search in TT)
    if onPV
        best_move = info.PV[ply+1]
    else
        TT_data,TT_score = TT_retrieve!(board.ZHash,depth)
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

    moves = generate_moves(board,legal_info)
    score_moves!(moves,info.Killers[ply+1],best_move)

    for i in eachindex(moves)
        next_best!(moves,i)
        move = moves[i]

        make_move!(move,board)
        score = -minimax(board,-player,-β,-α,depth-1,ply+1,onPV,info,logger)
        unmake_move!(board)

        #only first search is on PV
        onPV = false

        #update alpha when better score is found
        if score > α
            #cut when upper bound exceeded
            if score >= β
                #update killers if exceed β
                if !iscapture(move)
                    new_killer!(info.Killers,ply,move)
                end

                if move == best_move
                    logger.TT_cut += 1
                end

                TT_store!(board.ZHash,depth,score,BETA,move,logger)
                return β
            end
            node_type = EXACT
            cur_best_move = move
            α = score
            #exact score found, must copy up PV from further down the tree
            copy_PV!(info.PV,ply,info.PV_len,info.maxdepth,move)
        end
    end

    TT_store!(board.ZHash,depth,α,node_type,cur_best_move,logger)
    return α
end

"Root of minimax search. Deals in moves not scores"
function root(board,moves,depth,info::SearchInfo,logger::Logger)
    #whites current best score
    α = -INF 
    #whites current worst score (blacks best score)
    β = INF
    player::Int8 = sgn(board.Colour)
    ply = 0
    #search PV first, only if it exists
    onPV = true 

    #root node is always on PV
    score_moves!(moves,info.Killers[ply+1],info.PV[ply+1])

    for i in eachindex(moves)
        next_best!(moves,i)
        move = moves[i]

        make_move!(move,board)
        score = -minimax(board,-player,-β,-α,depth-1,ply+1,onPV,info,logger)
        unmake_move!(board)

        if logger.stopmidsearch
            break
        end

        if score > α
            copy_PV!(info.PV,ply,info.PV_len,info.maxdepth,move)
            α = score
        end
        onPV = false
    end
    return α
end

"Run minimax search to fixed depth then increase depth until time runs out"
function iterative_deepening(board::Boardstate,T_MAX,verbose::Bool)
    moves = generate_moves(board)
    depth = 0
    logger = Logger()
    info = SearchInfo(T_MAX)
    bestscore = 0

    #Quit early if we or opponent have M1
    while (depth < info.maxdepth) &&  
        !(abs(logger.best_score)==INF-1 || abs(logger.best_score)==INF-2)
        #If we run out of time, cancel next iteration
        if (time() - info.starttime) > 0.2*T_MAX
            break
        end

        depth += 1
        logger.cur_depth = depth
        info.PV_len = depth
        bestscore = root(board,moves,depth,info,logger)

        logger.PV = PV_string(info)
        if verbose
            println("Searched depth $(logger.cur_depth) in $(round(time()-info.starttime,sigdigits=4))s. Current maxdepth = $(logger.seldepth). PV so far: "*logger.PV)
        end
        
        if !logger.stopmidsearch
            logger.cum_nodes += logger.pos_eval
            logger.pos_eval = 0
            logger.best_score = bestscore 
        end
    end

    return info.PV[1], logger
end

"Evaluates the position to return the best move"
function best_move(board::Boardstate,T_MAX,logging=false)
    t = time()
    best_move,logger = iterative_deepening(board,T_MAX,logging)
    δt = time() - t

    best_move != NULLMOVE || error("Failed to find move better than null move")

    if logging
        best ="$(logger.best_score)"
        if abs(logger.best_score) >= INF - 100
            dist = Int((INF - abs(logger.best_score))÷2)
            best = logger.best_score > 0 ? "Engine Mate in $dist" : "Opponent Mate in $dist"
        end
        global cur_TT_entries += logger.hashfull

        #If we stopped midsearch, we still want to add to total nodes and nps (but not when calculating branching factor)

        println("Best = $(LONGmove(best_move)). \
        Score = "*best*". \
        Nodes = $(logger.nodes) ($(round(logger.nodes/δt,sigdigits=4)) nps). \
        Quiescent nodes = $(logger.Qnodes) ($(round(100*logger.Qnodes/logger.nodes,sigdigits=3))%). \
        Depth = $((logger.cur_depth)). \
        Max ply = $(logger.seldepth). \
        TT cuts = $(logger.TT_cut). \
        Hash full = $(round(cur_TT_entries*100/TT_ENTRIES,sigdigits=3))%. \
        Time = $(round(δt,sigdigits=6))s.")

        if logger.stopmidsearch
            println("Ran out of time mid search.")
        end
        println("#"^100)
    end
    return best_move,logger
end