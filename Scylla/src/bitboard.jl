import Base: +, -, *, &, |, ⊻, ~, <<, >>, ==, <, >, convert, promote_rule
import Random

struct BitBoard
    n::UInt64
end

BitBoard() = BitBoard(UInt64(0))
BitBoard_full() = BitBoard(typemax(UInt64))

const BITBOARD_EMPTY = BitBoard()
const BITBOARD_FULL = BitBoard_full()

"Define start of iterator through locations in a bitboard"
function Base.iterate(bb::BitBoard) 
    if bb == 0
        return nothing
    else
        next_state = bb & (bb - 1)
        first_item = LSB(bb)
        return first_item, next_state
    end
end

"Returns next (item, state) in iterator through locations in a bitboard"
function Base.iterate(bb::BitBoard, state::BitBoard) 
    if state == 0
        return nothing
    else
        next_state = state & (state-1)
        next_item = LSB(state)
        return next_item,next_state
    end
end
 
Random.rand(rng::Random.AbstractRNG, ::Random.SamplerType{BitBoard}) = BitBoard(rand(rng, UInt64))

#Extend minus operator on bitboards"
@inline -(a::BitBoard, b::BitBoard) = BitBoard(a.n - b.n)
@inline -(a::BitBoard, b::Integer) = -(promote(a,b)...)
@inline -(a::Integer, b::BitBoard) = -(promote(a,b)...)
#Extend add operator on bitboards"
@inline +(a::BitBoard, b::BitBoard) = BitBoard(a.n + b.n)
@inline +(a::BitBoard, b::Integer) = +(promote(a,b)...)
@inline +(a::Integer, b::BitBoard) = +(promote(a,b)...)
#Extend multiply operator on bitboards"
@inline *(a::BitBoard, b::BitBoard) = BitBoard(a.n * b.n)
@inline *(a::BitBoard, b::Integer) = *(promote(a,b)...)
@inline *(a::Integer, b::BitBoard) = *(promote(a,b)...)

#Extend comparison operators to compare bitboards to integers
@inline ==(a::BitBoard, b::BitBoard) = a.n == b.n
@inline ==(a::BitBoard, b::Integer) = ==(promote(a,b)...)
@inline ==(a::Integer, b::BitBoard) = ==(promote(a,b)...)

#Extend comparison operators to compare bitboards
@inline <(a::BitBoard, b::BitBoard) = a.n < b.n
@inline <(a::BitBoard, b::Integer) = <(promote(a,b)...)
@inline <(a::Integer, b::BitBoard) = <(promote(a,b)...)

@inline >(a::BitBoard, b::BitBoard) = a.n > b.n
@inline >(a::BitBoard, b::Integer) = >(promote(a,b)...)
@inline >(a::Integer, b::BitBoard) = >(promote(a,b)...)

#Extend and operator on bitboards"
@inline function Base.:&(a::BitBoard,b::BitBoard)
    BitBoard(a.n & b.n)
end

#Extend or operator on bitboards"
@inline |(a::BitBoard, b::BitBoard) = BitBoard(a.n | b.n)
#Extend xor operator on bitboards"
@inline ⊻(a::BitBoard, b::BitBoard) = BitBoard(a.n ⊻ b.n)
#Extend not operator on bitboards"
@inline ~(a::BitBoard) = BitBoard(~a.n)

#Extend bitshift left operator on bitboards"
@inline <<(a::BitBoard, b::BitBoard) = BitBoard(a.n << b.n)
#Extend bitshift right operator on bitboards"
@inline >>(a::BitBoard, b::BitBoard) = BitBoard(a.n >> b.n)
#Extend bitshift left operator for integers on bitboards"
@inline <<(a::BitBoard, b::Integer) = BitBoard(a.n << b)
#Extend bitshift right operator for integers on bitboards"
@inline >>(a::BitBoard, b::Integer) = BitBoard(a.n >> b)

@inbounds Base.getindex(a::AbstractArray, i::BitBoard) = getindex(a, i.n)
@inbounds Base.setindex!(a::AbstractArray ,v, i::BitBoard) = setindex!(a, v, i.n)

#convert and promote integers to bitboards
Base.convert(::Type{BitBoard}, int::Integer) = BitBoard(int)
Base.convert(::Type{UInt64}, b::BitBoard) = b.n
Base.promote_rule(::Type{BitBoard}, ::Type{<:Integer}) = BitBoard

Base.parse(::Type{BitBoard},s::String) = BitBoard(parse(UInt64,s))

"Define length of occupied positions in bb"
Base.length(bb::BitBoard) = count_ones(bb)

Base.count_ones(bb::BitBoard) = count_ones(bb.n)

@inline setone(bb::BitBoard,index::Integer) = BitBoard(setone(bb.n, index))

@inline setzero(bb::BitBoard,index::Integer) = BitBoard(setzero(bb.n, index))

"Least significant bit of a bitboard, returned as a UInt8"
@inline LSB(bb::BitBoard) = LSB(bb.n)

"Returns a single bitboard representing the positions of an array of pieces"
@inline function bb_union(piece_vec::AbstractArray{BitBoard})
    bb = BitBoard()
    for piece in piece_vec
        bb |= piece
    end
    return bb
end

"Count the total number of pieces in a vector of bitboards"
function count_pieces(pieces::AbstractArray{BitBoard})
    count = 0
    for bb in pieces
        count += length(bb)
    end
    return count
end