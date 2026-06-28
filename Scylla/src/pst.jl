#Define PST as position evaluation heuristic
#We dynamically update the PST evaluation in move make and unmake
#It is stored in the board struct but not in board history
#This saves looping over all pieces in position evaluation 

"Retrieve piece square tables from file"
function get_pst(type)
    h5open("$(dirname(@__DIR__))/src/PST/$(type).h5", "r") do fid
        MG::SVector{64, Int32} = round.(Int32, read(fid["MidGame"]))
        EG::SVector{64, Int32} = round.(Int32, read(fid["EndGame"]))
        return (MG, EG)
    end
end

"Setup vectors containing the PSTs for mid and endgame"
function PST()
    (kingMG, kingEG) = get_pst("king")
    (queenMG, queenEG) = get_pst("queen")
    (rookMG, rookEG) = get_pst("rook")
    (bishopMG, bishopEG) = get_pst("bishop")
    (knightMG, knightEG) = get_pst("knight")
    (pawnMG, pawnEG) = get_pst("pawn")

    return (SVector{6, SVector{64, Int32}}([
    kingMG, queenMG, rookMG, bishopMG, knightMG, pawnMG]),
    SVector{6, SVector{64, Int32}}([
    kingEG, queenEG, rookEG, bishopEG, knightEG, pawnEG]))
end

const MG_PSTs, EG_PSTs = PST()

struct PieceScore
    midgame::Int32
    endgame::Int32
end

PieceScore() = PieceScore(Int32(0), Int32(0))

==(a::PieceScore, b::PieceScore) = (a.midgame == b.midgame) && (a.endgame == b.endgame)

"Simulaneously update mid- and end-game PST scores from white's perspective"
function updated_pst_score(score::PieceScore, colour, type, pos, add_or_remove)
    # (+1 if adding, -1 if removing) * (+1 if white, -1 if black)
    sign = sgn(colour) * add_or_remove 
    ind = side_index(colour, pos)

    return @inbounds PieceScore(
           score.midgame + sign * MG_PSTs[type][ind+1],
           score.endgame + sign * EG_PSTs[type][ind+1])
end

"returns score of current position from whites perspective for mid and endgame. used when initialising boardstate"
function get_pst(pieces::AbstractArray{BitBoard})
    score = PieceScore()
    for type in [KING, QUEEN, ROOK, BISHOP, KNIGHT, PAWN]
        for colour in [WHITE, BLACK]
            for pos in pieces[long_index(colour) + type]
                score = updated_pst_score(score, colour, type, pos, +1)
            end
        end
    end
    return score
end

"phase starts at the max in the early game and linearly interpolates to zero in the endgame"
phase(pieces) = clamp(pieces * GRADIENT + INTERCEPT, Int32(0), QUANTISATION)
endgame_phase(phase) = QUANTISATION - phase