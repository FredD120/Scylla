"return location of king for side to move"
locate_king(B::Boardstate, colour) = LSB(B.pieces[colour_piece_id(colour, King)])

"Masked 4-bit integer representing king- and queen-side castling rights for one side"
function get_Crights(castling, colour_id, KorQside)
    #colour_id must be 0 for white and 1 for black
    #KorQside allows masking out of only king/queen side
    #for a given colour, =0 if both, 1 = king, 2 = queen
    return castling & moveset.CRightsMask[3 * colour_id + KorQside + 1]
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

"All pseudolegal King moves"
possible_king_moves(location) = moveset.king[location+1]
"All pseudolegal Knight moves"
possible_knight_moves(location) = moveset.knight[location+1]
"All pseudolegal Rook moves"
possible_rook_moves(location, all_pcs) = sliding_attacks(RookMagics[location+1], all_pcs)
"All pseudolegal Bishop moves"
possible_bishop_moves(location, all_pcs) = sliding_attacks(BishopMagics[location+1], all_pcs)
"All pseudolegal Queen moves"
possible_queen_moves(location, all_pcs) = sliding_attacks(RookMagics[location + 1], all_pcs) | sliding_attacks(BishopMagics[location + 1], all_pcs)

"Returns BB containing attacking moves assuming all pieces in BB are pawns"
function possible_pawn_moves(pawnBB, colour::Bool)
    pawn_push = cond_push(colour, pawnBB)
    return attack_left(pawn_push) | attack_right(pawn_push)
end

"checks enemy pieces to see if any are attacking the king square, returns BB of attackers"
function attack_pcs(pc_list::AbstractArray{BitBoard}, all_pcs::BitBoard, location::Integer, colour::Bool)::BitBoard
    attacks = BitBoard()
    knightmoves = possible_knight_moves(location)
    attacks |= (knightmoves & pc_list[Knight])

    rookmoves = possible_rook_moves(location,all_pcs)
    rookattacks = (rookmoves & (pc_list[Rook] | pc_list[Queen]))
    attacks |= rookattacks

    bishopmoves = possible_bishop_moves(location,all_pcs)
    bishopattacks = (bishopmoves & (pc_list[Bishop] | pc_list[Queen]))
    attacks |= bishopattacks

    pawnattacks = possible_pawn_moves(BitBoard(1)<<location,colour)
    attacks |= pawnattacks & pc_list[Pawn]

    return attacks
end

"Bitboard of all squares being attacked by a side"
function all_poss_moves(pc_list::AbstractArray{BitBoard},all_pcs,colour::Bool)::BitBoard
    attacks = BitBoard()

    pieceBB = pc_list[King]
    for location in pieceBB
        attacks |= possible_king_moves(location)
    end
    
    pieceBB = pc_list[Knight]
    for location in pieceBB
        attacks |= possible_knight_moves(location)
    end

    pieceBB = pc_list[Bishop]
    for location in pieceBB
        attacks |= possible_bishop_moves(location,all_pcs)
    end

    pieceBB = pc_list[Rook]
    for location in pieceBB
        attacks |= possible_rook_moves(location,all_pcs)
    end

    pieceBB = pc_list[Queen]
    for location in pieceBB
        attacks |= possible_queen_moves(location,all_pcs)
    end

    attacks |= possible_pawn_moves(pc_list[Pawn],opposite(colour))
    return attacks
end

"detect pins and create rook/bishop pin BBs"
function detect_pins(pos,pc_list,all_pcs,ally_pcs)
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
    rookpins = rpin_attacks & (pc_list[Rook] | pc_list[Queen])
    #iterate through rooks/queens pinning king
    for loc in rookpins
        #add squares on pin line to pinning BB
        rookpins |= rook_no_blocks & possible_rook_moves(loc,blocks_removed)
    end

    #same but for bishops
    bishop_no_blocks = possible_bishop_moves(pos,blocks_removed) 
    bpin_attacks = bishop_no_blocks & ~slide_attacks
    bishoppins = bpin_attacks & (pc_list[Bishop] | pc_list[Queen])
    for loc in bishoppins
        bishoppins |= bishop_no_blocks & possible_bishop_moves(loc,blocks_removed)
    end

    return rookpins,bishoppins
end

