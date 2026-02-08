#Define PST as position evaluation heuristic
#We dynamically update the PST evaluation in move make and unmake
#It is stored in the board struct but not in board history
#This saves looping over all pieces in position evaluation 

"Retrieve piece square tables from file"
function get_PST(type)
    h5open("$(dirname(@__DIR__))/src/PST/$(type).h5", "r") do fid
        MG::SVector{64, Float32} = read(fid["MidGame"])
        EG::SVector{64, Float32} = read(fid["EndGame"])
        return (MG, EG)
    end
end

"Setup vectors containing the PSTs for mid and endgame"
function PST()
    (kingMG, kingEG) = get_PST("king")
    (queenMG, queenEG) = get_PST("queen")
    (rookMG, rookEG) = get_PST("rook")
    (bishopMG, bishopEG) = get_PST("bishop")
    (knightMG, knightEG) = get_PST("knight")
    (pawnMG, pawnEG) = get_PST("pawn")

    return (SVector{6, SVector{64, Float32}}([
    kingMG, queenMG, rookMG, bishopMG, knightMG, pawnMG]),
    SVector{6, SVector{64, Float32}}([
    kingEG, queenEG, rookEG, bishopEG, knightEG, pawnEG]))
end

const MG_PSTs, EG_PSTs = PST()

"Simulaneously update mid- and end-game PST scores from white's perspective"
function update_PST_score!(score::Vector{Int32}, colour::UInt8, type_val, pos, add_or_remove)
    #+1 if adding, -1 if removing * +1 if white, -1 if black
    sign = sgn(colour) * add_or_remove 
    ind = side_index(colour,pos)

    score[1] += sign * MG_PSTs[type_val][ind+1]
    score[2] += sign * EG_PSTs[type_val][ind+1]
end

"Returns score of current position from whites perspective. used when initialising boardstate"
function set_PST!(score::Vector{Int32},pieces::AbstractArray{BitBoard})
    for type in [King, Queen, Rook, Bishop, Knight, Pawn]
        for colour in [white,black]
            for pos in pieces[ColourPieceID(colour, type)]
                update_PST_score!(score, colour, type, pos, +1)
            end
        end
    end
    return score
end

"number of pieces left when endgame begins"
const EGBEGIN = 12

const MG_grad = -1/(EGBEGIN+2)

"If more than EGBEGIN+2 pieces lost, set to 0. Between 0 and EGBEGIN+2 pieces lost, decrease linearly from 1 to 0"
function MGweighting(pc_remaining)::Float32 
    pc_lost = 24 - pc_remaining
    weight = 1 + MG_grad*pc_lost
    return max(0,weight)
end

const EG_grad = -1/EGBEGIN

"If more than EGBEGIN+2 pieces remaining, set to 0. Between EGBEGIN+2 and 2 remaining increase linearly to 1"
function EGweighting(pc_remaining)::Float32 
    weight = 1 + EG_grad*(pc_remaining-2)
    return max(0,weight)
end