using PrecompileTools 

@setup_workload begin
    engine = EngineState(sizeMb=8)
    @compile_workload begin
        move = best_move(engine)
    end
end