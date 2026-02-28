#define objects that make up the boardstate
#define helper functions to construct the boardstate
#define utility functions to fetch data from boardstate

"pre-allocated array of moves"
mutable struct MoveVec
    moves::Vector{Move}
    ind::UInt16
end

"create array of moves with default length, avoids allocating memory in tight loops"
MoveVec(len = MAXMOVES) = MoveVec(Vector{Move}(undef, len), FIRST_MOVE_INDEX)

"append move to move vec, increment index by one"
function append!(m::MoveVec, move::Move)
    m.ind += 1
    @inbounds m.moves[m.ind] = move
end

"reset index of movevec, but don't actually wipe data"
function clear!(m::MoveVec)
    m.ind = FIRST_MOVE_INDEX
end

"push pointer back to before current set of moves were generated. must do this at the end of every recursive call"
function clear_current_moves!(m::MoveVec, move_length)
    m.ind -= move_length
end

"return a view into the current moves in move vec"
current_moves(m::MoveVec, move_length) = @view m.moves[m.ind - move_length + 1:m.ind]

"Positive or negative for White/Black respectively"
sgn(colour::UInt8) = ifelse(colour==0, +1, -1)

"Boolean representing whose turn it is, chosen based on value on UInt8"
whitesmove(colour_index::UInt8) = ifelse(colour_index == 0, true, false)

"Colour ID from value stored in board representation"
colour_id(colour_index::UInt8)::UInt8 = colour_index % 5

"Helper functions to return opposite colour index"
opposite(colour_index::UInt8)::UInt8 = (colour_index + 6) % 12
opposite(colour::Bool) = !colour

"Helper functions to return index of piece BB in piece list"
colour_piece_id(colour::UInt8, piece::Integer) = colour + piece

"Index into PST based on colour index"
side_index(colour::UInt8, ind) = ifelse(colour==0, ind, 8 * rank(ind) + file(ind))

mutable struct BoardData
    half_moves::Vector{UInt8}
    castling::Vector{UInt8}
    castleCount::Vector{UInt16}
    enpassant::Vector{BitBoard}
    enpassant_count::Vector{UInt16}
    zobrist_hash_history::Vector{BitBoard}
end

mutable struct BoardState
    pieces::Vector{BitBoard}
    piece_union::Vector{BitBoard}
    colour::UInt8
    castle::UInt8
    enpassant_bb::BitBoard
    state::GAME_STATE
    pst_score::Vector{Int32}
    zobrist_hash::BitBoard
    move_history::Vector{Move}
    data::BoardData
    move_vector::MoveVec
end

"Find position of king on bitboard"
king_pos(board::BoardState, side_index) = LSB(board.pieces[side_index + KING])

function pc_unions(pieces)::Vector{BitBoard}
    white_pc_bb = bb_union(pieces[1:6]) 
    black_pc_bb = bb_union(pieces[7:12]) 
    all_pc_bb = white_pc_bb | black_pc_bb
    [white_pc_bb, black_pc_bb, all_pc_bb]
end

"Helper function when constructing a boardstate"
function place_piece!(pieces::AbstractArray{BitBoard}, piece_id, pos)
    pieces[piece_id] = setone(pieces[piece_id], pos)
end

"Helper function to modify zobrist based on castle rights"
function zobrist_castle(zobrist_hash, castling)
    #use last rank of black pawns and 8 extra indices (0⋜castling⋜15)
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
zobrist_piece(colour_id, pos) = ZOBRIST_KEYS[64 * (colour_id - 1) + pos + 1]

"Returns zobrist key associated with whose turn it is (switched on if black)"
zobrist_colour() = ZOBRIST_KEYS[end]

"Generate Zobrist hash of a boardstate"
function generate_hash(pieces, colour::UInt8, castling, enpassant)
    zobrist_hash = BitBoard()
    for (piece_id, piece_bb) in enumerate(pieces)
        for loc in piece_bb
            zobrist_hash ⊻= zobrist_piece(piece_id, loc)
        end
    end

    #the rest of this data is packed in using the fact that neither
    #black nor white pawns will exist on first or last rank
    zobrist_hash = zobrist_enpassant(zobrist_hash, enpassant)
    zobrist_hash = zobrist_castle(zobrist_hash, castling)

    if !whitesmove(colour)
        zobrist_hash ⊻= zobrist_colour()
    end
    return zobrist_hash
