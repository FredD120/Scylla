#Define TranspositionTable and utility functions for it 
#Initialise TT, define objects that go into TT
#Retrieve and store entries

const Mb = 1048576 #size of a Mb in bytes
const TT_DEFAULT_MB = 24
const TT_MIN_MB = 0
const TT_MAX_MB = 64

"hold hash table and bitshift to get index from zobrist hash"
struct TranspositionTable{T}
    Key::BitBoard
    HashTable::Vector{T}
end

"bitmask for first num binary digits of 64 bit int, takes in actual_size"
bitmask(TT_size::Integer) = BitBoard(TT_size-1)

"shift for 64 bit integers, takes in N as input s.t. actual_size = 2^N"
bitshift(num::Integer) = BitBoard(64-num)

"interrogate size of object in bytes"
entry_size(type) = Base.summarysize(type())

"return TT size in Mb"
TT_size(entry_size,len) = round(entry_size*(len)/Mb,sigdigits=4)
TT_size(TT::TranspositionTable{T}) where T = TT_size(entry_size(T),length(TT.HashTable))
TT_size(::Nothing) = 0.0

"total number of positions stored in TT"
num_entries(TT::TranspositionTable{T}) where {T} = length(TT.HashTable)*num_entries(T())
num_entries(::Nothing) = 0

"Reset all entries in TT to default constructor value"
function reset_TT!(TT::TranspositionTable{T}) where {T}
    for i in eachindex(TT.HashTable)
        TT.HashTable[i] = T()
    end
end

"do nothing if no TT to reset"
reset_TT!(::Nothing) = nothing

"construct TT of a given size (2^N) with entries of a given type"
function TranspositionTable(type, size::Integer, verbose::Bool)
    actual_len = UInt64(1) << size
    hash_table = [type() for _ in 1:actual_len]
    TT = TranspositionTable(bitmask(actual_len),hash_table)
    if verbose
        println("TT size = $(TT_size(TT)) Mb")
    end
    return TT
end

"construct TT using its size in Mb and type of data stored. return nothing if length = 0"
function TranspositionTable(verbose=false; 
    sizeMb=TT_DEFAULT_MB, size=nothing, type=TT_ENTRY_TYPE)::Union{TranspositionTable,Nothing}
    if !isnothing(size) && size > 0 && size <= 24 #arbitrary hard limit
        return TranspositionTable(type,size,verbose)

    elseif sizeMb > TT_MIN_MB && sizeMb <=  TT_MAX_MB
        num_entries = fld(sizeMb*Mb,entry_size(type))
        size = floor(Int16,log2(num_entries))
        return TranspositionTable(type,size,verbose)

    end
    return nothing
end

"retrieve transposition from TT using index derived from bitshift"
get_entry(TT::TranspositionTable,Zhash::BitBoard) = TT.HashTable[ZKey_mask(Zhash,TT.Key)+1]

"use zhash and bitshift to make zkey into TT"
ZKey_shift(ZHash,shift) = ZHash >> shift

"use zhash and bitmask to make zkey into TT"
ZKey_mask(ZHash,mask) = ZHash & mask

"set value of entry in TT"
function set_entry!(TT::TranspositionTable,data) 
    TT.HashTable[ZKey_mask(data.ZHash,TT.Key)+1] = data
end

"set value of entry in TT using zhash provided"
function set_entry!(TT::TranspositionTable,ZHash,data) 
    TT.HashTable[ZKey_mask(ZHash,TT.Key)+1] = data
end

"return a view into the TT that can be used to modify the entry"
view_entry(TT::TranspositionTable,ZHash) = @view TT.HashTable[convert(UInt64,ZKey_mask(ZHash,TT.Key))+1]

"data describing a node, to be stored in TT"
struct SearchData
    ZHash::BitBoard
    depth::UInt8
    score::Int16
    type::UInt8
    move::UInt32
end

"generic constructor for search data"
SearchData() = SearchData(BitBoard(),UInt8(0),Int16(0),NONE,NULLMOVE)

"store multiple entries at same Zkey, with different replace schemes"
mutable struct Bucket
    Depth::SearchData
    Always::SearchData
end
"construct bucket with two entries"
Bucket() = Bucket(SearchData(),SearchData())

num_entries(::Bucket) = 2
const TT_ENTRY_TYPE = Bucket

"add depth to score when storing and remove when retrieving"
function correct_score(score,depth,sgn)::Int16
    if score > MATE
        score += Int16(sgn*depth)
    elseif score < -MATE
        score -= Int16(sgn*depth)
    end
    return score
end