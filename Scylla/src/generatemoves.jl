"return location of king for a given colour"
locate_king(board::BoardState, colour) = LSB(board.pieces[colour_piece_id(colour, KING)])

"return location of king for side to move"
locate_king(board::BoardState) = locate_king(board, board.colour)

"Masked 4-bit integer representing king- and queen-side castling rights for one side"
function get_castle_rights(castling, colour_id, king_or_queen_side)
    #colour_id must be 0 for white and 1 for black
    #king_or_queen_side allows masking out of only king/queen side
    #for a given colour, =0 if both, 1 = king, 2 = queen
    rights = MOVESET.castle_rights_mask[3 * colour_id + king_or_queen_side + 1]
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
            slide_attckers = kingmoves & (enemy_piece(board, ROOK) | enemy_piece(board, QUEEN))
            for attack_pos in slide_attckers
                attackmoves = pseudolegal_rook_moves(attack_pos, all_pcs)
                evasions |= attackmoves & kingmoves
            end

            kingmoves = pseudolegal_bishop_moves(position, all_pcs)
            slide_attckers = kingmoves & (enemy_piece(board, BISHOP) | enemy_piece(board, QUEEN))
            for attack_pos in slide_attckers
                attackmoves = pseudolegal_bishop_moves(attack_pos, all_pcs)
                evasions |= attackmoves & kingmoves
            end
        end
    end
    rookpins, bishoppins = detect_pins(board, position, all_pcs, all_ally_pieces(board))
    return LegalInfo(attackers, evasions, rookpins, bishoppins, attacked_sqs, attacker_num)
end

pseudolegal_king_moves(location) = MOVESET.king[location + 1]

pseudolegal_knight_moves(location) = MOVESET.knight[location + 1]

pseudolegal_rook_moves(location, all_pcs) = sliding_attacks(ROOK_MAGICS[location + 1], all_pcs, ROOK_ATTACKS)

pseudolegal_bishop_moves(location, all_pcs) = sliding_attacks(BISHOP_MAGICS[location + 1], all_pcs, BISHOP_ATTACKS)

function pseudolegal_queen_moves(location, all_pcs)
    rook_attacks = sliding_attacks(ROOK_MAGICS[location + 1], all_pcs, ROOK_ATTACKS)
    bishop_attacks = sliding_attacks(BISHOP_MAGICS[location + 1], all_pcs, BISHOP_ATTACKS)
    return rook_attacks | bishop_attacks
end

"returns BB containing attacking moves assuming all pieces in BB are pawns"
function pseudolegal_pawn_moves(pawn_bb, colour::Bool)
    pawn_push = cond_push(colour, pawn_bb)
    return attack_left(pawn_push) | attack_right(pawn_push)
end

"checks enemy pieces to see if any are attacking the king square, returns BB of attackers"
function king_attackers(board::BoardState, all_pcs::BitBoard, location::Integer)::BitBoard
    attackers = BITBOARD_EMPTY
    knight_moves = pseudolegal_knight_moves(location)
    attackers |= (knight_moves & enemy_piece(board, KNIGHT))

    rook_moves = pseudolegal_rook_moves(location,all_pcs)
    rook_attackers = (rook_moves & (enemy_piece(board, ROOK) | enemy_piece(board, QUEEN)))
    attackers |= rook_attackers

    bishop_moves = pseudolegal_bishop_moves(location,all_pcs)
    bishop_attackers = (bishop_moves & (enemy_piece(board, BISHOP) | enemy_piece(board, QUEEN)))
    attackers |= bishop_attackers

    pawn_attackers = pseudolegal_pawn_moves(BitBoard(1) << location, whitesmove(board.colour))
    attackers |= pawn_attackers & enemy_piece(board, PAWN)

    return attackers
end

"bitboard of all squares being attacked by the opponent"
function enemy_attacks(board::BoardState, all_pcs)::BitBoard
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
function rook_pinlines(board::BoardState, king_pos, blocks_removed, slide_attacks)
    #recalculate rook attacks with blockers removed
    rook_no_blocks = pseudolegal_rook_moves(king_pos, blocks_removed) 
    #only want moves found after removing blockers
    rpin_attacks = rook_no_blocks & ~slide_attacks
    #start by adding attacker to pin line
    rook_pins = rpin_attacks & (enemy_piece(board, ROOK) | enemy_piece(board, QUEEN))
    #iterate through rooks/queens pinning king
    for loc in rook_pins
        #add squares on pin line to pinning BB
        rook_pins |= rook_no_blocks & pseudolegal_rook_moves(loc, blocks_removed)
    end
    return rook_pins
