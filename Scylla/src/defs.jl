#Define constants used by the Engine
#Utility functions for general use

const rng = Xoshiro(2955)

const NULL_PIECE = UInt8(0)
"Index associated with piecetype"
const King = UInt8(1)
const Queen = UInt8(2)
const Rook = UInt8(3)
const Bishop = UInt8(4)
const Knight = UInt8(5)
const Pawn = UInt8(6)

const FEN_DICT = Dict('K' => King, 'Q' => Queen, 'R' => Rook, 
                     'B' => Bishop, 'N' => Knight, 'P' => Pawn)

const startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

"return letter associated with piecetype index"
function piece_letter(p::UInt8)
    for (k,v) in FEN_DICT
        if p==v
            return k
        end
    end
    return ""
end

"Colour ID used in movegen/boardstate"
const white = UInt8(0)
const black = UInt8(6)

"instruction to move generator"
const ATTACKONLY = UInt64(0)
const ALLMOVES = UInt64(1)

const ZOBRIST_KEYS = rand(rng, BitBoard, 12 * 64 + 9)

const FIRST_MOVE_INDEX = 0

const NOFLAG = UInt8(0)
const KCASTLE = UInt8(1)
const QCASTLE = UInt8(2)
const EPFLAG = UInt8(3)
const DPUSH = UInt8(4)
const PROMQUEEN = UInt8(5)
const PROMROOK = UInt8(6)
const PROMBISHOP = UInt8(7)
const PROMKNIGHT = UInt8(8)

const PROMSHIFT = PROMQUEEN - Queen

"decide which piecetype to promote to"
function promote_type(flag)
    if flag >= PROMQUEEN
        return flag - PROMSHIFT
    end
    return NULL_PIECE
end

"return the promotion flag identifier using the char representing a piece"
function promote_id(c::Char)
    piecetype = FEN_DICT[uppercase(c)]
    return piecetype + PROMSHIFT
end

struct Promote end

struct Neutral end
struct Loss end
struct Draw end

const GAME_STATE = Union{Neutral, Loss, Draw}

"types of nodes based on position in search tree"
const NONE = UInt8(0)
const ALPHA = UInt8(1)
const BETA = UInt8(2)
const EXACT = UInt8(3)

setone(num::Integer, index::Integer) = num | (UInt64(1) << index)

setzero(num::Integer, index::Integer) = num & ~(UInt64(1) << index)

"Least significant bit of an integer, returned as a UInt8"
LSB(int::Integer) = UInt8(trailing_zeros(int))

"Get a rank from a 0-63 index"
rank(ind) = 7 - (ind >> 3)
"Get a file from a 0-63 index"
file(ind) = ind % 8

"convert a position in algebraic notation to a number from 0-63"
function algebraic_to_numeric(pos::AbstractString)
    rank = parse(Int, pos[2])
    file = Int(pos[1]) - Int('a') + 1
    return (-rank + 8) * 8 + file - 1
end

"take in all possible moves as a bitboard for a given piece from a txt file"
function read_txt(type,filename)
    data = Vector{type}()
    data_str = readlines("$(dirname(@__DIR__))/src/move_BBs/$(filename).txt")
    for d in data_str
        push!(data, parse(type,d))
    end   
    return data
end

"returns a list of positions of set bits in an integer"
function identify_locations(int::Integer)::Vector{UInt8}
    locations = Vector{UInt8}()
    temp = int
    while temp != 0
        loc = LSB(temp) 
        push!(locations,loc)
        temp &= temp - 1      
    end
    return locations
end

"convert a position from number 0-63 to rank/file notation"
UCIpos(pos) = ('a' + file(pos)) * string(Int(rank(pos) + 1))

#maximum search depth
const MAXDEPTH::UInt8 = UInt8(32)
const MINDEPTH::UInt8 = UInt8(0)
const DEFAULTDEPTH::UInt8 = UInt8(20)
const DEFAULTTIME::Float64 = Float64(1.5)
const DEFAULTNODES::UInt32 = UInt32(1e8)
#check for out of time/quit message every x nodes
const CHECKNODES::UInt32 = UInt32(1000)

abstract type Control end

"Time control for engine, where time is in seconds"
struct Time <: Control
    maxtime::Float64
    maxdepth::UInt8
end
Time() = Time(DEFAULTTIME, DEFAULTDEPTH)
Time(max_t) = Time(max_t, DEFAULTDEPTH)

struct Depth <: Control
    maxdepth::UInt8
end
Depth() = Depth(MAXDEPTH)

struct Nodes <: Control
    maxnodes::UInt64
    maxdepth::UInt8
end
Nodes() = Nodes(DEFAULTNODES, DEFAULTDEPTH)
Nodes(nodes) = Nodes(nodes, DEFAULTDEPTH)

struct Mate <: Control
    maxdepth::UInt8
end
Mate() = Mate(DEFAULTDEPTH)