"returns struct containing info on attacks, blocks and pins of king by enemy piecelist"
function attack_info(board::Boardstate)::LegalInfo
    attacks = BitBoard_full()
    blocks = BitBoard()
    attacker_num = 0

    enemy_list = enemy_pieces(board)
    
    ally_pcs = board.piece_union[colour_id(board.Colour) + 1]
    all_pcs = board.piece_union[end]
    KingBB = board.pieces[board.Colour + King]
    position = LSB(KingBB)
    colour::Bool = whitesmove(board.Colour)

    #construct BB of all enemy attacks, must remove king when checking if square is attacked
    all_except_king = all_pcs & ~(KingBB)
    attacked_sqs = all_poss_moves(enemy_list,all_except_king,colour)

    #if king not under attack, dont need to find attacking pieces or blockers
    if KingBB & attacked_sqs == BitBoard() 
        blocks = BitBoard_full()
    else
        attacks = attack_pcs(enemy_list,all_pcs,position,colour)
        attacker_num = count_ones(attacks)
        #if only a single sliding piece is attacking the king, it can be blocked
        if attacker_num == 1
            kingmoves = possible_rook_moves(position,all_pcs)
            slide_attckers = kingmoves & (enemy_list[Rook] | enemy_list[Queen])
            for attack_pos in slide_attckers
                attackmoves = possible_rook_moves(attack_pos,all_pcs)
                blocks |= attackmoves & kingmoves
            end

            kingmoves = possible_bishop_moves(position,all_pcs)
            slide_attckers = kingmoves & (enemy_list[Bishop] | enemy_list[Queen])
            for attack_pos in slide_attckers
                attackmoves = possible_bishop_moves(attack_pos,all_pcs)
                blocks |= attackmoves & kingmoves
            end
        end
    end
    rookpins,bishoppins = detect_pins(position,enemy_list,all_pcs,ally_pcs)
    return LegalInfo(attacks,blocks,rookpins,bishoppins,attacked_sqs,attacker_num)
end

"create a castling move where from and to is the rook to move"
function create_castle(KorQ,WorB)
    #KorQ is 0 if kingside, 1 if queenside 
    #WorB is 0 if white, 1 if black
    from = UInt8(63 - 7*KorQ - WorB*56)
    to = UInt8(from - 2 + 5*KorQ)
    return Move(King, from, to, NULL_PIECE, KCASTLE + KorQ)
end

"creates a move from a given location using the Move struct, with flag for attacks"
@inline function moves_from_location!(type::UInt8, moves, enemy_pcs::AbstractArray{BitBoard}, destinations::BitBoard, origin, isattack::Bool)
    for loc in destinations
        attacked_pieceID = NULL_PIECE
        if isattack
            #move struct needs info on piece being attacked
            attacked_pieceID = identify_piecetype(enemy_pcs, loc)
        end
        append!(moves, Move(type, origin, loc, attacked_pieceID, NOFLAG))
    end
end

"Bitboard containing only the attacks by a particular piece"
function attack_moves(move_bb, enemy_bb)
    return move_bb & enemy_bb
end

"Bitboard containing only the quiets by a particular piece"
function quiet_moves(moveBB,all_pcs)
    return moveBB & ~all_pcs
end

"Filter possible moves for legality for King"
function legal_king_moves(loc,info::LegalInfo)
    poss_moves = possible_king_moves(loc)
    #Filter out moves that put king in check
    legal_moves = poss_moves & ~info.attack_sqs
    return legal_moves
end

"Filter possible moves for legality for Knight"
function legal_knight_moves(loc,info::LegalInfo)
    poss_moves = possible_knight_moves(loc)
    #Filter out knight moves that don't block/capture if in check
    legal_moves = poss_moves & (info.checks | info.blocks) 
    return legal_moves
end

"Filter possible moves for legality for Bishop"
function legal_bishop_moves(loc,all_pcs,bishoppins,info::LegalInfo)
    poss_moves = possible_bishop_moves(loc,all_pcs)
    #Filter out bishop moves that don't block/capture if in check/pinned
    legal_moves = poss_moves & (info.checks | info.blocks) & bishoppins
    return legal_moves
end

