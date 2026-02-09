
"utilises setzero to remove a piece from a position"
function destroy_piece!(B::BoardState, colour::UInt8, pieceID, pos)
    CpieceID = colour_piece_id(colour, pieceID)
    B.pieces[CpieceID] = setzero(B.pieces[CpieceID], pos)
    update_PST_score!(B.PSTscore, colour, pieceID, pos, -1)
    B.zobrist_hash ⊻= zobrist_piece(CpieceID, pos)

    unionID = colour_id(colour) + 1
    B.piece_union[unionID] = setzero(B.piece_union[unionID], pos)
end

"utilises setone to create a piece in a position"
function create_piece!(B::BoardState, colour::UInt8, pieceID, pos)
    CpieceID = colour_piece_id(colour, pieceID)
    B.pieces[CpieceID] = setone(B.pieces[CpieceID], pos)
    update_PST_score!(B.PSTscore, colour, pieceID, pos, +1)
    B.zobrist_hash ⊻= zobrist_piece(CpieceID, pos)

    unionID = colour_id(colour)+1
    B.piece_union[unionID] = setone(B.piece_union[unionID], pos)
end

"utilises create and destroy to move single piece"
function move_piece!(B::BoardState, colour::UInt8, pieceID, from, to)
    destroy_piece!(B, colour, pieceID, from)
    create_piece!(B, colour, pieceID, to)
end

"switch to opposite colour and update hash key"
function swap_player!(board)
    board.colour = opposite(board.colour)
    board.zobrist_hash ⊻= zobrist_colour()
end

"shift king pos right for kingside castle"
Kcastle_shift(pos::Integer) = pos + 2
"shift king pos left for queenside castle"
Qcastle_shift(pos::Integer) = pos - 2

"make a kingside castle"
function Kcastle!(B::BoardState, colour)
    kingpos = locate_king(B, colour)
    move_piece!(B, colour, King, kingpos, Kcastle_shift(kingpos))
end 

"make a queenside castle"
function Qcastle!(B::BoardState, colour)
    kingpos = locate_king(B, colour)
    move_piece!(B, colour, King, kingpos, Qcastle_shift(kingpos))
end

"update castling rights and zobrist hash"
function updateCrights!(board::BoardState, ColId, side)
    #remove ally castling rights by &-ing with opponent mask
    #side is king=1, queen=2, both=0
    board.zobrist_hash = zobrist_castle(board.zobrist_hash, board.castle)
    board.castle = get_Crights(board.castle, ColId,side)
    board.zobrist_hash = zobrist_castle(board.zobrist_hash, board.castle)
end

"set new EP val and incrementally update zobrist hash"
function updateEP!(board::BoardState, newval::UInt64)
    board.zobrist_hash = zobrist_enpassant(board.zobrist_hash, board.enpassant_bb)
    board.enpassant_bb = newval
    board.zobrist_hash = zobrist_enpassant(board.zobrist_hash, board.enpassant_bb)
end

"Returns location of en-passant and also pawn being captured by en-passant"
EPlocation(colour::UInt8, moveloc) = ifelse(colour==0, moveloc + 8, moveloc - 8)

