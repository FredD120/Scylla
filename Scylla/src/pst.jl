#Define PST as position evaluation heuristic
#We dynamically update the PST evaluation in move make and unmake
#It is stored in the board struct but not in board history
#This saves looping over all pieces in position evaluation 

"Retrieve piece square tables from file"
function get_pst(type)
    h5open("$(dirname(@__DIR__))/src/PST/$(type).h5", "r") do fid
        MG::SVector{64, Float32} = read(fid["MidGame"])
        EG::SVector{64, Float32} = read(fid["EndGame"])
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

    return (SVector{6, SVector{64, Float32}}([
    kingMG, queenMG, rookMG, bishopMG, knightMG, pawnMG]),
    SVector{6, SVector{64, Float32}}([
    kingEG, queenEG, rookEG, bishopEG, knightEG, pawnEG]))
end

const MG_PSTs, EG_PSTs = PST()

"Simulaneously update mid- and end-game PST scores from white's perspective"
function update_pst_score!(score::Vector{Int32}, colour::UInt8, type_val, pos, add_or_remove)
    #+1 if adding, -1 if removing * +1 if white, -1 if black
    sign = sgn(colour) * add_or_remove 
    ind = side_index(colour, pos)

    @inbounds score[1] += sign * MG_PSTs[type_val][ind+1]
    @inbounds score[2] += sign * EG_PSTs[type_val][ind+1]
end

"returns score of current position from whites perspective for mid and endgame. used when initialising boardstate"
function get_pst(pieces::AbstractArray{BitBoard})
    score = zeros(Int32, 2)
    for type in [KING, QUEEN, ROOK, BISHOP, KNIGHT, PAWN]
        for colour in [WHITE, BLACK]
            for pos in pieces[colour_piece_id(colour, type)]
                update_pst_score!(score, colour, type, pos, +1)
            end
        end
    end
    return score
end

"phase starts at the max in the early game and linearly interpolates to zero in the endgame"
phase(pieces) = clamp(pieces * GRADIENT + INTERCEPT, Int32(0), QUANTISATION)
endgame_phase(phase) = QUANTISATION - phase