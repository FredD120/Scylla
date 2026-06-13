#define objects that make up the boardstate
#define helper functions to construct the boardstate
#define utility functions to fetch data from boardstate

"pre-allocated array of moves"
mutable struct MoveVec
    moves::Vector{Move}
    ind::UInt16
    len::UInt16
end

"create array of moves with default length, avoids allocating memory in tight loops"
MoveVec(len = MAXMOVES) = MoveVec(Vector{Move}(undef, len), UInt16(0), len)

"append move to move vec, increment index by one"
@inline function append!(m::MoveVec, move::Move)
    m.ind += 1
    @boundscheck if m.ind > m.len
        m.len *= 2
        new_moves = Vector{Move}(undef, m.len)

        for (i, move) in enumerate(m.moves)
            new_moves[i] = move
        end
        m.moves = new_moves
    end
    @inbounds m.moves[m.ind] = move
end

"reset index of movevec, but don't actually wipe data"
function clear!(m::MoveVec)
    m.ind = UInt16(0)
end

"push pointer back to before current set of moves were generated. must do this at the end of every recursive call"
function clear_current_moves!(m::MoveVec, move_length)
    m.ind -= move_length
end

"return a view into the current moves in move vec"
current_moves(m::MoveVec, move_length) = @view m.moves[m.ind - move_length + 1:m.ind]

"index into PST based on side-to-move"
side_index(colour::Bool, ind) = ifelse(colour, ind, 8 * rank(ind) + file(ind))

"offset for index into piece array based on side-to-move"
long_index(colour::Bool) = ifelse(colour, 0, 6)

"index either 0 or 1 for white or black, used for indexing small arrays"
short_index(colour::Bool) = Int(!colour)

"Positive or negative for White/Black respectively"
sgn(colour::Bool) = ifelse(colour, +1, -1)

"state of non-invertible board information and move that occurred next"
struct BoardHistory
    half_moves::UInt8
    castling::UInt8
    enpassant::BitBoard
    zobrist_hash::BitBoard
    move::Move
end

"pre-allocated array of board history data"
mutable struct HistoryVec
    vec::Vector{BoardHistory}
    ind::UInt16
    len::UInt16
end

"create array of historic states with default length, avoids allocating memory in tight loops"
HistoryVec(len = TYPICAL_GAME_LENGTH) = HistoryVec(Vector{BoardHistory}(undef, len), UInt16(0), len)

"extend push to add a new board history state to the history stack"
function Base.push!(history::HistoryVec, state::BoardHistory)
    history.ind += 1
    @boundscheck if history.ind > history.len
        history.len *= 2
        new_vec = Vector{BoardHistory}(undef, history.len)

        for (i, hist) in enumerate(history.vec)
            new_vec[i] = hist
        end
        history.vec = new_vec
    end
    @inbounds history.vec[history.ind] = state
end

"extend pop to remove a board history state from the history stack and return it"
function Base.pop!(history::HistoryVec)
    @boundscheck if history.ind < 1
        error("No move history to unmake")
    end
    state = @inbounds history.vec[history.ind]
    history.ind -= 1
    return state
end

mutable struct BoardState
    pieces::MVector{12, BitBoard}
    piece_union::MVector{3, BitBoard}
    piece_positions::MVector{64, UInt8}
    colour::Bool
    half_moves::UInt8
    castle::UInt8
    enpassant_bb::BitBoard
    zobrist_hash::BitBoard
    pst_score::PieceScore
    history::HistoryVec
    move_vector::MoveVec
end

"extract latest history state and update current board values to reflect it. return move for further unmaking"
function rollback_history!(board::BoardState)
    state = pop!(board.history)

    # zobrist hash is reversed automatically when unmaking move
    board.zobrist_hash = state.zobrist_hash
    board.half_moves = state.half_moves
    board.castle = state.castling
    board.enpassant_bb = state.enpassant

    return state.move
end

"create history data fromh move, enpassant, zobrist hash and castling rights, push to history stack"
function update_history!(board::BoardState, move::Move)
   state = BoardHistory(
    board.half_moves, 
    board.castle,
    board.enpassant_bb,
    board.zobrist_hash,
    move)

   push!(board.history, state)
end

"test draw by repetition of a position three times" 
@inline function three_repetition(board::BoardState)
    count = 0
    history = board.history
    for i in (history.ind - 1):-2:(history.ind - board.half_moves + 1)
        if history.vec[i].zobrist_hash == board.zobrist_hash
            count += 1
            if count > 1
                return true
            end
        end
    end
    return false
end

"implement 50 move rule and 3 position repetition"
@inline function draw_state(board::BoardState)::Bool
    return (board.half_moves >= 100) || three_repetition(board)
end

"Find position of king on bitboard"
king_pos(board::BoardState, side_index) = LSB(board.pieces[side_index + KING])

"generate bitboards representing positions of white, black and all pieces"
function pc_unions(pieces)::Vector{BitBoard}
    white_pc_bb = bb_union(pieces[1:6]) 
    black_pc_bb = bb_union(pieces[7:12]) 
    all_pc_bb = white_pc_bb | black_pc_bb
    return [white_pc_bb, black_pc_bb, all_pc_bb]
