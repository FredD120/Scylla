#Define move struct and make/unmake move
#Also utilities for incrementally updating boardstate
#Move is defined by the piece moving - piece_type (3 bits)
#Where it is moving from - from (6 bits)
#Where it is moving to - to (6 bits)
#What (if any) piece it is capturing - capture_type (3 bits)
#Any flag for pawns/castling - flag (4 bits)
#Score of move from heuristic - score (8 bits)
#This can be packed into a UInt32

const PIECEMASK = 0x7
const LOCMASK   = 0x3F
const FLAGMASK = 0xF
const SCOREMASK = 0xFF

const TYPESIZE = 3
const FROMSIZE = 6
const TOSIZE   = 6
const CAPSIZE  = 3
const FLAGSIZE = 4

const FROMSHIFT = TYPESIZE
const TOSHIFT   = TYPESIZE + FROMSIZE
const CAPSHIFT  = TYPESIZE + FROMSIZE + TOSIZE
const FLAGSHIFT = TYPESIZE + FROMSIZE + TOSIZE + CAPSIZE
const SCORESHIFT = TYPESIZE + FROMSIZE + TOSIZE + CAPSIZE + FLAGSIZE

"Mask and shift UInt32 to unpack move data"
pc_type(move::UInt32) = UInt8(move & PIECEMASK)
from(move::UInt32) = UInt8((move >> FROMSHIFT) & LOCMASK)
to(move::UInt32) = UInt8((move >> TOSHIFT) & LOCMASK)
cap_type(move::UInt32) = UInt8((move >> CAPSHIFT) & PIECEMASK)
flag(move::UInt32) = UInt8((move >> FLAGSHIFT) & FLAGMASK)
score(move::UInt32) = UInt8((move >> SCORESHIFT) & SCOREMASK)

"Return move with score set"
set_score(move::UInt32,score::UInt8) = move | (UInt32(score) << SCORESHIFT)

"return true if move captures a piece"
iscapture(move::UInt32) = cap_type(move) > 0

function unpack_move(move::UInt32)
    mv_pc_type = pc_type(move)
    mv_from = from(move)
    mv_to = to(move)
    mv_cap_type = cap_type(move)
    mv_flag = flag(move)
    (mv_pc_type,mv_from,mv_to,mv_cap_type,mv_flag)
end

"construct move 'struct' as a UInt32"
function Move(pc_type::UInt8,from::UInt8,to::UInt8,cap_type::UInt8,flag::UInt8,score=UInt8(0))::UInt32
    UInt32(pc_type) |
    (UInt32(from) << FROMSHIFT) |
    (UInt32(to) << TOSHIFT) |
    (UInt32(cap_type) << CAPSHIFT) | 
    (UInt32(flag) << FLAGSHIFT) |
    (UInt32(score) << SCORESHIFT)
end

const NULLMOVE = Move(UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0))

"convert a position from number 0-63 to rank/file notation"
UCIpos(pos) = ('a'+file(pos))*string(Int(rank(pos)+1))

"convert a move to UCI notation"
function UCImove(B::Boardstate,move::UInt32)
    flg = flag(move)
    F = from(move)
    T = to(move)

    if flg == KCASTLE || flg == QCASTLE
        F = locate_king(B,B.Colour)
        T = F + 2
        if flg == QCASTLE
            T = F -2
        end
    end

    p = ""
    prom_type = promote_type(flg)
    if  prom_type != NULL_PIECE
        p = lowercase(piece_letter(prom_type))
    end
    return UCIpos(F)*UCIpos(T)*p
end

"convert a position in algebraic notation to a number from 0-63"
function algebraic_to_numeric(pos::AbstractString)
    rank = parse(Int,pos[2])
    file = Int(pos[1]) - Int('a') + 1
    return (-rank+8)*8 + file-1
end

"try to match given UCI move to a legal move. return null move otherwise"
function identify_UCImove(B::Boardstate,UCImove::AbstractString)
    moves = generate_moves(B)
    num_from = algebraic_to_numeric(UCImove[1:2])
    num_to = algebraic_to_numeric(UCImove[3:4])
    num_promote = NOFLAG
    kingsmove = num_from == locate_king(B,B.Colour)

    if length(UCImove) > 4
        num_promote = promote_id(Char(UCImove[5]))
    end

    for move in moves
        flg = flag(move)
        if from(move) == num_from && to(move) == num_to
            if num_promote == NOFLAG || num_promote == flg
                return move
            end
        #check for castling if the king is moving
        elseif kingsmove
            if (flg == KCASTLE && num_to == Kcastle_shift(num_from)) ||
                (flg == QCASTLE && num_to == Qcastle_shift(num_from))
                return move 
            end
        end
    end
    return NULLMOVE
