"return location of king for a given colour"
@inline locate_king(board::BoardState, colour) = LSB(colour_piece(board, colour, KING))

"return location of king for side to move"
@inline locate_king(board::BoardState) = locate_king(board, board.colour)

"Masked 4-bit integer representing king- and queen-side castling rights for one side"
@inline function get_castle_rights(castling, colour_id, king_or_queen_side)
    #colour_id is 0 for white and 1 for black
    #king_or_queen_side allows masking out of only king/queen side
    #for a given colour, =0 if both, 1 = king, 2 = queen
    @inbounds rights = CASTLE_RIGHTS[3 * colour_id + king_or_queen_side + 1]
    return castling & rights
end

"store information about how to make moves without king being captured"
struct LegalInfo
    attackers::BitBoard     # pieces currently attacking the king
    evasion_mask::BitBoard  # squares that can be moved to while/if in check
    rookpins::BitBoard      # all squares that can be moved to by pieces pinned by a rook
    bishoppins::BitBoard    # all squares that can be moved to by pieces pinned by a bishop
    attack_sqs::BitBoard    # all squares being attacked by the opponent
    attack_num::UInt8       # number of enemy pieces attacking the king
end

"constructor that uses board information to compute info on blocks, pins and evasions for legal move generation"
function LegalInfo(board::BoardState)
    attackers = BITBOARD_FULL
    evasions = BITBOARD_EMPTY
    attacker_num = 0
    
    all_pcs = all_pieces(board)
    king_bb = board.pieces[board.colour + KING]
    position = LSB(king_bb)

    #construct BB of all enemy attacks, must remove king when checking if square is attacked
    all_except_king = all_pcs & ~(king_bb)
    attacked_sqs = enemy_attacks(board, all_except_king)

    #if king not under attack, dont need to find attacking pieces or blockers
    if king_bb & attacked_sqs == BITBOARD_EMPTY
        evasions = BITBOARD_FULL
    else
        attackers = king_attackers(board, all_pcs, position)
        attacker_num = count_ones(attackers)
        #if only a single sliding piece is attacking the king, it can be blocked
        if attacker_num == 1
            kingmoves = pseudolegal_rook_moves(position, all_pcs)
            slide_attackers = kingmoves & (enemy_piece(board, ROOK) | enemy_piece(board, QUEEN))
            for attack_pos in slide_attackers
                attackmoves = pseudolegal_rook_moves(attack_pos, all_pcs)
                evasions |= attackmoves & kingmoves
            end

            kingmoves = pseudolegal_bishop_moves(position, all_pcs)
            slide_attackers = kingmoves & (enemy_piece(board, BISHOP) | enemy_piece(board, QUEEN))
            for attack_pos in slide_attackers
                attackmoves = pseudolegal_bishop_moves(attack_pos, all_pcs)
                evasions |= attackmoves & kingmoves
            end
        end
    end
    rookpins, bishoppins = detect_pins(board, position, all_pcs, all_ally_pieces(board))
    return LegalInfo(attackers, evasions, rookpins, bishoppins, attacked_sqs, attacker_num)
end

@inline pseudolegal_king_moves(location) = @inbounds MOVESET.king[location + 1]

@inline pseudolegal_knight_moves(location) = @inbounds MOVESET.knight[location + 1]

@inline pseudolegal_rook_moves(location, all_pcs) = @inbounds sliding_attacks(ROOK_MAGICS[location + 1], all_pcs, ROOK_ATTACKS)

@inline pseudolegal_bishop_moves(location, all_pcs) = @inbounds sliding_attacks(BISHOP_MAGICS[location + 1], all_pcs, BISHOP_ATTACKS)

@inline function pseudolegal_queen_moves(location, all_pcs)
    rook_attacks = sliding_attacks(ROOK_MAGICS[location + 1], all_pcs, ROOK_ATTACKS)
    bishop_attacks = sliding_attacks(BISHOP_MAGICS[location + 1], all_pcs, BISHOP_ATTACKS)
    return rook_attacks | bishop_attacks
end

"returns BB containing attacking moves assuming all pieces in BB are pawns"
@inline function pseudolegal_pawn_moves(pawn_bb, colour::Bool)
    pawn_push = cond_push(colour, pawn_bb)
    return attack_left(pawn_push) | attack_right(pawn_push)
end

