#Perft function to test speed/accuracy of move generator
#Option to add TT hashing to speedup 4x

"hold data required for perft"
struct PerftData
    zobrist_hash::BitBoard
    depth::UInt8
    leaves::UInt128
end

"generic constructor for perft data"
PerftData() = PerftData(BitBoard(), UInt8(0), UInt128(0))

"count leaf nodes from a position at a given depth"
function perft(board::BoardState, depth, TT::Union{TranspositionTable,Nothing}=nothing, verbose=false; TT_enabled=!isnothing(TT))
    if depth == 1
        moves, move_length = generate_moves(board)
        clear_current_moves!(board.move_vector, move_length)
        return move_length
    end
    
    if TT_enabled
        TT_entry = get_entry(TT, board.zobrist_hash)
        if TT_entry.zobrist_hash == board.zobrist_hash
            if depth == TT_entry.depth
                return TT_entry.leaves
            end
        end
    end

    leaf_nodes = 0
    moves, move_length = generate_moves(board)
    for move in moves
        make_move!(move, board)
        nodecount = perft(board, depth - 1, TT, TT_enabled=TT_enabled)
        
        if verbose == true
            println(long_move(move) * ": " * string(nodecount))
        end
        
        leaf_nodes += nodecount
        unmake_move!(board)
    end
    clear_current_moves!(board.move_vector, move_length)

    if TT_enabled
        set_entry!(TT, PerftData(board.zobrist_hash, depth, leaf_nodes))
    end
    return leaf_nodes
end