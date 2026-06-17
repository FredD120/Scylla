#Define PV, Killers, MVV-LVA table
#Score move using above heuristics
#Dynamically push next best move to top of list

"store two best quiet moves for a given ply"
struct Killer
    first::Move
    second::Move
end

"construct killers with null moves"
Killer() = Killer(NULLMOVE, NULLMOVE)

const DEFAULT_KILLER = Killer()

"check that new move does not match second best killer, then push first to second and replace first"
function new_killer!(killer_vec, ply, move)
    move = strip_move(move)
    old = @inbounds killer_vec[ply + 1]

    if move != old.first
        @inbounds killer_vec[ply + 1] = Killer(move, old.first)
    end
end

mutable struct SearchInfo
    # record best moves from root to leaves for move ordering
    pv::Vector{Move}
    pv_len::Vector{UInt8}
    pv_offsets::Vector{UInt16}
    killers::Vector{Killer}
end

"Constructor for search info struct"
function SearchInfo(depth = MAXDEPTH + 1)
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
triangle_number(x) =  x * (x + 1) ÷ 2

"find the index of the first move in the PV at a given ply"
pv_ind(ply, maxdepth) = (2 * maxdepth + 1 - ply) * ply ÷ 2

"copies line below in triangular PV table"
function copy_pv!(info::SearchInfo, ply, move)
    # 1-based indexes of current and next ply
    ply_cur = ply + 1
    ply_next = ply + 2

    # 0-based indexes into PV array
    cur_ind = info.pv_offsets[ply_cur]
    lower_ind = info.pv_offsets[ply_next]

    @inbounds info.pv[cur_ind + 1] = strip_move(move)
    lower_pv_len = info.pv_len[ply_next]
    for i in 1:lower_pv_len # i is a 1-based index
        @inbounds info.pv[cur_ind + i + 1] = info.pv[lower_ind + i]
    end
    # update pv len at current ply
    info.pv_len[ply_cur] = lower_pv_len + 1
end

"set an entry in PV table when a transposition table cut-off occurs"
function set_pv!(info::SearchInfo, ply, move)
    ply_cur = ply + 1
    cur_ind = info.pv_offsets[ply_cur]
    @inbounds info.pv[cur_ind + 1] = strip_move(move)
    info.pv_len[ply_cur] = 1
end

"lookup value of capture in MVV_LVA table, removing colour of attacker/victim in the process"
@inline most_least_value(victim, attacker)::UInt8 = 
    @inbounds MVV_LVA[5 * (colourless_piecetype(attacker) - 1) + colourless_piecetype(victim) - 1]

const STAGE_TT = UInt8(0)
const STAGE_GENERATE_ATTACKS = UInt8(1)
const STAGE_ATTACKS = UInt8(2)
const STAGE_KILLER_1 = UInt8(3)
const STAGE_KILLER_2 = UInt8(4)
const STAGE_GENERATE_QUIETS = UInt8(5)
const STAGE_QUIETS = UInt8(6)

# type of view into MoveVec, used to persistently store generated moves for staging
const MoveView = SubArray{Move, 1, Vector{Move}, Tuple{UnitRange{Int}}, true}

mutable struct MoveStager
    stage::UInt8
    tt_move::Move
    killers::Killer
    is_done::Bool
    board::BoardState
    moves::Union{Nothing, MoveView}
    cur_ind::UInt16
    move_length::UInt16
end

function MoveStager(tt_move, killers, board)
    return MoveStager(UInt8(0), tt_move, killers, false, board, nothing, 1, 0)
end

"swap the positions of two entries in a vector"
function swap!(list, ind1, ind2)
    temp = list[ind1]
    list[ind1] = list[ind2]
    list[ind2] = temp
end

"lazily search for tt move/killers before move generation/scoring"
function next_best!(st::MoveStager)
    if st.stage == STAGE_TT
        st.stage += 1
        return st.tt_move
    
    elseif st.stage == STAGE_GENERATE_ATTACKS
        st.stage += 1
        (moves, move_length) = generate_pseudolegal_attacks(st.board)
        score_moves!(moves)
        st.moves = moves
        st.move_length = move_length
        return next_best!(st)
    
    elseif st.stage == STAGE_ATTACKS
        next_best!(st.moves, st.cur_ind)

    elseif st.stage == STAGE_KILLER_1
        st.stage += 1
        move = st.killers.first
        if (move != st.tt_move) && is_quiet_move_possible(move, st.board)
            return move
        else
            return next_best!(st)
        end

    elseif st.stage == STAGE_KILLER_2
        st.stage += 1
        move = st.killers.second
        if (move != st.tt_move) && is_quiet_move_possible(move, st.board)
            return move
        else
            return next_best!(st)
        end

    elseif st.stage == STAGE_GENERATE_QUIETS
        st.stage += 1
        (moves, move_length) = generate_pseudolegal_quiets(st.board)
        st.moves = moves
        st.move_length = move_length
        st.cur_ind = 1
        return next_best!(st)
    end

    if st.cur_ind > st.move_length
        if st.stage == STAGE_QUIETS
            st.is_done = true
            return NULLMOVE
        else
            clear_current_moves!(st.board.move_vector, st.move_length)
            st.stage += 1
            st.move_length = 0
            return next_best!(st)
        end
    else
        next_move = @inbounds st.moves[st.cur_ind]
        st.cur_ind += 1

        if is_move_equal(next_move, st.tt_move, st.killers.first, st.killers.second)
            return next_best!(st)
        end
        return next_move
    end
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

"Score moves based MVV-LVA"
@inline function score_moves!(moves::AbstractArray)
    @inbounds for (i, move) in enumerate(moves)
        if is_capture(move)
            moves[i] = set_score(move, most_least_value(cap_type(move), pc_type(move)))
        end
    end
end