"checks enemy pieces to see if any are attacking the king square, returns BB of attackers"
@inline function king_attackers(board::BoardState, all_pcs::BitBoard, location::Integer)::BitBoard
    attackers = BITBOARD_EMPTY
    enemy_queen_bb = enemy_piece(board, QUEEN)

    knight_moves = pseudolegal_knight_moves(location)
    attackers |= (knight_moves & enemy_piece(board, KNIGHT))
    
    rook_moves = pseudolegal_rook_moves(location, all_pcs)
    rook_attackers = (rook_moves & (enemy_piece(board, ROOK) | enemy_queen_bb))
    attackers |= rook_attackers

    bishop_moves = pseudolegal_bishop_moves(location, all_pcs)
    bishop_attackers = (bishop_moves & (enemy_piece(board, BISHOP) | enemy_queen_bb))
    attackers |= bishop_attackers

    pawn_attackers = pseudolegal_pawn_moves(BitBoard(1) << location, whitesmove(board.colour))
    attackers |= pawn_attackers & enemy_piece(board, PAWN)

    return attackers
end

"bitboard of all squares being attacked by the opponent"
@inline function enemy_attacks(board::BoardState, all_pcs)::BitBoard
    attacks = BITBOARD_EMPTY

    for location in enemy_piece(board, KING)
        attacks |= pseudolegal_king_moves(location)
    end
    
    for location in enemy_piece(board, KNIGHT)
        attacks |= pseudolegal_knight_moves(location)
    end

    for location in enemy_piece(board, BISHOP)
        attacks |= pseudolegal_bishop_moves(location, all_pcs)
    end

    for location in enemy_piece(board, ROOK)
        attacks |= pseudolegal_rook_moves(location, all_pcs)
    end

    for location in enemy_piece(board, QUEEN)
        attacks |= pseudolegal_queen_moves(location, all_pcs)
    end

    enemy_colour = opposite(whitesmove(board.colour))
    attacks |= pseudolegal_pawn_moves(enemy_piece(board, PAWN), enemy_colour)
    return attacks
end

"return a bitboard containing squares that can be moved to by pieces pinned by a rook"
@inline function rook_pinlines(board::BoardState, king_pos, blocks_removed, slide_attacks)
    #recalculate rook attacks with blockers removed
    rook_no_blocks = pseudolegal_rook_moves(king_pos, blocks_removed) 
    #only want moves found after removing blockers
    rpin_attacks = rook_no_blocks & ~slide_attacks
    #start by adding attackers to pin line
    rook_pins = rpin_attacks & (enemy_piece(board, ROOK) | enemy_piece(board, QUEEN))
    #iterate through rooks/queens pinning king
    for loc in rook_pins
        #add squares on pin line to pinning BB
        rook_pins |= rook_no_blocks & pseudolegal_rook_moves(loc, blocks_removed)
    end
    return rook_pins
end

"return a bitboard containing squares that can be moved to by pieces pinned by a bishop"
@inline function bishop_pinlines(board::BoardState, king_pos, blocks_removed, slide_attacks)
    bishop_no_blocks = pseudolegal_bishop_moves(king_pos, blocks_removed) 
    bpin_attacks = bishop_no_blocks & ~slide_attacks
    bishop_pins = bpin_attacks & (enemy_piece(board, BISHOP) | enemy_piece(board, QUEEN))

    for loc in bishop_pins
        bishop_pins |= bishop_no_blocks & pseudolegal_bishop_moves(loc, blocks_removed)
    end
    return bishop_pins
end

"detect pins and create rook/bishop pin BBs"
@inline function detect_pins(board::BoardState, king_pos, all_pcs, ally_pcs)
    #imagine king is a queen, what can it see?
    slide_attacks = pseudolegal_queen_moves(king_pos, all_pcs)
    #identify ally pieces seen by king
    ally_block = slide_attacks & ally_pcs
    #remove these ally pieces
    blocks_removed = all_pcs & ~ally_block

    rookpins = rook_pinlines(board, king_pos, blocks_removed, slide_attacks)
    bishoppins = bishop_pinlines(board, king_pos, blocks_removed, slide_attacks)

    return rookpins, bishoppins
end

"create a castling move where the king is considered to be the piece moving"
@inline function create_castle(king_or_queen, white_or_black)
    # king_or_queen is 0 if kingside, 1 if queenside 
    # white_or_black is 0 if white, 1 if black
    castle_lookup = king_or_queen + white_or_black * 2 + 1
    return CASTLE_MOVES[castle_lookup]
end

"creates a move from a given location using the Move struct, with flag for attacks"
@inline function moves_from_location!(type::UInt8, board::BoardState, destinations::BitBoard, origin, isattack::Bool)
    for loc in destinations
        attacked_piece_id = NULL_PIECE
        if isattack
            #move struct needs info on piece being attacked
            attacked_piece_id = identify_piecetype(board, loc)
        end
        append!(board.move_vector, Move(type, origin, loc, attacked_piece_id, NOFLAG))
    end
end

"bitboard containing only the attacks by a particular piece"
@inline attack_moves(::MoveMode, move_bb, enemy_bb) = move_bb & enemy_bb

