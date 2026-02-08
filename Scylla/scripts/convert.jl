using Scylla
using HDF5

function convert(type)
    MGPST = Scylla.get_PST(type)
    EGPST = Scylla.get_PST(type * "EG")

    println(MGPST)
    println(EGPST)

    h5open("$(dirname(@__DIR__))/src/PST/$(type).h5", "w") do fid
        fid["MidGame"] = MGPST
        fid["EndGame"] = EGPST
    end
end

#println(Scylla.get_PST("pawn"))