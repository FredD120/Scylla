struct BitBoard 
    n::UInt64
end

BitBoard() = BitBoard(UInt64(0))

BitBoard_full() = BitBoard(typemax(UInt64))

"Define start of iterator through locations in a bitboard"
function Base.iterate(BB::BitBoard) 
    if BB.n == 0
        return nothing
    else
        next_state = BB.n & (BB.n-1)
        first_item = LSB(BB)
        return first_item,next_state
    end
end

"Returns next (item, state) in iterator through locations in a bitboard"
function Base.iterate(BB::BitBoard,state::BitBoard) 
    if state.n == 0
        return nothing
    else
        next_state = state.n & (state.n-1)
        next_item = LSB(state)
        return next_item,next_state
    end
end

#Extend and operator on bitboards"
Base.&(a::BitBoard,b::BitBoard) = BitBoard(a.n & b.n)
#Extend or operator on bitboards"
Base.|(a::BitBoard,b::BitBoard) = BitBoard(a.n | b.n)
#Extend not operator on bitboards"
Base.~(a::BitBoard) = BitBoard(~a.n)
#Extend minus operator on bitboards"
Base.-(a::BitBoard,b::BitBoard) = BitBoard(a.n - b.n)
#Extend minus operator on bitboards"
Base.-(a::BitBoard,b::Integer) = BitBoard(a.n - b)
#Extend add operator on bitboards"
Base.+(a::BitBoard,b::BitBoard) = BitBoard(a.n + b.n)

Base.convert(::Type{UInt64},BB::BitBoard) = BB.n
Base.convert(::Type{BitBoard},int::Integer) = BitBoard(int)

"Define length of occupied positions in BB"
Base.length(BB::BitBoard) = count_ones(BB)

Base.count_ones(BB::BitBoard) = count_ones(BB.n)

setone(BB::BitBoard,index::Integer) = BitBoard(setone(BB.n, index))

setzero(BB::BitBoard,index::Integer) = BitBoard(setzero(BB.n, index))

"Least significant bit of a bitboard, returned as a UInt8"
LSB(BB::BitBoard) = LSB(BB.n)

"Returns a single bitboard representing the positions of an array of pieces"
function BBunion(piece_vec::AbstractArray{BitBoard})
    BB = BitBoard()
    for piece in piece_vec
        BB |= piece
    end
    return BB
end

"Count the total number of pieces in a vector of bitboards"
function count_pieces(pieces::AbstractArray{BitBoard})
    count = 0
    for BB in pieces
        count += length(BB)
    end
    return count
end

"loop through a list of piece BBs for one colour and return ID of enemy piece at a location"
function identify_piecetype(one_side_BBs::AbstractArray{BitBoard},location::Integer)::UInt8
    ID = NULL_PIECE
    for (pieceID,pieceBB) in enumerate(one_side_BBs)
        if pieceBB.n & (UInt64(1) << location) != 0
            ID = pieceID
            break
        end
    end
    return ID
end