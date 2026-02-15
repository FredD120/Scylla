#define objects that make up the boardstate
#define helper functions to construct the boardstate
#define utility functions to fetch data from boardstate

const MAXMOVES = 4096

"pre-allocated array of moves"
mutable struct MoveVec
    moves::Vector{Move}
    ind::UInt16
    cur_move_len::UInt16
end

"max theoretical number of moves in a boardstate is ≈ 200, assuming 20 move depth gives ≈ 4000 total moves in recursive call"
MoveVec(len = MAXMOVES) = MoveVec(Vector{Move}(undef, len), FIRST_MOVE_INDEX, FIRST_MOVE_INDEX)

"append move to move vec, increment index by one"
function append!(m::MoveVec, move::Move)
    m.ind += 1
    m.cur_move_len += 1
    #=@inbounds=# m.moves[m.ind] = move
end

"reset index of movevec, but don't actually wipe data"
function clear!(m::MoveVec)
    m.ind = FIRST_MOVE_INDEX
    m.cur_move_len = FIRST_MOVE_INDEX
end

"push pointer back to before current set of moves were generated. must do this at the end of every recursive call"
function clear_current_moves!(m::MoveVec, move_length)
    m.ind -= move_length
end

"reset current move count to zero after generating moves "
function reset_movecount!(m::MoveVec)
    m.cur_move_len = FIRST_MOVE_INDEX
end

"helper function to find length of current move vector"
current_movecount(m::MoveVec) = m.cur_move_len

"return a view into the current moves in move vec"
current_moves(m::MoveVec) = @view m.moves[m.ind - m.cur_move_len + 1:m.ind]

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
    PSTscore::Vector{Int32}
    zobrist_hash::BitBoard
    move_history::Vector{Move}
    Data::BoardData
    move_vector::MoveVec
end

"Find position of king on bitboard"
king_pos(board::BoardState, side_index) = LSB(board.pieces[side_index + King])

function pc_unions(pieces)::Vector{BitBoard}
    white_pc_BB = bb_union(pieces[1:6]) 
    black_pc_BB = bb_union(pieces[7:12]) 
    all_pc_BB = white_pc_BB | black_pc_BB
    [white_pc_BB,black_pc_BB,all_pc_BB]
end

"Helper function when constructing a boardstate"
function place_piece!(pieces::AbstractArray{BitBoard},pieceID,pos)
    pieces[pieceID] = setone(pieces[pieceID],pos)
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
    for (pieceID,pieceBB) in enumerate(pieces)
        for loc in pieceBB
            zobrist_hash ⊻= zobrist_piece(pieceID, loc)
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
    colour = white
    PSTscore = zeros(Int32,2)
    move_historyory = Vector{Move}()

    #Keep track of where we are on chessboard
    i = UInt32(0)           
    FENvec = split(FEN)

    #Positions of  pieces
    for char in FENvec[1]
        if isletter(char)
            upper_letter = uppercase(char)
            piece_colour = char == upper_letter ? white : black
            place_piece!(pieces, FEN_DICT[upper_letter] + piece_colour, i)
            i += 1
        elseif isnumeric(char)
            i += parse(Int, char)
        end
    end
  
    #Determine whose turn it is
    if FENvec[2] == "b"
        colour = black
    end

    #castling rights
    for c in FENvec[3]
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
    if length(FENvec[4]) == 2
        enpassant = setone(enpassant, algebraic_to_numeric(FENvec[4]))
    end

    if length(FENvec) > 4
        half_moves = parse(UInt8,FENvec[5])
    end

    Zobrist = generate_hash(pieces, colour, castling, enpassant)
    data = BoardData(Vector{UInt8}([half_moves]),
                     Vector{UInt8}([castling]),Vector{UInt8}([0]),
                     Vector{BitBoard}([enpassant]),Vector{UInt8}([0]),
                     Vector{BitBoard}([Zobrist]))

    set_PST!(PSTscore, pieces)

    BoardState(pieces, pc_unions(pieces), colour, castling, enpassant,
    Neutral(), PSTscore, Zobrist, move_historyory, data, MoveVec())
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

"tells GUI where pieces are on the board"
function GUIposition(board::BoardState)
    position = zeros(UInt8, 64)
    for (pieceID, piece) in enumerate(board.pieces)
        for i in 0:63
            if piece & BitBoard(1) << i > 0
                position[i + 1] = pieceID
            end
        end
    end
    return position
end

"loop through a list of piece BBs for one colour and return ID of enemy piece at a location"
function identify_piecetype(board::BoardState, location::Integer)::UInt8
    ID = NULL_PIECE
    for (pieceID, pieceBB) in enumerate(board.pieces)
        if pieceBB & (BitBoard(1) << location) != 0
            ID = pieceID
            break
        end
    end
    return ID - opposite(board.colour)
end