"Filter possible moves for legality for Rook"
function legal_rook_moves(loc,all_pcs, rookpins, info::LegalInfo)
    poss_moves = possible_rook_moves(loc, all_pcs)
    #Filter out rook moves that don't block/capture if in check/pinned
    legal_moves = poss_moves & (info.checks | info.blocks) & rookpins
    return legal_moves
end

"Filter possible moves for legality for Queen"
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

"Bishop can only move if pinned diagonally"
pinned_bishop(piece_bb, bishoppins) = piece_bb & bishoppins

"Rook can only move if pinned vertic/horizontally"
pinned_rook(piece_bb,rookpins) = piece_bb & rookpins

"returns attack and quiet moves only if legal, based on checks and pins"
@inline function get_queen_moves!(moves,pieceBB,enemy_vec::AbstractArray{BitBoard},enemy_pcs,all_pcs,MODE,info::LegalInfo)
    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinnedBB = pieceBB & ~(info.rookpins | info.bishoppins)
    RpinnedBB = pinned_rook(pieceBB,info.rookpins)
    BpinnedBB = pinned_bishop(pieceBB,info.bishoppins)

    for loc in unpinnedBB
        legal = legal_queen_moves(loc,all_pcs,BitBoard_full(),BitBoard_full(),info)
        quiets,attacks = QAtt(legal,all_pcs,enemy_pcs,MODE)

        moves_from_location!(Queen,moves,enemy_vec,quiets,loc,false)
        moves_from_location!(Queen,moves,enemy_vec,attacks,loc,true)
    end

    for loc in RpinnedBB
        legal = legal_rook_moves(loc,all_pcs,info.rookpins,info)
        quiets,attacks = QAtt(legal,all_pcs,enemy_pcs,MODE)

        moves_from_location!(Queen,moves,enemy_vec,quiets,loc,false)
        moves_from_location!(Queen,moves,enemy_vec,attacks,loc,true)
    end

    for loc in BpinnedBB
        legal = legal_bishop_moves(loc,all_pcs,info.bishoppins,info)
        quiets,attacks = QAtt(legal,all_pcs,enemy_pcs,MODE)

        moves_from_location!(Queen,moves,enemy_vec,quiets,loc,false)
        moves_from_location!(Queen,moves,enemy_vec,attacks,loc,true)
    end
end

"Returns true if any queen moves exist"
@inline function any_queen_moves(pieceBB,all_pcs,ally_pcsBB,info::LegalInfo)::Bool
    unpinnedBB = pieceBB & ~(info.rookpins | info.bishoppins)
    RpinnedBB = pinned_rook(pieceBB,info.rookpins)
    BpinnedBB = pinned_bishop(pieceBB,info.bishoppins)

    for loc in unpinnedBB
        if (legal_queen_moves(loc,all_pcs,BitBoard_full(),BitBoard_full(),info) & ~ally_pcsBB) > 0
            return true
        end
    end
    for loc in RpinnedBB
        if (legal_rook_moves(loc,all_pcs,info.rookpins,info) & ~ally_pcsBB) > 0
            return true
        end
    end
    for loc in BpinnedBB
        if (legal_bishop_moves(loc,all_pcs,info.bishoppins,info) & ~ally_pcsBB) > 0
            return true
        end
    end
    return false
end

"returns attack and quiet moves only if legal for rook, based on checks and pins"
@inline function get_rook_moves!(moves,pieceBB,enemy_vec::AbstractArray{BitBoard},enemy_pcs,all_pcs,MODE,info::LegalInfo)
    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinnedBB = pieceBB & ~(info.rookpins | info.bishoppins)
    pinnedBB = pinned_rook(pieceBB,info.rookpins)

    for (BB,rpins) in zip([pinnedBB,unpinnedBB],[info.rookpins,BitBoard_full()])
        for loc in BB
            legal = legal_rook_moves(loc,all_pcs,rpins,info)
            quiets,attacks = QAtt(legal,all_pcs,enemy_pcs,MODE)

            moves_from_location!(Rook,moves,enemy_vec,quiets,loc,false)
            moves_from_location!(Rook,moves,enemy_vec,attacks,loc,true)
        end
    end
end

