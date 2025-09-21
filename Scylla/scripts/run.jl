using Scylla 

#=
"task to run best_move and put outputs in channel"
function run_engine(E,ch_out::Channel)
    best, logger = best_move(E)
    put!(ch_out,(best,logger))
end

mutable struct state
    QUIT::Bool
    listen::Channel
    worker::Union{Task,Nothing}
    chnnlCMD::Union{Channel,Nothing}
    chnnlOUT::Union{Channel,Nothing}
end
state() = state(false,Channel{String}(1),nothing,nothing,nothing)

function reset_worker!(st::state)
    st.worker = nothing
    st.chnnlCMD = nothing
    st.chnnlOUT = nothing
end

function parse!(st::state,E::EngineState,msg)
    msg_in = split(uppercase(msg))
    if "QUIT" in msg_in
        st.QUIT = true

    elseif "HELLO" in msg_in
        println("world")

    elseif "BEGIN" in msg_in && isnothing(st.worker)
        st.chnnlCMD = E.config.forcequit
        st.chnnlOUT = Channel{Tuple{UInt32,Logger}}(1)
        st.worker = Threads.@spawn run_engine(E,st.chnnlOUT)
    
    elseif "STOP" in msg_in && !isnothing(st.worker)
        put!(st.chnnlCMD,FORCEQUIT())
    end
end

"task to listen for input and put into listen channel"
function listen(st::state)
    for input in eachline()
        put!(st.listen, input)
    end
end
 
function loop()
    st = state() 
    listener = Threads.@spawn listen(st)
    engine = EngineState(comms=Channel{FORCEQUIT}(1),control=Time(10))

    while !st.QUIT
        if isready(st.listen)
            parse!(st,engine,take!(st.listen))
        end
        if !isnothing(st.worker) && isready(st.chnnlOUT)
            output = take!(st.chnnlOUT)
            print_log(output[2])
            reset_worker!(st)
        end
        sleep(0.1)
    end
    reset_worker!(st)
    listener = nothing
end

function tst()
    e = EngineState(control=Time(2))
    e.config.debug = true
    #e.config.quiescence = false
    b,l = best_move(e)
    print_log(l)
end

abstract type A end
abstract type B end

struct typeA1 <: A 
    v::Int64 
end

struct typeA2 <: A
    v::Int64
end

struct typeB1 <: B 
    v::Int64 
end

struct typeB2 <: B 
    v::Int64 
end

mutable struct Foo{a<:A,b<:B}
    var_a::a
    var_b::b
end

function printfoo(F::Foo{a,b}) where {a<:A,b<:typeB1} 
    println("Subtype of B")
end

function printfoo(F::Foo{a}) where {a<:A}
    println("Subtype of A") 
end

function printfoo(F::Foo{a}) where a<:typeA1
    println("Type 1") 
end

=#
#f = Foo(typeA2(1),typeB1(2))
#printfoo(f)
#tst()
#loop()
Scylla.run_cli()