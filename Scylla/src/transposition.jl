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
function TranspositionTable(verbose=false; size_mb=TT_DEFAULT_MB, type=TT_ENTRY_TYPE)
    if size_mb > TT_MIN_MB
        size_mb = min(size_mb, TT_MAX_MB)
        num_entries = fld(size_mb * MB_SIZE, entry_size(type))
        size = floor(Int16, log2(num_entries))
        return TranspositionTable(type, size, verbose)
    end

    if verbose
        println("TT size = 0.0 Mb")
    end
    return nothing
end

"retrieve transposition from TT using index derived from bitshift"
get_entry(table::TranspositionTable, zobrist::BitBoard) = @inbounds table.hash_table[zobrist_mask(zobrist, table.key) + 1]

"use zhash and bitshift to make zkey into TT - not currently in use"
zobrist_shift(zobrist_hash, shift) = zobrist_hash >> shift

"use zhash and bitmask to make zkey into TT"
zobrist_mask(zobrist_hash, mask) = zobrist_hash & mask

"set value of entry in TT"
function set_entry!(table::TranspositionTable, data)
    @inbounds table.hash_table[zobrist_mask(data.zobrist_hash, table.key) + 1] = data
end

"set value of entry in TT using zhash provided"
function set_entry!(table::TranspositionTable, zobrist_hash, data) 
    @inbounds table.hash_table[zobrist_mask(zobrist_hash, table.key) + 1] = data
end

"data describing a node, to be stored in TT"
struct SearchData
    zobrist_hash::UInt64
    data::UInt64
end

"generic constructor for search data"
SearchData() = SearchData(UInt64(0), UInt64(0))

"construct SearchData with default age zero"
SearchData(z::BitBoard, d::UInt8, s::Int16, t::UInt8, m::Move) = SearchData(z, d, s, t, UInt8(0), m)

"construct SearchData by packing move data into a UInt64 and combining with Zobrist hash"
function SearchData(zobrist::BitBoard, depth::UInt8, score::Int16, type::UInt8, age::UInt8, move::Move)  
    score = UInt64(reinterpret(UInt16, score))

    data = UInt64(depth) |
    (score << EVALUATIONSHIFT) |
    (UInt64(type) << NODESHIFT) |
    (UInt64(age) << AGESHIFT) |
    (UInt64(move.n & MOVEMASK) << MOVESHIFT)
    
    return SearchData(zobrist.n, data)
end

get_zobrist(d::SearchData) = BitBoard(d.zobrist_hash)
get_depth(d::SearchData) = UInt8(d.data & DEPTHMASK)
get_type(d::SearchData) = UInt8((d.data >> NODESHIFT) & NODEMASK)
get_age(d::SearchData) = UInt8((d.data >> AGESHIFT) & DEPTHMASK)
get_move(d::SearchData) = Move(UInt32((d.data >> MOVESHIFT) & MOVEMASK))

remove_age(d::UInt64) = UInt64(d & AGEMASK)
set_age(d::UInt64, age::UInt8) = remove_age(d) | (UInt64(age) << AGESHIFT)

"increase age of SearchData entry, but avoid UInt8 overflow"
function increment_age(d::SearchData)
    age = get_age(d)
    new_age = age == typemax(UInt8) ? age : age + UInt8(1)
    SearchData(d.zobrist_hash, set_age(d.data, new_age))
end

"reinterpret raw bits as a signed int after unpacking from unsigned int"
function get_score(d::SearchData)
    score_bits = (d.data >> EVALUATIONSHIFT) & EVALUATIONMASK
    return reinterpret(Int16, UInt16(score_bits))
end

"store multiple entries at same Zkey, with different replace schemes"
struct Bucket
    depth::SearchData
    always::SearchData
end
"construct bucket with two entries"
Bucket() = Bucket(SearchData(), SearchData())

num_entries(::Bucket) = 2
const TT_ENTRY_TYPE = Bucket

"add ply to score when storing and remove when retrieving"
function correct_score(score, ply, sgn)::Int16
    if score > MATE
        score += Int16(sgn * ply)
    elseif score < -MATE
        score -= Int16(sgn * ply)
    end
    return score
end

"relative effective depths of different node types"
function type_value(type::UInt8)
    if type == EXACT
        return Float32(4)

    elseif type == BETA
        return Float32(2)

    else
        return Float32(0)
    end
end

"calculate whether deep transposition table entry should be replaced"
function replace_depth(current, new_depth, old_type, new_type)
    type_diff = type_value(old_type) - type_value(new_type)
    age = Float32(get_age(current))
    depth = Float32(get_depth(current))
    return new_depth >= depth - age * Float32(0.25) + type_diff
end

"update entry in transposition table. either greater depth or always replace. return true if successfull"
@inline function store!(table::TranspositionTable{Bucket}, zobrist_hash, depth, ply, score, node_type, best_move)::Bool
    ind = convert(UInt64, zobrist_mask(zobrist_hash, table.key)) + 1

    @inbounds current_entry = table.hash_table[ind]
    store_success = false

    new_deep = current_entry.depth
    new_always = current_entry.always

    #correct mate scores in TT
    score = correct_score(score, ply, -1)
    new_data = SearchData(zobrist_hash, depth, score, node_type, best_move)

    deep_type = get_type(current_entry.depth)
    if replace_depth(current_entry.depth, depth, deep_type, node_type)
        if deep_type == NONE
            store_success = true
        end 
        new_deep = new_data
    else
        if get_type(current_entry.always) == NONE
            store_success = true
        end
        new_always = new_data
    end

    @inbounds table.hash_table[ind] = Bucket(new_deep, new_always)
    return store_success
end

"retrieve transposition table entry and corrected score, returning nothing if unsuccessful"
function retrieve(table::TranspositionTable{Bucket}, zobrist_hash, cur_ply)
    bucket = get_entry(table, zobrist_hash)
    deep = bucket.depth

    # if full hash doesn't match, position is wrong
    if get_zobrist(deep) == zobrist_hash
        return deep, correct_score(get_score(deep), cur_ply, +1)

    # increase age of depth stored entry every time it fails to be retrieved
    else
        aged_bucket = Bucket(increment_age(deep), bucket.always)
        set_entry!(table, zobrist_hash, aged_bucket)
    end

    if get_zobrist(bucket.always) == zobrist_hash
        return bucket.always, correct_score(get_score(bucket.always), cur_ply, +1)
    else
        return nothing, nothing
    end
end