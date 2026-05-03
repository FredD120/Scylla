#Define move struct
#Move is defined by the piece moving - piece_type (3 bits)
#Where it is moving from - from (6 bits)
#Where it is moving to - to (6 bits)
#What (if any) piece it is capturing - capture_type (3 bits)
#Any flag for pawns/castling - flag (4 bits)
#Score of move from heuristic - score (8 bits)
#This is packed into a UInt32

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

remove_score(move::Move) = Move(move.n & MOVEMASK)
set_score(move::Move, score::UInt8) = Move(remove_score(move).n | (UInt32(score) << SCORESHIFT))

"helper functions to determine contents of move struct"
is_capture(move::Move) = is_capture(cap_type(move))
is_capture(cap_type::UInt8) = cap_type > 0

is_castle(move_flag::UInt8) = (move_flag == KING_CASTLE) || (move_flag == QUEEN_CASTLE)

function is_promotion(move_flag::UInt8)
    return (move_flag == PROMQUEEN) ||
           (move_flag == PROMROOK) ||
           (move_flag == PROMBISHOP) ||
           (move_flag == PROMKNIGHT)
end

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
end

"constructor for Move_BB that reads all moves from txt files"
function Move_BB()
    king_mvs = get_normal_masks("king")
    knight_mvs = get_normal_masks("knight")
    return Move_BB(king_mvs, knight_mvs)
end

const MOVESET = Move_BB()

"named tuple storing castling moves for white and black king-/queen-side"
const CASTLE_MOVES = (
    white_kingside = Move(KING, UInt8(60), UInt8(62), NULL_PIECE, KING_CASTLE),
    white_queenside = Move(KING, UInt8(60), UInt8(58), NULL_PIECE, QUEEN_CASTLE),
    black_kingside  = Move(KING, UInt8(4), UInt8(6), NULL_PIECE, KING_CASTLE),
    black_queenside = Move(KING, UInt8(4), UInt8(2), NULL_PIECE, QUEEN_CASTLE)
)