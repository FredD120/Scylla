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
tt_size(table::TranspositionTable{T}) where T = tt_size(entry_size(T), length(table.hash_table))
tt_size(::Nothing) = 0.0

"total number of positions stored in TT"
num_entries(table::TranspositionTable{T}) where {T} = length(table.hash_table) * num_entries(T())
num_entries(::Nothing) = 0

"Reset all entries in TT to default constructor value"
function reset_tt!(table::TranspositionTable{T}) where {T}
    for i in eachindex(table.hash_table)
        table.hash_table[i] = T()
    end
end

"do nothing if no TT to reset"
reset_tt!(::Nothing) = nothing

"construct TT of a given size (2^N) with entries of a given type"
function TranspositionTable(type, size::Integer, verbose::Bool)
    actual_len = UInt64(1) << size
    hash_table = [type() for _ in 1:actual_len]
    table = TranspositionTable(bitmask(actual_len), hash_table)
    if verbose
        println("TT size = $(tt_size(table)) Mb")
    end
    return table
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
get_entry(table::TranspositionTable, zobrist::BitBoard) = table.hash_table[zobrist_mask(zobrist, table.key) + 1]

"use zhash and bitshift to make zkey into TT - not currently in use"
zobrist_shift(zobrist_hash, shift) = zobrist_hash >> shift

"use zhash and bitmask to make zkey into TT"
zobrist_mask(zobrist_hash, mask) = zobrist_hash & mask

"set value of entry in TT"
function set_entry!(table::TranspositionTable, data) 
    table.hash_table[zobrist_mask(data.zobrist_hash, table.key) + 1] = data
end

"set value of entry in TT using zhash provided"
function set_entry!(table::TranspositionTable, zobrist_hash, data) 
    table.hash_table[zobrist_mask(zobrist_hash, table.key) + 1] = data
end

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
struct Bucket
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
    ind = convert(UInt64, zobrist_mask(zobrist_hash, table.key)) + 1

    @inbounds current_entry = table.hash_table[ind]
    store_success = false

    new_depth = current_entry.depth
    new_always = current_entry.always

    #correct mate scores in TT
    score = correct_score(score, depth, -1)
    new_data = SearchData(zobrist_hash, depth, score, node_type, best_move)

    if depth >= current_entry.depth.depth
        if current_entry.depth.type == NONE
            store_success = true
        end  
        new_depth = new_data
    else
        if current_entry.always.type == NONE
            store_success = true
        end
        new_always = new_data
    end

    @inbounds table.hash_table[ind] = Bucket(new_depth, new_always)
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