end

all_ally_pieces(board::BoardState) = board.piece_union[short_index(board.colour) + 1]

all_enemy_pieces(board::BoardState) = board.piece_union[short_index(!board.colour) + 1]

all_pieces(board::BoardState) = board.piece_union[end]

"count the total number of pieces in a vector of bitboards"
count_pieces(board::BoardState) = length(all_pieces(board))

"recalculate piece union after pieces have moved"
function update_piece_union!(board::BoardState)
    board.piece_union[end] = board.piece_union[1] | board.piece_union[2]
end

"Helper function when constructing a boardstate"
function place_piece!(pieces::AbstractArray{BitBoard}, piece_id, pos)
    pieces[piece_id] = setone(pieces[piece_id], pos)
end

"Helper function to modify zobrist based on castle rights"
function zobrist_castle(zobrist_hash, castling)
    #use last rank of black pawns and 8 extra indices (0 ⋜ castling ⋜ 15)
    zobrist_hash ⊻= ZOBRIST_KEYS[end - 16 + castling]
    return zobrist_hash
end

"Helper function to modify zobrist based on en-passant"
function zobrist_enpassant(zobrist_hash, enpassant)
    for ep in enpassant
        file = ep % 8
        #use first rank of black pawns
        zobrist_hash ⊻= ZOBRIST_KEYS[(64 * 11) + file + 1]
    end
    return zobrist_hash
end

"Returns zobrist key associated with a coloured piece at a location"
zobrist_piece(piece_id, pos) = ZOBRIST_KEYS[64 * (piece_id - 1) + pos + 1]

"Returns zobrist key associated with whose turn it is (switched on if black)"
const ZOBRIST_COLOUR = ZOBRIST_KEYS[end]

"Generate Zobrist hash of a boardstate"
function generate_hash(pieces, colour, castling, enpassant)
    zobrist_hash = BitBoard()
    for (piece_id, piece_bb) in enumerate(pieces)
        for loc in piece_bb
            zobrist_hash ⊻= zobrist_piece(piece_id, loc)
        end
    end

    # the rest of this data is packed in using the fact that neither
    # black nor white pawns will exist on first or last rank
    zobrist_hash = zobrist_enpassant(zobrist_hash, enpassant)
    zobrist_hash = zobrist_castle(zobrist_hash, castling)

    if !colour
        zobrist_hash ⊻= ZOBRIST_COLOUR
    end
    return zobrist_hash
end

"generate zobrist hash statically from existing boardstate"
generate_hash(b::BoardState) = generate_hash(b.pieces, b.colour, b.castle, b.enpassant_bb)

"create array of piece bitboards and populate using first section of FEN_string"
function get_pieces(FEN_board)
    pieces = [BitBoard() for _ in 1:12]
    i = UInt32(0)

    for char in FEN_board
        if isletter(char)
            upper_letter = uppercase(char)
            colour_ind = long_index(char == upper_letter ? WHITE : BLACK)
            place_piece!(pieces, FEN_DICT[upper_letter] + colour_ind, i)
            i += 1
        elseif isnumeric(char)
            i += parse(Int, char)
        end
    end
    return pieces
end

"create UInt8 containing castling rights for black/white on king/queen-side from castling part of a FEN string"
function get_castle_rights(FEN_castle)
    castling = UInt8(0)
    for c in FEN_castle
        if c == 'K'
            castling = setone(castling, 0)
        elseif c == 'Q'
            castling = setone(castling, 1)
        elseif c == 'k'
            castling = setone(castling, 2)
        elseif c == 'q'
            castling = setone(castling, 3)
        end
    end
    return castling
end

"return side to move from FEN string, defaults to white"
function get_side_to_move(FEN_colour)
    if FEN_colour == "b"
        return BLACK
    else
        return WHITE
    end
end

"return en-passant from FEN string, empty bitboard if no enpassant available"
function get_enpassant(FEN_enpassant)
    enpassant = BitBoard()
    if length(FEN_enpassant) == 2
        return setone(enpassant, algebraic_to_numeric(FEN_enpassant))
    else
        return enpassant
    end
end

"Initialise a boardstate from a FEN string"
function BoardState(FEN)
    fen_vec = split(FEN)

    pieces = get_pieces(fen_vec[1])
    colour = get_side_to_move(fen_vec[2])
    castling = get_castle_rights(fen_vec[3])
    enpassant = get_enpassant(fen_vec[4])

    half_moves = if length(fen_vec) > 4
        parse(UInt8, fen_vec[5])
    else
        UInt8(0)
    end

    zobrist = generate_hash(pieces, colour, castling, enpassant)
    pst_score = get_pst(pieces)

    BoardState(pieces, pc_unions(pieces), offset_board(pieces), colour, half_moves,
    castling, enpassant, zobrist, pst_score, HistoryVec(), MoveVec())
end

"default constructor for BoardState"
BoardState() = BoardState(START_FEN)

"helper function to obtain vector of ally bitboards"
function ally_pieces(b::BoardState)
    ind = long_index(b.colour)
    return @view b.pieces[ind + 1:ind + 6]
end