"Returns true if any rook moves exist"
@inline function any_rook_moves(pieceBB,all_pcs,ally_pcsBB,info::LegalInfo)::Bool
    unpinnedBB = pieceBB & ~(info.rookpins | info.bishoppins)
    pinnedBB = pinned_rook(pieceBB,info.rookpins)
      for (BB,rpins) in zip([pinnedBB,unpinnedBB],[info.rookpins,BitBoard_full()])
        for loc in BB
            if (legal_rook_moves(loc,all_pcs,rpins,info) & ~ally_pcsBB) > 0
                return true
            end
        end
    end
    return false
end

"returns attack and quiet moves only if legal for bishop, based on checks and pins"
@inline function get_bishop_moves!(moves,pieceBB,enemy_vec::AbstractArray{BitBoard},enemy_pcs,all_pcs,MODE,info::LegalInfo)
    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinnedBB = pieceBB & ~(info.rookpins | info.bishoppins)
    pinnedBB = pinned_bishop(pieceBB,info.bishoppins)

    for (BB,bpins) in zip([pinnedBB,unpinnedBB],[info.bishoppins,BitBoard_full()])
        for loc in BB
            legal = legal_bishop_moves(loc,all_pcs,bpins,info)
            quiets,attacks = QAtt(legal,all_pcs,enemy_pcs,MODE)

            moves_from_location!(Bishop,moves,enemy_vec,quiets,loc,false)
            moves_from_location!(Bishop,moves,enemy_vec,attacks,loc,true)
        end
    end
end

"Returns true if any bishop moves exist"
@inline function any_bishop_moves(pieceBB,all_pcs,ally_pcsBB,info::LegalInfo)::Bool
    unpinnedBB = pieceBB & ~(info.rookpins | info.bishoppins)
    pinnedBB = pinned_bishop(pieceBB,info.bishoppins)
    for (BB,bpins) in zip([pinnedBB,unpinnedBB],[info.bishoppins,BitBoard_full()])
        for loc in BB
            if (legal_bishop_moves(loc,all_pcs,bpins,info) & ~ally_pcsBB) > 0
                return true
            end
        end
    end
    return false
end

"returns attack and quiet moves only if legal for knight, based on checks and pins"
@inline function get_knight_moves!(moves,pieceBB,enemy_vec::AbstractArray{BitBoard},enemy_pcs,all_pcs,MODE,info::LegalInfo)
    #split into pinned and unpinned pieces, only unpinned knights can move
    unpinnedBB = pieceBB & ~(info.rookpins | info.bishoppins)
    for loc in unpinnedBB
        legal = legal_knight_moves(loc,info)
        quiets,attacks = QAtt(legal,all_pcs,enemy_pcs,MODE)

        moves_from_location!(Knight,moves,enemy_vec,quiets,loc,false)
        moves_from_location!(Knight,moves,enemy_vec,attacks,loc,true)
    end
end

"Returns true if any knight moves exist"
@inline function any_knight_moves(pieceBB,ally_pcsBB,info::LegalInfo)::Bool
    unpinnedBB = pieceBB & ~(info.rookpins | info.bishoppins)
    for loc in unpinnedBB
        if (legal_knight_moves(loc,info) & ~ally_pcsBB) > 0
            return true
        end
    end
    return false
end

"returns attacks, quiet moves and castles for king only if legal, based on checks"
@inline function get_king_moves!(moves, pieceBB, enemy_vec::AbstractArray{BitBoard}, enemy_pcs, all_pcs, castlrts, colID, MODE, info::LegalInfo)
    for loc in pieceBB
        legal = legal_king_moves(loc, info)
        quiets, attacks = QAtt(legal, all_pcs, enemy_pcs, MODE)

        moves_from_location!(King, moves, enemy_vec, quiets, loc, false)
        moves_from_location!(King, moves, enemy_vec, attacks, loc, true)
    end
    #cannot castle out of check. castling is a quiet move
    if info.attack_num == 0 && MODE == ALLMOVES
        #index into lookup table containing squares that must be free/not in check to castle
        #must mask out opponent's castle rights
        for castleID in identify_locations(get_Crights(castlrts, (colID + 1) % 2, 0))
            castleattack = moveset.CastleCheck[castleID + 1]
            blockId = castleID % 2 # only queenside castle (=1) has extra block squares
            #white queen blockers are at index 5, black queen blockers are at index 6
            castleblock = moveset.CastleCheck[castleID + blockId * (2 + (castleID % 3)) + 1]
            if (castleblock & all_pcs == 0) & (castleattack & info.attack_sqs == 0)
                append!(moves, create_castle(UInt8(castleID % 2), colID))
            end
        end
    end
