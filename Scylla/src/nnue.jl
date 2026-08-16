"change a white piece to a black piece and vice versa"
@inline swap_piece_colour(piece) = piece > BLACK_OFFSET ? piece - BLACK_OFFSET : piece + BLACK_OFFSET

"mirror a board position along the horizontal axis"
@inline mirror_position(pos) = UInt64(pos) ⊻ UInt64(56)

"generate index into 768-dimensional feature vector representing piece positions"
@inline feature_ind(piece_id, pos) = 64 * (piece_id - 1) + pos + 1

"activation function for hidden layer of NNUE - quantised for Int16"
@inline SCReLU(x::Int16) = (clamp(x, zero(Int16), QUANTISATION_A)) ^ 2

struct Network
    accumulator_weights::Matrix{Int16}
    us_output_weights::Vector{Int16}
    us_output_bias::Int32
    them_output_weights::Vector{Int16}
    them_output_bias::Int32
    accumulator_white::Vector{Int16}
    accumulator_black::Vector{Int16}
end

# SIMD + inbounds fast accumulation - add row of weights
function accumulate_add!(accumulator, weights, ind)
    @inbounds @simd for i in 1:HIDDEN_NODES
        accumulator[i] += weights[i, ind]
    end
end

# SIMD + inbounds fast accumulation - subtract row of weights
function accumulate_sub!(accumulator, weights, ind)
    @inbounds @simd for i in 1:HIDDEN_NODES
        accumulator[i] -= weights[i, ind]
    end
end

"add new index into white's feature vector and update hidden layer using weights"
accumulate_add_white!(nn::Network, ind) = 
    accumulate_add!(nn.accumulator_white, nn.accumulator_weights, ind)

"add new index into black's feature vector and update hidden layer using weights"
accumulate_add_black!(nn::Network, ind) = 
    accumulate_add!(nn.accumulator_black, nn.accumulator_weights, ind)

"remove old index into white's feature vector and update hidden layer using weights"
accumulate_sub_white!(nn::Network, ind) = 
    accumulate_sub!(nn.accumulator_white, nn.accumulator_weights, ind)

"remove old index into black's feature vector and update hidden layer using weights"
accumulate_sub_black!(nn::Network, ind) = 
    accumulate_sub!(nn.accumulator_black, nn.accumulator_weights, ind)

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

"convert float to integer type while multiplying by quantisation factor"
quantise_parameter(x, quantisation, type) = round(type, x * quantisation)

"divide by quantisation parameter using fast bit-shift to scale output"
dequantise_parameter(x, quant_shift) = x >> quant_shift

function load_network()
    path = joinpath(dirname(@__DIR__), "src", "NNUE", "$(NNUE_NAME).h5")
    h5open(path, "r") do fid
        accum_weights    = read(fid["accum_weights"])
        accum_bias       = vec(read(fid["accum_bias"]))
        us_out_weights   = vec(read(fid["us_out_weights"]))
        us_out_bias      = read(fid["us_out_bias"])[1]
        them_out_weights = vec(read(fid["them_out_weights"]))
        them_out_bias    = read(fid["them_out_bias"])[1]

        accum_weights    = quantise_parameter.(accum_weights, QUANTISATION_A, Int16)
        accum_bias       = quantise_parameter.(accum_bias, QUANTISATION_A, Int16)
        us_out_weights   = quantise_parameter.(us_out_weights, QUANTISATION_B, Int16)
        them_out_weights = quantise_parameter.(them_out_weights, QUANTISATION_B, Int16)
        us_out_bias      = quantise_parameter.(us_out_bias, QUANTISATION_A * QUANTISATION_B, Int32)
        them_out_bias    = quantise_parameter.(them_out_bias, QUANTISATION_A * QUANTISATION_B, Int32)

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
    out = Int32(0)
    @inbounds @simd for i in 1:HIDDEN_NODES
        screlu = SCReLU(accumulator[i])
        out += Int32(screlu) * weights[i]
    end
    # remove additional QUANT_SHIFT_A due to squaring in SCReLU
    out = dequantise_parameter(out, QUANT_SHIFT_A) 
    out += bias

    return Int16(dequantise_parameter(out, QUANT_SHIFT_A + QUANT_SHIFT_B))
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