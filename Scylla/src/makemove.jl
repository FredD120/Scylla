# Define make and unmake move functions
# Define all helper functions to ensure zobrist hash, board position and PST scores are preserved

"utilises setzero to remove a piece from a position"
@inline function destroy_piece!(board::BoardState, colour, piece_type, pos)
    piece_id = long_index(colour) + piece_type
    board.pieces[piece_id] = setzero(board.pieces[piece_id], pos)
    update_pst_score!(board.pst_score, colour, piece_type, pos, -1)
    board.zobrist_hash ⊻= zobrist_piece(piece_id, pos)
    board.piece_positions[pos + 1] = 0

    union_id = short_index(colour) + 1
    board.piece_union[union_id] = setzero(board.piece_union[union_id], pos)
end

"utilises setone to create a piece in a position"
@inline function create_piece!(board::BoardState, colour, piece_type, pos)
    piece_id = long_index(colour) + piece_type
    board.pieces[piece_id] = setone(board.pieces[piece_id], pos)
    update_pst_score!(board.pst_score, colour, piece_type, pos, +1)
    board.zobrist_hash ⊻= zobrist_piece(piece_id, pos)
    board.piece_positions[pos + 1] = piece_type

    union_id = short_index(colour) + 1 
    board.piece_union[union_id] = setone(board.piece_union[union_id], pos)
end

"utilises create and destroy to move single piece"
@inline function move_piece!(board::BoardState, colour, piece_type, from, to)
    destroy_piece!(board, colour, piece_type, from)
    create_piece!(board, colour, piece_type, to)
end

"switch to opposite colour and update hash key"
@inline function swap_player!(board)
    board.colour = !board.colour
    board.zobrist_hash ⊻= ZOBRIST_COLOUR
end

"remove both castling rights for side-to-move and update zobrist hash"
@inline function remove_all_castle_rights!(board::BoardState, colour)
    board.zobrist_hash = zobrist_castle(board.zobrist_hash, board.castle)

    # logical AND with NOT of castle rights mask to remove ally bits
    board.castle &= ~CASTLE_RIGHTS_MASK[short_index(colour) + 1]
    board.zobrist_hash = zobrist_castle(board.zobrist_hash, board.castle)
end

"remove king castling rights for side-to-move and update zobrist hash"
@inline function remove_king_castle_rights!(board::BoardState, colour)
    board.zobrist_hash = zobrist_castle(board.zobrist_hash, board.castle)

    # logical AND with all but king castle rights of side-to-move
    board.castle &= ~(UInt8(1) << (short_index(colour) * 2))
    board.zobrist_hash = zobrist_castle(board.zobrist_hash, board.castle)
end

"remove queen castling rights for side-to-move and update zobrist hash"
@inline function remove_queen_castle_rights!(board::BoardState, colour)
    board.zobrist_hash = zobrist_castle(board.zobrist_hash, board.castle)

    # logical AND with all but queen castle rights of side-to-move
    board.castle &= ~(UInt8(1) << (short_index(colour) * 2 + 1))
    board.zobrist_hash = zobrist_castle(board.zobrist_hash, board.castle)
end

"set new EP val and incrementally update zobrist hash"
@inline function update_enpassant!(board::BoardState, newval::BitBoard)
    board.zobrist_hash = zobrist_enpassant(board.zobrist_hash, board.enpassant_bb)
    board.enpassant_bb = newval
    board.zobrist_hash = zobrist_enpassant(board.zobrist_hash, board.enpassant_bb)
end

"returns location of sqaure behind pawn, either to capture by en-passant or to flag square for attack by en-passant"
enpassant_location(colour, destination) = ifelse(colour, destination + 8, destination - 8)

"play a castling move onto the board. perform lookup of rook square to move from/to"
@inline function make_castle!(board::BoardState, move_from, move_to, move_flag)
    move_piece!(board, board.colour, KING, move_from, move_to)
    
    castle_lookup = (move_flag == QUEEN_CASTLE) + short_index(board.colour) * 2 + 1
    rook_from = ROOK_START_SQUARES[castle_lookup]
    rook_to = ROOK_CASTLE_SQUARES[castle_lookup]
    move_piece!(board, board.colour, ROOK, rook_from, rook_to)

    remove_all_castle_rights!(board, board.colour)
    #castling does not reset halfmove clock
    board.half_moves += 1
end

"if not castling, moving the king/rooks or capturing rooks can update castling rights"
@inline function implicit_update_castle!(board::BoardState, piece_type, move_from, move_to)
    if board.castle == 0
        return nothing
    end

    if piece_type == KING
        remove_all_castle_rights!(board, board.colour)
    else
        # lose self castle rights if rook moves
        if move_from == ROOK_START_SQUARES[2 * short_index(board.colour) + 1]
            remove_king_castle_rights!(board, board.colour)
            
        elseif move_from == ROOK_START_SQUARES[2 * short_index(board.colour) + 2]
            remove_queen_castle_rights!(board, board.colour)
        end
    end
    
    #remove enemy castle rights if rook captured
    if move_to == ROOK_START_SQUARES[2 * short_index(!board.colour) + 1]
        remove_king_castle_rights!(board, !board.colour)
    elseif move_to == ROOK_START_SQUARES[2 * short_index(!board.colour) + 2]
        remove_queen_castle_rights!(board, !board.colour)
    end
