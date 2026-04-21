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

const TYPICAL_GAME_LENGTH = 100

const FIRST_MOVE_INDEX = 0

const NOFLAG = UInt8(0)
const KING_CASTLE = UInt8(1)
const QUEEN_CASTLE = UInt8(2)
const ENPASSANT = UInt8(3)
const DOUBLE_PUSH = UInt8(4)
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

const GameState = Union{Neutral, Loss, Draw}
const LOSS = Loss()
const DRAW = Draw()

### Bitboard Features ###

setone(num::I, index::Integer) where {I <: Integer} = num | (I(1) << index)

setzero(num::I, index::Integer) where {I <: Integer} = num & ~(I(1) << index)

"Least significant bit of an integer, returned as a UInt8"
LSB(int::Integer) = UInt8(trailing_zeros(int))


### Move Features ###

const PIECEMASK = UInt32(0x7)
const LOCMASK   = UInt32(0x3F)
const FLAGMASK = UInt32(0xF)
const SCOREMASK = UInt32(0xFF)

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

const MOVEMASK = UInt32((1 << SCORESHIFT) - 1)


### Move Generator Features ###

"types to allow multiple dispatch during move generation for all moves or only attacks"
abstract type MoveMode end

struct AllMoves <: MoveMode end

struct AttacksOnly <: MoveMode end

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

"named tuple storing positions of rook home squares for use when generating castling moves"
const ROOK_START_SQUARES = (
    white_kingside = UInt8(63),
    white_queenside = UInt8(56),
    black_kingside  = UInt8(7),
    black_queenside = UInt8(0)
)

"named tuple storing positions of squares the rook finishes on after castling"
const ROOK_CASTLE_SQUARES = (
    white_kingside = UInt8(61),
    white_queenside = UInt8(59),
    black_kingside  = UInt8(5),
    black_queenside = UInt8(3)
)

"named tuple storing castling rights masks to check if it is legal for black/white to castle king/queenside"
const CASTLE_RIGHTS = (
    white_king_and_queen = UInt8(12),
    white_king = UInt8(14),
    white_queen = UInt8(13),
    black_king_and_queen = UInt8(3),
    black_king = UInt8(11),
    black_queen = UInt8(7)
)

"named tuple storing masks of squares that can't be blocked for black/white to castle king/queenside"
const CASTLE_BLOCKS = (
    white_king = BitBoard(0b01100000_00000000_00000000_00000000_00000000_00000000_00000000_00000000),
    white_queen = BitBoard(0b00001110_00000000_00000000_00000000_00000000_00000000_00000000_00000000),
    black_king = BitBoard(0b00000000_00000000_00000000_00000000_00000000_00000000_00000000_01100000),
    black_queen = BitBoard(0b00000000_00000000_00000000_00000000_00000000_00000000_00000000_00001110),
)

"named tuple storing masks of squares that can't be attacked for black/white to castle king/queenside"
const CASTLE_ATTACKS = (
    white_king = BitBoard(0b01110000_00000000_00000000_00000000_00000000_00000000_00000000_00000000),
    white_queen = BitBoard(0b00011100_00000000_00000000_00000000_00000000_00000000_00000000_00000000),
    black_king = BitBoard(0b00000000_00000000_00000000_00000000_00000000_00000000_00000000_01110000),
    black_queen = BitBoard(0b00000000_00000000_00000000_00000000_00000000_00000000_00000000_00011100),
)

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

const PAWN_LEFT_ATTACK_MASK = BitBoard(0x7F7F7F7F7F7F7F7F)

const PAWN_RIGHT_ATTACK_MASK = BitBoard(0xFEFEFEFEFEFEFEFE)

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
uci_pos(pos) = ('a' + file(pos)) * string(Int(rank(pos) + 1))


### Engine Features ###

#maximum search depth
const MAXDEPTH::UInt8 = UInt8(32)
const MINDEPTH::UInt8 = UInt8(0)
const DEFAULTDEPTH::UInt8 = UInt8(24)
const DEFAULTTIME::Float64 = Float64(1.5)
const DEFAULTNODES::UInt32 = UInt32(1e8)
#check for out of time/quit message every x nodes
const CHECKNODES::UInt32 = UInt32(10_000)

abstract type Control end

"Time control for engine, where time is in seconds"
struct Time <: Control
    maxtime::Float64
    maxdepth::UInt8
end
Time(;maxdepth = DEFAULTDEPTH) = Time(DEFAULTTIME, maxdepth)
Time(max_t) = Time(max_t, DEFAULTDEPTH)

"Depth control for engine, where depth is in halfmoves"
struct Depth <: Control
    maxdepth::UInt8

    "inner constructor, limits depth to MAXDEPTH"
    Depth(depth) = new(min(depth, MAXDEPTH))
end
Depth(;maxdepth = MAXDEPTH) = Depth(maxdepth)

"Node control for engine, where nodes are any leaf node visited"
struct Nodes <: Control
    maxnodes::UInt64
    maxdepth::UInt8
end
Nodes(;maxdepth = DEFAULTDEPTH) = Nodes(DEFAULTNODES, maxdepth)
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
const TT_DEFAULT_MB = 48
const TT_MIN_SIZE = 0
const TT_MAX_MB = 192
const TT_MAX_SIZE = 25


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
const MVV_LVA = UInt8[
    50, 40, 30, 30, 10,
    51, 41, 31, 31, 11,
    52, 42, 32, 32, 12,
    53, 43, 33, 33, 13,
    53, 43, 33, 33, 13,
    55, 45, 35, 35, 15]


### PST Features ###

"quantise phase into a byte"
const QUANTISATION_SHIFT::Int32 =  8
const QUANTISATION::Int32 = 1 << QUANTISATION_SHIFT
"number of pieces left when we are fully in endgame"
const MIN_PIECES::Int32 = 8
"number of pieces left when endgame begins"
const MAX_PIECES::Int32 = 24
const GRADIENT::Int32 = QUANTISATION / (MAX_PIECES - MIN_PIECES)
const INTERCEPT::Int32 = -MIN_PIECES * GRADIENT


### CLI Features ###

const NAME = "Scylla"

const UCI_OK_MESSAGE = string(
    "id name ", NAME, "\n",
    "pid author FD\n",
    "option name Hash type spin default $TT_DEFAULT_MB min $TT_MIN_SIZE max $TT_MAX_MB\n",
    "option name Clear Hash type button\n",
    "uciok")

# fraction of a second to give time to send info back to GUI
const GUI_SAFETY_FACTOR = 0.05

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

        "--perft_full", "-f"
            help = "Run perft on over 100 tricky positions"
            action = :store_true 

        "--pseudolegal", "-s"
            help = "Run pseudolegal perft to validate pseudolegal move generation and legality checking"
            action = :store_true 
            
        "--maxtime", "-m"
            help = "Maximum time the engine will spend on a move during testing" 
            arg_type = Float64
            default = 0.5
    end
    return parse_args(s)
end