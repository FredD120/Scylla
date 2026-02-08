#Perft function to test speed/accuracy of move generator
#Option to add TT hashing to speedup 4x

"hold data required for perft"
struct PerftData
    ZHash::BitBoard
    depth::UInt8
    leaves::UInt128
end

"generic constructor for perft data"
PerftData() = PerftData(BitBoard(), UInt8(0), UInt128(0))

"count leaf nodes from a position at a given depth"
function perft(board::Boardstate, depth,TT::Union{TranspositionTable,Nothing}=nothing, verbose=false; TT_enabled=!isnothing(TT))
    if depth == 1
        return length(generate_moves(board))
    end
    
    if TT_enabled
        TT_entry = get_entry(TT, board.ZHash)
        if TT_entry.ZHash == board.ZHash
            if depth == TT_entry.depth
                return TT_entry.leaves
            end
        end
    end

    leaf_nodes = 0
    moves = generate_moves(board)
    for move in moves
        make_move!(move, board)
        nodecount = perft(board, depth-1, TT, TT_enabled=TT_enabled)
        
        if verbose == true
            println(LONGmove(move) * ": " * string(nodecount))
        end
        
        leaf_nodes += nodecount
        unmake_move!(board)
    end

    if TT_enabled
        set_entry!(TT, PerftData(board.ZHash, depth, leaf_nodes))
    end
    return leaf_nodes
end