end

"return a bitboard containing squares that can be moved to by pieces pinned by a bishop"
function bishop_pinlines(board::BoardState, king_pos, blocks_removed, slide_attacks)
    bishop_no_blocks = pseudolegal_bishop_moves(king_pos, blocks_removed) 
    bpin_attacks = bishop_no_blocks & ~slide_attacks
    bishop_pins = bpin_attacks & (enemy_piece(board, BISHOP) | enemy_piece(board, QUEEN))

    for loc in bishop_pins
        bishop_pins |= bishop_no_blocks & pseudolegal_bishop_moves(loc, blocks_removed)
    end
    return bishop_pins
end

"detect pins and create rook/bishop pin BBs"
function detect_pins(board::BoardState, king_pos, all_pcs, ally_pcs)
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

"create a castling move where from and to is the rook to move"
function create_castle(king_or_queen, white_or_black)
    #king_or_queen is 0 if kingside, 1 if queenside 
    #white_or_black is 0 if white, 1 if black
    from = UInt8(63 - 7*king_or_queen - white_or_black*56)
    to = UInt8(from - 2 + 5*king_or_queen)
    return Move(KING, from, to, NULL_PIECE, KING_CASTLE + king_or_queen)
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

"Bitboard containing only the attacks by a particular piece"
function attack_moves(move_bb, enemy_bb)
    return move_bb & enemy_bb
end

"Bitboard containing only the quiets by a particular piece"
function quiet_moves(move_bb, all_pcs)
    return move_bb & ~all_pcs
end

"Filter pseudolegal moves for legality for king"
function legal_king_moves(loc,info::LegalInfo)
    poss_moves = pseudolegal_king_moves(loc)
    #Filter out moves that put king in check
    legal_moves = poss_moves & ~info.attack_sqs
    return legal_moves
end

"Filter pseudolegal moves for legality for knight"
function legal_knight_moves(loc,info::LegalInfo)
    poss_moves = pseudolegal_knight_moves(loc)
    #Filter out knight moves that don't block/capture if in check
    legal_moves = poss_moves & (info.attackers | info.evasion_mask) 
    return legal_moves
end

"Filter pseudolegal moves for legality for bishop"
function legal_bishop_moves(loc,all_pcs,bishoppins,info::LegalInfo)
    poss_moves = pseudolegal_bishop_moves(loc,all_pcs)
    #Filter out bishop moves that don't block/capture if in check/pinned
    legal_moves = poss_moves & (info.attackers | info.evasion_mask) & bishoppins
    return legal_moves
end

"Filter pseudolegal moves for legality for rook"
function legal_rook_moves(loc,all_pcs, rookpins, info::LegalInfo)
    poss_moves = pseudolegal_rook_moves(loc, all_pcs)
    #Filter out rook moves that don't block/capture if in check/pinned
    legal_moves = poss_moves & (info.attackers | info.evasion_mask) & rookpins
    return legal_moves
end

"Filter pseudolegal moves for legality for queen"
function legal_queen_moves(loc, all_pcs, rookpins, bishoppins, info::LegalInfo)
    legal_rook = legal_rook_moves(loc, all_pcs, rookpins, info)
    legal_bishop = legal_bishop_moves(loc, all_pcs, bishoppins, info)
    return legal_rook | legal_bishop
end

"Bitboard logic to get attacks and quiets from legal moves"
function quiets_and_attacks(legal, all_bb, enemy_bb, MODE::UInt64)
    attacks = attack_moves(legal, enemy_bb)
    #set quiets to zero if only generating attacks
    quiets = quiet_moves(legal, all_bb) * MODE
    return quiets, attacks
end

"bishop can only move if pinned diagonally"
pinned_bishop(piece_bb, bishoppins) = piece_bb & bishoppins

"rook can only move if pinned vertic/horizontally"
pinned_rook(piece_bb, rookpins) = piece_bb & rookpins

