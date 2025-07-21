#define objects that make up the boardstate
#define helper functions to construct the boardstate
#define utility functions to fetch data from boardstate

"Positive or negative for White/Black respectively"
sgn(colour::UInt8) = ifelse(colour==0,+1,-1)

"Boolean representing whose turn it is, chosen based on value on UInt8"
Whitesmove(ColourIndex::UInt8) = ifelse(ColourIndex == 0, true, false)

"Colour ID from value stored in board representation"
ColID(ColourIndex::UInt8)::UInt8 = ColourIndex % 5

"Helper functions to return opposite colour index"
Opposite(ColourIndex::UInt8)::UInt8 = (ColourIndex+6)%12
Opposite(colour::Bool) = !colour

"Helper functions to return index of piece BB in piece list"
ColourPieceID(colour::UInt8,piece::Integer) = colour + piece

"Index into PST based on colour index"
side_index(colour::UInt8,ind) = ifelse(colour==0,ind,8*rank(ind) + file(ind))


mutable struct BoardData
    Halfmoves::Vector{UInt8}
    Castling::Vector{UInt8}
    CastleCount::Vector{UInt16}
    EnPassant::Vector{UInt64}
    EPCount::Vector{UInt16}
    ZHashHist::Vector{UInt64}
end

mutable struct Boardstate
    pieces::Vector{UInt64}
    piece_union::Vector{UInt64}
    Colour::UInt8
    Castle::UInt8
    EnPass::UInt64
    State::GameState
    PSTscore::Vector{Int32}
    ZHash::UInt64
    MoveHist::Vector{UInt32}
    Data::BoardData
end

"Find position of king on bitboard"
king_pos(board::Boardstate,side_index) = LSB(board.pieces[side_index+King])

function pc_unions(pieces)::Vector{UInt64}
    white_pc_BB = BBunion(pieces[1:6]) 
    black_pc_BB = BBunion(pieces[7:12]) 
    all_pc_BB = white_pc_BB | black_pc_BB
    [white_pc_BB,black_pc_BB,all_pc_BB]
end

"Helper function when constructing a boardstate"
function place_piece!(pieces::AbstractArray{UInt64},pieceID,pos)
    pieces[pieceID] = setone(pieces[pieceID],pos)
end

"Helper function to modify Zhash based on castle rights"
function Zhashcastle(ZHash,castling)
    #use last rank of black pawns and 8 extra indices (0⋜castling⋜15)
    ZHash ⊻= ZobristKeys[end - 16 + castling]
    return ZHash
end

"Helper function to modify Zhash based on en-passant"
function ZhashEP(ZHash,enpassant)
    for EP in enpassant
        file = EP % 8
        #use first rank of black pawns
        ZHash ⊻= ZobristKeys[64*(11)+file+1]
    end
    return ZHash
end

"Returns zobrist key associated with a coloured piece at a location"
ZKey_piece(CpieceID,pos) = ZobristKeys[64*(CpieceID-1)+pos+1]

"Returns zobrist key associated with whose turn it is (switched on if black)"
ZKeyColour() = ZobristKeys[end]

"Generate Zobrist hash of a boardstate"
function generate_hash(pieces,colour::UInt8,castling,enpassant)
    ZHash = UInt64(0)
    for (pieceID,pieceBB) in enumerate(pieces)
        for loc in pieceBB
            ZHash ⊻= ZKey_piece(pieceID,loc)
        end
    end

    #the rest of this data is packed in using the fact that neither
    #black nor white pawns will exist on first or last rank
    ZHash = ZhashEP(ZHash,enpassant)
    ZHash = Zhashcastle(ZHash,castling)

    if !Whitesmove(colour)
        ZHash ⊻= ZKeyColour()
    end
    return ZHash
end

"generate zobrist hash statically from existing boardstate"
generate_hash(b::Boardstate) = generate_hash(b.pieces,b.Colour,b.Castle,b.EnPass)

