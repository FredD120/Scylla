#Define PV, Killers, MVV-LVA table
#Score move using above heuristics
#Dynamically push next best move to top of list

"Store two best quiet moves for a given ply"
mutable struct Killer
    first::Move
    second::Move
end

"Construct killers with null moves"
Killer() = Killer(NULLMOVE, NULLMOVE)

const DEFAULT_KILLER = Killer()

"Check that new move does not match second best killer, then push first to second and replace first"
function new_killer!(killer_vec::Vector{Killer}, ply, move)
    if move != killer_vec[ply + 1].first
        @inbounds killer_vec[ply + 1].second = killer_vec[ply + 1].first 
        @inbounds killer_vec[ply + 1].first = move 
    end
end

"Triangle number for an index starting from zero"
triangle_number(x) = Int(0.5 * x * (x + 1))

"find index of PV move at current ply"
pv_ind(ply, maxdepth) = Int(ply / 2 * (2 * maxdepth + 1 - ply))

"Copies line below in triangular PV table"
function copy_pv!(triangle_pv, ply, pv_len, maxdepth, move)
    cur_ind = pv_ind(ply, maxdepth)
    @inbounds triangle_pv[cur_ind + 1] = move
    for i in (cur_ind + 1):(cur_ind + pv_len - ply - 1)
        @inbounds triangle_pv[i + 1] = triangle_pv[i + maxdepth - ply]
    end
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
function score_moves!(moves::AbstractArray, killers::Killer=DEFAULT_KILLER, best_move::Move=NULLMOVE)
    @inbounds for (i, move) in enumerate(moves)
        if move == best_move
            moves[i] = set_score(move, MAXMOVESCORE)

        #sort captures
        elseif iscapture(move)
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

