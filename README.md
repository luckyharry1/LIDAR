# LIDAR

LIDAR is a co-op horror maze for Roblox. It is a Rojo project written in Luau.

- The maze is pitch black and generated from a seed. Its walls are invisible.
- You see it only by scanning. A LIDAR gun leaves small glowing dots on whatever its rays hit, and those dots are the only map you get.
- Up to 4 players explore together. Monsters roam the maze. You do not see them. You see the red marks, footprints and breath they leave, and you hear them.
- Every two levels there is a lit safe room with a piece of the story, a checkpoint and a workbench where upgrades are bought with a currency called Static.

## Status

The game is in the middle of a rework called v2. `docs/PROGRESS.md` is the source of truth for what is finished, what has actually been run and what has not. Read it first.

Nothing has been published to Roblox, and the working branch has not been pushed.

## What you need

| Tool | Version | What it is for |
| --- | --- | --- |
| [Rokit](https://github.com/rojo-rbx/rokit) | any | Installs the four pinned tools below from `rokit.toml` |
| Rojo | 7.7.1 | Syncs `src/` into Studio and builds the place file |
| Lune | 0.8.9 | Runs the tests and helper scripts outside Roblox |
| StyLua | 0.20.0 | Format check |
| Selene | 0.27.1 | Lint |
| Roblox Studio | current | Runs the game |
| Rojo plugin for Studio | one that pairs with Rojo 7 | Connects Studio to `rojo serve` |

## Run it

1. Install the tools: `rokit install`
2. Start the sync server: `rojo serve`
3. In Roblox Studio open a place. A new Baseplate is fine: the server removes the Baseplate and the SpawnLocation when the game starts and turns all the lighting off.
4. Open the Rojo plugin and press Connect.
5. Press Play.

To build a place file instead of syncing: `rojo build -o build/LIDAR.rbxl`. The `build/` folder is ignored by git.

`default.project.json` decides where the code goes in the place:

| Folder | Goes to |
| --- | --- |
| `src/shared` | `ReplicatedStorage.Shared` |
| `src/server` | `ServerScriptService.Server` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |

The same file switches off `Players.CharacterAutoLoads` and `Workspace.StreamingEnabled` and sets the Lighting service to black. Keep those settings.

Saving in Studio only works when Studio has access to API services (see `docs/PUBLISHING.md`). Without it the game keeps each profile in memory for the session and tells the player so.

## Run the checks

| Command | What it does |
| --- | --- |
| `./scripts/check.sh` | Everything: `stylua --check src tests`, `selene src tests`, `lune run tests/run`, then `rojo build -o build/LIDAR.rbxl` |
| `lune run tests/run` | Only the unit tests and the bot simulation |

The GitHub workflow in `.github/workflows/check.yml` runs `./scripts/check.sh` on every push and pull request.

`docs/TESTING.md` explains what the tests cover and gives a manual checklist for Studio.

## Controls

These come from the Input contract in `docs/PROGRESS.md`.

| Action | Mouse and keyboard | Gamepad | Touch |
| --- | --- | --- | --- |
| Scatter dots (hold) | Left mouse button | RT | SCAN button (a toggle) |
| Sweep (one shot, then it recharges) | Right mouse button or F | LT | SWEEP button |
| Narrow the spread | Scroll wheel up or Z | LB | SPREAD button cycles through the widths |
| Widen the spread | Scroll wheel down or X | RB | SPREAD button cycles through the widths |
| Crouch | Left Ctrl (hold) or C (toggle) | B (toggle) | CROUCH button (toggle) |
| Sprint | Left Shift (hold) | L3 (toggle) | RUN button |
| Interact with a door, pickup, note or the workbench | E | X | The on-screen prompt |

Things to know:

- Sprinting cancels crouching, and crouching cancels sprinting.
- Jumping is disabled in the maze.
- Ping, emote, photo and map are also actions in the Input contract, but the contract does not fix their keys. Look in `src/client/Input.luau` once the v2 client has landed.

## Dev commands (Studio only)

`src/server/Dev.luau` adds playtest shortcuts. They do nothing outside Studio. While the game is running, switch Studio to the server view and type this in the command bar:

```lua
workspace:SetAttribute("DevCommand", "tier 6")
```

| Command text | What it does |
| --- | --- |
| `tier 6` | Jumps everyone to that tier. Players still on the title screen or in the tutorial are pulled in. |
| `lore office` | Sends everyone to a lit room. The room ids are the keys of `Lore.rooms` in `src/shared/data/Lore.luau`. `Dev.luau` lists `office`, `cistern`, `breakroom`, `stairwell` and `landing`. |
| `echo` | Reveals the next hidden recorder on the level, as if the first player in the level had scanned it. That player is moved to it. |
| `clear` | Finishes the current level. |
| `static 500` | Gives everyone that much Static. |
| `lights on` | Lights the maze so you can inspect it. `lights off` puts it back. |

## Repo layout

```
default.project.json      Rojo project: where each src folder goes in the place
rokit.toml                pinned tool versions
selene.toml, stylua.toml  lint and format settings
scripts/check.sh          runs every check
scripts/*.luau            Lune helpers: bot statistics, bot traces, level dumps
src/shared/Config.luau    every tunable number
src/shared/Net.luau       the names of the remotes
src/shared/data/          content tables: tiers, monsters, upgrades, story text
src/shared/pure/          the game rules, with no Roblox dependencies, so Lune can test them
src/server/               the authoritative game: flow, world building, monsters, saves, telemetry
src/client/               scanner, dots, HUD, menus and audio
tests/                    Lune test suites and the headless bot simulation
docs/                     documentation (see below)
docs/story/               the story bible and the full line list, owned by the story thread
build/                    build output, ignored by git
```

The server modules, in the order a reader should meet them:

| File | Job |
| --- | --- |
| `Main.server.luau` | Entry point. Makes the world dark, then starts the services. |
| `Director.luau` | The game flow: title, tutorial, levels, lit rooms, catches, revives, rewards. The only module that changes profiles. |
| `World.luau` | Turns a level plan into invisible maze parts, pickups, lanterns, recorders, pits and plates. |
| `Props.luau`, `Figures.luau`, `Build.luau` | Furniture kits, monster and surveyor shapes, and the part helpers they share. |
| `Enemies.luau` | Steps the monster state machines and moves their models. |
| `LoreRooms.luau`, `TutorialRoom.luau` | The lit rooms and the first dark room a new player stands in. |
| `Remotes.luau` | Creates every remote. Validates and rate limits everything a client sends. |
| `Data.luau`, `Leaderboard.luau` | Profile saves and the daily leaderboard, both on DataStores with an in-memory fallback. |
| `Telemetry.luau` | Analytics events for the Creator Hub. |
| `Party.luau` | The optional lobby and reserved-server flow. |
| `Dev.luau` | The Studio-only commands above. |

## More documentation

| File | What is in it |
| --- | --- |
| `docs/PROGRESS.md` | Where the build stands, the client module contracts, and the honest list of what has been verified |
| `docs/DESIGN.md` | The design: loops, scanner rules, monsters, hazards, tiers, co-op, economy, and what to tune first |
| `docs/DECISIONS.md` | The decision log, with the reason and the cost of each decision |
| `docs/LORE.md` | A short guide to the story and how the game delivers it |
| `docs/story/` | The full story bible and every line of in-game text |
| `docs/ASSETS.md` | Every asset the game uses and where it comes from |
| `docs/TESTING.md` | What the automated tests cover, and a manual checklist for Studio |
| `docs/PUBLISHING.md` | The owner's checklist for publishing |
