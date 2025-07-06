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

"Store two best quiet moves for a given ply"
mutable struct Killer
    First::UInt32
    Second::UInt32
end

"Construct killers with null moves"
Killer() = Killer(NULLMOVE,NULLMOVE)

"Check that new move does not match second best killer, then push first to second and replace first"
function new_killer!(KV::Vector{Killer},ply,move)
    if move != KV[ply+1].First
        KV[ply+1].Second = KV[ply+1].First 
        KV[ply+1].First = move 
    end
end

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

"Triangle number for an index starting from zero"
triangle_number(x) = Int(0.5*x*(x+1))

"Constructor for search info struct"
function SearchInfo(t_max,maxdepth=MAXDEPTH)
    triangular_PV = NULLMOVE*ones(UInt32,triangle_number(maxdepth))
    killers = [Killer() for _ in 1:maxdepth]
    SearchInfo(time(),t_max,maxdepth,triangular_PV,0,0,killers)
end

"find index of PV move at current ply"
PV_ind(ply,maxdepth) = Int(ply/2 * (2*maxdepth + 1 - ply))

"Copies line below in triangular PV table"
function copy_PV!(triangle_PV,ply,PV_len,maxdepth,move)
    cur_ind = PV_ind(ply,maxdepth)
    triangle_PV[cur_ind+1] = move
    for i in (cur_ind+1):(cur_ind+PV_len-ply-1)
        triangle_PV[i+1] = triangle_PV[i+maxdepth-ply]
    end
end

"return PV as string"
PV_string(info::SearchInfo) = "$([LONGmove(m) for m in info.PV[1:info.PV_len]])"

"types of nodes based on position in search tree"
const NONE = UInt8(0)
const ALPHA = UInt8(1)
const BETA = UInt8(2)
const EXACT = UInt8(3)

"data describing a node, to be stored in TT"
struct SearchData
    ZHash::UInt64
    depth::UInt8
    score::Int16
    type::UInt8
    move::UInt32
end

"generic constructor for search data"
SearchData() = SearchData(UInt64(0),UInt8(0),Int16(0),NONE,NULLMOVE)

"store multiple entries at same Zkey, with different replace schemes"
mutable struct Bucket
    Depth::SearchData
    Always::SearchData
end
"construct bucket with two entries"
Bucket() = Bucket(SearchData(),SearchData())

const TTSIZE::UInt8 = UInt8(18)
"create transposition table in global state so it persists between moves"
const TT = TranspositionTable(TTSIZE,Bucket,true)
const TT_ENTRIES = 2*2^TTSIZE

global cur_TT_entries::Int32 = 0

"add depth to score when storing and remove when retrieving"
function correct_score(score,depth,sgn)::Int16
    if score > MATE
        score += Int16(sgn*depth)
    elseif score < -MATE
        score -= Int16(sgn*depth)
    end
    return score
end

"update entry in TT. currently always replace"
function TT_store!(ZHash,depth,score,node_type,best_move,logger)
    if !isnothing(TT)
        TT_view = view_entry(TT,ZHash)
        #correct mate scores in TT
        score = correct_score(score,depth,-1)
        new_data = SearchData(ZHash,depth,score,node_type,best_move)
        if depth >= TT_view[].Depth.depth
            if TT_view[].Depth.type == NONE
              logger.hashfull += 1
            end  
            TT_view[].Depth = new_data
        else
            if TT_view[].Always.type == NONE
              logger.hashfull += 1
            end
            TT_view[].Always = new_data
        end
    end
end

"retrieve TT entry, returning nothing if there is no entry"
function TT_retrieve!(ZHash,cur_depth)
    if !isnothing(TT)
        bucket = get_entry(TT,ZHash)
        #no point using TT if hash collision
        if bucket.Depth.ZHash == ZHash
            return bucket.Depth, correct_score(bucket.Depth.score,cur_depth,+1)
        elseif bucket.Always.ZHash == ZHash
            return bucket.Always, correct_score(bucket.Always.score,cur_depth,+1)
        end
    end
    return nothing,nothing
end

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

#number of pieces left when endgame begins
const EGBEGIN = 12

const MG_grad = -1/(EGBEGIN+2)

"If more than EGBEGIN+2 pieces lost, set to 0. Between 0 and EGBEGIN+2 pieces lost, decrease linearly from 1 to 0"
function MGweighting(pc_remaining)::Float32 
    pc_lost = 24 - pc_remaining
    weight = 1 + MG_grad*pc_lost
    return max(0,weight)
end

const EG_grad = -1/EGBEGIN

"If more than EGBEGIN+2 pieces remaining, set to 0. Between EGBEGIN+2 and 2 remaining increase linearly to 1"
function EGweighting(pc_remaining)::Float32 
    weight = 1 + EG_grad*(pc_remaining-2)
    return max(0,weight)
end

"Returns score of current position from whites perspective"
function evaluate(board::Boardstate)::Int16
    num_pieces = count_pieces(board.pieces)
    score = board.PSTscore[1]*MGweighting(num_pieces) + board.PSTscore[2]*EGweighting(num_pieces)
    
    return Int16(round(score))
end

#Score of PV/TT move = 255
const MAXMOVESCORE::UInt8 = typemax(UInt8)
#Minimum capture score = 199
const MINCAPSCORE::UInt8 = MAXMOVESCORE - 56

"""
Attackers
↓ Q  R  B  N  P <- Victims
K 50 40 30 30 10
Q 51 41 31 31 11
R 52 42 32 32 12
B 53 43 33 33 13
N 53 43 33 33 13
P 55 45 35 35 15
"""
const MV_LV = UInt8[
    50, 40, 30, 30, 10,
    51, 41, 31, 31, 11,
    52, 42, 32, 32, 12,
    53, 43, 33, 33, 13,
    53, 43, 33, 33, 13,
    55, 45, 35, 35, 15]

"lookup value of capture in MVV_LVA table"
MVV_LVA(victim,attacker)::UInt8 = MINCAPSCORE + MV_LV[5*(attacker-1)+victim-1]

"swap the positions of two entries in a vector"
function swap!(list,ind1,ind2)
    temp = list[ind1]
    list[ind1] = list[ind2]
    list[ind2] = temp
end

"iterates through scores and swaps next best score and move to top of list"
function next_best!(moves,cur_ind)
    len = length(moves)
    if cur_ind < len
        cur_best_score = 0
        cur_best_ind = cur_ind

        for i in cur_ind:len
            score_i = score(moves[i])
            if score_i > cur_best_score
                cur_best_score = score_i
                cur_best_ind = i 
            end
        end
        swap!(moves,cur_ind,cur_best_ind)
    end
end

"Score moves based on PV/TT move, MVV-LVA and killers"
function score_moves!(moves,killers::Killer=Killer(),best_move::UInt32=NULLMOVE)
    for (i,move) in enumerate(moves)
        if move == best_move
            moves[i] = set_score(move,MAXMOVESCORE)

        #sort captures
        elseif iscapture(move)
            moves[i] = set_score(move,MVV_LVA(cap_type(move),pc_type(move)))

        #sort quiet moves
        else
            if move == killers.First
                moves[i] = set_score(move,MINCAPSCORE-UInt8(1))
            elseif move == killers.Second
                moves[i] = set_score(move,MINCAPSCORE-UInt8(2))
            end
        end
    end
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