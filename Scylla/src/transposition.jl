#Define TranspositionTable and utility functions for it 
#Initialise TT, define objects that go into TT
#Retrieve and store entries

"hold hash table and bitshift to get index from zobrist hash"
struct TranspositionTable{T}
    Key::UInt64
    HashTable::Vector{T}
end

"bitmask for first num binary digits of 64 bit int"
function bitmask(num)
    mask = UInt64(0)
    for i in 0:num-1
        mask |= UInt(1) << i
    end
    return mask
end

"shift for 64 bit integers"
bitshift(num) = UInt64(64-num)

"construct TT using its size in Mb and type of data stored. return nothing if length = 0"
function TranspositionTable(type,verbose=false;sizeMb=nothing,size=18)::Union{TranspositionTable,Nothing}
    Mb = 1048576 #size of a Mb in bytes
    if size > 0
        entry_size = Base.summarysize(type())
        #calculate size from Mb requirements if given
        #otherwise use size provided or default
        if !isnothing(sizeMb)
            num_entries = fld(sizeMb*Mb,entry_size)
            size = floor(Int16,log2(num_entries))
        end

        hash_table = [type() for _ in 1:2^size]
        if verbose
            println("TT size = $(round(entry_size*(2^size)/Mb,sigdigits=4)) Mb")
        end
        return TranspositionTable(bitmask(size),hash_table)
    end
    return nothing
end

"retrieve transposition from TT using index derived from bitshift"
get_entry(TT::TranspositionTable,Zhash::UInt64) = TT.HashTable[ZKey_mask(Zhash,TT.Key)+1]

"use zhash and bitshift to make zkey into TT"
ZKey_shift(ZHash,shift) = ZHash>>shift

"use zhash and bitmask to make zkey into TT"
ZKey_mask(ZHash,mask) = ZHash&mask

"set value of entry in TT"
function set_entry!(TT::TranspositionTable,data) 
    TT.HashTable[ZKey_mask(data.ZHash,TT.Key)+1] = data
end

"set value of entry in TT using zhash provided"
function set_entry!(TT::TranspositionTable,ZHash,data) 
    TT.HashTable[ZKey_mask(ZHash,TT.Key)+1] = data
end

"return a view into the TT that can be used to modify the entry"
view_entry(TT::TranspositionTable,ZHash) = @view TT.HashTable[ZKey_mask(ZHash,TT.Key)+1]

"data describing a node, to be stored in TT"
struct SearchData
    ZHash::UInt64
    depth::UInt8
    score::Int16
    type::UInt8
    move::UInt32
end

"generic constructor for search data"
SearchData() = SearchData(UInt64(0),UInt8(0),Int16(0),NONE,NULLMOVE)

"store multiple entries at same Zkey, with different replace schemes"
mutable struct Bucket
    Depth::SearchData
    Always::SearchData
end
"construct bucket with two entries"
Bucket() = Bucket(SearchData(),SearchData())

"add depth to score when storing and remove when retrieving"
function correct_score(score,depth,sgn)::Int16
    if score > MATE
        score += Int16(sgn*depth)
    elseif score < -MATE
        score -= Int16(sgn*depth)
    end
    return score
end

"update entry in TT. either greater depth or always replace"
function TT_store!(TT,ZHash,depth,score,node_type,best_move,logger)
    if !isnothing(TT)
        TT_view = view_entry(TT,ZHash)
        #correct mate scores in TT
        score = correct_score(score,depth,-1)
        new_data = SearchData(ZHash,depth,score,node_type,best_move)
        if depth >= TT_view[].Depth.depth
            if TT_view[].Depth.type == NONE
              logger.hashfull += 1
            end  
            TT_view[].Depth = new_data
        else
            if TT_view[].Always.type == NONE
              logger.hashfull += 1
            end
            TT_view[].Always = new_data
        end
    end
end

"retrieve TT entry, returning nothing if there is no entry"
function TT_retrieve!(TT,ZHash,cur_depth)
    if !isnothing(TT)
        bucket = get_entry(TT,ZHash)
        #no point using TT if hash collision
        if bucket.Depth.ZHash == ZHash
            return bucket.Depth, correct_score(bucket.Depth.score,cur_depth,+1)
        elseif bucket.Always.ZHash == ZHash
            return bucket.Always, correct_score(bucket.Always.score,cur_depth,+1)
        end
    end
    return nothing,nothing
end