"modify boardstate by making a move. increment halfmove count. add move to move_history. update castling rights"
function make_move!(move::Move, board::BoardState)
    mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag = unpack_move(move::Move)

    #0 = white, 1 = black
    ColId = colour_id(board.colour)

    #deal with castling
    if (mv_flag == KCASTLE) || (mv_flag == QCASTLE)
        move_piece!(board, board.colour, Rook, mv_from, mv_to)
        updateCrights!(board,ColId,0)
        if mv_flag == KCASTLE
            Kcastle!(board,board.colour)
        else
            Qcastle!(board,board.colour)
        end
        #castling does not reset halfmove count
        board.Data.half_moves[end] += 1

    #update castling rights if not castling    
    else
        if board.castle > 0
            if mv_pc_type == King
                updateCrights!(board,ColId,0)
            else
                #lose self castle rights
                if mv_from == 63 - 56 * ColId     #kingside
                    updateCrights!(board,ColId,1)
                elseif mv_from == 56 - 56 * ColId #queenside
                    updateCrights!(board,ColId,2)
                end
            end
            #remove enemy castle rights
            if mv_to == 7 + 56 * ColId      #kingside
                updateCrights!(board, (ColId+1) % 2, 1)
            elseif mv_to == 56 * ColId      #queenside
                updateCrights!(board, (ColId+1) % 2, 2)
            end
        end
        #deal with promotions, always reset halfmove clock
        if (mv_flag == PROMQUEEN) | (mv_flag == PROMROOK) | (mv_flag == PROMBISHOP) | (mv_flag == PROMKNIGHT)
            push!(board.Data.half_moves, 0)
            destroy_piece!(board, board.colour, mv_pc_type, mv_from)
            create_piece!(board, board.colour, promote_type(mv_flag), mv_to)

            if mv_cap_type > 0
                destroy_piece!(board, opposite(board.colour), mv_cap_type, mv_to)
            end

        else #no flag, en-passant, double push
            move_piece!(board, board.colour, mv_pc_type, mv_from, mv_to)

            if mv_cap_type > 0
                destroy_loc = mv_to
                if mv_flag == EPFLAG
                    destroy_loc = EPlocation(board.colour, destroy_loc)
                end
                destroy_piece!(board, opposite(board.colour), mv_cap_type, destroy_loc)
                push!(board.Data.half_moves, 0)
            elseif mv_pc_type == Pawn
                push!(board.Data.half_moves, 0)
            else
                board.Data.half_moves[end] += 1
            end
        end
    end

    #update enpassant
    if mv_flag == DPUSH
        location = EPlocation(board.colour, mv_to)
        updateEP!(board, UInt64(1) << location)

        push!(board.Data.enpassant, board.enpassant_bb)
        push!(board.Data.enpassant_count, 0)
    elseif board.enpassant_bb > 0
        updateEP!(board, UInt64(0))

        push!(board.Data.enpassant, board.enpassant_bb)
        push!(board.Data.enpassant_count, 0)
    else
        board.Data.enpassant_count[end] += 1
    end

    swap_player!(board)
    push!(board.move_history, move)
    push!(board.Data.zobrist_hash_history, board.zobrist_hash)
    board.piece_union[end] = board.piece_union[1] | board.piece_union[2]

    #check if castling rights have changed
    if board.castle == board.Data.castling[end]
        board.Data.castleCount[end] += 1
    else
        #add new castling rights to history stack
        push!(board.Data.castling, board.castle)
        push!(board.Data.castleCount, 0)
    end
end


"unmakes last move on move_history stack. restore halfmoves, EP squares and castle rights"
function unmake_move!(board::BoardState)
    OppCol = opposite(board.colour)
    if length(board.move_history) > 0
        board.state = Neutral()
        move = board.move_history[end]
        mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag = unpack_move(move)

        if (mv_flag == KCASTLE) || (mv_flag == QCASTLE)
            move_piece!(board, OppCol, Rook, mv_to, mv_from)
            #unmaking a kingside castle is the same as a queenside castle and vice-versa
            if mv_flag == KCASTLE
                Qcastle!(board, OppCol)
            else
                Kcastle!(board, OppCol)
            end
        
        #deal with everything other than castling
        else
            if (mv_flag==NOFLAG) | (mv_flag==DPUSH) | (mv_flag==EPFLAG)
                move_piece!(board, OppCol, mv_pc_type, mv_to, mv_from)

                if mv_cap_type > 0
                    create_loc = mv_to
                    if mv_flag == EPFLAG
                        create_loc = EPlocation(OppCol, create_loc)
                    end
                    create_piece!(board, board.colour, mv_cap_type, create_loc)
                end
            else #deal with promotions
                create_piece!(board, OppCol, mv_pc_type, mv_from)
                destroy_piece!(board, OppCol, promote_type(mv_flag), mv_to)

                if mv_cap_type > 0
                    create_piece!(board, board.colour, mv_cap_type, mv_to)
                end
            end
        end

        swap_player!(board)
        pop!(board.move_history)

        #update data struct with halfmoves, en-passant, hash and castling
        pop!(board.Data.zobrist_hash_history)
        board.zobrist_hash = board.Data.zobrist_hash_history[end]
        board.piece_union[end] = board.piece_union[1] | board.piece_union[2]

        if board.Data.half_moves[end] > 0 
            board.Data.half_moves[end] -= 1
        else
            pop!(board.Data.half_moves)
        end

        if board.Data.castleCount[end] == 0
            pop!(board.Data.castleCount)
            pop!(board.Data.castling)
            board.castle = board.Data.castling[end]
        else
            board.Data.castleCount[end] -= 1
        end

        if board.Data.enpassant_count[end] == 0
            pop!(board.Data.enpassant_count)
            pop!(board.Data.enpassant)
            board.enpassant_bb = board.Data.enpassant[end]
        else
            board.Data.enpassant_count[end] -= 1
        end  
    end
end