using Scylla 

#Scylla.run_cli()

#=
moves = [Scylla.NULLMOVE]
ls = map(m->Scylla.LONGmove(m), moves)
println(typeof(ls),ls)
=#


#=
e = EngineState()
println("Num entries: ",Scylla.num_entries(e.TT))
println("Size in Mb: ",Scylla.TT_size(e.TT))
@time mve,logg = best_move(e,max_depth=8)

Threads.@spawn wait mve,logg = best_move(e,max_depth=8)
=#
#Scylla.print_log(logg)

struct FORCEQUIT end

mutable struct CFG
    ischannel::Bool 
    chnnlCMD::Union{Channel,Nothing}
end

function expensive(cfg::CFG,ch_out::Channel)
    for _ in 1:30
        sleep(0.1)
        if isready(cfg.chnnlCMD) #&& take!(cfg.chnnlCMD) == FORCEQUIT()
            put!(ch_out,("stop","expensive task interrupted"))
            return nothing
        end
    end
    put!(ch_out,("finish","expensive task finished"))
    return nothing
end

mutable struct state
    QUIT::Bool
    worker::Union{Task,Nothing}
    chnnlCMD::Union{Channel,Nothing}
    chnnlOUT::Union{Channel,Nothing}
end
state() = state(false,nothing,nothing,nothing)

function reset_state!(st::state)
    st.worker = nothing
    st.chnnlCMD = nothing
    st.chnnlOUT = nothing
end

function parse!(st::state,msg)
    msg_in = split(uppercase(msg))
    if "QUIT" in msg_in
        st.QUIT = true

    elseif "HELLO" in msg_in
        println("world")

    elseif "BEGIN" in msg_in && isnothing(st.worker)
        st.chnnlCMD = Channel{FORCEQUIT}(1)
        st.chnnlOUT = Channel{Tuple{String,String}}(1)
        st.worker = Threads.@spawn expensive(CFG(true,st.chnnlCMD),st.chnnlOUT)
    
    elseif "STOP" in msg_in && !isnothing(st.worker)
        put!(st.chnnlCMD,FORCEQUIT())

    end
end

function listen(ch::Channel)
    input = readline()
    put!(ch, input)
end
 
function loop()
    st = state()
    input_channel = Channel{String}(1)
    Threads.@spawn listen(input_channel)

    while !st.QUIT
        if isready(input_channel)
            parse!(st,take!(input_channel))
            Threads.@spawn(listen(input_channel))
        end
        if !isnothing(st.worker) && istaskdone(st.worker)
            output = fetch(st.chnnlOUT)
            println(output[2])
            reset_state!(st)
        end
        sleep(0.1)
    end
    reset_state!(st)
end

loop()