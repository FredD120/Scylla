using Scylla
using HDF5

function convert()
    h5open("$(dirname(@__DIR__))/src/move_bitboards/knight.h5", "w") do fid
        fid["moves"] = knight_mvs
    end
end
#convert()