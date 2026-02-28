#Define TranspositionTable and utility functions for it 
#Initialise TT, define objects that go into TT
#Retrieve and store entries

"hold hash table and bitshift to get index from zobrist hash"
struct TranspositionTable{T}
    key::BitBoard
    hash_table::Vector{T}
end

"bitmask for first num binary digits of 64 bit int, takes in actual_size"
bitmask(tt_size::Integer) = BitBoard(tt_size-1)

"shift for 64 bit integers, takes in N as input s.t. actual_size = 2^N"
bitshift(num::Integer) = BitBoard(64-num)

"interrogate size of object in bytes"
entry_size(type) = Base.summarysize(type())

"return TT size in Mb"
tt_size(entry_size, len) = round((entry_size * len) / MB_SIZE, sigdigits=4)
tt_size(TT::TranspositionTable{T}) where T = tt_size(entry_size(T), length(TT.hash_table))
tt_size(::Nothing) = 0.0

"total number of positions stored in TT"
num_entries(TT::TranspositionTable{T}) where {T} = length(TT.hash_table) * num_entries(T())
num_entries(::Nothing) = 0

"Reset all entries in TT to default constructor value"
function reset_TT!(TT::TranspositionTable{T}) where {T}
    for i in eachindex(TT.hash_table)
        TT.hash_table[i] = T()
    end
end

"do nothing if no TT to reset"
reset_TT!(::Nothing) = nothing

"construct TT of a given size (2^N) with entries of a given type"
function TranspositionTable(type, size::Integer, verbose::Bool)
    actual_len = UInt64(1) << size
    hash_table = [type() for _ in 1:actual_len]
    TT = TranspositionTable(bitmask(actual_len), hash_table)
    if verbose
        println("TT size = $(tt_size(TT)) Mb")
    end
    return TT
end

"construct TT using its size in Mb and type of data stored. return nothing if length = 0"
function TranspositionTable(verbose=false; 
    size_mb=TT_DEFAULT_MB, size=nothing, type=TT_ENTRY_TYPE)::Union{TranspositionTable,Nothing}
    if !isnothing(size) && size > 0 && size <= 24 #arbitrary hard limit
        return TranspositionTable(type, size, verbose)

    elseif size_mb > TT_MIN_MB && size_mb <=  TT_MAX_MB
        num_entries = fld(size_mb * MB_SIZE, entry_size(type))
        size = floor(Int16, log2(num_entries))
        return TranspositionTable(type, size, verbose)

    end
    return nothing
end

"retrieve transposition from TT using index derived from bitshift"
get_entry(tt::TranspositionTable, zobrist::BitBoard) = tt.hash_table[ZKey_mask(zobrist, tt.key) + 1]

"use zhash and bitshift to make zkey into TT"
ZKey_shift(zobrist_hash, shift) = zobrist_hash >> shift

"use zhash and bitmask to make zkey into TT"
ZKey_mask(zobrist_hash, mask) = zobrist_hash & mask

"set value of entry in TT"
function set_entry!(TT::TranspositionTable, data) 
    TT.hash_table[ZKey_mask(data.zobrist_hash, TT.key) + 1] = data
end

"set value of entry in TT using zhash provided"
function set_entry!(TT::TranspositionTable, zobrist_hash, data) 
    TT.hash_table[ZKey_mask(zobrist_hash, TT.key) + 1] = data
end

"return a view into the TT that can be used to modify the entry"
view_entry(TT::TranspositionTable, zobrist_hash) = @view TT.hash_table[convert(UInt64, ZKey_mask(zobrist_hash, TT.key)) + 1]

"data describing a node, to be stored in TT"
struct SearchData
    zobrist_hash::BitBoard
    depth::UInt8
    score::Int16
    type::UInt8
    move::Move
end

"generic constructor for search data"
SearchData() = SearchData(BitBoard(), UInt8(0), Int16(0), NONE, NULLMOVE)

"store multiple entries at same Zkey, with different replace schemes"
mutable struct Bucket
    depth::SearchData
    always::SearchData
end
"construct bucket with two entries"
Bucket() = Bucket(SearchData(), SearchData())

num_entries(::Bucket) = 2
const TT_ENTRY_TYPE = Bucket

"add depth to score when storing and remove when retrieving"
function correct_score(score, depth, sgn)::Int16
    if score > MATE
        score += Int16(sgn * depth)
    elseif score < -MATE
        score -= Int16(sgn * depth)
    end
    return score
end

"update entry in transposition table. either greater depth or always replace. return true if successfull"
function store!(table::TranspositionTable{Bucket}, zobrist_hash, depth, score, node_type, best_move)::Bool
    TT_view = view_entry(table, zobrist_hash)[]
    store_success = false
    #correct mate scores in TT
    score = correct_score(score, depth, -1)
    new_data = SearchData(zobrist_hash, depth, score, node_type, best_move)
    if depth >= TT_view.depth.depth
        if TT_view.depth.type == NONE
            store_success = true
        end  
        TT_view.depth = new_data
    else
        if TT_view.always.type == NONE
            store_success = true
        end
        TT_view.always = new_data
    end
    return store_success
end

"fallback for transposition table store if table doesn't exist"
store!(::Nothing, _, _, _, _, _)::Bool = false

"retrieve transposition table entry and corrected score, returning nothing if unsuccessful"
function retrieve(table::TranspositionTable{Bucket}, zobrist_hash, cur_depth)
    bucket = get_entry(table, zobrist_hash)
    #no point using TT if hash collision
    if bucket.depth.zobrist_hash == zobrist_hash
        return bucket.depth, correct_score(bucket.depth.score, cur_depth, +1)
    elseif bucket.always.zobrist_hash == zobrist_hash
        return bucket.always, correct_score(bucket.always.score, cur_depth, +1)
    else
        return nothing, nothing
    end
end

"retrieve function barrier in case transposition table doesn't exist, returning nothing"
retrieve(::Nothing, _, _) = (nothing, nothing)