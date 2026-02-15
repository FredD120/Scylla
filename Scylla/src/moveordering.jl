#Define PV, Killers, MVV-LVA table
#Score move using above heuristics
#Dynamically push next best move to top of list

"Store two best quiet moves for a given ply"
mutable struct Killer
    First::Move
    Second::Move
end

"Construct killers with null moves"
Killer() = Killer(NULLMOVE, NULLMOVE)

"Check that new move does not match second best killer, then push first to second and replace first"
function new_killer!(KV::Vector{Killer}, ply, move)
    if move != KV[ply + 1].First
        @inbounds KV[ply + 1].Second = KV[ply + 1].First 
        @inbounds KV[ply + 1].First = move 
    end
end

"Triangle number for an index starting from zero"
triangle_number(x) = Int(0.5 * x * (x + 1))

"find index of PV move at current ply"
PV_ind(ply,maxdepth) = Int(ply / 2 * (2 * maxdepth + 1 - ply))

"Copies line below in triangular PV table"
function copy_PV!(triangle_PV, ply, PV_len, maxdepth, move)
    cur_ind = PV_ind(ply, maxdepth)
    @inbounds triangle_PV[cur_ind + 1] = move
    for i in (cur_ind + 1):(cur_ind + PV_len - ply - 1)
        @inbounds triangle_PV[i + 1] = triangle_PV[i + maxdepth - ply]
    end
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
MVV_LVA(victim, attacker)::UInt8 = MINCAPSCORE + MV_LV[5 * (attacker - 1) + victim - 1]

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
function score_moves!(moves, killers::Killer=Killer(), best_move::Move=NULLMOVE)
    @inbounds for (i, move) in enumerate(moves)
        if move == best_move
            moves[i] = set_score(move, MAXMOVESCORE)

        #sort captures
        elseif iscapture(move)
            moves[i] = set_score(move, MVV_LVA(cap_type(move), pc_type(move)))

        #sort quiet moves
        else
            if move == killers.First
                moves[i] = set_score(move, MINCAPSCORE - UInt8(1))
            elseif move == killers.Second
                moves[i] = set_score(move, MINCAPSCORE - UInt8(2))
            end
        end
    end
end