"Initialise a boardstate from a FEN string"
function Boardstate(FEN)
    pieces = zeros(UInt64,12)
    Castling = UInt64(0)
    EnPassant = UInt64(0)
    Halfmoves = UInt8(0)
    Colour = white
    PSTscore = zeros(Int32,2)
    MoveHistory = Vector{UInt32}()
    rank = nothing
    file = nothing

    #Keep track of where we are on chessboard
    i = UInt32(0)         
    #Sections of FEN string are separated by ' '      
    num_spaces = UInt32(0)      
    for c in FEN
        #use spaces to know where we are in FEN
        if c == ' '
            num_spaces += 1
        #Positions of  pieces
        elseif num_spaces == 0
            if isletter(c)
                upperC = uppercase(c)
                if c == upperC
                    colour = white
                else
                    colour = black
                end
                place_piece!(pieces,FENdict[upperC]+colour,i)
                i+=1
            elseif isnumeric(c)
                i+=parse(Int,c)
            end
        #Determine whose turn it is
        elseif num_spaces == 1
            if c == 'w'
                Colour = white
            elseif c == 'b'
                Colour = black
            end
        #castling rights
        elseif num_spaces == 2
            if c == 'K'
                Castling = setone(Castling,0)
            elseif c == 'Q'
                Castling = setone(Castling,1)
            elseif c == 'k'
                Castling = setone(Castling,2)
            elseif c == 'q'
                Castling = setone(Castling,3)
            end
        #en-passant
        elseif num_spaces == 3
            if isnumeric(c)
                rank = parse(Int,c)
            elseif c != '-'
                file = Int(c) - Int('a') + 1
            end
            if !isnothing(rank) && !isnothing(file)
                EnPassant = setone(EnPassant,(-rank+8)*8 + file-1)
            end
        elseif num_spaces == 4
            Halfmoves = parse(UInt8,c)
        end
    end

    Zobrist = generate_hash(pieces,Colour,Castling,EnPassant)
    data = BoardData(Vector{UInt8}([Halfmoves]),
                     Vector{UInt8}([Castling]),Vector{UInt8}([0]),
                     Vector{UInt64}([EnPassant]),Vector{UInt8}([0]),
                     Vector{UInt64}([Zobrist]))

    set_PST!(PSTscore,pieces)

    Boardstate(pieces,pc_unions(pieces),Colour,Castling,EnPassant,Neutral(),PSTscore,Zobrist,MoveHistory,data)
end

"Returns a single bitboard representing the positions of an array of pieces"
function BBunion(piece_vec::AbstractArray{UInt64})
    BB = UInt64(0)
    for piece in piece_vec
        BB |= piece
    end
    return BB
end

"Helper function to obtain vector of ally bitboards"
ally_pieces(b::Boardstate) = @view b.pieces[b.Colour+1:b.Colour+6]

"Helper function to obtain vector of enemy bitboards"
function enemy_pieces(b::Boardstate) 
    enemy_ind = Opposite(b.Colour)
    return @view b.pieces[enemy_ind+1:enemy_ind+6]
end

"tells GUI where pieces are on the board"
function GUIposition(board::Boardstate)
    position = zeros(UInt8,64)
    for (pieceID,piece) in enumerate(board.pieces)
        for i in UInt64(0):UInt64(63)
            if piece & UInt64(1) << i > 0
                position[i+1] = pieceID
            end
        end
    end
    return position
end


"Count the total number of pieces in a vector of bitboards"
function count_pieces(pieces::AbstractArray{UInt64})
    count = 0
    for BB in pieces
        count += length(BB)
    end
    return count
end

"returns a list of numbers between 0 and 63 to indicate positions on a chessboard"
function identify_locations(pieceBB::Integer)::Vector{UInt8}
    locations = Vector{UInt8}()
    temp_BB = pieceBB
    while temp_BB != 0
        loc = LSB(temp_BB) #find 0-indexed location of least significant bit in BB
        push!(locations,loc)
        temp_BB &= temp_BB - 1        #trick to remove least significant bit
    end
    return locations
end

"Define start of iterator through locations in a bitboard"
function Base.iterate(BB::UInt64) 
    if BB == 0
        return nothing
    else
        next_state = BB & (BB-1)
        first_item = LSB(BB)
        return first_item,next_state
    end
end

"Returns next (item, state) in iterator through locations in a bitboard"
function Base.iterate(BB::UInt64,state::UInt64) 
    if state == 0
        return nothing
    else
        next_state = state & (state-1)
        next_item = LSB(state)
        return next_item,next_state
    end
end

"Define length of occupied positions in BB"
Base.length(BB::UInt64) = count_ones(BB)

"loop through a list of piece BBs for one colour and return ID of enemy piece at a location"
function identify_piecetype(one_side_BBs::AbstractArray{UInt64},location::Integer)::UInt8
    ID = NULL_PIECE
    for (pieceID,pieceBB) in enumerate(one_side_BBs)
        if pieceBB & (UInt64(1) << location) != 0
            ID = pieceID
            break
        end
    end
    return ID
end