"bitboard containing only the quiets by a particular piece"
@inline quiet_moves(::AllMoves, move_bb, all_pcs) = move_bb & ~all_pcs

"bitboard containing no moves if we only want to generate attacks"
@inline quiet_moves(::AttacksOnly, move_bb, all_pcs) = BITBOARD_EMPTY

"bitboard logic to get attacks and quiets from a set of moves"
@inline function quiets_and_attacks(moves, all_bb, enemy_bb, MODE::MoveMode)
    attacks = attack_moves(MODE, moves, enemy_bb)
    #set quiets to zero if only generating attacks
    quiets = quiet_moves(MODE, moves, all_bb)
    return quiets, attacks
end

"filter pseudolegal moves for legality for king"
@inline function legal_king_moves(loc, info::LegalInfo)
    poss_moves = pseudolegal_king_moves(loc)
    #Filter out moves that put king in check
    legal_moves = poss_moves & ~info.attack_sqs
    return legal_moves
end

"filter pseudolegal moves for legality for knight"
@inline function legal_knight_moves(loc, info::LegalInfo)
    poss_moves = pseudolegal_knight_moves(loc)
    #Filter out knight moves that don't block/capture if in check
    legal_moves = poss_moves & (info.attackers | info.evasion_mask) 
    return legal_moves
end

"filter pseudolegal moves for legality for bishop"
@inline function legal_bishop_moves(loc, all_pcs, bishoppins, info::LegalInfo)
    poss_moves = pseudolegal_bishop_moves(loc,all_pcs)
    #Filter out bishop moves that don't block/capture if in check/pinned
    legal_moves = poss_moves & (info.attackers | info.evasion_mask) & bishoppins
    return legal_moves
end

"filter pseudolegal moves for legality for rook"
@inline function legal_rook_moves(loc,all_pcs, rookpins, info::LegalInfo)
    poss_moves = pseudolegal_rook_moves(loc, all_pcs)
    #Filter out rook moves that don't block/capture if in check/pinned
    legal_moves = poss_moves & (info.attackers | info.evasion_mask) & rookpins
    return legal_moves
end

"filter pseudolegal moves for legality for queen"
@inline function legal_queen_moves(loc, all_pcs, rookpins, bishoppins, info::LegalInfo)
    legal_rook = legal_rook_moves(loc, all_pcs, rookpins, info)
    legal_bishop = legal_bishop_moves(loc, all_pcs, bishoppins, info)
    return legal_rook | legal_bishop
end

"when not pinned, use a full bitboard as a mask that allows all moves"
@inline legal_bishop_moves(loc, all_pcs, info) = legal_bishop_moves(loc, all_pcs, BITBOARD_FULL, info)
@inline legal_rook_moves(loc, all_pcs, info) = legal_rook_moves(loc, all_pcs, BITBOARD_FULL, info)
@inline legal_queen_moves(loc, all_pcs, info) = legal_queen_moves(loc, all_pcs, BITBOARD_FULL, BITBOARD_FULL, info)

"bishop can only move if pinned diagonally"
@inline pinned_bishop(piece_bb, bishoppins) = piece_bb & bishoppins

"rook can only move if pinned vertic/horizontally"
@inline pinned_rook(piece_bb, rookpins) = piece_bb & rookpins

