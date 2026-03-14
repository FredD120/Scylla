# Define make and unmake move functions
# Define all helper functions to ensure zobrist hash, board position and PST scores are preserved

"utilises setzero to remove a piece from a position"
@inline function destroy_piece!(board::BoardState, colour::UInt8, piece_type, pos)
    piece_id = colour_piece_id(colour, piece_type)
    board.pieces[piece_id] = setzero(board.pieces[piece_id], pos)
    update_pst_score!(board.pst_score, colour, piece_type, pos, -1)
    board.zobrist_hash ⊻= zobrist_piece(piece_id, pos)

    union_id = piece_union_index(colour)
    board.piece_union[union_id] = setzero(board.piece_union[union_id], pos)
end

"utilises setone to create a piece in a position"
@inline function create_piece!(board::BoardState, colour::UInt8, piece_type, pos)
    piece_id = colour_piece_id(colour, piece_type)
    board.pieces[piece_id] = setone(board.pieces[piece_id], pos)
    update_pst_score!(board.pst_score, colour, piece_type, pos, +1)
    board.zobrist_hash ⊻= zobrist_piece(piece_id, pos)

    union_id = piece_union_index(colour) 
    board.piece_union[union_id] = setone(board.piece_union[union_id], pos)
end

"utilises create and destroy to move single piece"
function move_piece!(board::BoardState, colour::UInt8, piece_type, from, to)
    destroy_piece!(board, colour, piece_type, from)
    create_piece!(board, colour, piece_type, to)
end

"switch to opposite colour and update hash key"
function swap_player!(board)
    board.colour = opposite(board.colour)
    board.zobrist_hash ⊻= zobrist_colour()
end

"shift king pos right for kingside castle"
king_castle_shift(pos::Integer) = pos + 2
"shift king pos left for queenside castle"
queen_castle_shift(pos::Integer) = pos - 2

"make a kingside castle"
function king_castle!(board::BoardState, colour)
    kingpos = locate_king(board, colour)
    move_piece!(board, colour, KING, kingpos, king_castle_shift(kingpos))
end 

"make a queenside castle"
function queen_castle!(board::BoardState, colour)
    kingpos = locate_king(board, colour)
    move_piece!(board, colour, KING, kingpos, queen_castle_shift(kingpos))
end

"update castling rights and zobrist hash"
function update_castle_rights!(board::BoardState, colour_id, side)
    #remove old castling rights from zobrist hash
    board.zobrist_hash = zobrist_castle(board.zobrist_hash, board.castle)
    #remove ally castling rights by &-ing with opponent mask
    board.castle = get_castle_rights(board.castle, colour_id, side)
    #add new castling rights to zobrist hash
    board.zobrist_hash = zobrist_castle(board.zobrist_hash, board.castle)
end

"set new EP val and incrementally update zobrist hash"
function update_enpassant!(board::BoardState, newval::BitBoard)
    board.zobrist_hash = zobrist_enpassant(board.zobrist_hash, board.enpassant_bb)
    board.enpassant_bb = newval
    board.zobrist_hash = zobrist_enpassant(board.zobrist_hash, board.enpassant_bb)
end

"returns location of sqaure behind pawn, either to capture by en-passant or to flag square for attack by en-passant"
enpassant_location(colour::UInt8, destination) = ifelse(colour==0, destination + 8, destination - 8)

"play a castling move onto the board"
@inline function make_castle!(board::BoardState, move_from, move_to, move_flag)
    move_piece!(board, board.colour, ROOK, move_from, move_to)
    update_castle_rights!(board, colour_id(board.colour), 0)
    if move_flag == KING_CASTLE
        king_castle!(board, board.colour)
    else
        queen_castle!(board, board.colour)
    end
    #castling does not reset halfmove clock
    board.data.half_moves[end] += 1
end

