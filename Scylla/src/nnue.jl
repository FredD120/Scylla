"change a white piece to a black piece and vice versa"
@inline swap_piece_colour(piece) = piece > BLACK_OFFSET ? piece - BLACK_OFFSET : piece + BLACK_OFFSET

"mirror a board position along the horizontal axis"
@inline mirror_position(pos) = UInt64(pos) ⊻ UInt64(56)

"generate index into 768-dimensional feature vector representing piece positions"
@inline feature_ind(piece_id, pos) = 64 * (piece_id - 1) + pos + 1

"activation function for hidden layer of NNUE"
@inline SCReLU(x::T) where {T <: AbstractFloat} = (clamp(x, T(0.0), T(1.0))) ^ 2

struct Network
    accumulator_weights::Matrix{Float32}
    us_output_weights::Vector{Float32}
    us_output_bias::Float32
    them_output_weights::Vector{Float32}
    them_output_bias::Float32
    accumulator_white::Vector{Float32}
    accumulator_black::Vector{Float32}
end

"add new index into white's feature vector and update hidden layer using weights column ind"
function accumulate_add_white!(nn::Network, ind)
    nn.accumulator_white .+= @view nn.accumulator_weights[:, ind]
end

"add new index into black's feature vector and update hidden layer using weights column ind"
function accumulate_add_black!(nn::Network, ind)
    nn.accumulator_black .+= @view nn.accumulator_weights[:, ind]
end

"remove old index into white's feature vector and update hidden layer using weights column ind"
function accumulate_sub_white!(nn::Network, ind)
    nn.accumulator_white .-= @view nn.accumulator_weights[:, ind]
end

"remove old index into black's feature vector and update hidden layer using weights column ind"
function accumulate_sub_black!(nn::Network, ind)
    nn.accumulator_black .-= @view nn.accumulator_weights[:, ind]
end

"update both side accumulators with added piece"
function add_accumulate_piece!(nn::Network, piece_id, pos)
    white_ind = feature_ind(piece_id, pos)
    black_ind = feature_ind(swap_piece_colour(piece_id), mirror_position(pos))

    accumulate_add_white!(nn, white_ind)
    accumulate_add_black!(nn, black_ind)
end

"update both side accumulators with removed piece"
function sub_accumulate_piece!(nn::Network, piece_id, pos)
    white_ind = feature_ind(piece_id, pos)
    black_ind = feature_ind(swap_piece_colour(piece_id), mirror_position(pos))

    accumulate_sub_white!(nn, white_ind)
    accumulate_sub_black!(nn, black_ind)
end

function load_network()
    path = joinpath(dirname(@__DIR__), "src", "NNUE", "$(NNUE_NAME).h5")
    h5open(path, "r") do fid
        accum_weights::Matrix{Float32}    = read(fid["accum_weights"])
        accum_bias::Vector{Float32}       = vec(read(fid["accum_bias"]))
        us_out_weights::Vector{Float32}   = vec(read(fid["us_out_weights"]))
        us_out_bias::Float32              = Float32(read(fid["us_out_bias"])[1])
        them_out_weights::Vector{Float32} = vec(read(fid["them_out_weights"]))
        them_out_bias::Float32            = Float32(read(fid["them_out_bias"])[1])

        @assert size(accum_weights) == (HIDDEN_NODES, 768)
        @assert length(accum_bias) == HIDDEN_NODES
        @assert length(us_out_weights) == HIDDEN_NODES
        @assert length(them_out_weights) == HIDDEN_NODES
        return Network(
                accum_weights,
                us_out_weights,
                us_out_bias,
                them_out_weights,
                them_out_bias,
                copy(accum_bias),
                copy(accum_bias),
        )
    end
end

"load neural network from a file and initialise accumulators with current piece positions"
function initialise_network(piece_vec)
    nn = load_network()
    for (piece_id, piece_bb) in enumerate(piece_vec)
        for position in piece_bb
            add_accumulate_piece!(nn, piece_id, position)
        end
    end
    return nn
end

"apply activation to accumulator then pass through output layer of network"
function activate_output(accumulator, weights, bias)
    out = mapreduce(+, accumulator, weights) do a, w
        return SCReLU(a) * w
    end
    return out + bias
end

"forward pass of efficiently updated neural network - assumes filled accumulators"
function forward(nn::Network, side_to_move)
    if side_to_move
        us = activate_output(nn.accumulator_white, nn.us_output_weights, nn.us_output_bias)
        them = activate_output(nn.accumulator_black, nn.them_output_weights, nn.them_output_bias)
        return us + them
    else
        us = activate_output(nn.accumulator_black, nn.us_output_weights, nn.us_output_bias)
        them = activate_output(nn.accumulator_white, nn.them_output_weights, nn.them_output_bias)
        return us + them
    end
end