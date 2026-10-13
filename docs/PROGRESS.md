# Progress

Last updated 13 October 2026. Work stopped mid-polish when the usage limit was reached.

## Done and checked

- **Tooling.** Rojo project, Rokit pins, StyLua and Selene pass, `rojo build` works.
- **Pure logic** (`src/shared/pure`, `src/shared/data`): maze generator, level plans, four enemy
  state machines, progression, saves with migration, daily seeds. 62 Lune tests pass
  (`lune run tests/run`), including 10,000 maze seeds and a wall-crossing fuzz test.
- **Headless bot simulation** (`tests/Sim.luau`, `lune run scripts/simstats 40`). Latest run,
  40 seeds per tier, 900 simulated seconds allowed:

| Tier | Clear rate | Mean time to clear (s) | Mean catches per run | Deadlocks |
| --- | --- | --- | --- | --- |
| 1 | 100% | 33 | 0.00 | 0 |
| 2 | 100% | 36 | 0.00 | 0 |
| 3 | 100% | 74 | 0.05 | 0 |
| 4 | 100% | 102 | 0.12 | 0 |
| 5 | 100% | 94 | 0.35 | 0 |
| 6 | 100% | 87 | 0.15 | 0 |
| 7 | 98% | 131 | 0.57 | 0 |
| 8 | 90% | 194 | 1.95 | 0 |
| 9 | 88% | 213 | 2.00 | 0 |
| 10 | 92% | 251 | 1.57 | 0 |
| 11 | 98% | 292 | 2.85 | 0 |

- **Played in Studio through the Studio MCP link** (one player, PC input): title screen,
  tutorial room, tiers 1 to 3 and 5, being caught and respawning, cell and surveyor pickups,
  exit doors, the office lore room, the workbench (buying upgrades), the Mimic's disguise and
  reveal. About 58 fps while scanning; server and client logs clean apart from the expected
  DataStore warning (API access is off in Studio, so saves fall back to memory).

## Written but not yet run in Studio

- Listener and Stalker in a live level (their logic is covered by tests and the simulation).
- Daily survey mode and its leaderboard, the ending card, endless tiers.
- Wayfinder needle and map, pings and decoys, emotes, photo mode, settings screen.
- Mirror and upside-down anomaly rooms. The bloom room ran but drew too few dots; a fix is
  committed and not re-checked.
- The rescued surveyor's green trail to the exit (ran, but not seen on screen).
- Everything co-op: downed and revive, shared scans, spectating. Needs two players.
- DataStore saving with API access on, and the reserved-server party flow (`server/Party`).
- Audio: every clip loads, nobody has listened to it.

## Known problems

- **Phone layout is too small.** On a 705x338 viewport the interface scales to 0.55 and text
  is about 7 px. Plan: lay out for 830x400 with a minimum scale of 0.8 (`client/Ui.luau`) and
  shrink the windows in `client/Menus.luau` to fit 800x380.
- The title scene scans a flat horizontal band; it should sweep floor and ceiling too.
- No frame-rate measurement at the full 3,000 dots, and none on a real phone.
- `scripts/check.sh` has not been run end to end since the server and client were added.

## Not started

- `docs/DESIGN.md`, `LORE.md`, `ASSETS.md`, `TESTING.md`, `PUBLISHING.md`; `DECISIONS.md` is
  out of date. The story bible exists only as data in `src/shared/data/Lore.luau`.
- Static review write-up of remotes and DataStore calls.

## Studio playtest shortcuts

While playing in Studio, run on the server from the command bar:

```lua
workspace:SetAttribute("DevCommand", "tier 6") -- also: "lore office", "clear", "static 500", "lights on"
```

See `src/server/Dev.luau`. These do nothing outside Studio.
