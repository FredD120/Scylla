"return location of king for side to move"
locate_king(B::BoardState, colour) = LSB(B.pieces[colour_piece_id(colour, KING)])

"Masked 4-bit integer representing king- and queen-side castling rights for one side"
function get_Crights(castling, colour_id, KorQside)
    #colour_id must be 0 for white and 1 for black
    #KorQside allows masking out of only king/queen side
    #for a given colour, =0 if both, 1 = king, 2 = queen
    return castling & MOVESET.CRightsMask[3 * colour_id + KorQside + 1]
end

"store information about how to make moves without king being captured"
struct LegalInfo
    checks::BitBoard
    blocks::BitBoard
    rookpins::BitBoard
    bishoppins::BitBoard
    attack_sqs::BitBoard
    attack_num::UInt8
end

"All pseudolegal king moves"
possible_king_moves(location) = MOVESET.king[location + 1]
"All pseudolegal knight moves"
possible_knight_moves(location) = MOVESET.knight[location + 1]
"All pseudolegal rook moves"
possible_rook_moves(location, all_pcs) = sliding_attacks(ROOK_MAGICS[location + 1], all_pcs, ROOK_ATTACKS)
"All pseudolegal bishop moves"
possible_bishop_moves(location, all_pcs) = sliding_attacks(BISHOP_MAGICS[location + 1], all_pcs, BISHOP_ATTACKS)
"All pseudolegal queen moves"
function possible_queen_moves(location, all_pcs)
    rook_attacks = sliding_attacks(ROOK_MAGICS[location + 1], all_pcs, ROOK_ATTACKS)
    bishop_attacks = sliding_attacks(BISHOP_MAGICS[location + 1], all_pcs, BISHOP_ATTACKS)
    return rook_attacks | bishop_attacks
end

"Returns BB containing attacking moves assuming all pieces in BB are pawns"
function possible_pawn_moves(pawn_bb, colour::Bool)
    pawn_push = cond_push(colour, pawn_bb)
    return attack_left(pawn_push) | attack_right(pawn_push)
end

"checks enemy pieces to see if any are attacking the king square, returns BB of attackers"
function attack_pcs(board::BoardState, all_pcs::BitBoard, location::Integer, colour::Bool)::BitBoard
    attacks = BITBOARD_EMPTY
    knightmoves = possible_knight_moves(location)
    attacks |= (knightmoves & enemy_piece(board, KNIGHT))

    rookmoves = possible_rook_moves(location,all_pcs)
    rookattacks = (rookmoves & (enemy_piece(board, ROOK) | enemy_piece(board, QUEEN)))
    attacks |= rookattacks

    bishopmoves = possible_bishop_moves(location,all_pcs)
    bishopattacks = (bishopmoves & (enemy_piece(board, BISHOP) | enemy_piece(board, QUEEN)))
    attacks |= bishopattacks

    pawnattacks = possible_pawn_moves(BitBoard(1)<<location, colour)
    attacks |= pawnattacks & enemy_piece(board, PAWN)

    return attacks
end

"Bitboard of all squares being attacked by a side"
function all_poss_moves(board::BoardState, all_pcs, colour::Bool)::BitBoard
    attacks = BITBOARD_EMPTY

    for location in enemy_piece(board, KING)
        attacks |= possible_king_moves(location)
    end
    
    for location in enemy_piece(board, KNIGHT)
        attacks |= possible_knight_moves(location)
    end

    for location in enemy_piece(board, BISHOP)
        attacks |= possible_bishop_moves(location, all_pcs)
    end

    for location in enemy_piece(board, ROOK)
        attacks |= possible_rook_moves(location, all_pcs)
    end

    for location in enemy_piece(board, QUEEN)
        attacks |= possible_queen_moves(location, all_pcs)
    end

    attacks |= possible_pawn_moves(enemy_piece(board, PAWN), opposite(colour))
    return attacks
end

