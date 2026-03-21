using PrecompileTools 

@setup_workload begin
    engine = EngineState(size_mb=48, control = Time(GUI_SAFETY_FACTOR))
    @compile_workload begin
        move = best_move(engine)
    end
end