end

"Returns true if any king moves exist. Don't need to check castles as castle is only legal if sideways moves are"
@inline function any_king_moves(kingpos,ally_pcsBB,info::LegalInfo)::Bool
    if (legal_king_moves(kingpos,info) & ~ally_pcsBB) > 0
        return true
    else
        return false
    end
end

"use bitshifts to push all white/black pawns at once"
cond_push(colour::Bool, pawnBB) = ifelse(colour, pawnBB >> 8, pawnBB << 8)

const white_masks = (
        doublepush = BitBoard(0xFF0000000000),
        promote = BitBoard(0xFF),
        shift =  8
)

const black_masks = (
        doublepush = BitBoard(0xFF0000),
        promote = BitBoard(0xFF00000000000000),
        shift =  -8
)

attack_left(pieceBB) = (pieceBB >> 1) & BitBoard(0x7F7F7F7F7F7F7F7F)

attack_right(pieceBB) = (pieceBB << 1) & BitBoard(0xFEFEFEFEFEFEFEFE)

"appends 4 promotion moves"
function append_moves!(moves,piece_type,from,to,capture_type,::Promote)
    for flag in [PROMQUEEN,PROMROOK,PROMBISHOP,PROMKNIGHT]
        append!(moves, Move(piece_type, from, to, capture_type, flag))
    end
end

"appends a non-promote move with a given flag"
function append_moves!(moves,piece_type,from,to,capture_type,flag::UInt8)
    append!(moves, Move(piece_type, from, to, capture_type, flag))
end

"Create list of pawn push moves with a given flag"
function push_moves!(moves, singlepush, promotemask, shift, blocks, flag, MODE::UInt64)
    for q1 in ((singlepush * MODE) & blocks & promotemask)
        append_moves!(moves, Pawn, UInt8(q1 + shift), q1, NULL_PIECE, flag)
    end
end

"Create list of double pawn push moves"
function push_moves!(moves,doublepush,shift,blocks,MODE::UInt64)
    for q2 in ((doublepush*MODE) & blocks)
        append!(moves, Move(Pawn, UInt8(q2 + 2 * shift), q2, NULL_PIECE, DPUSH))
    end
end

"Create list of pawn capture moves with a given flag"
function capture_moves!(moves, leftattack, rightattack, promotemask, shift, enemy_pcs, checks, enemy_vec::AbstractArray{BitBoard}, flag)
    for la in (leftattack & enemy_pcs & promotemask & checks)
        attack_pcID = identify_piecetype(enemy_vec, la)
        append_moves!(moves, Pawn, UInt8(la + shift + 1), la, attack_pcID, flag)
    end
    for ra in (rightattack & enemy_pcs & promotemask & checks)
        attack_pcID = identify_piecetype(enemy_vec, ra)
        append_moves!(moves, Pawn, UInt8(ra + shift - 1), ra, attack_pcID, flag)
    end
end

"returns false if it fails edge case where EP exposes attack on king"
function EPedgecase(from,EPcap,kingpos,all_pcs,enemy_vec)
    #test if king is on same rank as EP pawn
    if rank(from) == rank(kingpos)
        #all pcs BB after en-passant
        after_EP = setzero(setzero(all_pcs,from),EPcap)
        kingrookmvs = possible_rook_moves(kingpos,after_EP)
        if (kingrookmvs & (enemy_vec[Rook] | enemy_vec[Queen])) > 0
            return false
        end
    end
    return true
end

"Check legality of en-passant before adding it to move list"
function push_EP!(moves, from, to, shift, checks, all_pcs, enemy_vec, kingpos)
    EPcap = to + shift
    if checks & (BitBoard(1) << EPcap) > 0
        if EPedgecase(from, EPcap, kingpos, all_pcs, enemy_vec)
            append!(moves, Move(Pawn, from, to, Pawn, EPFLAG))
        end
    end
end

