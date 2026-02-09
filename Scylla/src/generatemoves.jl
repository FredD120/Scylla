
"utilises setzero to remove a piece from a position"
function destroy_piece!(B::Boardstate, colour::UInt8, pieceID, pos)
    CpieceID = colour_piece_id(colour, pieceID)
    B.pieces[CpieceID] = setzero(B.pieces[CpieceID], pos)
    update_PST_score!(B.PSTscore, colour, pieceID, pos, -1)
    B.zobrist_hash ⊻= ZKey_piece(CpieceID, pos)

    unionID = colour_id(colour) + 1
    B.piece_union[unionID] = setzero(B.piece_union[unionID], pos)
end

"utilises setone to create a piece in a position"
function create_piece!(B::Boardstate, colour::UInt8, pieceID, pos)
    CpieceID = colour_piece_id(colour, pieceID)
    B.pieces[CpieceID] = setone(B.pieces[CpieceID], pos)
    update_PST_score!(B.PSTscore, colour, pieceID, pos, +1)
    B.zobrist_hash ⊻= ZKey_piece(CpieceID, pos)

    unionID = colour_id(colour)+1
    B.piece_union[unionID] = setone(B.piece_union[unionID], pos)
end

"utilises create and destroy to move single piece"
function move_piece!(B::Boardstate, colour::UInt8, pieceID, from, to)
    destroy_piece!(B, colour, pieceID, from)
    create_piece!(B, colour, pieceID, to)
end

"switch to opposite colour and update hash key"
function swap_player!(board)
    board.Colour = opposite(board.Colour)
    board.zobrist_hash ⊻= ZKeyColour()
end

"shift king pos right for kingside castle"
Kcastle_shift(pos::Integer) = pos + 2
"shift king pos left for queenside castle"
Qcastle_shift(pos::Integer) = pos - 2

"make a kingside castle"
function Kcastle!(B::Boardstate, colour)
    kingpos = locate_king(B, colour)
    move_piece!(B, colour, King, kingpos, Kcastle_shift(kingpos))
end 

"make a queenside castle"
function Qcastle!(B::Boardstate, colour)
    kingpos = locate_king(B, colour)
    move_piece!(B, colour, King, kingpos, Qcastle_shift(kingpos))
end

"update castling rights and Zhash"
function updateCrights!(board::Boardstate, ColId, side)
    #remove ally castling rights by &-ing with opponent mask
    #side is king=1, queen=2, both=0
    board.zobrist_hash = Zhashcastle(board.zobrist_hash, board.Castle)
    board.Castle = get_Crights(board.Castle, ColId,side)
    board.zobrist_hash = Zhashcastle(board.zobrist_hash, board.Castle)
end

"set new EP val and incrementally update zobrist hash"
function updateEP!(board::Boardstate, newval::UInt64)
    board.zobrist_hash = ZhashEP(board.zobrist_hash, board.EnPass)
    board.EnPass = newval
    board.zobrist_hash = ZhashEP(board.zobrist_hash, board.EnPass)
end

"Returns location of en-passant and also pawn being captured by en-passant"
EPlocation(colour::UInt8, moveloc) = ifelse(colour==0, moveloc+8, moveloc-8)

"modify boardstate by making a move. increment halfmove count. add move to MoveHist. update castling rights"
function make_move!(move::Move, board::Boardstate)
    mv_pc_type, mv_from, mv_to, mv_cap_type, mv_flag = unpack_move(move::Move)

    #0 = white, 1 = black
    ColId = colour_id(board.Colour)

    #deal with castling
    if (mv_flag == KCASTLE) || (mv_flag == QCASTLE)
        move_piece!(board,board.Colour,Rook,mv_from,mv_to)
        updateCrights!(board,ColId,0)
        if mv_flag == KCASTLE
            Kcastle!(board,board.Colour)
        else
            Qcastle!(board,board.Colour)
        end
        #castling does not reset halfmove count
        board.Data.Halfmoves[end] += 1

    #update castling rights if not castling    
    else
        if board.Castle > 0
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
            push!(board.Data.Halfmoves, 0)
            destroy_piece!(board, board.Colour, mv_pc_type, mv_from)
            create_piece!(board, board.Colour, promote_type(mv_flag), mv_to)

            if mv_cap_type > 0
                destroy_piece!(board, opposite(board.Colour), mv_cap_type, mv_to)
            end

        else #no flag, en-passant, double push
            move_piece!(board, board.Colour, mv_pc_type, mv_from, mv_to)

            if mv_cap_type > 0
                destroy_loc = mv_to
                if mv_flag == EPFLAG
                    destroy_loc = EPlocation(board.Colour, destroy_loc)
                end
                destroy_piece!(board, opposite(board.Colour), mv_cap_type, destroy_loc)
                push!(board.Data.Halfmoves, 0)
            elseif mv_pc_type == Pawn
                push!(board.Data.Halfmoves, 0)
            else
                board.Data.Halfmoves[end] += 1
            end
        end
    end

    #update EnPassant
    if mv_flag == DPUSH
        location = EPlocation(board.Colour, mv_to)
        updateEP!(board, UInt64(1) << location)

        push!(board.Data.EnPassant, board.EnPass)
        push!(board.Data.EPCount, 0)
    elseif board.EnPass > 0
        updateEP!(board, UInt64(0))

        push!(board.Data.EnPassant, board.EnPass)
        push!(board.Data.EPCount, 0)
    else
        board.Data.EPCount[end] += 1
    end

    swap_player!(board)
    push!(board.MoveHist, move)
    push!(board.Data.zobrist_hash_history, board.zobrist_hash)
    board.piece_union[end] = board.piece_union[1] | board.piece_union[2]

    #check if castling rights have changed
    if board.Castle == board.Data.Castling[end]
        board.Data.CastleCount[end] += 1
    else
        #add new castling rights to history stack
        push!(board.Data.Castling, board.Castle)
        push!(board.Data.CastleCount, 0)
    end
end

"unmakes last move on MoveHist stack. restore halfmoves, EP squares and castle rights"
function unmake_move!(board::Boardstate)
    OppCol = opposite(board.Colour)
    if length(board.MoveHist) > 0
        board.State = Neutral()
        move = board.MoveHist[end]
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
                    create_piece!(board, board.Colour, mv_cap_type, create_loc)
                end
            else #deal with promotions
                create_piece!(board, OppCol, mv_pc_type, mv_from)
                destroy_piece!(board, OppCol, promote_type(mv_flag), mv_to)

                if mv_cap_type > 0
                    create_piece!(board, board.Colour, mv_cap_type, mv_to)
                end
            end
        end

        swap_player!(board)
        pop!(board.MoveHist)

        #update data struct with halfmoves, en-passant, hash and castling
        pop!(board.Data.zobrist_hash_history)
        board.zobrist_hash = board.Data.zobrist_hash_history[end]
        board.piece_union[end] = board.piece_union[1] | board.piece_union[2]

        if board.Data.Halfmoves[end] > 0 
            board.Data.Halfmoves[end] -= 1
        else
            pop!(board.Data.Halfmoves)
        end

        if board.Data.CastleCount[end] == 0
            pop!(board.Data.CastleCount)
            pop!(board.Data.Castling)
            board.Castle = board.Data.Castling[end]
        else
            board.Data.CastleCount[end] -= 1
        end

        if board.Data.EPCount[end] == 0
            pop!(board.Data.EPCount)
            pop!(board.Data.EnPassant)
            board.EnPass = board.Data.EnPassant[end]
        else
            board.Data.EPCount[end] -= 1
        end  
    end
end