end

"convert a move to long algebraic notation for clarity"
function LONGmove(move::UInt32)
    flg = flag(move)
    if flg == KCASTLE
        return "O-O"
    elseif flg == QCASTLE
        return "O-O-O"
    else
        F = UCIpos(from(move))
        T = UCIpos(to(move))
        P = piece_letter(pc_type(move))
        mid = "-"
        if cap_type(move) > 0
            mid = "x"
        end

        promote = piece_letter(promote_type(flg))
        return P*F*mid*T*promote
    end
end

"convert a move to short algebraic notation for comparison/communication"
function SHORTmove(move::UInt32)
    flg = flag(move)
    if flg == KCASTLE
        return "O-O"
    elseif flg == QCASTLE
        return "O-O-O"
    else
        T = UCIpos(to(move))
        P = piece_letter(pc_type(move))
        mid = "x"

        if cap_type(move) == 0
            mid = ""
        end
        if pc_type(move) == Pawn
            if cap_type(move) == 0
                P = ""
            else
                P = 'a' + (from(move) % 8)
            end
        end

        promote = piece_letter(promote_type(flg))
        return P*mid*T*promote
    end
end

"utilises setzero to remove a piece from a position"
function destroy_piece!(B::Boardstate,colour::UInt8,pieceID,pos)
    CpieceID = ColourPieceID(colour, pieceID)
    B.pieces[CpieceID] = setzero(B.pieces[CpieceID],pos)
    update_PST_score!(B.PSTscore,colour,pieceID,pos,-1)
    B.ZHash ⊻= ZKey_piece(CpieceID,pos)

    unionID = ColID(colour)+1
    B.piece_union[unionID] = setzero(B.piece_union[unionID],pos)
end

"utilises setone to create a piece in a position"
function create_piece!(B::Boardstate,colour::UInt8,pieceID,pos)
    CpieceID = ColourPieceID(colour, pieceID)
    B.pieces[CpieceID] = setone(B.pieces[CpieceID],pos)
    update_PST_score!(B.PSTscore,colour,pieceID,pos,+1)
    B.ZHash ⊻= ZKey_piece(CpieceID,pos)

    unionID = ColID(colour)+1
    B.piece_union[unionID] = setone(B.piece_union[unionID],pos)
end

"utilises create and destroy to move single piece"
function move_piece!(B::Boardstate,colour::UInt8,pieceID,from,to)
    destroy_piece!(B,colour,pieceID,from)
    create_piece!(B,colour,pieceID,to)
end

"switch to opposite colour and update hash key"
function swap_player!(board)
    board.Colour = Opposite(board.Colour)
    board.ZHash ⊻= ZKeyColour()
end

"shift king pos right for kingside castle"
Kcastle_shift(pos::Integer) = pos + 2
"shift king pos left for queenside castle"
Qcastle_shift(pos::Integer) = pos - 2

"make a kingside castle"
function Kcastle!(B::Boardstate,colour)
    kingpos = locate_king(B,colour)
    move_piece!(B,colour,King,kingpos,Kcastle_shift(kingpos))
end 

"make a queenside castle"
function Qcastle!(B::Boardstate,colour)
    kingpos = locate_king(B,colour)
    move_piece!(B,colour,King,kingpos,Qcastle_shift(kingpos))
end

"update castling rights and Zhash"
function updateCrights!(board::Boardstate,ColId,side)
    #remove ally castling rights by &-ing with opponent mask
    #side is king=1, queen=2, both=0
    board.ZHash = Zhashcastle(board.ZHash,board.Castle)
    board.Castle = get_Crights(board.Castle,ColId,side)
    board.ZHash = Zhashcastle(board.ZHash,board.Castle)
end

"set new EP val and incrementally update zobrist hash"
function updateEP!(board::Boardstate,newval::UInt64)
    board.ZHash = ZhashEP(board.ZHash,board.EnPass)
    board.EnPass = newval
    board.ZHash = ZhashEP(board.ZHash,board.EnPass)
end

"Returns location of en-passant and also pawn being captured by en-passant"
EPlocation(colour::UInt8,moveloc) = ifelse(colour==0,moveloc+8,moveloc-8)