"Create list of pawn en-passant moves"
function EP_moves!(movelist, leftattack, rightattack, shift, EP_sqs, checks, all_pcs, enemy_vec, kingpos)
    for la in (leftattack & EP_sqs)  
        push_EP!(movelist, UInt8(la + shift + 1), la, shift, checks, all_pcs, enemy_vec, kingpos)
    end
    for ra in (rightattack & EP_sqs)
        push_EP!(movelist, UInt8(ra + shift - 1), ra, shift, checks, all_pcs, enemy_vec, kingpos)
    end
end

"returns attack and quiet moves for pawns only if legal, based on checks and pins"
function get_pawn_moves!(movelist, pieceBB, enemy_vec::AbstractArray{BitBoard}, enemy_pcs, all_pcs, enpassBB, colour::Bool, kingpos, MODE, info::LegalInfo)
    pawnMasks = ifelse(colour, white_masks, black_masks)

    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinnedBB = pieceBB & ~(info.rookpins | info.bishoppins)
    RpinnedBB = pinned_rook(pieceBB, info.rookpins)
    BpinnedBB = pinned_bishop(pieceBB, info.bishoppins)

    #push once and remove any that are blocked
    pushpawn1 = cond_push(colour, unpinnedBB)
    legalpush1 = quiet_moves(pushpawn1, all_pcs)
    pushpinned = cond_push(colour, RpinnedBB)
    legalpush1 |= quiet_moves(pushpinned, all_pcs) & info.rookpins

    #push twice if possible
    pushpawn2 = cond_push(colour, legalpush1 & pawnMasks.doublepush)
    legalpush2 = quiet_moves(pushpawn2, all_pcs)

    #shift left and right to attack
    attackleft = attack_left(pushpawn1)
    attackright = attack_right(pushpawn1)

    Bpush = cond_push(colour,BpinnedBB)
    Battackleft = attack_left(Bpush)
    Battackright = attack_right(Bpush)

    #combine with attacks pinned by a bishop
    attackleft |= Battackleft & info.bishoppins
    attackright |= Battackright & info.bishoppins
    
    #add non-promote pushes, promote pushes, double pushes, non-promote captures, promote captures and en-passant
    push_moves!(movelist, legalpush1, ~pawnMasks.promote, pawnMasks.shift, info.blocks, NOFLAG, MODE),
    push_moves!(movelist, legalpush1, pawnMasks.promote, pawnMasks.shift, info.blocks, Promote(), MODE),
    push_moves!(movelist, legalpush2, pawnMasks.shift, info.blocks, MODE),
    capture_moves!(movelist, attackleft, attackright, ~pawnMasks.promote, pawnMasks.shift, enemy_pcs, info.checks, enemy_vec, NOFLAG),
    capture_moves!(movelist, attackleft, attackright, pawnMasks.promote, pawnMasks.shift, enemy_pcs,info.checks, enemy_vec, Promote()),
    EP_moves!(movelist, attackleft, attackright, pawnMasks.shift, enpassBB, info.checks, all_pcs, enemy_vec, kingpos)
end

"Return true if any pawn moves exist"
function any_pawn_moves(pieceBB,all_pcs,ally_pcsBB,colour::Bool,info::LegalInfo)::Bool
    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinnedBB = pieceBB & ~(info.rookpins | info.bishoppins)
    RpinnedBB = pinned_rook(pieceBB, info.rookpins)
    BpinnedBB = pinned_bishop(pieceBB, info.bishoppins)

    #push once and remove any that are blocked
    pushpawn1 = cond_push(colour, unpinnedBB)
    legalpush1 = quiet_moves(pushpawn1, all_pcs)
    pushpinned = cond_push(colour, RpinnedBB)
    legalpush1 |= quiet_moves(pushpinned, all_pcs) & info.rookpins

    if (legalpush1 & info.blocks) > 0
        return true
    end

    #shift left and right to attack
    attackleft = attack_left(pushpawn1)
    attackright = attack_right(pushpawn1)

    Bpush = cond_push(colour, BpinnedBB)
    Battackleft = attack_left(Bpush)
    Battackright = attack_right(Bpush)

    #combine with attacks pinned by a bishop
    attackleft |= Battackleft & info.bishoppins
    attackright |= Battackright & info.bishoppins

    enemy_piecesBB = all_pcs & ~ally_pcsBB

    if ((attackleft & enemy_piecesBB) & (info.checks | info.blocks)) > 0 || ((attackright & enemy_piecesBB) & (info.checks | info.blocks)) > 0
        return true
    end
    return false