"detect pins and create rook/bishop pin BBs"
function detect_pins(board::BoardState, pos, all_pcs, ally_pcs)
    #imagine king is a queen, what can it see?
    slide_attacks = possible_queen_moves(pos,all_pcs)
    #identify ally pieces seen by king
    ally_block = slide_attacks & ally_pcs
    #remove these ally pieces
    blocks_removed = all_pcs & ~ally_block

    #recalculate rook attacks with blockers removed
    rook_no_blocks = possible_rook_moves(pos,blocks_removed) 
    #only want moves found after removing blockers
    rpin_attacks = rook_no_blocks & ~slide_attacks
    #start by adding attacker to pin line
    rookpins = rpin_attacks & (enemy_piece(board, ROOK) | enemy_piece(board, QUEEN))
    #iterate through rooks/queens pinning king
    for loc in rookpins
        #add squares on pin line to pinning BB
        rookpins |= rook_no_blocks & possible_rook_moves(loc,blocks_removed)
    end

    #same but for bishops
    bishop_no_blocks = possible_bishop_moves(pos,blocks_removed) 
    bpin_attacks = bishop_no_blocks & ~slide_attacks
    bishoppins = bpin_attacks & (enemy_piece(board, BISHOP) | enemy_piece(board, QUEEN))
    for loc in bishoppins
        bishoppins |= bishop_no_blocks & possible_bishop_moves(loc,blocks_removed)
    end

    return rookpins, bishoppins
end

"returns struct containing info on attacks, blocks and pins of king by enemy piecelist"
function attack_info(board::BoardState)::LegalInfo
    attacks = BITBOARD_FULL
    blocks = BITBOARD_EMPTY
    attacker_num = 0
    
    ally_pcs = board.piece_union[colour_id(board.colour) + 1]
    all_pcs = board.piece_union[end]
    king_bb = board.pieces[board.colour + KING]
    position = LSB(king_bb)
    colour::Bool = whitesmove(board.colour)

    #construct BB of all enemy attacks, must remove king when checking if square is attacked
    all_except_king = all_pcs & ~(king_bb)
    attacked_sqs = all_poss_moves(board, all_except_king, colour)

    #if king not under attack, dont need to find attacking pieces or blockers
    if king_bb & attacked_sqs == BITBOARD_EMPTY
        blocks = BITBOARD_FULL
    else
        attacks = attack_pcs(board, all_pcs, position, colour)
        attacker_num = count_ones(attacks)
        #if only a single sliding piece is attacking the king, it can be blocked
        if attacker_num == 1
            kingmoves = possible_rook_moves(position, all_pcs)
            slide_attckers = kingmoves & (enemy_piece(board, ROOK) | enemy_piece(board, QUEEN))
            for attack_pos in slide_attckers
                attackmoves = possible_rook_moves(attack_pos,all_pcs)
                blocks |= attackmoves & kingmoves
            end

            kingmoves = possible_bishop_moves(position,all_pcs)
            slide_attckers = kingmoves & (enemy_piece(board, BISHOP) | enemy_piece(board, QUEEN))
            for attack_pos in slide_attckers
                attackmoves = possible_bishop_moves(attack_pos, all_pcs)
                blocks |= attackmoves & kingmoves
            end
        end
    end
    rookpins, bishoppins = detect_pins(board, position, all_pcs, ally_pcs)
    return LegalInfo(attacks, blocks, rookpins, bishoppins, attacked_sqs, attacker_num)
end

"create a castling move where from and to is the rook to move"
function create_castle(KorQ,WorB)
    #KorQ is 0 if kingside, 1 if queenside 
    #WorB is 0 if white, 1 if black
    from = UInt8(63 - 7*KorQ - WorB*56)
    to = UInt8(from - 2 + 5*KorQ)
    return Move(KING, from, to, NULL_PIECE, KCASTLE + KorQ)
end

"creates a move from a given location using the Move struct, with flag for attacks"
@inline function moves_from_location!(type::UInt8, board::BoardState, destinations::BitBoard, origin, isattack::Bool)
    for loc in destinations
        attacked_pieceID = NULL_PIECE
        if isattack
            #move struct needs info on piece being attacked
            attacked_pieceID = identify_piecetype(board, loc)
        end
        append!(board.move_vector, Move(type, origin, loc, attacked_pieceID, NOFLAG))
    end
end

"Bitboard containing only the attacks by a particular piece"
function attack_moves(move_bb, enemy_bb)
    return move_bb & enemy_bb
end

"Bitboard containing only the quiets by a particular piece"
function quiet_moves(move_bb,all_pcs)
    return move_bb & ~all_pcs
end