"modify boardstate by making a move. increment halfmove count. add move to MoveHist. update castling rights"
function make_move!(move::UInt32,board::Boardstate)
    mv_pc_type,mv_from,mv_to,mv_cap_type,mv_flag = unpack_move(move::UInt32)

    #0 = white, 1 = black
    ColId = ColID(board.Colour)

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
                if mv_from == 63-56*ColId     #kingside
                    updateCrights!(board,ColId,1)
                elseif mv_from == 56-56*ColId #queenside
                    updateCrights!(board,ColId,2)
                end
            end
            #remove enemy castle rights
            if mv_to == 7+56*ColId        #kingside
                updateCrights!(board,(ColId+1)%2,1)
            elseif mv_to == 56*ColId      #queenside
                updateCrights!(board,(ColId+1)%2,2)
            end
        end
        #deal with promotions, always reset halfmove clock
        if (mv_flag == PROMQUEEN)|(mv_flag == PROMROOK)|(mv_flag == PROMBISHOP)|(mv_flag == PROMKNIGHT)
            push!(board.Data.Halfmoves,0)
            destroy_piece!(board,board.Colour,mv_pc_type,mv_from)
            create_piece!(board,board.Colour,promote_type(mv_flag),mv_to)

            if mv_cap_type > 0
                destroy_piece!(board,Opposite(board.Colour),mv_cap_type,mv_to)
            end

        else #no flag, en-passant, double push
            move_piece!(board,board.Colour,mv_pc_type,mv_from,mv_to)

            if mv_cap_type > 0
                destroy_loc = mv_to
                if mv_flag == EPFLAG
                    destroy_loc = EPlocation(board.Colour,destroy_loc)
                end
                destroy_piece!(board,Opposite(board.Colour),mv_cap_type,destroy_loc)
                push!(board.Data.Halfmoves,0)
            elseif mv_pc_type == Pawn
                push!(board.Data.Halfmoves,0)
            else
                board.Data.Halfmoves[end] += 1
            end
        end
    end

    #update EnPassant
    if mv_flag == DPUSH
        location = EPlocation(board.Colour,mv_to)
        updateEP!(board,UInt64(1) << location)

        push!(board.Data.EnPassant,board.EnPass)
        push!(board.Data.EPCount,0)
    elseif board.EnPass > 0
        updateEP!(board,UInt64(0))

        push!(board.Data.EnPassant,board.EnPass)
        push!(board.Data.EPCount,0)
    else
        board.Data.EPCount[end] += 1
    end

    swap_player!(board)
    push!(board.MoveHist,move)
    push!(board.Data.ZHashHist,board.ZHash)
    board.piece_union[end] = board.piece_union[1] | board.piece_union[2]

    #check if castling rights have changed
    if board.Castle == board.Data.Castling[end]
        board.Data.CastleCount[end] += 1
    else
        #add new castling rights to history stack
        push!(board.Data.Castling,board.Castle)
        push!(board.Data.CastleCount,0)
    end
end

"unmakes last move on MoveHist stack. restore halfmoves, EP squares and castle rights"
function unmake_move!(board::Boardstate)
    OppCol = Opposite(board.Colour)
    if length(board.MoveHist) > 0
        board.State = Neutral()
        move = board.MoveHist[end]
        mv_pc_type,mv_from,mv_to,mv_cap_type,mv_flag = unpack_move(move::UInt32)

        if (mv_flag == KCASTLE) || (mv_flag == QCASTLE)
            move_piece!(board,OppCol,Rook,mv_to,mv_from)
            #unmaking a kingside castle is the same as a queenside castle and vice-versa
            if mv_flag == KCASTLE
                Qcastle!(board,OppCol)
            else
                Kcastle!(board,OppCol)
            end
        
        #deal with everything other than castling
        else
            if (mv_flag==NOFLAG)|(mv_flag==DPUSH)|(mv_flag==EPFLAG)
                move_piece!(board,OppCol,mv_pc_type,mv_to,mv_from)

                if mv_cap_type > 0
                    create_loc = mv_to
                    if mv_flag == EPFLAG
                        create_loc = EPlocation(OppCol,create_loc)
                    end
                    create_piece!(board,board.Colour,mv_cap_type,create_loc)
                end
            else #deal with promotions
                create_piece!(board,OppCol,mv_pc_type,mv_from)
                destroy_piece!(board,OppCol,promote_type(mv_flag),mv_to)

                if mv_cap_type > 0
                    create_piece!(board,board.Colour,mv_cap_type,mv_to)
                end
            end
        end

        swap_player!(board)
        pop!(board.MoveHist)

        #update data struct with halfmoves, en-passant, hash and castling
        pop!(board.Data.ZHashHist)
        board.ZHash = board.Data.ZHashHist[end]
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
    else
        println("Failed to unmake move: No move history")
    end
end