end

"deals with promotions, always resets halfmove clock"
@inline function make_promotion!(board::BoardState, mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag)
    if is_capture(mv_cap_type)
        destroy_piece!(board, !board.colour, mv_cap_type, mv_to)
    end

    destroy_piece!(board, board.colour, mv_pc_type, mv_from)
    create_piece!(board, board.colour, promote_type(mv_flag), mv_to)
    board.half_moves = 0
end

"handle cases where there is no flag, or the pawn moves en-passant and double push"
@inline function make_normal_move!(board::BoardState, mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag)
    if is_capture(mv_cap_type)
        destroy_loc = mv_to
        if mv_flag == ENPASSANT
            destroy_loc = enpassant_location(board.colour, destroy_loc)
        end
        destroy_piece!(board, !board.colour, mv_cap_type, destroy_loc)
        board.half_moves = 0
    elseif mv_pc_type == PAWN
        board.half_moves = 0
    else
       board.half_moves += 1
    end

    move_piece!(board, board.colour, mv_pc_type, mv_from, mv_to)
end

"if necessary, push new enpassant location to bitboard, or wipe previous enpassant location"
@inline function enpassant_cleanup!(board::BoardState, move_flag, move_to)
    if move_flag == DOUBLE_PUSH
        location = enpassant_location(board.colour, move_to)
        update_enpassant!(board, BitBoard(1) << location)
    elseif board.enpassant_bb > 0
        update_enpassant!(board, BitBoard())
    end
end

"modify boardstate by making a move. increment halfmove count. add move to move_history. update castling rights"
@inline function make_move!(move::Move, board::BoardState)
    update_history!(board, move)
    mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag = unpack_move(move::Move)

    if is_castle(mv_flag)
        make_castle!(board, mv_from, mv_to, mv_flag)
    else
        implicit_update_castle!(board, mv_pc_type, mv_from, mv_to)
        
        if is_promotion(mv_flag)
            make_promotion!(board, mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag)
        else
            make_normal_move!(board, mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag)
        end
    end

    enpassant_cleanup!(board, mv_flag, mv_to)
    swap_player!(board)
    update_piece_union!(board)
end

"unmake king- or queen-side castle for opponent"
@inline function unmake_castle!(board::BoardState, opposite_colour, move_from, move_to, move_flag)
    move_piece!(board, opposite_colour, KING, move_to, move_from)
    
    castle_lookup = (move_flag == QUEEN_CASTLE) + short_index(opposite_colour) * 2 + 1
    rook_from = ROOK_START_SQUARES[castle_lookup]
    rook_to = ROOK_CASTLE_SQUARES[castle_lookup]
    move_piece!(board, opposite_colour, ROOK, rook_to, rook_from)
end

"uses opponents colour to create a pawn and destroy promotion piece. uses own colour to undo capture"
@inline function unmake_promotion!(board::BoardState, opposite_colour, mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag)
    create_piece!(board, opposite_colour, mv_pc_type, mv_from)
    destroy_piece!(board, opposite_colour, promote_type(mv_flag), mv_to)

    if is_capture(mv_cap_type)
        create_piece!(board, board.colour, mv_cap_type, mv_to)
    end
end

"undo normal quiets and attacks, pawn double pushes and enpassant"
@inline function unmake_normal_move!(board::BoardState, opposite_colour, mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag)
    move_piece!(board, opposite_colour, mv_pc_type, mv_to, mv_from)

    if is_capture(mv_cap_type)
        create_loc = mv_to
        if mv_flag == ENPASSANT
            create_loc = enpassant_location(opposite_colour, create_loc)
        end
        create_piece!(board, board.colour, mv_cap_type, create_loc)
    end
end

"unmakes last move on move_history stack. restore halfmoves, EP squares and castle rights"
@inline function unmake_move!(board::BoardState)
    board.state = Neutral()
    move = rollback_history!(board)
    zobrist = board.zobrist_hash
    mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag = unpack_move(move)

    if is_castle(mv_flag)
        unmake_castle!(board, !board.colour, mv_from, mv_to, mv_flag)
    
    elseif is_promotion(mv_flag)
        unmake_promotion!(board, !board.colour, mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag)

    else
        unmake_normal_move!(board, !board.colour, mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag)
    end

    board.colour = !board.colour
    update_piece_union!(board)
    board.zobrist_hash = zobrist
end

"attempt to make a pseudolegal move and check if it worked. returns true if successful, false if not and rolls back illegal move"
function make_pseudolegal_move!(move::Move, board::BoardState, skip_legal_check = false)
    make_move!(move, board)

    if skip_legal_check
        return true
    end

    success = !in_check(board, !board.colour)
    if !success
        unmake_move!(board)
    end
    return success
end