"if not castling, moving the king/rooks or capturing rooks can update castling rights"
@inline function implicit_update_castle!(board::BoardState, piece_type, move_from, move_to)
    if board.castle == 0
        return nothing
    end

    colour_idx = colour_id(board.colour)
    if piece_type == KING
        update_castle_rights!(board, colour_idx, 0)
    else
        #lose self castle rights if rook moves
        if move_from == ROOK_START_SQUARES[2 * colour_idx + 1]     #kingside
            update_castle_rights!(board, colour_idx, 1)
        elseif move_from == ROOK_START_SQUARES[2 * colour_idx + 2] #queenside
            update_castle_rights!(board, colour_idx, 2)
        end
    end
    
    #remove enemy castle rights if rook captured
    opponent_idx = (colour_idx + 1) % 2
    if move_to == ROOK_START_SQUARES[2 * opponent_idx + 1]         #kingside
        update_castle_rights!(board, opponent_idx, 1)
    elseif move_to == ROOK_START_SQUARES[2 * opponent_idx + 2]     #queenside
        update_castle_rights!(board, opponent_idx, 2)
    end
end

"deals with promotions, always resets halfmove clock"
@inline function make_promotion!(board::BoardState, mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag)
    push!(board.data.half_moves, 0)
    destroy_piece!(board, board.colour, mv_pc_type, mv_from)
    create_piece!(board, board.colour, promote_type(mv_flag), mv_to)

    if is_capture(mv_cap_type)
        destroy_piece!(board, opposite(board.colour), mv_cap_type, mv_to)
    end
end

"handle cases where there is no flag, or the pawn moves en-passant and double push"
@inline function make_normal_move!(board::BoardState, mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag)
    move_piece!(board, board.colour, mv_pc_type, mv_from, mv_to)

    if is_capture(mv_cap_type)
        destroy_loc = mv_to
        if mv_flag == ENPASSANT
            destroy_loc = enpassant_location(board.colour, destroy_loc)
        end
        destroy_piece!(board, opposite(board.colour), mv_cap_type, destroy_loc)
        push!(board.data.half_moves, 0)
    elseif mv_pc_type == PAWN
        push!(board.data.half_moves, 0)
    else
        board.data.half_moves[end] += 1
    end
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

"push move to move history and enpassant, zobrist hash and castling rights to BoardData"
@inline function update_history(board::BoardState, move::Move)
    push!(board.move_history, move)
    push!(board.data.enpassant, board.enpassant_bb)
    push!(board.data.zobrist_hash_history, board.zobrist_hash)
    push!(board.data.castling, board.castle)
end

"modify boardstate by making a move. increment halfmove count. add move to move_history. update castling rights"
@inline function make_move!(move::Move, board::BoardState)
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
    update_history(board, move)
end

"unmaking a kingside castle is the same as a queenside castle and vice-versa"
@inline function unmake_castle!(board::BoardState, opposite_colour, move_from, move_to, move_flag)
    move_piece!(board, opposite_colour, ROOK, move_to, move_from)
    if move_flag == KING_CASTLE
        queen_castle!(board, opposite_colour)
    else
        king_castle!(board, opposite_colour)
    end
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

"update data struct with halfmoves, en-passant, zobrist hash and castling"
@inline function rollback_history!(board::BoardState)
    if board.data.half_moves[end] > 0 
        board.data.half_moves[end] -= 1
    else
        pop!(board.data.half_moves)
    end

    pop!(board.data.castling)
    board.castle = board.data.castling[end]

    pop!(board.data.enpassant)
    board.enpassant_bb = board.data.enpassant[end]

    pop!(board.data.zobrist_hash_history)
    board.zobrist_hash = board.data.zobrist_hash_history[end]
end

"unmakes last move on move_history stack. restore halfmoves, EP squares and castle rights"
@inline function unmake_move!(board::BoardState)
    if length(board.move_history) > 0
        #error("unmake_move called with no move history")
    end

    opposite_colour = opposite(board.colour)
    board.state = Neutral()
    move = pop!(board.move_history)
    mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag = unpack_move(move)

    if is_castle(mv_flag)
        unmake_castle!(board, opposite_colour, mv_from, mv_to, mv_flag)
    
    elseif is_promotion(mv_flag)
        unmake_promotion!(board, opposite_colour, mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag)

    else
        unmake_normal_move!(board, opposite_colour, mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag)
    end

    swap_player!(board)
    update_piece_union!(board)
    rollback_history!(board)
end

"attempt to make a pseudolegal move and check if it worked. returns true if successful, false if not and rolls back illegal move"
function make_pseudolegal_move!(move::Move, board::BoardState)
    make_move!(move, board)
    success = !in_check(board, opposite(board.colour))

    if !success
        unmake_move!(board)
    end
    return success
end