"Filter possible moves for legality for king"
function legal_king_moves(loc,info::LegalInfo)
    poss_moves = possible_king_moves(loc)
    #Filter out moves that put king in check
    legal_moves = poss_moves & ~info.attack_sqs
    return legal_moves
end

"Filter possible moves for legality for knight"
function legal_knight_moves(loc,info::LegalInfo)
    poss_moves = possible_knight_moves(loc)
    #Filter out knight moves that don't block/capture if in check
    legal_moves = poss_moves & (info.checks | info.blocks) 
    return legal_moves
end

"Filter possible moves for legality for bishop"
function legal_bishop_moves(loc,all_pcs,bishoppins,info::LegalInfo)
    poss_moves = possible_bishop_moves(loc,all_pcs)
    #Filter out bishop moves that don't block/capture if in check/pinned
    legal_moves = poss_moves & (info.checks | info.blocks) & bishoppins
    return legal_moves
end

"Filter possible moves for legality for rook"
function legal_rook_moves(loc,all_pcs, rookpins, info::LegalInfo)
    poss_moves = possible_rook_moves(loc, all_pcs)
    #Filter out rook moves that don't block/capture if in check/pinned
    legal_moves = poss_moves & (info.checks | info.blocks) & rookpins
    return legal_moves
end

"Filter possible moves for legality for queen"
function legal_queen_moves(loc, all_pcs, rookpins, bishoppins, info::LegalInfo)
    legal_rook = legal_rook_moves(loc, all_pcs, rookpins, info)
    legal_bishop = legal_bishop_moves(loc, all_pcs, bishoppins, info)
    return legal_rook | legal_bishop
end

"Bitboard logic to get attacks and quiets from legal moves"
function QAtt(legal, all_bb, enemy_bb, MODE::UInt64)
    attacks = attack_moves(legal, enemy_bb)
    #set quiets to zero if only generating attacks
    quiets = quiet_moves(legal, all_bb) * MODE
    return quiets, attacks
end

"bishop can only move if pinned diagonally"
pinned_bishop(piece_bb, bishoppins) = piece_bb & bishoppins

"rook can only move if pinned vertic/horizontally"
pinned_rook(piece_bb,rookpins) = piece_bb & rookpins

