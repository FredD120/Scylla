#Define constants used by the Engine
#Utility functions for general use

### General Setup ###

const rng = Xoshiro(2955)

### Board Features ###

const NULL_PIECE = UInt8(0)
"Index associated with piecetype"
const KING = UInt8(1)
const QUEEN = UInt8(2)
const ROOK = UInt8(3)
const BISHOP = UInt8(4)
const KNIGHT = UInt8(5)
const PAWN = UInt8(6)

const FEN_DICT = Dict('K' => KING, 'Q' => QUEEN, 'R' => ROOK, 
                     'B' => BISHOP, 'N' => KNIGHT, 'P' => PAWN)

const START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

"return letter associated with piecetype index"
function piece_letter(p::UInt8)
    for (key, value) in FEN_DICT
        if p == value
            return key
        end
    end
    return ""
end

"Colour ID used in movegen/boardstate"
const WHITE = UInt8(0)
const BLACK = UInt8(6)

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

const PROMSHIFT = PROMQUEEN - QUEEN

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


### Bitboard Features ###

setone(num::Integer, index::Integer) = num | (UInt64(1) << index)

setzero(num::Integer, index::Integer) = num & ~(UInt64(1) << index)

"Least significant bit of an integer, returned as a UInt8"
LSB(int::Integer) = UInt8(trailing_zeros(int))


### Move Features ###

const PIECEMASK = 0x7
const LOCMASK   = 0x3F
const FLAGMASK = 0xF
const SCOREMASK = 0xFF

const TYPESIZE = 3
const FROMSIZE = 6
const TOSIZE   = 6
const CAPSIZE  = 3
const FLAGSIZE = 4

const FROMSHIFT = TYPESIZE
const TOSHIFT   = TYPESIZE + FROMSIZE
const CAPSHIFT  = TYPESIZE + FROMSIZE + TOSIZE
const FLAGSHIFT = TYPESIZE + FROMSIZE + TOSIZE + CAPSIZE
const SCORESHIFT = TYPESIZE + FROMSIZE + TOSIZE + CAPSIZE + FLAGSIZE


### Move Generator Features ###

"read masks for checking castling rights and legality"
function get_castle_masks()
    h5open("$(dirname(@__DIR__))/src/move_bitboards/castle.h5", "r") do fid
        castle_rights = read(fid["rights"])
        castle_check = read(fid["check"])
        return castle_rights, castle_check
    end
end

"read bitboards for king/knight moves from any position"
function get_normal_masks(piece)
    h5open("$(dirname(@__DIR__))/src/move_bitboards/$(piece).h5", "r") do fid
        return read(fid["moves"])
    end
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

"bitboard masks for pawn double push and promotion legality
shift to define whether pawn moves forwards or backwards from white's perspective"
const WHITE_MASKS = (
        doublepush = BitBoard(0xFF0000000000),
        promote = BitBoard(0xFF),
        shift =  8
)

const BLACK_MASKS = (
        doublepush = BitBoard(0xFF0000),
        promote = BitBoard(0xFF00000000000000),
        shift =  -8
)

const PROMOTE_TYPES = [PROMQUEEN, PROMROOK, PROMBISHOP, PROMKNIGHT]

"max theoretical number of moves in a boardstate is ≈ 200, assuming 20 move depth gives ≈ 4000 total moves in move heap"
const MAXMOVES = 4096

### Position Descriptions

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

"convert a position from number 0-63 to rank/file notation"
UCIpos(pos) = ('a' + file(pos)) * string(Int(rank(pos) + 1))


### Engine Features ###

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


### Transposition Table Features ###

"types of nodes based on position in search tree"
const NONE = UInt8(0)
const ALPHA = UInt8(1)
const BETA = UInt8(2)
const EXACT = UInt8(3)

const MB_SIZE = 1048576 #size of a Mb in bytes
const TT_DEFAULT_MB = 32
const TT_MIN_MB = 0
const TT_MAX_MB = 64


### Heuristic Evaluation Features ###

const MAXMATEDEPTH::Int16 = Int16(100)
const INF::Int16 = typemax(Int16)
const MATE::Int16 = INF - MAXMATEDEPTH

"Score of PV/TT move = 255"
const MAXMOVESCORE::UInt8 = typemax(UInt8)
"Minimum score of a capture move = 199"
const MINCAPSCORE::UInt8 = MAXMOVESCORE - 56

""" 
Used for move ordering

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


### CLI Features ###

const NAME = "Scylla"

const UCI_OK_MESSAGE = string(
    "id name ", NAME, "\n",
    "pid author FD\n",
    "option name Hash type spin default $TT_DEFAULT_MB min $TT_MIN_MB max $TT_MAX_MB\n",
    "option name Clear Hash type button\n",
    "uciok")


### Test Features ###

function test_args()
    s = ArgParseSettings(description="Run chess engine tests with optional extra tests.")

    @add_arg_table! s begin
        "--perft_extra", "-p"
            help = "Run more expensive perft tests to validate move generation and incremental updates"
            action = :store_true

        "--verbose", "-v"
            help = "Verbose output"
            action = :store_true

        "--TT_perft", "-t"
            help = "Run perft from start position with bulk counting and hash table"
            action = :store_true
            
        "--engine", "-e"
            help = "Run expensive engine tests from difficult test suite"
            action = :store_true

        "--profile", "-f"
            help = "Profile engine on a slow position"
            action = :store_true 
            
        "--maxtime", "-m"
            help = "Maximum time the engine will spend on a move during testing" 
            arg_type = Float64
            default = 0.5
    end
    return parse_args(s)
end