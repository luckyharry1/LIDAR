# Testing

What is checked automatically, what is checked by hand, and what nobody has checked yet.
`docs/PROGRESS.md` keeps the running list of what has actually been run.

## Automated checks

`./scripts/check.sh` runs everything below except the type check, in this order, and stops at
the first failure. The GitHub workflow (`.github/workflows/check.yml`) runs it on every push
and pull request.

| Step | Command | What it catches |
| --- | --- | --- |
| Format | `stylua --check src tests` | Formatting drift. `stylua src tests` fixes it. `LoreText.luau` is generated and skipped (`.styluaignore`). |
| Lint | `selene src tests` | Unused variables, shadowing, suspicious code. Selene needs Roblox's standard library; it downloads it on first run. |
| Unit tests | `lune run tests/run` | The game rules, which have no Roblox dependencies (see below). |
| Build | `rojo build -o build/LIDAR.rbxl` | A broken project file or a module in the wrong place. |

### The test suites

All suites live in `tests/` and run under Lune with the small runner in `tests/run.luau`.
They only test `src/shared` (the pure rules and the content tables), which is why those
modules may not touch Roblox globals.

| Suite | Tests | Covers |
| --- | --- | --- |
| Maze | 7 | Seeded generation: 10,000 seeds solvable within the time budget, deterministic per seed, symmetric passages, BFS paths, line of sight. |
| LevelPlan | 6 | Turning a tier and a seed into a level: valid, non-overlapping contents on every tier, determinism, the difficulty ramp, lore rooms every two to three tiers, forced anomalies. |
| DotRules | 9 | What a ray hit becomes: classification by tags and surface normal, the Mimic's disguise, which dots are permanent, sizes, packing grids, fading, the dot budget, the sweep's recharge. |
| EnemyBrain | 21 | The four monster state machines: roaming, hearing and sight (crouched players are not seen), chasing and giving up, the Listener and decoys, the Mimic's disguise and reveal, the Stalker pinned by scans and withdrawing, sleeping when far away, stuns, plus a fuzz test that no monster walks through walls or produces bad numbers. |
| Progression | 8 | Buying upgrades and cosmetics with Static, costs, upgrade effects, level rewards, the daily streak, how much noise each action makes. |
| SaveData | 7 | Loading saves: defaults, migration from version 1, newer versions, hostile or corrupt values clamped or dropped, round trips. |
| Daily | 4 | Daily seeds and calendar keys, week boundaries, the weekly featured anomaly. |
| Simulation | 3 | A headless bot that plays every tier against the real enemy state machines (`tests/Sim.luau`): every tier is completable without deadlock, the run is deterministic, tier one is forgiving. |
| Lore | 9 | The story wiring in `src/shared/data/Lore.luau`: every lit room has three notes that exist (the room layouts have three spots), one tape per hidden recorder, the manual pages, no stray placeholders, the finale on the last note, a floor for every authored tier. |

### Bot simulation helpers

| Command | Prints |
| --- | --- |
| `lune run scripts/simstats 40` | Per-tier clear rate, time and catches over 40 seeds (a Markdown table). |
| `lune run scripts/simcauses 7 40` | For one tier: which monster caught the bot, in which state, while the bot was doing what. |
| `lune run scripts/simtrace` | One run, step by step. |
| `lune run scripts/plandump` | The contents of a level plan. |

The latest `simstats` numbers are in `docs/DESIGN.md`.

### Optional: strict type check

`./scripts/typecheck.sh` type-checks every module against Roblox's API types with
[luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) (`luau-lsp analyze` with a Rojo sourcemap).
It needs `luau-lsp` on your PATH (or `LUAU_LSP=/path/to/luau-lsp`) and downloads Roblox's type
definitions into `build/` the first time. Pass files to check fewer: `./scripts/typecheck.sh
src/client/Hud.luau`.

This is the closest thing to running the client without Studio: it catches missing members,
stale names and wrong argument types, which lint cannot. The v2 client slices were written in
a cloud session without Studio and checked this way; it found one real bug.

It is not part of `check.sh`, because the newer Luau type solver reports some patterns that
are fine at runtime and ran fine in Studio in v1. Treat these as known false positives:

- `Types Part and nil cannot be compared with ==` (and the same for `Beam`, `Frame`).
- `Expected ... '"wall" | "floor" | ...' but got 'string'`: string literals widened to `string`.
- `Expected this to be '{Instance}?' but got '{UIListLayout}'`: an array of mixed instances.
- `Cannot call a value of type {...} in union`: iterating `list or {}`.
- `Value of type 'Model?' could be nil` right after the value was assigned.

Anything else it reports deserves a look.

## Manual checks in Studio

Start with `rojo serve`, connect the Rojo plugin, press Play. The Studio-only dev commands in
the README jump straight to any tier or lit room. Turn on Game Settings > Security > Enable
Studio Access to API Services to test saving; without it profiles live in memory and the game
says so.

### Single player, PC

- [ ] Title: the corridor scans itself, floor and ceiling included. Buttons work; settings
      open and return to the title.
- [ ] Tutorial room: scatter (hold left mouse) lands dots; after about 50 the hint moves on to
      the sweep (right mouse); the sweep draws the whole view top to bottom and recharges; the
      spread ring shows when scrolling; the door shows gold and opens.
- [ ] Hints read as notices and manual rules, with the control in brackets underneath.
- [ ] Tier 1: dots are tiny and permanent, walls invisible, dots show through walls. The floor
      card reads "THE ANNEX" with "B3 / offices after hours". Base says "Floor B3. Counting."
- [ ] A monster: red footprints appear and fade, footsteps sound from them, breath shows near
      its head, the red glow creeps in at the screen edges as it closes in, the heartbeat rises.
- [ ] Crouch (Ctrl or C): the view drops, you slow down, the Pacer loses you.
- [ ] Caught: the catch message names the monster ("Caught by the Pacer."), you wake at the
      level start and Base says something like "Back at the last lamp. Good."
- [ ] A hidden recorder: the progress bar under the crosshair fills, it reveals itself, lights
      up, and the tape types out with the speaker's name.
- [ ] A lantern lights a patch of real floor and wall.
- [ ] A pit (violet hazard dots at the rim): falling in fades to black and puts you back at
      the start. An alarm plate rings a bell and draws monsters.
- [ ] Cells recharge the sweep; the exit door opens with its sound; level-clear card.
- [ ] Each lit room: the right title card, three notes that read correctly, the workbench.
      The Night Desk plays Base's first call once. The guest book at the Falls lists the
      party's names.
- [ ] The Lamp Room: reading page 12 brings Ines, who counts your falls; both choices show
      their end card. "Climb the ladder" returns you to the title with Continue offered;
      "Take the lamp" lets the door lead into a Relay floor.
- [ ] Settings: dot colours, teammates' scans, scan button mode, volume, DOT DETAIL (watch the
      frame rate on high), freeze dots.
- [ ] Workbench: buying each upgrade does what it says (Pulse Radar pulses on its own, Wide
      Lens widens the spread, Wayfinder shows the needle then the map).

### Phone (Studio's device emulator, then a real phone)

- [ ] Nothing overlaps at 705x338: touch buttons (SCAN, SWEEP, RUN, CROUCH, PING, SPREAD,
      SAY), hint panel, dialogue panel, top bar, map. Text is readable (scale about 0.85).
- [ ] Every window fits and long notes scroll.
- [ ] SCAN, RUN and CROUCH toggle; prompts can be tapped.
- [ ] Frame rate with a full screen of dots on DOT DETAIL auto (low on phones).

### Two or more players

- [ ] Teammates' names show through walls; their scans redraw on your screen; their
      footprints are green.
- [ ] Downed and revive; spectating while down; "DOWN" on the name marker.
- [ ] A disguised Echo: it scans green with late dots, it gives off no footprints, breath or
      heartbeat, and only near it does a false "Base?" give directions.
- [ ] One player climbs the ladder, the other takes the lamp: the climber returns to the
      title, the other carries on.

### Published experience only

- [ ] Saving with DataStores across sessions; the session lock when joining a second server.
- [ ] The daily leaderboard with more than one entry.
- [ ] The lobby and reserved-server party flow (`Config.Places.runPlaceId`).
- [ ] Game pass prompt for the Surveyor's Kit (`Config.Monetization`).