"add all legal moves that can be made by a pinned rook from locations on bitboard that are pinned"
@inline function pinned_rook_moves!(board::BoardState, enemy_pcs, all_pcs, pinned_bb, TYPE, MODE, info::LegalInfo)
    for loc in pinned_bb
        legal = legal_rook_moves(loc, all_pcs, info.rookpins, info)
        quiets, attacks = quiets_and_attacks(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(TYPE, board, quiets, loc, false)
        moves_from_location!(TYPE, board, attacks, loc, true)
    end
end

"add all legal moves that can be made by a non-pinned rook from locations on bitboard that are not pinned"
@inline function unpinned_rook_moves!(board::BoardState, enemy_pcs, all_pcs, unpinned_bb, TYPE, MODE, info::LegalInfo)
    for loc in unpinned_bb
        legal = legal_rook_moves(loc, all_pcs, info)
        quiets, attacks = quiets_and_attacks(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(TYPE, board, quiets, loc, false)
        moves_from_location!(TYPE, board, attacks, loc, true)
    end
end

"add all legal moves that can be made by a pinned bishop from locations on bitboard that are pinned"
@inline function pinned_bishop_moves!(board::BoardState, enemy_pcs, all_pcs, pinned_bb, TYPE, MODE, info::LegalInfo)
    for loc in pinned_bb
        legal = legal_bishop_moves(loc, all_pcs, info.bishoppins, info)
        quiets, attacks = quiets_and_attacks(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(TYPE, board, quiets, loc, false)
        moves_from_location!(TYPE, board, attacks, loc, true)
    end
end

"add all legal moves that can be made by a non-pinned bishop from locations on bitboard that are not pinned"
@inline function unpinned_bishop_moves!(board::BoardState, enemy_pcs, all_pcs, unpinned_bb, TYPE, MODE, info::LegalInfo)
    for loc in unpinned_bb
        legal = legal_bishop_moves(loc, all_pcs, info)
        quiets, attacks = quiets_and_attacks(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(TYPE, board, quiets, loc, false)
        moves_from_location!(TYPE, board, attacks, loc, true)
    end
end

"add all legal moves that can be made by a non-pinned queen from locations on bitboard that are not pinned"
@inline function unpinned_queen_moves(board::BoardState, enemy_pcs, all_pcs, unpinned_bb, MODE, info::LegalInfo)
    for loc in unpinned_bb
        legal = legal_queen_moves(loc, all_pcs, info)
        quiets, attacks = quiets_and_attacks(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(QUEEN, board, quiets, loc, false)
        moves_from_location!(QUEEN, board, attacks, loc, true)
    end
end

"generate all moves by all queens of side-to-move. may leave king in check"
@inline function get_pseudolegal_queen_moves!(board::BoardState, enemy_pcs, all_pcs, MODE)
    piece_bb = ally_piece(board, QUEEN)
    all_pseudolegal_rooks!(board, piece_bb, enemy_pcs, all_pcs, QUEEN, MODE)
    all_pseudolegal_bishops!(board, piece_bb, enemy_pcs, all_pcs, QUEEN, MODE)
end

"returns attack and quiet moves only if legal, based on checks and pins"
@inline function get_queen_moves!(board::BoardState, enemy_pcs, all_pcs, MODE, info::LegalInfo)
    piece_bb = ally_piece(board, QUEEN)
    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinned_bb = piece_bb & ~(info.rookpins | info.bishoppins)
    rook_pinned_bb = pinned_rook(piece_bb, info.rookpins)
    bishop_pinned_bb = pinned_bishop(piece_bb, info.bishoppins)

    unpinned_queen_moves(board, enemy_pcs, all_pcs, unpinned_bb, MODE, info)
    pinned_rook_moves!(board, enemy_pcs, all_pcs, rook_pinned_bb, QUEEN, MODE, info)
    pinned_bishop_moves!(board, enemy_pcs, all_pcs, bishop_pinned_bb, QUEEN, MODE, info)
end

"iterate through all rooks/queens for side-to-move and add their moves to movelist"
@inline function all_pseudolegal_rooks!(board::BoardState, piece_bb, enemy_pcs, all_pcs, TYPE, MODE)
    for loc in piece_bb
        moves = pseudolegal_rook_moves(loc, all_pcs)
        quiets, attacks = quiets_and_attacks(moves, all_pcs, enemy_pcs, MODE)

        moves_from_location!(TYPE, board, quiets, loc, false)
        moves_from_location!(TYPE, board, attacks, loc, true)
    end
end

"generate all moves by all rooks of side-to-move. may leave king in check"
@inline function get_pseudolegal_rook_moves!(board::BoardState, enemy_pcs, all_pcs, MODE)
    piece_bb = ally_piece(board, ROOK)
    all_pseudolegal_rooks!(board, piece_bb, enemy_pcs, all_pcs, ROOK, MODE)
end

"returns attack and quiet moves only if legal for rook, based on checks and pins"
@inline function get_rook_moves!(board::BoardState, enemy_pcs, all_pcs, MODE, info::LegalInfo)
    piece_bb = ally_piece(board, ROOK)
    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinned_bb = piece_bb & ~(info.rookpins | info.bishoppins)
    pinned_bb = pinned_rook(piece_bb, info.rookpins)

    pinned_rook_moves!(board, enemy_pcs, all_pcs, pinned_bb, ROOK, MODE, info)
    unpinned_rook_moves!(board, enemy_pcs, all_pcs, unpinned_bb, ROOK, MODE, info)
end

"iterate through all rooks/queens for side-to-move and add their moves to movelist"
@inline function all_pseudolegal_bishops!(board::BoardState, piece_bb, enemy_pcs, all_pcs, TYPE, MODE)
    for loc in piece_bb
        moves = pseudolegal_bishop_moves(loc, all_pcs)
        quiets, attacks = quiets_and_attacks(moves, all_pcs, enemy_pcs, MODE)

        moves_from_location!(TYPE, board, quiets, loc, false)
        moves_from_location!(TYPE, board, attacks, loc, true)
    end
end

"generate all moves by all bishops of side-to-move. may leave king in check"
@inline function get_pseudolegal_bishop_moves!(board::BoardState, enemy_pcs, all_pcs, MODE)
    piece_bb = ally_piece(board, BISHOP)
    all_pseudolegal_bishops!(board, piece_bb, enemy_pcs, all_pcs, BISHOP, MODE)
end

"returns attack and quiet moves only if legal for bishop, based on checks and pins"
@inline function get_bishop_moves!(board::BoardState, enemy_pcs, all_pcs, MODE, info::LegalInfo)
    piece_bb = ally_piece(board, BISHOP)
    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinned_bb = piece_bb & ~(info.rookpins | info.bishoppins)
    pinned_bb = pinned_bishop(piece_bb, info.bishoppins)

    pinned_bishop_moves!(board, enemy_pcs, all_pcs, pinned_bb, BISHOP, MODE, info)
    unpinned_bishop_moves!(board, enemy_pcs, all_pcs, unpinned_bb, BISHOP, MODE, info)
end

"returns all possible attack/quiet move for all knights of side-to-move, regardless of whether king is left under attack"
@inline function get_pseudolegal_knight_moves!(board::BoardState, enemy_pcs, all_pcs, MODE)
    piece_bb = ally_piece(board, KNIGHT)

    for loc in piece_bb
        moves = pseudolegal_knight_moves(loc)
        quiets, attacks = quiets_and_attacks(moves, all_pcs, enemy_pcs, MODE)

        moves_from_location!(KNIGHT, board, quiets, loc, false)
        moves_from_location!(KNIGHT, board, attacks, loc, true)
    end
end

"returns attack and quiet moves only if legal for knight, based on checks and pins"
@inline function get_knight_moves!(board::BoardState, enemy_pcs, all_pcs, MODE, info::LegalInfo)
    #split into pinned and unpinned pieces, only unpinned knights can move
    piece_bb = ally_piece(board, KNIGHT)
    unpinned_bb = piece_bb & ~(info.rookpins | info.bishoppins)
    
    for loc in unpinned_bb
        legal = legal_knight_moves(loc, info)
        quiets, attacks = quiets_and_attacks(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(KNIGHT, board, quiets, loc, false)
        moves_from_location!(KNIGHT, board, attacks, loc, true)
    end
end

"mask out opponents castle rights, retrieve king- and queen-side castling rights index if possible. 
must return a Bitboard to iterate through the set bits"
function self_castle_rights(castle_rights, colour_id)::BitBoard
    opponent_id = (colour_id + 1) % 2
    return get_castle_rights(castle_rights, opponent_id, 0)
end

"return mask for squares that can block castling, either by ally or enemy pieces"
castle_blocker_mask(castle_id) = CASTLE_BLOCKS[castle_id + 1]

"retrieve mask from lookup table containing squares that must not be attacked to castle"
castle_attacker_mask(castle_id) = CASTLE_ATTACKS[castle_id + 1]

"returns true if there are no attacks or blockers on squares required for castling"
function can_castle(castle_id, all_pieces_bb, attacked_squares_bb)
    if castle_blocker_mask(castle_id) & all_pieces_bb == 0
        if castle_attacker_mask(castle_id) & attacked_squares_bb == 0
            return true
        end
    end
    return false
end

"generate castling moves for side-to-move if the rights exist and it is legal to do so"
@inline function get_castle_moves!(::AllMoves, board::BoardState, all_pcs, attacked_squares)
    castle_rights = board.castle
    colour_index = colour_id(board.colour)
    for castle_id in self_castle_rights(castle_rights, colour_index)
        if can_castle(castle_id, all_pcs, attacked_squares)
            append!(board.move_vector, create_castle(UInt8(castle_id % 2), colour_index))
        end
    end
end

"castling must be legal to be generated, but correctness requirement on all-attacked-sqaures is lower"
@inline function get_pseudolegal_castle_moves!(MODE::AllMoves, board::BoardState, all_pcs)
    attacked_squares = enemy_attacks(board, all_pcs)
    get_castle_moves!(MODE, board, all_pcs, attacked_squares)
end

"castling is a quiet move, not generated during attack-only move generation"
get_pseudolegal_castle_moves!(::AttacksOnly, _, _) = nothing
get_castle_moves!(::AttacksOnly, _, _, _) = nothing

"returns all possible attack/quiet move for the king for side-to-move, regardless of whether it is left under attack"
@inline function get_pseudolegal_king_moves!(board::BoardState, enemy_pcs, all_pcs, MODE)
    piece_bb = ally_piece(board, KING)

    for loc in piece_bb
        moves = pseudolegal_king_moves(loc)
        quiets, attacks = quiets_and_attacks(moves, all_pcs, enemy_pcs, MODE)

        moves_from_location!(KING, board, quiets, loc, false)
        moves_from_location!(KING, board, attacks, loc, true)
    end
end

"generate attacks, quiet moves and castles for king only if legal, based on checks"
@inline function get_king_moves!(board::BoardState, enemy_pcs, all_pcs, MODE, info::LegalInfo)
    piece_bb = ally_piece(board, KING)
    for loc in piece_bb
        legal = legal_king_moves(loc, info)
        quiets, attacks = quiets_and_attacks(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(KING, board, quiets, loc, false)
        moves_from_location!(KING, board, attacks, loc, true)
    end
end

"use bitshifts to push all white/black pawns at once"
@inline cond_push(colour::Bool, pawn_bb) = ifelse(colour, pawn_bb >> 8, pawn_bb << 8)

@inline attack_left(piece_bb) = (piece_bb >> 1) & PAWN_LEFT_ATTACK_MASK

@inline attack_right(piece_bb) = (piece_bb << 1) & PAWN_RIGHT_ATTACK_MASK

"appends 4 promotion moves"
@inline function append_moves!(board::BoardState, piece_type, from, to, capture_type,::Promote)
    for flag in PROMOTE_TYPES
        append!(board.move_vector, Move(piece_type, from, to, capture_type, flag))
    end
end

"appends a non-promote move with a given flag"
@inline function append_moves!(board::BoardState, piece_type, from, to, capture_type, flag::UInt8)
    append!(board.move_vector, Move(piece_type, from, to, capture_type, flag))
end

"Create list of pawn push moves with a given flag"
@inline function push_moves!(board::BoardState, single_push, shift, flag)
    for q1 in single_push
        append_moves!(board, PAWN, UInt8(q1 + shift), q1, NULL_PIECE, flag)
    end
end

"Create list of double pawn push moves"
@inline function double_push_moves!(board::BoardState, double_push, shift)
    for q2 in double_push
        append!(board.move_vector, Move(PAWN, UInt8(q2 + 2 * shift), q2, NULL_PIECE, DOUBLE_PUSH))
    end
end

"Create list of pawn capture moves with a given flag"
@inline function capture_moves!(board::BoardState, attackable_mask, attack_left, attack_right, shift, flag)
    for la in (attack_left & attackable_mask)
        attack_piece_id = identify_piecetype(board, la)
        append_moves!(board, PAWN, UInt8(la + shift + 1), la, attack_piece_id, flag)
    end
    for ra in (attack_right & attackable_mask)
        attack_piece_id = identify_piecetype(board, ra)
        append_moves!(board, PAWN, UInt8(ra + shift - 1), ra, attack_piece_id, flag)
    end
end

"returns false if it fails edge case where EP exposes attack on king"
@inline function enpassant_edge_case(board::BoardState, from, enpassant_cap, kingpos, all_pcs)
    #test if king is on same rank as EP pawn
    if rank(from) == rank(kingpos)
        #all pcs BB after en-passant
        after_enpassant = setzero(setzero(all_pcs, from), enpassant_cap)
        kingrookmvs = pseudolegal_rook_moves(kingpos, after_enpassant)

        if (kingrookmvs & (enemy_piece(board, ROOK) | enemy_piece(board, QUEEN))) > 0
            return false
        end
    end
    return true
end

"Check legality of en-passant before adding it to move list"
@inline function push_enpassant!(board::BoardState, from, to, shift, checks, all_pcs, kingpos)
    enpassant_capture = to + shift
    if checks & (BitBoard(1) << enpassant_capture) > 0
        if enpassant_edge_case(board, from, enpassant_capture, kingpos, all_pcs)
            append!(board.move_vector, Move(PAWN, from, to, PAWN, ENPASSANT))
        end
    end
end

"Create list of pawn en-passant moves"
@inline function enpassant_moves!(board::BoardState, helper, shift, enpassant_sqs, checks, all_pcs, kingpos)
    for la in (helper.attack_left & enpassant_sqs)  
        push_enpassant!(board, UInt8(la + shift + 1), la, shift, checks, all_pcs, kingpos)
    end
    for ra in (helper.attack_right & enpassant_sqs)
        push_enpassant!(board, UInt8(ra + shift - 1), ra, shift, checks, all_pcs, kingpos)
    end
end

"store useful bitboards that are used for pawn legal move generation"
struct PawnMoveHelper
    single_push::BitBoard
    double_push::BitBoard
    attack_left::BitBoard
    attack_right::BitBoard
end

function PawnMoveHelper(piece_bb, double_push_mask, all_pcs, colour, MODE, info::LegalInfo)
    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinned_bb = piece_bb & ~(info.rookpins | info.bishoppins)
    rook_pinned_bb = pinned_rook(piece_bb, info.rookpins)
    bishop_pinned_bb = pinned_bishop(piece_bb, info.bishoppins)

    #push once and remove any that are blocked
    pushpawn1 = cond_push(colour, unpinned_bb)
    legalpush1 = quiet_moves(MODE, pushpawn1, all_pcs)
    pushpinned = cond_push(colour, rook_pinned_bb)
    legalpush1 |= quiet_moves(MODE, pushpinned, all_pcs) & info.rookpins

    #push twice if possible
    pushpawn2 = cond_push(colour, legalpush1 & double_push_mask)
    legalpush2 = quiet_moves(MODE, pushpawn2, all_pcs)

    #shift left and right to attack
    attackleft = attack_left(pushpawn1)
    attackright = attack_right(pushpawn1)

    bishop_pin_push = cond_push(colour, bishop_pinned_bb)
    bishop_pin_attack_left = attack_left(bishop_pin_push)
    bishop_pin_attack_right = attack_right(bishop_pin_push)

    #combine with attacks pinned by a bishop
    attackleft |= bishop_pin_attack_left & info.bishoppins
    attackright |= bishop_pin_attack_right & info.bishoppins

    return PawnMoveHelper(legalpush1, legalpush2, attackleft, attackright)
end

"add all legal single pawn pushes to move list"
@inline function legal_single_push!(board::BoardState, helper, pawn_masks, info::LegalInfo)
    single_legal = helper.single_push & info.evasion_mask
    single_normal = single_legal & ~pawn_masks.promote
    single_promote = single_legal & pawn_masks.promote

    push_moves!(board, single_normal, pawn_masks.shift, NOFLAG)
    push_moves!(board, single_promote, pawn_masks.shift, Promote())
end

"add all legal double pawn pushes to move list"
@inline function legal_double_push!(board::BoardState, helper, pawn_masks, info::LegalInfo)
    double_legal = helper.double_push & info.evasion_mask
    double_push_moves!(board, double_legal, pawn_masks.shift)
end

"add all legal pawn attacks to move list"
@inline function legal_pawn_attacks!(board::BoardState, enemy_pcs, helper, pawn_masks, info::LegalInfo)
    attackable_squares = enemy_pcs & info.attackers
    attack_normal = attackable_squares & ~pawn_masks.promote
    attack_promote = attackable_squares & pawn_masks.promote

    left = helper.attack_left
    right = helper.attack_right

    capture_moves!(board, attack_normal, left, right, pawn_masks.shift, NOFLAG)
    capture_moves!(board, attack_promote, left, right, pawn_masks.shift, Promote())
end

"returns attack and quiet moves for pawns only if legal, based on checks and pins"
@inline function get_pawn_moves!(board::BoardState, enemy_pcs, all_pcs, MODE, info::LegalInfo)
    colour = whitesmove(board.colour)
    piece_bb = ally_piece(board, PAWN)
    kingpos = locate_king(board)
    pawn_masks = ifelse(colour, WHITE_MASKS, BLACK_MASKS)
    helper = PawnMoveHelper(piece_bb, pawn_masks.doublepush, all_pcs, colour, MODE, info)

    legal_single_push!(board, helper, pawn_masks, info)
    legal_double_push!(board, helper, pawn_masks, info)
    legal_pawn_attacks!(board, enemy_pcs, helper, pawn_masks, info)
    enpassant_moves!(board, helper, pawn_masks.shift, board.enpassant_bb, info.attackers, all_pcs, kingpos)
end

#TODO: refactor into separate functions
@inline function get_pseudolegal_pawn_moves!(board::BoardState, enemy_pcs, all_pcs, MODE)
    colour = whitesmove(board.colour)    
    pawn_bb = ally_piece(board, PAWN)
    pawn_masks = ifelse(colour, WHITE_MASKS, BLACK_MASKS)

    # single push
    single_push = cond_push(colour, pawn_bb)
    quiet_single = quiet_moves(MODE, single_push, all_pcs)
    single_normal = quiet_single & ~pawn_masks.promote
    single_promote = quiet_single & pawn_masks.promote
    push_moves!(board, single_normal, pawn_masks.shift, NOFLAG)
    push_moves!(board, single_promote, pawn_masks.shift, Promote())

    # double push
    double_push = cond_push(colour, quiet_single & pawn_masks.doublepush)
    quiet_double = quiet_moves(MODE, double_push, all_pcs)
    double_push_moves!(board, quiet_double, pawn_masks.shift)

    # attacks
    attack_normal = enemy_pcs & ~pawn_masks.promote
    attack_promote = enemy_pcs & pawn_masks.promote
    left = attack_left(single_push)
    right = attack_right(single_push)

    capture_moves!(board, attack_normal, left, right, pawn_masks.shift, NOFLAG)
    capture_moves!(board, attack_promote, left, right, pawn_masks.shift, Promote())

    # enpassant
    left_enpassant = left & board.enpassant_bb
    for to in left_enpassant
        from = UInt8(to + pawn_masks.shift + 1)
        append!(board.move_vector, Move(PAWN, from, to, PAWN, ENPASSANT))
    end

    right_enpassant = right & board.enpassant_bb
    for to in right_enpassant
        from = UInt8(to + pawn_masks.shift - 1)
        append!(board.move_vector, Move(PAWN, from, to, PAWN, ENPASSANT))
    end
end

#TODO: count backwards from latest position and quit early if halfmove count is reset
"one-liner to test draw by repetition" 
@inline three_repetition(board::BoardState) = count(i->(i==board.zobrist_hash), board.data.zobrist_hash_history) >= 3

"implement 50 move rule and 3 position repetition"
@inline function draw_state(board::BoardState)::Bool
    return (board.data.half_moves[end] >= 100) || three_repetition(board)
end

"find locations of owned pieces and create a movelist of all legal moves"
function generate_legal_moves(board::BoardState, legal_info=LegalInfo(board), MODE=AllMoves())
    prev_move_index = board.move_vector.ind
    enemy_pcs_bb = all_enemy_pieces(board)
    all_pcs_bb = all_pieces(board)

    get_king_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE, legal_info)
    get_castle_moves!(MODE, board, all_pcs_bb, legal_info.attack_sqs)

    #if multiple checks on king, only king can move
    if legal_info.attack_num <= 1
        #run through pieces and BBs, adding moves to list
        get_knight_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE, legal_info)

        get_bishop_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE, legal_info)
        
        get_rook_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE, legal_info)
        
        get_queen_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE, legal_info)

        get_pawn_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE, legal_info)
    end

    move_count = board.move_vector.ind - prev_move_index
    move_view = current_moves(board.move_vector, move_count)
    return move_view, move_count
end

"helper function that uses generate moves to create a movelist of all attacking moves (no quiets)"
function generate_legal_attacks(board::BoardState, legal_info=LegalInfo(board))
    return generate_legal_moves(board, legal_info, AttacksOnly())
end

"fetch bitboards of all/enemy piece positions and generate pseudolegal moves for all ally pieces"
function generate_pseudolegal_moves(board::BoardState, MODE=AllMoves())
    prev_move_index = board.move_vector.ind
    enemy_pcs_bb = all_enemy_pieces(board)
    all_pcs_bb = all_pieces(board)

    get_pseudolegal_king_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE)
    get_pseudolegal_castle_moves!(MODE, board, all_pcs_bb)
    get_pseudolegal_knight_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE)
    get_pseudolegal_bishop_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE)
    get_pseudolegal_rook_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE)
    get_pseudolegal_queen_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE)
    get_pseudolegal_pawn_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE)

    move_count = board.move_vector.ind - prev_move_index
    move_view = current_moves(board.move_vector, move_count)
    return move_view, move_count