"helper function to obtain vector of enemy bitboards"
function enemy_pieces(b::BoardState) 
    ind = long_index(!b.colour)
    return @view b.pieces[ind + 1:ind + 6]
end

"helper function to access pieces bitboards for either player"
@inline colour_piece(b::BoardState, colour, piece) = @inbounds b.pieces[long_index(colour) + piece]

"helper function to obtain bitboard of ally piece"
@inline ally_piece(b::BoardState, piece) = colour_piece(b, b.colour, piece)

"helper function to obtain bitboard of enemy piece"
@inline enemy_piece(b::BoardState, piece) = colour_piece(b, !b.colour, piece)

"create a 64-length vector of where pieces are on the board"
function offset_board(piece_vec::Vector{BitBoard})
    position = zeros(UInt8, 64)
    for (piece_id, piece) in enumerate(piece_vec)
        for i in 0:63
            if piece & BitBoard(1) << i > 0
                colourless_piece = (piece_id - 1) % 6 + 1
                position[i + 1] = colourless_piece
            end
        end
    end
    return position
end

offset_board(board::BoardState) = offset_board(board.pieces)
identify_piecetype(board::BoardState, location) = board.piece_positions[location + 1]

"check if a given quiet move is possible to play on the current boardstate"
function is_quiet_move_possible(move, board::BoardState)
    if move == NULLMOVE
        return false
    end
    mv_pc_type, mv_from, mv_to, _, mv_flag = unpack_move(move)
    positions = board.piece_positions

    # need to make move types have colour and only PST access is colourless
    if positions[mv_from + 1] != mv_pc_type
        return false
    end

    if positions[mv_to + 1] != NULL_PIECE
        return false
    end

    if is_castle(mv_flag)
        castle_id = mv_flag - 1 + 2 * !board.colour
        if ((UInt8(1) << castle_id) & self_castle_rights(board)) == UInt8(0)
            return false
        end

        all_pcs = all_pieces(board)
        if CASTLE_BLOCKS[castle_id + 1] & all_pcs != 0
            return false
        end

        if CASTLE_ATTACKS[castle_id + 1] & enemy_attacks(board, all_pcs) != 0
            return false
        end
    end

    if mv_flag == DOUBLE_PUSH
        push_mask = ifelse(board.colour, WHITE_MASKS, BLACK_MASKS).shift
        if positions[mv_from + 1 - push_mask] != NULL_PIECE
            return false
        end
    end

    if mv_pc_type == ROOK
        moves = pseudolegal_rook_moves(mv_from, all_pieces(board))
        if (BitBoard(1) << mv_to) & moves == BITBOARD_EMPTY
            return false
        end

    elseif mv_pc_type == BISHOP
        moves = pseudolegal_bishop_moves(mv_from, all_pieces(board))
        if (BitBoard(1) << mv_to) & moves == BITBOARD_EMPTY
            return false
        end

    elseif mv_pc_type == QUEEN
        moves = pseudolegal_queen_moves(mv_from, all_pieces(board))
        if (BitBoard(1) << mv_to) & moves == BITBOARD_EMPTY
            return false
        end
    end

    return true
end

"convert a move to UCI notation"
function uci_move(move::Move)
    flg = flag(move)
    F = from(move)
    T = to(move)

    p = ""
    prom_type = promote_type(flg)
    if  prom_type != NULL_PIECE
        p = lowercase(piece_letter(prom_type))
    end
    return uci_pos(F) * uci_pos(T) * p
end

"convert a move to long algebraic notation for clarity"
function long_move(move::Move)
    flg = flag(move)
    if flg == KING_CASTLE
        return "O-O"
    elseif flg == QUEEN_CASTLE
        return "O-O-O"
    else
        F = uci_pos(from(move))
        T = uci_pos(to(move))
        P = piece_letter(pc_type(move))
        mid = "-"
        if cap_type(move) > 0
            mid = "x"
        end

        promote = piece_letter(promote_type(flg))
        return P * F * mid * T * promote
    end
end

"convert a move to short algebraic notation for comparison/communication"
function short_move(move::Move)
    flg = flag(move)
    if flg == KING_CASTLE
        return "O-O"
    elseif flg == QUEEN_CASTLE
        return "O-O-O"
    else
        T = uci_pos(to(move))
        P = piece_letter(pc_type(move))
        mid = "x"

        if cap_type(move) == 0
            mid = ""
        end
        if pc_type(move) == PAWN
            if cap_type(move) == 0
                P = ""
            else
                P = 'a' + (from(move) % 8)
            end
        end

        promote = piece_letter(promote_type(flg))
        return P * mid * T * promote
    end
end

"print a visualisation of the board to StdOut"
function print_board(piece_positions::Vector{UInt8})
    for (pos, piece) in enumerate(piece_positions)
        if piece == NULL_PIECE
            print(". ")
        else
            str = if piece < 7
                INV_FEN_DICT[piece]
            else
                lowercase(INV_FEN_DICT[piece - 6])
            end
            print(str, " ")
        end

        if file(pos - 1) == 7
            println("")
        end
    end
end

print_board(board::BoardState) = print_board(board.piece_positions)