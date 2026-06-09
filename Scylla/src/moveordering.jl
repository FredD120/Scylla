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
    move = remove_score(move)
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

    @inbounds info.pv[cur_ind + 1] = remove_score(move)
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
    @inbounds info.pv[cur_ind + 1] = remove_score(move)
    info.pv_len[ply_cur] = 1
end

"lookup value of capture in MVV_LVA table"
@inline most_least_value(victim, attacker)::UInt8 = @inbounds MVV_LVA[5 * (attacker - 1) + victim - 1]

const STAGE_TT = UInt8(0)
const STAGE_KILLER_1 = UInt8(1)
const STAGE_KILLER_2 = UInt8(2)
const STAGE_GENERATE = UInt8(3)
const STAGE_MOVES = UInt8(4)

mutable struct MoveStager
    stage::UInt8
    tt_move::Move
    killers::Killer
    is_check::Bool
    is_done::Bool
    board::BoardState
    cur_ind::UInt16
    move_length::UInt16
end

function MoveStager(tt_move, killers, board, is_check)
    return MoveStager(UInt8(0), tt_move, killers, is_check, false, board, 1, 0)
end

"if there is a specific move to look for at this stage, return that move"
function select_staged_move(stager::MoveStager)
    if stager.stage == STAGE_TT
        return stager.tt_move
        
    elseif stager.stage == STAGE_KILLER_1
        move = stager.killers.first
        if is_pseudolegal(move, stager.board)
            return move
        end

    elseif stager.stage == STAGE_KILLER_2
        move = stager.killers.second
        if is_pseudolegal(move, stager.board)
            return move
        end
    end
    return NULLMOVE
end

"swap the positions of two entries in a vector"
function swap!(list, ind1, ind2)
    temp = list[ind1]
    list[ind1] = list[ind2]
    list[ind2] = temp
end

"lazily search for tt move/killers before move scoring to try to avoid O(m^2) lookup"
function next_best!(st::MoveStager)
    while st.stage < STAGE_GENERATE
        next_move = select_staged_move(st)
        st.stage += 1

        if next_move != NULLMOVE
            return next_move
        end
    end

    if st.stage == STAGE_GENERATE
        (moves, move_length) = if st.is_check 
            generate_legal_moves(st.board)
        else
            generate_pseudolegal_moves(st.board)
        end
        score_moves!(moves)
        st.move_length = move_length
        st.stage += 1
    end

    if st.cur_ind > st.move_length
        st.is_done = true
        return NULLMOVE
    end

    moves = current_moves(st.board.move_vector, st.move_length)
    next_best!(moves, st.cur_ind)
    next_move = moves[st.cur_ind]
    st.cur_ind += 1
    return next_move
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