end

"generate zobrist hash statically from existing boardstate"
generate_hash(b::BoardState) = generate_hash(b.pieces, b.colour, b.castle, b.enpassant_bb)

"Initialise a boardstate from a FEN string"
function BoardState(FEN)
    pieces = [BitBoard() for _ in 1:12]
    castling = UInt8(0)
    half_moves = UInt8(0)
    enpassant = BitBoard()
    colour = WHITE
    pst_score = zeros(Int32,2)
    move_history = Vector{Move}()

    #Keep track of where we are on chessboard
    i = UInt32(0)           
    fen_vec = split(FEN)

    #Positions of  pieces
    for char in fen_vec[1]
        if isletter(char)
            upper_letter = uppercase(char)
            piece_colour = char == upper_letter ? WHITE : BLACK
            place_piece!(pieces, FEN_DICT[upper_letter] + piece_colour, i)
            i += 1
        elseif isnumeric(char)
            i += parse(Int, char)
        end
    end
  
    #Determine whose turn it is
    if fen_vec[2] == "b"
        colour = BLACK
    end

    #castling rights
    for c in fen_vec[3]
        if c == 'K'
            castling = setone(castling,0)
        elseif c == 'Q'
            castling = setone(castling,1)
        elseif c == 'k'
            castling = setone(castling,2)
        elseif c == 'q'
            castling = setone(castling,3)
        end
    end

    #en-passant
    if length(fen_vec[4]) == 2
        enpassant = setone(enpassant, algebraic_to_numeric(fen_vec[4]))
    end

    if length(fen_vec) > 4
        half_moves = parse(UInt8, fen_vec[5])
    end

    zobrist = generate_hash(pieces, colour, castling, enpassant)
    data = BoardData(Vector{UInt8}([half_moves]),
                     Vector{UInt8}([castling]),Vector{UInt8}([0]),
                     Vector{BitBoard}([enpassant]),Vector{UInt8}([0]),
                     Vector{BitBoard}([zobrist]))

    set_pst!(pst_score, pieces)

    BoardState(pieces, pc_unions(pieces), colour, castling, enpassant,
    Neutral(), pst_score, zobrist, move_history, data, MoveVec())
end

"helper function to obtain vector of ally bitboards"
ally_pieces(b::BoardState) = @view b.pieces[b.colour + 1:b.colour + 6]

"helper function to obtain vector of enemy bitboards"
function enemy_pieces(b::BoardState) 
    enemy_ind = opposite(b.colour)
    return @view b.pieces[enemy_ind + 1:enemy_ind + 6]
end

"helper function to obtain bitboard of ally piece"
ally_piece(b::BoardState, piece) = b.pieces[b.colour + piece]

"helper function to obtain bitboard of enemy piece"
enemy_piece(b::BoardState, piece) = b.pieces[opposite(b.colour) + piece]

"create a 64-length vector of where pieces are on the board, useful for a GUI"
function GUIposition(board::BoardState)
    position = zeros(UInt8, 64)
    for (piece_id, piece) in enumerate(board.pieces)
        for i in 0:63
            if piece & BitBoard(1) << i > 0
                position[i + 1] = piece_id
            end
        end
    end
    return position
end

"loop through a list of piece BBs for one colour and return ID of enemy piece at a location"
function identify_piecetype(board::BoardState, location::Integer)::UInt8
    id = NULL_PIECE
    for (piece_id, piece_bb) in enumerate(board.pieces)
        if piece_bb & (BitBoard(1) << location) != 0
            id = piece_id
            break
        end
    end
    return id - opposite(board.colour)
end


"convert a move to UCI notation"
function uci_move(board::BoardState, move::Move)
    flg = flag(move)
    F = from(move)
    T = to(move)

    if flg == KING_CASTLE || flg == QUEEN_CASTLE
        F = locate_king(board)
        T = F + 2
        if flg == QUEEN_CASTLE
            T = F -2
        end
    end

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