using PrecompileTools 

@setup_workload begin
    engine = EngineState()
    @compile_workload begin
        move = best_move(engine,max_T=2.0)
    end
end