"returns attack and quiet moves only if legal, based on checks and pins"
@inline function get_queen_moves!(board::BoardState, enemy_pcs, all_pcs, MODE, info::LegalInfo)
    piece_bb = ally_piece(board, QUEEN)
    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinned_bb = piece_bb & ~(info.rookpins | info.bishoppins)
    rook_pinned_bb = pinned_rook(piece_bb, info.rookpins)
    bishop_pinned_bb = pinned_bishop(piece_bb, info.bishoppins)

    for loc in unpinned_bb
        legal = legal_queen_moves(loc, all_pcs, BITBOARD_FULL, BITBOARD_FULL, info)
        quiets, attacks = QAtt(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(QUEEN, board, quiets, loc, false)
        moves_from_location!(QUEEN, board, attacks, loc, true)
    end

    for loc in rook_pinned_bb
        legal = legal_rook_moves(loc, all_pcs, info.rookpins, info)
        quiets,attacks = QAtt(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(QUEEN, board, quiets, loc, false)
        moves_from_location!(QUEEN, board, attacks, loc, true)
    end

    for loc in bishop_pinned_bb
        legal = legal_bishop_moves(loc, all_pcs, info.bishoppins, info)
        quiets,attacks = QAtt(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(QUEEN, board, quiets, loc, false)
        moves_from_location!(QUEEN, board, attacks, loc, true)
    end
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

    for loc in pinned_bb
        legal = legal_rook_moves(loc, all_pcs, info.rookpins, info)
        quiets, attacks = QAtt(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(ROOK, board, quiets, loc, false)
        moves_from_location!(ROOK, board, attacks, loc, true)
    end

    for loc in unpinned_bb
        legal = legal_rook_moves(loc, all_pcs, BITBOARD_FULL, info)
        quiets, attacks = QAtt(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(ROOK, board, quiets, loc, false)
        moves_from_location!(ROOK, board, attacks, loc, true)
    end   
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

    for loc in pinned_bb
        legal = legal_bishop_moves(loc, all_pcs, info.bishoppins, info)
        quiets, attacks = QAtt(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(BISHOP, board, quiets, loc, false)
        moves_from_location!(BISHOP, board, attacks, loc, true)
    end
    for loc in unpinned_bb
        legal = legal_bishop_moves(loc, all_pcs, BITBOARD_FULL, info)
        quiets, attacks = QAtt(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(BISHOP, board, quiets, loc, false)
        moves_from_location!(BISHOP, board, attacks, loc, true)
    end
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
        quiets,attacks = QAtt(legal,all_pcs,enemy_pcs,MODE)

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
@inline function get_king_moves!(board::BoardState, enemy_pcs, all_pcs, castlrts, colID, MODE, info::LegalInfo)
    piece_bb = ally_piece(board, KING)
    for loc in piece_bb
        legal = legal_king_moves(loc, info)
        quiets, attacks = QAtt(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(KING, board, quiets, loc, false)
        moves_from_location!(KING, board, attacks, loc, true)
    end
    #cannot castle out of check. castling is a quiet move
    if info.attack_num == 0 && MODE == ALLMOVES
        #index into lookup table containing squares that must be free/not in check to castle
        #must mask out opponent's castle rights
        for castleID in BitBoard(get_Crights(castlrts, (colID + 1) % 2, 0))
            castleattack = MOVESET.castleCheck[castleID + 1]
            blockId = castleID % 2 # only queenside castle (=1) has extra block squares
            #white queen blockers are at index 5, black queen blockers are at index 6
            castleblock = MOVESET.castleCheck[castleID + blockId * (2 + (castleID % 3)) + 1]
            if (castleblock & all_pcs == 0) && (castleattack & info.attack_sqs == 0)
                append!(board.move_vector, create_castle(UInt8(castleID % 2), colID))
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
        append!(board.move_vector, Move(PAWN, UInt8(q2 + 2 * shift), q2, NULL_PIECE, DPUSH))
    end
end

"Create list of pawn capture moves with a given flag"
function capture_moves!(board::BoardState, leftattack, rightattack, promotemask, shift, enemy_pcs, checks, flag)
    for la in (leftattack & enemy_pcs & promotemask & checks)
        attack_pcID = identify_piecetype(board, la)
        append_moves!(board, PAWN, UInt8(la + shift + 1), la, attack_pcID, flag)
    end
    for ra in (rightattack & enemy_pcs & promotemask & checks)
        attack_pcID = identify_piecetype(board, ra)
        append_moves!(board, PAWN, UInt8(ra + shift - 1), ra, attack_pcID, flag)
    end
end

"returns false if it fails edge case where EP exposes attack on king"
function EPedgecase(board::BoardState, from, EPcap, kingpos, all_pcs)
    #test if king is on same rank as EP pawn
    if rank(from) == rank(kingpos)
        #all pcs BB after en-passant
        after_enpassant = setzero(setzero(all_pcs, from), EPcap)
        kingrookmvs = possible_rook_moves(kingpos, after_enpassant)

        if (kingrookmvs & (enemy_piece(board, ROOK) | enemy_piece(board, QUEEN))) > 0
            return false
        end
    end
    return true
end

"Check legality of en-passant before adding it to move list"
function push_enpassant!(board::BoardState, from, to, shift, checks, all_pcs, kingpos)
    EPcap = to + shift
    if checks & (BitBoard(1) << EPcap) > 0
        if EPedgecase(board, from, EPcap, kingpos, all_pcs)
            append!(board.move_vector, Move(PAWN, from, to, PAWN, EPFLAG))
        end
    end
end

"Create list of pawn en-passant moves"
function EP_moves!(board::BoardState, leftattack, rightattack, shift, EP_sqs, checks, all_pcs, kingpos)
    for la in (leftattack & EP_sqs)  
        push_enpassant!(board, UInt8(la + shift + 1), la, shift, checks, all_pcs, kingpos)
    end
    for ra in (rightattack & EP_sqs)
        push_enpassant!(board, UInt8(ra + shift - 1), ra, shift, checks, all_pcs, kingpos)
    end
end

"returns attack and quiet moves for pawns only if legal, based on checks and pins"
function get_pawn_moves!(board::BoardState, enemy_pcs, all_pcs, enpass_bb, colour::Bool, kingpos, MODE, info::LegalInfo)
    piece_bb = ally_piece(board, PAWN)
    pawn_masks = ifelse(colour, WHITE_MASKS, BLACK_MASKS)

    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinned_bb = piece_bb & ~(info.rookpins | info.bishoppins)
    Rpinned_bb = pinned_rook(piece_bb, info.rookpins)
    Bpinned_bb = pinned_bishop(piece_bb, info.bishoppins)

    #push once and remove any that are blocked
    pushpawn1 = cond_push(colour, unpinned_bb)
    legalpush1 = quiet_moves(pushpawn1, all_pcs)
    pushpinned = cond_push(colour, Rpinned_bb)
    legalpush1 |= quiet_moves(pushpinned, all_pcs) & info.rookpins

    #push twice if possible
    pushpawn2 = cond_push(colour, legalpush1 & pawn_masks.doublepush)
    legalpush2 = quiet_moves(pushpawn2, all_pcs)

    #shift left and right to attack
    attackleft = attack_left(pushpawn1)
    attackright = attack_right(pushpawn1)

    Bpush = cond_push(colour,Bpinned_bb)
    Battackleft = attack_left(Bpush)
    Battackright = attack_right(Bpush)

    #combine with attacks pinned by a bishop
    attackleft |= Battackleft & info.bishoppins
    attackright |= Battackright & info.bishoppins
    
    #add non-promote pushes, promote pushes, double pushes, non-promote captures, promote captures and en-passant
    push_moves!(board, legalpush1, ~pawn_masks.promote, pawn_masks.shift, info.blocks, NOFLAG, MODE),
    push_moves!(board, legalpush1, pawn_masks.promote, pawn_masks.shift, info.blocks, Promote(), MODE),
    push_moves!(board, legalpush2, pawn_masks.shift, info.blocks, MODE),
    capture_moves!(board, attackleft, attackright, ~pawn_masks.promote, pawn_masks.shift, enemy_pcs, info.checks, NOFLAG),
    capture_moves!(board, attackleft, attackright, pawn_masks.promote, pawn_masks.shift, enemy_pcs,info.checks, Promote()),
    EP_moves!(board, attackleft, attackright, pawn_masks.shift, enpass_bb, info.checks, all_pcs, kingpos)
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

    if (legalpush1 & info.blocks) > 0
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

    if ((attackleft & enemy_pieces_bb) & (info.checks | info.blocks)) > 0 || ((attackright & enemy_pieces_bb) & (info.checks | info.blocks)) > 0
        return true
    end
    return false
end

"Iterate through zhash list until last halfmove reset to check for repeated positions - not working"
function three_repetition(zobrist_hash ,Data::BoardData)::Bool
    count = 1
    for zhist in Data.zobrist_hash_history[end - 1:end - Data.half_moves[end] - 1]
        if zhist == zobrist_hash 
            count += 1
        end
        if count > 2
            return true
        end
    end
    return false
end

"one-liner to test repetition. function above should be faster but doesn't seem to work currently"
three_repetition(board::BoardState) = count(i->(i==board.zobrist_hash), board.Data.zobrist_hash_history) >= 3

"implement 50 move rule and 3 position repetition"
function draw_state(board::BoardState)::Bool
    return (board.Data.half_moves[end] >= 100) || three_repetition(board) #three_repetition(board.zobrist_hash, board.Data)
end

"get lists of pieces and piece types, find locations of owned pieces and create a movelist of all legal moves"
function generate_moves(board::BoardState, legal_info::LegalInfo=attack_info(board), MODE::UInt64=ALLMOVES)
    prev_move_index = board.move_vector.ind
    enemy_pcs_bb = board.piece_union[colour_id(opposite(board.colour)) + 1] 
    all_pcs_bb = board.piece_union[end]
    
    kingpos = locate_king(board, board.colour)

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
function generate_attacks(board::BoardState, legal_info::LegalInfo=attack_info(board))
    return generate_moves(board, legal_info, ATTACKONLY)
end

"evaluates whether we are in a terminal node due to draw conditions, or check/stale-mates"
function gameover!(board::BoardState)
    info = attack_info(board)
    if draw_state(board)
        board.state = Draw()
    else
        all_pcs_bb = board.piece_union[end]
        ally_pcs_bb = board.piece_union[colour_id(board.colour) + 1] 
        kingpos = locate_king(board, board.colour)

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
    return info
end