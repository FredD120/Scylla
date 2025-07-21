#Define Magic struct and initialise from file
#Use MagivVec (rook/bishop) to lookup (pseudolegal) sliding moves

struct Magic 
    MagNum::UInt64
    Mask::UInt64
    BitShift::UInt8
    Attacks::Vector{UInt64}
end
    
function read_magics(piece)
    path = "$(dirname(@__DIR__))/src/move_BBs/Magic$(piece)s.jld2"
    Masks = UInt64[]
    Magics = UInt64[]
    BitShifts = UInt8[]
    AttackVec = Vector{UInt64}[]

    jldopen(path, "r") do file
        Masks = file["Masks"]
        Magics = file["Magics"]
        BitShifts = file["BitShifts"]
        AttackVec = file["AttackVec"]
    end

    MagicVec = @SVector [Magic(Magics[i],Masks[i],BitShifts[i],AttackVec[i]) for i in 1:64]
    return MagicVec
end

const BishopMagics = read_magics("Bishop")
const RookMagics = read_magics("Rook")

"Magic function to transform positional information to an index (0-63) into an attack lookup table"
magicIndex(BB,num,N) = (BB*num) >> (64-N)

"Uses magic bitboards to identify blockers and retrieve legal attacks against them"
function sliding_attacks(MagRef::Magic,all_pieces)
    blocker_BB = all_pieces & MagRef.Mask
    return MagRef.Attacks[magicIndex(blocker_BB,MagRef.MagNum,MagRef.BitShift)+1]
end
