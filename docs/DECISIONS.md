# Decisions

- Tooling is pinned with Rokit (`rokit.toml`); versions are best guesses and may need bumping at install time.
- Maze randomness uses a Lehmer PRNG (`src/shared/pure/Rng.luau`) so seeds reproduce on every machine.
- The exit is the cell farthest from the start by BFS; dead ends are kept for side objectives.
- Tests run under Lune with a small custom runner (`tests/run.luau`).
