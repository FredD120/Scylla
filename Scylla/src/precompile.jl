using PrecompileTools 

@setup_workload begin
    engine = EngineState(size_mb=8)
    @compile_workload begin
        move = best_move(engine)
    end
end