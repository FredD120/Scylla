using Scylla

engine = Scylla.EngineState(control = Time(10))

@time move, logger = best_move(engine)
Scylla.print_log(logger)