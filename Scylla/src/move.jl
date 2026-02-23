#Define move struct and make/unmake move
#Also utilities for incrementally updating boardstate
#Move is defined by the piece moving - piece_type (3 bits)
#Where it is moving from - from (6 bits)
#Where it is moving to - to (6 bits)
#What (if any) piece it is capturing - capture_type (3 bits)
#Any flag for pawns/castling - flag (4 bits)
#Score of move from heuristic - score (8 bits)
#This is packed into a UInt32

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

struct Move
    n::UInt32
end

"Mask and shift UInt32 inside Move struct to unpack move data"
pc_type(move::Move) = UInt8(move.n & PIECEMASK)
from(move::Move) = UInt8((move.n >> FROMSHIFT) & LOCMASK)
to(move::Move) = UInt8((move.n >> TOSHIFT) & LOCMASK)
cap_type(move::Move) = UInt8((move.n >> CAPSHIFT) & PIECEMASK)
flag(move::Move) = UInt8((move.n >> FLAGSHIFT) & FLAGMASK)
score(move::Move) = UInt8((move.n >> SCORESHIFT) & SCOREMASK)

"Return move with score set"
set_score(move::Move, score::UInt8) = Move(move.n | (UInt32(score) << SCORESHIFT))

"return true if move captures a piece"
iscapture(move::Move) = cap_type(move) > 0

"allocate array of null moves with length len"
nulls(len::Integer) = [NULLMOVE for _ in 1:len]

function unpack_move(move::Move)
    return (pc_type(move),
            from(move),
            to(move),
            cap_type(move),
            flag(move))
end

"construct move struct, containing a UInt32"
function Move(pc_type::UInt8, from::UInt8, to::UInt8, cap_type::UInt8, flag::UInt8, score=UInt8(0))
    return Move(UInt32(pc_type) |
    (UInt32(from) << FROMSHIFT) |
    (UInt32(to) << TOSHIFT) |
    (UInt32(cap_type) << CAPSHIFT) | 
    (UInt32(flag) << FLAGSHIFT) |
    (UInt32(score) << SCORESHIFT))
end

const NULLMOVE = Move(UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0))

struct Move_BB
    king::SVector{64, BitBoard}
    knight::SVector{64, BitBoard}
    CRightsMask::SVector{6, UInt8}
    castleCheck::SVector{6, BitBoard}
end

"constructor for Move_BB that reads all moves from txt files"
function Move_BB()
    king_mvs = read_txt(BitBoard, "king")
    knight_mvs = read_txt(BitBoard, "knight")
    Crights = [0b1100, 0b1110, 0b1101, 0b0011, 0b1011, 0b0111]
    castle_check = read_txt(BitBoard, "castleCheck")
    return Move_BB(king_mvs, knight_mvs, Crights, castle_check)
end

const moveset = Move_BB()