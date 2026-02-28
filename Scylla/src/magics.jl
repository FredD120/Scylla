#Define Magic struct and initialise from file
#Use MagicVec (rook/bishop) to lookup (pseudolegal) sliding moves

"one lookup table for all possible moves from all possible rook/bishop positions"
struct MagicVector
    attacks::Vector{BitBoard}
end

"information to access correct position in lookup table for a given square"
struct Magic 
    magic_number::BitBoard
    mask::BitBoard
    bit_shift::UInt8
    offset::UInt32
end

Magic(magic::BitBoard, mask::BitBoard, bitshift::Integer, attackvec::BitBoard) = 
    Magic(BitBoard(magic), BitBoard(mask), bitshift, BitBoard(attackvec))
    
function read_magics(piece)
    h5open("$(dirname(@__DIR__))/src/move_bitboards/magic_$(piece).h5", "r") do file
        masks = read(file["masks"])
        magics = read(file["magics"])
        bit_shifts = read(file["bit_shifts"])
        offsets = read(file["offsets"])
        all_attack_vec = read(file["attack_vec"])

        magic_vec = @SVector [Magic(magics[i], masks[i], bit_shifts[i], offsets[i]) for i in 1:64]
        return magic_vec, MagicVector(all_attack_vec)
    end
end

const BISHOP_MAGICS, BISHOP_ATTACKS = read_magics("bishop")
const ROOK_MAGICS, ROOK_ATTACKS = read_magics("rook")

"Magic function to transform positional information to an index (0-63) into an attack lookup table"
magic_index(bb::BitBoard, num, shift) = (bb * num) >> (64 - shift)

"Uses magic bitboards to identify blockers and retrieve legal attacks against them"
function sliding_attacks(magic::Magic, all_pieces::BitBoard, vector::MagicVector)
    blocker_bb = all_pieces & magic.mask
    index = magic_index(blocker_bb, magic.magic_number, magic.bit_shift)
    return vector.attacks[magic.offset + index + 1]
end
