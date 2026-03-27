# Scylla

Scylla version 1.0 contains the following features:

GENERAL
-> Legal and pseudo-legal move generation
-> Incremental updates using make/unmake

TREE SEARCH
-> Minimax with alpha-beta pruning
-> Iterative deepening
-> Transposition table memoisation

EVALUATION
-> Tapered piece square tables for positional/piece evaluation
-> Quiescence search (PSTs are only accurate in quiet positions)
-> Check extension

MOVE ORDERING
-> Principle variation
-> Transposition table hash move
-> MVV-LVA (good captures before bad)
-> Killer moves (quiet moves that cause beta cut-off)