end

"Iterate through zhash list until last halfmove reset to check for repeated positions - not working"
function three_repetition(Zhash,Data::BoardData)::Bool
    count = 1
    for zhist in Data.zobrist_hash_history[end - 1:end - Data.Halfmoves[end] - 1]
        if zhist == Zhash 
            count += 1
        end
        if count > 2
            return true
        end
    end
    return false
end

"one-liner to test repetition. function above should be faster but doesn't seem to work currently"
three_repetition(board::Boardstate) = count(i->(i==board.zobrist_hash), board.Data.zobrist_hash_history) >= 3

"implement 50 move rule and 3 position repetition"
function draw_state(board::Boardstate)::Bool
    return (board.Data.Halfmoves[end] >= 100) || three_repetition(board) #three_repetition(board.zobrist_hash, board.Data)
end

"get lists of pieces and piece types, find locations of owned pieces and create a movelist of all legal moves"
function generate_moves(board::Boardstate, legal_info::LegalInfo=attack_info(board), MODE::UInt64=ALLMOVES)::Vector{Move}
    clear!(board.Moves)
    enemy = enemy_pieces(board)

    enemy_pcsBB = board.piece_union[colour_id(opposite(board.Colour)) + 1] 
    all_pcsBB = board.piece_union[end]
    
    kingBB = board.pieces[King + board.Colour]
    kingpos = LSB(kingBB)

    get_king_moves!(board.Moves, kingBB, enemy, enemy_pcsBB, all_pcsBB,
    board.Castle, colour_id(board.Colour), MODE, legal_info)

    #if multiple checks on king, only king can move
    if legal_info.attack_num <= 1
        #run through pieces and BBs, adding moves to list
        get_knight_moves!(board.Moves, board.pieces[Knight + board.Colour], enemy,
            enemy_pcsBB, all_pcsBB, MODE, legal_info)

        get_bishop_moves!(board.Moves, board.pieces[Bishop + board.Colour], enemy,
            enemy_pcsBB, all_pcsBB, MODE, legal_info)
        
        get_rook_moves!(board.Moves, board.pieces[Rook + board.Colour], enemy,
            enemy_pcsBB, all_pcsBB, MODE, legal_info)
        
        get_queen_moves!(board.Moves, board.pieces[Queen + board.Colour], enemy,
            enemy_pcsBB, all_pcsBB, MODE, legal_info)

        get_pawn_moves!(board.Moves, board.pieces[Pawn + board.Colour], enemy, enemy_pcsBB, all_pcsBB, board.EnPass,
        whitesmove(board.Colour), kingpos, MODE, legal_info)
    end
    return current_moves(board.Moves)
end

"helper function that used generate moves create a movelist of all attacking moves (no quiets)"
function generate_attacks(board::Boardstate, legal_info::LegalInfo=attack_info(board))::Vector{Move}
    return generate_moves(board, legal_info, ATTACKONLY)
end

"evaluates whether we are in a terminal node due to draw conditions, or check/stale-mates"
function gameover!(board::Boardstate)
    info = attack_info(board)
    if draw_state(board)
        board.State = Draw()
    else
        all_pcsBB = board.piece_union[end]
        ally_pcsBB = board.piece_union[colour_id(board.Colour)+1] 
        kingpos = locate_king(board,board.Colour)

        if any_king_moves(kingpos,ally_pcsBB,info) 
            board.State = Neutral()
        elseif info.attack_num <= 1 && (
                any_pawn_moves(board.pieces[board.Colour+Pawn],all_pcsBB,ally_pcsBB,whitesmove(board.Colour),info) ||
                any_knight_moves(board.pieces[board.Colour+Knight],ally_pcsBB,info) ||
                any_bishop_moves(board.pieces[board.Colour+Bishop],all_pcsBB,ally_pcsBB,info) ||
                any_rook_moves(board.pieces[board.Colour+Rook],all_pcsBB,ally_pcsBB,info) ||
                any_queen_moves(board.pieces[board.Colour+Queen],all_pcsBB,ally_pcsBB,info))
            board.State = Neutral() 
        else
            if info.attack_num > 0
                board.State = Loss()
            else
                board.State = Draw()
            end
        end
    end
    return info
end