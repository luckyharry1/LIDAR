# Decisions

The decision log: what was decided, why, and what it costs. Newest sections last.

## Foundations (v1)

- Tooling is pinned with Rokit (`rokit.toml`); versions are best guesses and may need bumping at install time.
- Maze randomness uses a Lehmer PRNG (`src/shared/pure/Rng.luau`) so seeds reproduce on every machine.
- The exit is the cell farthest from the start by BFS; dead ends are kept for side objectives.
- Tests run under Lune with a small custom runner (`tests/run.luau`).

## The v2 rework

Vasco playtested v1 with a friend and asked for a rework; the feedback is listed in
`docs/PROGRESS.md`. Each decision below answers part of it.

| Decision | Why | Cost |
| --- | --- | --- |
| The maze is invisible; dots show through walls | Asked for in the playtest; the dots become the only picture of a level | No fallback picture at all: a player who stops scanning sees nothing. Inspecting geometry in Studio needs the `lights on` dev command |
| Dots are tiny, many, fast and permanent, up to a budget, packed one per grid cell | Asked for ("tiny, dim, very many, fast, and permanent") | Tens of thousands of parts: the budget has to follow the device (DOT DETAIL), and the oldest dots are recycled when it is full |
| Right click is a loud top-to-bottom sweep that recharges, instead of a focus beam | Asked for | A resource to manage, and monsters hear it |
| Crouch: slow, silent and unseen by the Wanderer, except when wading | Asked for | Strong: balanced by its speed (5 studs/s) and by water |
| Monsters are invisible, roam, and are sensed by marks, breath, aura and sound | Asked for: "sensed rather than seen", "much scarier" | Players have to learn the signals; a scan only ever glimpses a monster |
| Lanterns, hidden recorders, pits, alarm plates, a lit waterfall room, Pulse Radar | Asked for | More to build and balance per level |

## Cloud session (13 October 2026)

The v2 client slices, the story integration and the docs were written in a cloud session
without Roblox Studio. These are its decisions.

| Decision | Why | Cost |
| --- | --- | --- |
| The interface is laid out for 830x400 with a minimum scale of 0.8 | On a 705x338 phone the v1 layout scaled to 0.55 and text was about 7 px | Every window must fit 800x380; on mid-size PC screens the interface is a little larger than before (still capped at 1.5) |
| Client modules follow the contracts in `docs/PROGRESS.md` exactly; extras are listed there | Several helpers were meant to write them in parallel against those contracts | A few small additions (`Menus.dotQuality`, `Radio`) had to be documented after the fact |
| A disguised Mimic gives nothing away: no footprints, breath, aura, heartbeat or breathing loop | The new presence cues would otherwise expose it and spoil its one trick | A player who relies on the aura gets no warning from a Mimic until it reveals itself |
| `src/shared/data/Lore.luau` builds all text from the story thread's `LoreText.luau` instead of holding prose | One source of truth: regenerating the story text updates the game | The story's ids become part of the code; `tests/LoreTests.luau` guards the wiring |
| Lit rooms keep their v2 ids, themes and layouts, with three story notes each | The layouts have three note spots, and new props cannot be placed well without Studio | Some story lines are not used yet (listed in `docs/PROGRESS.md`) |
| Tiers are named for the story's floors (The Annex, The Flooded Wing, The Overgrowth, The Foundation), two to a floor | The v2 names belonged to an earlier story (the Datum), and the story bible maps tiers to floors | Two consecutive tiers share a name |
| Tutorial hints are the story's own notices and manual rules, with the device's control in brackets | The story bible says the game never lectures; the controls still have to be learnable on every device | Hints are a line longer than plain instructions |
| Base on the radio, and a false Base that gives directions only near a disguised Mimic | The story bible's tell: real Base reports and counts, never directs | One more voice competing with recorder tapes (they queue, never overlap) |
| "Climb the ladder" ends the run and returns to the title with the checkpoint kept | The bible's harder "Night Shift +" run is not specified, and wiping progress on a story choice would be harsh | There is no new game plus yet; going back down from the title is the same as having stayed |
| A strict type check (`scripts/typecheck.sh`, luau-lsp) is used but not run in CI | It catches what lint cannot, and was the only check of the client possible without Studio | The newer Luau solver reports known false positives (listed in `docs/TESTING.md`), so it cannot gate a build yet |
| `scripts/check.sh` is executable in git | The CI workflow runs it as `./scripts/check.sh`, which failed with "Permission denied" | None |