"add all legal moves that can be made by a pinned rook from locations on bitboard that are pinned"
function pinned_rook_moves!(board::BoardState, enemy_pcs, all_pcs, pinned_bb, TYPE, MODE, info::LegalInfo)
    for loc in pinned_bb
        legal = legal_rook_moves(loc, all_pcs, info.rookpins, info)
        quiets, attacks = quiets_and_attacks(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(TYPE, board, quiets, loc, false)
        moves_from_location!(TYPE, board, attacks, loc, true)
    end
end

"add all legal moves that can be made by a non-pinned rook from locations on bitboard that are not pinned"
function unpinned_rook_moves!(board::BoardState, enemy_pcs, all_pcs, unpinned_bb, TYPE, MODE, info::LegalInfo)
    for loc in unpinned_bb
        legal = legal_rook_moves(loc, all_pcs, BITBOARD_FULL, info)
        quiets, attacks = quiets_and_attacks(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(TYPE, board, quiets, loc, false)
        moves_from_location!(TYPE, board, attacks, loc, true)
    end
end

"add all legal moves that can be made by a pinned bishop from locations on bitboard that are pinned"
function pinned_bishop_moves!(board::BoardState, enemy_pcs, all_pcs, pinned_bb, TYPE, MODE, info::LegalInfo)
    for loc in pinned_bb
        legal = legal_bishop_moves(loc, all_pcs, info.bishoppins, info)
        quiets, attacks = quiets_and_attacks(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(TYPE, board, quiets, loc, false)
        moves_from_location!(TYPE, board, attacks, loc, true)
    end
end

"add all legal moves that can be made by a non-pinned bishop from locations on bitboard that are not pinned"
function unpinned_bishop_moves!(board::BoardState, enemy_pcs, all_pcs, unpinned_bb, TYPE, MODE, info::LegalInfo)
    for loc in unpinned_bb
        legal = legal_bishop_moves(loc, all_pcs, BITBOARD_FULL, info)
        quiets, attacks = quiets_and_attacks(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(TYPE, board, quiets, loc, false)
        moves_from_location!(TYPE, board, attacks, loc, true)
    end
end

"add all legal moves that can be made by a non-pinned queen from locations on bitboard that are not pinned"
function unpinned_queen_moves(board::BoardState, enemy_pcs, all_pcs, unpinned_bb, MODE, info::LegalInfo)
    for loc in unpinned_bb
        legal = legal_queen_moves(loc, all_pcs, BITBOARD_FULL, BITBOARD_FULL, info)
        quiets, attacks = quiets_and_attacks(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(QUEEN, board, quiets, loc, false)
        moves_from_location!(QUEEN, board, attacks, loc, true)
    end
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

"Returns true if any queen moves exist"
@inline function any_queen_moves(piece_bb, all_pcs, ally_pcs_bb, info::LegalInfo)::Bool
    unpinned_bb = piece_bb & ~(info.rookpins | info.bishoppins)
    for loc in unpinned_bb
        legal_bitboard = legal_queen_moves(loc, all_pcs, BITBOARD_FULL, BITBOARD_FULL, info)
        if (legal_bitboard & ~ally_pcs_bb) > 0
            return true
        end
    end

    rook_pinned_bb = pinned_rook(piece_bb, info.rookpins)
    for loc in rook_pinned_bb
        unpinned_bb = legal_rook_moves(loc, all_pcs, info.rookpins, info)
        if (unpinned_bb & ~ally_pcs_bb) > 0
            return true
        end
    end

    bishop_pinned_bb = pinned_bishop(piece_bb, info.bishoppins)
    for loc in bishop_pinned_bb
        unpinned_bb = legal_bishop_moves(loc, all_pcs, info.bishoppins, info)
        if (unpinned_bb & ~ally_pcs_bb) > 0
            return true
        end
    end
    return false
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

"Returns true if any rook moves exist"
@inline function any_rook_moves(piece_bb, all_pcs, ally_pcs_bb, info::LegalInfo)::Bool
    unpinned_bb = piece_bb & ~(info.rookpins | info.bishoppins)
    pinned_bb = pinned_rook(piece_bb, info.rookpins)

    for loc in pinned_bb
        if (legal_rook_moves(loc, all_pcs, info.rookpins, info) & ~ally_pcs_bb) > 0
            return true
        end
    end

    for loc in unpinned_bb
        if (legal_rook_moves(loc, all_pcs, BITBOARD_FULL, info) & ~ally_pcs_bb) > 0
            return true
        end
    end
    return false
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

"Returns true if any bishop moves exist"
@inline function any_bishop_moves(piece_bb, all_pcs, ally_pcs_bb, info::LegalInfo)::Bool
    unpinned_bb = piece_bb & ~(info.rookpins | info.bishoppins)
    pinned_bb = pinned_bishop(piece_bb, info.bishoppins)

    for loc in pinned_bb
        if (legal_bishop_moves(loc, all_pcs, info.bishoppins, info) & ~ally_pcs_bb) > 0
            return true
        end
    end

    for loc in unpinned_bb
        if (legal_bishop_moves(loc, all_pcs, BITBOARD_FULL, info) & ~ally_pcs_bb) > 0
            return true
        end
    end
    return false
end

"returns attack and quiet moves only if legal for knight, based on checks and pins"
@inline function get_knight_moves!(board::BoardState, enemy_pcs, all_pcs, MODE, info::LegalInfo)
    #split into pinned and unpinned pieces, only unpinned knights can move
    piece_bb = ally_piece(board, KNIGHT)
    unpinned_bb = piece_bb & ~(info.rookpins | info.bishoppins)
    
    for loc in unpinned_bb
        legal = legal_knight_moves(loc,info)
        quiets, attacks = quiets_and_attacks(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(KNIGHT, board, quiets, loc, false)
        moves_from_location!(KNIGHT, board, attacks, loc, true)
    end
end

"Returns true if any knight moves exist"
@inline function any_knight_moves(piece_bb, ally_pcs_bb, info::LegalInfo)::Bool
    unpinned_bb = piece_bb & ~(info.rookpins | info.bishoppins)
    for loc in unpinned_bb
        if (legal_knight_moves(loc,info) & ~ally_pcs_bb) > 0
            return true
        end
    end
    return false
end

"returns attacks, quiet moves and castles for king only if legal, based on checks"
@inline function get_king_moves!(board::BoardState, enemy_pcs, all_pcs, castlrts, colour_id, MODE, info::LegalInfo)
    piece_bb = ally_piece(board, KING)
    for loc in piece_bb
        legal = legal_king_moves(loc, info)
        quiets, attacks = quiets_and_attacks(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(KING, board, quiets, loc, false)
        moves_from_location!(KING, board, attacks, loc, true)
    end
    #cannot castle out of check. castling is a quiet move
    if info.attack_num == 0 && MODE == ALLMOVES
        #index into lookup table containing squares that must be free/not in check to castle
        #must mask out opponent's castle rights
        for castle_id in BitBoard(get_castle_rights(castlrts, (colour_id + 1) % 2, 0))
            castleattack = MOVESET.castle_check[castle_id + 1]
            blockId = castle_id % 2 # only queenside castle (=1) has extra block squares
            #white queen blockers are at index 5, black queen blockers are at index 6
            castleblock = MOVESET.castle_check[castle_id + blockId * (2 + (castle_id % 3)) + 1]
            if (castleblock & all_pcs == 0) && (castleattack & info.attack_sqs == 0)
                append!(board.move_vector, create_castle(UInt8(castle_id % 2), colour_id))
            end
        end
    end
end

"Returns true if any king moves exist. Don't need to check castles as castle is only legal if sideways moves are"
@inline function any_king_moves(kingpos, ally_pcs_bb, info::LegalInfo)::Bool
    if (legal_king_moves(kingpos,info) & ~ally_pcs_bb) > 0
        return true
    else
        return false
    end
end

"use bitshifts to push all white/black pawns at once"
cond_push(colour::Bool, pawn_bb) = ifelse(colour, pawn_bb >> 8, pawn_bb << 8)

attack_left(piece_bb) = (piece_bb >> 1) & BitBoard(0x7F7F7F7F7F7F7F7F)

attack_right(piece_bb) = (piece_bb << 1) & BitBoard(0xFEFEFEFEFEFEFEFE)

"appends 4 promotion moves"
function append_moves!(board::BoardState, piece_type, from, to, capture_type,::Promote)
    for flag in PROMOTE_TYPES
        append!(board.move_vector, Move(piece_type, from, to, capture_type, flag))
    end
end

"appends a non-promote move with a given flag"
function append_moves!(board::BoardState, piece_type, from, to, capture_type, flag::UInt8)
    append!(board.move_vector, Move(piece_type, from, to, capture_type, flag))
end

"Create list of pawn push moves with a given flag"
function push_moves!(board::BoardState, singlepush, promotemask, shift, blocks, flag, MODE::UInt64)
    for q1 in ((singlepush * MODE) & blocks & promotemask)
        append_moves!(board, PAWN, UInt8(q1 + shift), q1, NULL_PIECE, flag)
    end
end

"Create list of double pawn push moves"
function push_moves!(board::BoardState, doublepush, shift, blocks, MODE::UInt64)
    for q2 in ((doublepush * MODE) & blocks)
        append!(board.move_vector, Move(PAWN, UInt8(q2 + 2 * shift), q2, NULL_PIECE, DOUBLE_PUSH))
    end
end

"Create list of pawn capture moves with a given flag"
function capture_moves!(board::BoardState, leftattack, rightattack, promotemask, shift, enemy_pcs, checks, flag)
    for la in (leftattack & enemy_pcs & promotemask & checks)
        attack_piece_id = identify_piecetype(board, la)
        append_moves!(board, PAWN, UInt8(la + shift + 1), la, attack_piece_id, flag)
    end
    for ra in (rightattack & enemy_pcs & promotemask & checks)
        attack_piece_id = identify_piecetype(board, ra)
        append_moves!(board, PAWN, UInt8(ra + shift - 1), ra, attack_piece_id, flag)
    end
end

"returns false if it fails edge case where EP exposes attack on king"
function enpassant_edge_case(board::BoardState, from, enpassant_cap, kingpos, all_pcs)
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
function push_enpassant!(board::BoardState, from, to, shift, checks, all_pcs, kingpos)
    enpassant_capture = to + shift
    if checks & (BitBoard(1) << enpassant_capture) > 0
        if enpassant_edge_case(board, from, enpassant_capture, kingpos, all_pcs)
            append!(board.move_vector, Move(PAWN, from, to, PAWN, ENPASSANT))
        end
    end
end

"Create list of pawn en-passant moves"
function enpassant_moves!(board::BoardState, leftattack, rightattack, shift, enpassant_sqs, checks, all_pcs, kingpos)
    for la in (leftattack & enpassant_sqs)  
        push_enpassant!(board, UInt8(la + shift + 1), la, shift, checks, all_pcs, kingpos)
    end
    for ra in (rightattack & enpassant_sqs)
        push_enpassant!(board, UInt8(ra + shift - 1), ra, shift, checks, all_pcs, kingpos)
    end
end

"returns attack and quiet moves for pawns only if legal, based on checks and pins"
function get_pawn_moves!(board::BoardState, enemy_pcs, all_pcs, enpass_bb, colour::Bool, kingpos, MODE, info::LegalInfo)
    piece_bb = ally_piece(board, PAWN)
    pawn_masks = ifelse(colour, WHITE_MASKS, BLACK_MASKS)

    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinned_bb = piece_bb & ~(info.rookpins | info.bishoppins)
    rook_pinned_bb = pinned_rook(piece_bb, info.rookpins)
    bishop_pinned_bb = pinned_bishop(piece_bb, info.bishoppins)

    #push once and remove any that are blocked
    pushpawn1 = cond_push(colour, unpinned_bb)
    legalpush1 = quiet_moves(pushpawn1, all_pcs)
    pushpinned = cond_push(colour, rook_pinned_bb)
    legalpush1 |= quiet_moves(pushpinned, all_pcs) & info.rookpins

    #push twice if possible
    pushpawn2 = cond_push(colour, legalpush1 & pawn_masks.doublepush)
    legalpush2 = quiet_moves(pushpawn2, all_pcs)

    #shift left and right to attack
    attackleft = attack_left(pushpawn1)
    attackright = attack_right(pushpawn1)

    Bpush = cond_push(colour, bishop_pinned_bb)
    Battackleft = attack_left(Bpush)
    Battackright = attack_right(Bpush)

    #combine with attacks pinned by a bishop
    attackleft |= Battackleft & info.bishoppins
    attackright |= Battackright & info.bishoppins
    
    #add non-promote pushes, promote pushes, double pushes, non-promote captures, promote captures and en-passant
    push_moves!(board, legalpush1, ~pawn_masks.promote, pawn_masks.shift, info.evasion_mask, NOFLAG, MODE),
    push_moves!(board, legalpush1, pawn_masks.promote, pawn_masks.shift, info.evasion_mask, Promote(), MODE),
    push_moves!(board, legalpush2, pawn_masks.shift, info.evasion_mask, MODE),
    capture_moves!(board, attackleft, attackright, ~pawn_masks.promote, pawn_masks.shift, enemy_pcs, info.attackers, NOFLAG),
    capture_moves!(board, attackleft, attackright, pawn_masks.promote, pawn_masks.shift, enemy_pcs,info.attackers, Promote()),
    enpassant_moves!(board, attackleft, attackright, pawn_masks.shift, enpass_bb, info.attackers, all_pcs, kingpos)
end

"Return true if any pawn moves exist"
function any_pawn_moves(piece_bb, all_pcs, ally_pcs_bb, colour::Bool, info::LegalInfo)::Bool
    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinned_bb = piece_bb & ~(info.rookpins | info.bishoppins)
    Rpinned_bb = pinned_rook(piece_bb, info.rookpins)
    Bpinned_bb = pinned_bishop(piece_bb, info.bishoppins)

    #push once and remove any that are blocked
    pushpawn1 = cond_push(colour, unpinned_bb)
    legalpush1 = quiet_moves(pushpawn1, all_pcs)
    pushpinned = cond_push(colour, Rpinned_bb)
    legalpush1 |= quiet_moves(pushpinned, all_pcs) & info.rookpins

    if (legalpush1 & info.evasion_mask) > 0
        return true
    end

    #shift left and right to attack
    attackleft = attack_left(pushpawn1)
    attackright = attack_right(pushpawn1)

    Bpush = cond_push(colour, Bpinned_bb)
    Battackleft = attack_left(Bpush)
    Battackright = attack_right(Bpush)

    #combine with attacks pinned by a bishop
    attackleft |= Battackleft & info.bishoppins
    attackright |= Battackright & info.bishoppins

    enemy_pieces_bb = all_pcs & ~ally_pcs_bb

    if ((attackleft & enemy_pieces_bb) & (info.attackers | info.evasion_mask)) > 0 || ((attackright & enemy_pieces_bb) & (info.attackers | info.evasion_mask)) > 0
        return true
    end
    return false
end

"one-liner to test repetition. function above should be faster but doesn't seem to work currently"
three_repetition(board::BoardState) = count(i->(i==board.zobrist_hash), board.data.zobrist_hash_history) >= 3

"implement 50 move rule and 3 position repetition"
function draw_state(board::BoardState)::Bool
    return (board.data.half_moves[end] >= 100) || three_repetition(board) #three_repetition(board.zobrist_hash, board.data)
end

"get lists of pieces and piece types, find locations of owned pieces and create a movelist of all legal moves"
function generate_legal_moves(board::BoardState, legal_info::LegalInfo=LegalInfo(board), MODE::UInt64=ALLMOVES)
    prev_move_index = board.move_vector.ind
    enemy_pcs_bb = all_enemy_pieces(board)
    all_pcs_bb = all_pieces(board)
    
    kingpos = locate_king(board)

    get_king_moves!(board, enemy_pcs_bb, all_pcs_bb,
    board.castle, colour_id(board.colour), MODE, legal_info)

    #if multiple checks on king, only king can move
    if legal_info.attack_num <= 1
        #run through pieces and BBs, adding moves to list
        get_knight_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE, legal_info)

        get_bishop_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE, legal_info)
        
        get_rook_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE, legal_info)
        
        get_queen_moves!(board, enemy_pcs_bb, all_pcs_bb, MODE, legal_info)

        get_pawn_moves!(board, enemy_pcs_bb, all_pcs_bb, board.enpassant_bb,
        whitesmove(board.colour), kingpos, MODE, legal_info)
    end

    move_count = board.move_vector.ind - prev_move_index
    move_view = current_moves(board.move_vector, move_count)
    return move_view, move_count
end

"helper function that used generate moves create a movelist of all attacking moves (no quiets)"
function generate_legal_attacks(board::BoardState, legal_info::LegalInfo=LegalInfo(board))
    return generate_legal_moves(board, legal_info, ATTACKONLY)
end

"evaluates whether we are in a terminal node due to draw conditions, or check/stale-mates"
function gameover!(board::BoardState, info = LegalInfo(board))
    if draw_state(board)
        board.state = Draw()
    else
        all_pcs_bb = all_pieces(board)
        ally_pcs_bb = all_ally_pieces(board)
        kingpos = locate_king(board)

        if any_king_moves(kingpos, ally_pcs_bb, info) 
            board.state = Neutral()
        elseif info.attack_num <= 1 && (
                any_pawn_moves(ally_piece(board, PAWN), all_pcs_bb, ally_pcs_bb, whitesmove(board.colour), info) ||
                any_knight_moves(ally_piece(board, KNIGHT), ally_pcs_bb, info) ||
                any_bishop_moves(ally_piece(board, BISHOP), all_pcs_bb, ally_pcs_bb, info) ||
                any_rook_moves(ally_piece(board, ROOK), all_pcs_bb, ally_pcs_bb, info) ||
                any_queen_moves(ally_piece(board, QUEEN), all_pcs_bb, ally_pcs_bb, info))
            board.state = Neutral() 
        else
            if info.attack_num > 0
                board.state = Loss()
            else
                board.state = Draw()
            end
        end
    end
end