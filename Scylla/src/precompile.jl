using PrecompileTools 

@setup_workload begin
    dummy_cli_state = CLI_state()
    dummy_wrapper = EngineWrapper()
    @compile_workload begin
        move = best_move(dummy_wrapper.engine)
        parse_msg!(dummy_wrapper, dummy_cli_state, "isready")
    end
end

# to compile into an app: julia> using PackageCompiler; create_app("Scylla", "Scylla_VX")