end

"helper function that uses generate moves to create a movelist of all pseudolegal attacking moves (no quiets)"
function generate_pseudolegal_attacks(board::BoardState)
    return generate_pseudolegal_moves(board, AttacksOnly())
end

"scan all enemy pieces from 'colour' king's perspective to determine whether king is under attack"
@inline function in_check(board::BoardState, colour = board.colour)
    king_pos = locate_king(board, colour)
    enemy_colour = opposite(colour)

    knight_moves = pseudolegal_knight_moves(king_pos)
    if (knight_moves & colour_piece(board, enemy_colour, KNIGHT)) > 0
        return true
    end

    king_moves = pseudolegal_king_moves(king_pos)
    if (king_moves & colour_piece(board, enemy_colour, KING)) > 0
        return true
    end

    queen_bb = colour_piece(board, enemy_colour, QUEEN)
    all_pcs = all_pieces(board)

    rook_moves = pseudolegal_rook_moves(king_pos, all_pcs)
    if (rook_moves & (colour_piece(board, enemy_colour, ROOK) | queen_bb)) > 0
        return true
    end

    bishop_moves = pseudolegal_bishop_moves(king_pos, all_pcs)
    if (bishop_moves & (colour_piece(board, enemy_colour, BISHOP) | queen_bb)) > 0
        return true
    end

    pawn_attackers = pseudolegal_pawn_moves(BitBoard(1) << king_pos, whitesmove(colour))
    if (pawn_attackers & colour_piece(board, enemy_colour, PAWN)) > 0
        return true
    end
    return false
end