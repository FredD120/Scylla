using PrecompileTools 

@setup_workload begin
    engine = EngineState(8)
    @compile_workload begin
        move = best_move(engine,max_T=1.5)
    end
end