# Define make and unmake move functions
# Define all helper functions to ensure zobrist hash, board position and PST scores are preserved

"utilises setzero to remove a piece from a position"
function destroy_piece!(board::BoardState, colour::UInt8, piece_type, pos)
    piece_id = colour_piece_id(colour, piece_type)
    board.pieces[piece_id] = setzero(board.pieces[piece_id], pos)
    update_pst_score!(board.pst_score, colour, piece_type, pos, -1)
    board.zobrist_hash ⊻= zobrist_piece(piece_id, pos)

    union_id = colour_id(colour) + 1
    board.piece_union[union_id] = setzero(board.piece_union[union_id], pos)
end

"utilises setone to create a piece in a position"
function create_piece!(board::BoardState, colour::UInt8, piece_type, pos)
    piece_id = colour_piece_id(colour, piece_type)
    board.pieces[piece_id] = setone(board.pieces[piece_id], pos)
    update_pst_score!(board.pst_score, colour, piece_type, pos, +1)
    board.zobrist_hash ⊻= zobrist_piece(piece_id, pos)

    union_id = colour_id(colour)+1
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
function update_castle_rights!(board::BoardState, ColId, side)
    #remove ally castling rights by &-ing with opponent mask
    #side is king=1, queen=2, both=0
    board.zobrist_hash = zobrist_castle(board.zobrist_hash, board.castle)
    board.castle = get_castle_rights(board.castle, ColId,side)
    board.zobrist_hash = zobrist_castle(board.zobrist_hash, board.castle)
end

"set new EP val and incrementally update zobrist hash"
function update_enpassant!(board::BoardState, newval::UInt64)
    board.zobrist_hash = zobrist_enpassant(board.zobrist_hash, board.enpassant_bb)
    board.enpassant_bb = newval
    board.zobrist_hash = zobrist_enpassant(board.zobrist_hash, board.enpassant_bb)
end

"Returns location of en-passant and also pawn being captured by en-passant"
enpassant_location(colour::UInt8, moveloc) = ifelse(colour==0, moveloc + 8, moveloc - 8)

"modify boardstate by making a move. increment halfmove count. add move to move_history. update castling rights"
function make_move!(move::Move, board::BoardState)
    mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag = unpack_move(move::Move)

    #0 = white, 1 = black
    ColId = colour_id(board.colour)

    #deal with castling
    if (mv_flag == KING_CASTLE) || (mv_flag == QUEEN_CASTLE)
        move_piece!(board, board.colour, ROOK, mv_from, mv_to)
        update_castle_rights!(board,ColId,0)
        if mv_flag == KING_CASTLE
            king_castle!(board,board.colour)
        else
            queen_castle!(board,board.colour)
        end
        #castling does not reset halfmove count
        board.data.half_moves[end] += 1

    #update castling rights if not castling    
    else
        if board.castle > 0
            if mv_pc_type == KING
                update_castle_rights!(board, ColId, 0)
            else
                #lose self castle rights
                if mv_from == 63 - 56 * ColId     #kingside
                    update_castle_rights!(board, ColId, 1)
                elseif mv_from == 56 - 56 * ColId #queenside
                    update_castle_rights!(board, ColId, 2)
                end
            end
            #remove enemy castle rights
            if mv_to == 7 + 56 * ColId      #kingside
                update_castle_rights!(board, (ColId + 1) % 2, 1)
            elseif mv_to == 56 * ColId      #queenside
                update_castle_rights!(board, (ColId + 1) % 2, 2)
            end
        end
        #deal with promotions, always reset halfmove clock
        if (mv_flag == PROMQUEEN) | (mv_flag == PROMROOK) | (mv_flag == PROMBISHOP) | (mv_flag == PROMKNIGHT)
            push!(board.data.half_moves, 0)
            destroy_piece!(board, board.colour, mv_pc_type, mv_from)
            create_piece!(board, board.colour, promote_type(mv_flag), mv_to)

            if mv_cap_type > 0
                destroy_piece!(board, opposite(board.colour), mv_cap_type, mv_to)
            end

        else #no flag, en-passant, double push
            move_piece!(board, board.colour, mv_pc_type, mv_from, mv_to)

            if mv_cap_type > 0
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
    end

    #update enpassant
    if mv_flag == DOUBLE_PUSH
        location = enpassant_location(board.colour, mv_to)
        update_enpassant!(board, UInt64(1) << location)

        push!(board.data.enpassant, board.enpassant_bb)
        push!(board.data.enpassant_count, 0)
    elseif board.enpassant_bb > 0
        update_enpassant!(board, UInt64(0))

        push!(board.data.enpassant, board.enpassant_bb)
        push!(board.data.enpassant_count, 0)
    else
        board.data.enpassant_count[end] += 1
    end

    swap_player!(board)
    push!(board.move_history, move)
    push!(board.data.zobrist_hash_history, board.zobrist_hash)
    board.piece_union[end] = board.piece_union[1] | board.piece_union[2]

    #check if castling rights have changed
    if board.castle == board.data.castling[end]
        board.data.castleCount[end] += 1
    else
        #add new castling rights to history stack
        push!(board.data.castling, board.castle)
        push!(board.data.castleCount, 0)
    end
end


"unmakes last move on move_history stack. restore halfmoves, EP squares and castle rights"
function unmake_move!(board::BoardState)
    opposite_colour = opposite(board.colour)
    if length(board.move_history) > 0
        board.state = Neutral()
        move = board.move_history[end]
        mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag = unpack_move(move)

        if (mv_flag == KING_CASTLE) || (mv_flag == QUEEN_CASTLE)
            move_piece!(board, opposite_colour, ROOK, mv_to, mv_from)
            #unmaking a kingside castle is the same as a queenside castle and vice-versa
            if mv_flag == KING_CASTLE
                queen_castle!(board, opposite_colour)
            else
                king_castle!(board, opposite_colour)
            end
        
        #deal with everything other than castling
        else
            if (mv_flag==NOFLAG) | (mv_flag==DOUBLE_PUSH) | (mv_flag==ENPASSANT)
                move_piece!(board, opposite_colour, mv_pc_type, mv_to, mv_from)

                if mv_cap_type > 0
                    create_loc = mv_to
                    if mv_flag == ENPASSANT
                        create_loc = enpassant_location(opposite_colour, create_loc)
                    end
                    create_piece!(board, board.colour, mv_cap_type, create_loc)
                end
            else #deal with promotions
                create_piece!(board, opposite_colour, mv_pc_type, mv_from)
                destroy_piece!(board, opposite_colour, promote_type(mv_flag), mv_to)

                if mv_cap_type > 0
                    create_piece!(board, board.colour, mv_cap_type, mv_to)
                end
            end
        end

        swap_player!(board)
        pop!(board.move_history)

        #update data struct with halfmoves, en-passant, hash and castling
        pop!(board.data.zobrist_hash_history)
        board.zobrist_hash = board.data.zobrist_hash_history[end]
        board.piece_union[end] = board.piece_union[1] | board.piece_union[2]

        if board.data.half_moves[end] > 0 
            board.data.half_moves[end] -= 1
        else
            pop!(board.data.half_moves)
        end

        if board.data.castleCount[end] == 0
            pop!(board.data.castleCount)
            pop!(board.data.castling)
            board.castle = board.data.castling[end]
        else
            board.data.castleCount[end] -= 1
        end

        if board.data.enpassant_count[end] == 0
            pop!(board.data.enpassant_count)
            pop!(board.data.enpassant)
            board.enpassant_bb = board.data.enpassant[end]
        else
            board.data.enpassant_count[end] -= 1
        end  
    end
end