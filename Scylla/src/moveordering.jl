#Define PV, Killers, MVV-LVA table
#Score move using above heuristics
#Dynamically push next best move to top of list

"store two best quiet moves for a given ply"
mutable struct Killer
    first::Move
    second::Move
end

"construct killers with null moves"
Killer() = Killer(NULLMOVE, NULLMOVE)

const DEFAULT_KILLER = Killer()

"check that new move does not match second best killer, then push first to second and replace first"
function new_killer!(killer_vec::Vector{Killer}, ply, move)
    move = remove_score(move)
    if move != killer_vec[ply + 1].first
        @inbounds killer_vec[ply + 1].second = killer_vec[ply + 1].first 
        @inbounds killer_vec[ply + 1].first = move 
    end
end

mutable struct SearchInfo
    #Record best moves from root to leaves for move ordering
    pv::Vector{Move}
    pv_len::Vector{UInt8}
    pv_offsets::Vector{UInt16}
    killers::Vector{Killer}
end

"Constructor for search info struct"
function SearchInfo(depth)
    triangular_pv = nulls(triangle_number(depth))
    killers = [Killer() for _ in 1:depth]
    pv_lens = zeros(UInt8, depth)
    pv_offs = [pv_ind(ply, depth) for ply in 0:depth-1]
    SearchInfo(triangular_pv, pv_lens, pv_offs, killers)
end

function reset_search_info!(info::SearchInfo)
    depth = length(info.killers)

    info.pv = nulls(triangle_number(depth))
    info.killers = [Killer() for _ in 1:depth]
    info.pv_len = zeros(UInt8, depth)
    info.pv_offsets = [pv_ind(ply, depth) for ply in 0:depth-1]
end

"triangle number for an index starting from zero"
triangle_number(x) = Int(0.5 * x * (x + 1))

"find the index of the first move in the PV at a given ply"
pv_ind(ply, maxdepth) = Int(ply / 2 * (2 * maxdepth + 1 - ply))

"assume new PV length at each ply is zero until proven otherwise"
function reset_pv_lens!(info::SearchInfo)
    maxdepth = length(info.pv_len)
    info.pv_len = zeros(UInt8, maxdepth)
end

"copies line below in triangular PV table"
function copy_pv!(info::SearchInfo, ply, move)
    # 1-based indexes of current and next ply
    ply_cur = ply + 1
    ply_next = ply + 2

    # 0-based indexes into PV array
    cur_ind = info.pv_offsets[ply_cur]
    lower_ind = info.pv_offsets[ply_next]

    @inbounds info.pv[cur_ind + 1] = remove_score(move)
    lower_pv_len = info.pv_len[ply_next]
    for i in 1:lower_pv_len # i is a 1-based index
        @inbounds info.pv[cur_ind + i + 1] = info.pv[lower_ind + i]
    end
    # update pv len at current ply
    info.pv_len[ply_cur] = lower_pv_len + 1
end

"lookup value of capture in MVV_LVA table"
most_least_value(victim, attacker)::UInt8 = MINCAPSCORE + MVV_LVA[5 * (attacker - 1) + victim - 1]

"swap the positions of two entries in a vector"
function swap!(list, ind1, ind2)
    temp = list[ind1]
    list[ind1] = list[ind2]
    list[ind2] = temp
end

"iterates through scores and swaps next best score and move to top of list"
function next_best!(moves, cur_ind)
    len = length(moves)
    if cur_ind < len
        cur_best_score = 0
        cur_best_ind = cur_ind

        @inbounds for i in cur_ind:len
            score_i = score(moves[i])
            if score_i > cur_best_score
                cur_best_score = score_i
                cur_best_ind = i 
            end
        end
        swap!(moves, cur_ind, cur_best_ind)
    end
end

"Score moves based on PV/TT move, MVV-LVA and killers"
@inline function score_moves!(moves::AbstractArray, killers::Killer=DEFAULT_KILLER, best_move::Move=NULLMOVE)
    # TODO: ensure that wherever moves are stored (PV, TT, killers), their score is removed first
    @inbounds for (i, move) in enumerate(moves)
        if move == best_move
            moves[i] = set_score(move, MAXMOVESCORE)

        #sort captures
        elseif is_capture(move)
            moves[i] = set_score(move, most_least_value(cap_type(move), pc_type(move)))

        #sort quiet moves
        else
            if move == killers.first
                moves[i] = set_score(move, MINCAPSCORE - UInt8(1))
            elseif move == killers.second
                moves[i] = set_score(move, MINCAPSCORE - UInt8(2))
            end
        end
    end
end