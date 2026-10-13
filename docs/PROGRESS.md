# Progress

Living log of where the build is. Update it whenever a slice lands, so a fresh session can
pick up from exactly here.

Last updated: 13 Oct 2026, during the v2 rework (branch `claude/project-thread-btlp2q`,
local only, nothing pushed).

## Where things stand

v1 (commits up to `41db249` on `main`) is a complete, playable loop that was verified in
Studio: title, tutorial, tiers, lore rooms, bench, saves in memory. Vasco playtested it with
a friend and asked for a rework ("v2"). The feedback, in short:

- Dots tiny, dim, very many, fast, and permanent. Dots show through walls. Bigger spread.
- Right click is a top-to-bottom sweep, not a focus beam. Add a crouch.
- Monsters roam instead of lingering; they are sensed (footprints, mist, a red aura, sound)
  rather than tracked as silhouettes. Much scarier atmosphere.
- Teammates are easy to find and their dots stay.
- Blue water, lanterns that light a patch of real floor and wall, hidden objects that reveal
  themselves and a line of story when scanned enough, pits and traps, a lit waterfall room.
- More adventure than puzzle. A later "pulse radar" upgrade.

### v2 status by slice

| Slice | Files | State |
| --- | --- | --- |
| Rules and data | `src/shared/**`, `tests/**` | Done. `lune run tests/run` passes (67). |
| Server | `src/server/**` | Written, linted. Not yet run in Studio. |
| Client core | `State`, `Dots`, `Lidar`, `Main.client` | Written (`913c1ec`). Not yet run in Studio. |
| Client controls and menus | `Input`, `Avatar`, `Viewmodel`, `Atmosphere`, `Ui`, `Menus`, `Title` | Written (cloud session), type-checked. Not yet run in Studio. |
| Client presence and sound | `Audio`, `Presence` (new), `Effects` | Written (cloud session), type-checked. Not yet run in Studio. |
| Client HUD and teaching | `Hud`, `Tutorial` | Written (cloud session), type-checked. Not yet run in Studio. |
| Docs | `README`, `docs/DESIGN`, `LORE`, `ASSETS`, `TESTING`, `PUBLISHING`, `DECISIONS` | In progress (helper E). |
| Integration and playtest | everything | Not started. Main session only (Studio). |

All client slices are now written to the contracts below, so the place should run again; it
has not been opened in Studio since the rework, so expect a round of fixes there.

How the cloud session checked the client without Studio: `scripts/check.sh` (format, lint,
Lune tests, Rojo build) plus a strict type check with `luau-lsp analyze` against Roblox's
type definitions and a Rojo sourcemap. That catches missing members and stale names (it
found one); it cannot catch anything that only shows at runtime. Its remaining complaints are
known false positives of the newer Luau solver (string literals widened to `string`, mixed
instance arrays, `Part == nil` comparisons), which v1 code had too and ran fine.

Choices made while writing the client slices, beyond the contracts:

- Touch layout: SCAN, SWEEP, RUN, CROUCH, PING, SPREAD and SAY round the bottom-right
  corner; RUN and CROUCH always toggle on touch, SCAN follows the scan-mode setting. The
  hint panel is 360 wide so it clears the buttons on a phone.
- `Menus.applyCosmetics` also applies the dot budget (`Dots.setBudget`) from the new DOT
  DETAIL setting and the Phosphor level; `Menus.dotQuality()` resolves "auto" (phones low,
  everything else medium).
- A Mimic that is still disguised gives nothing away: no footprints, breath, aura, heartbeat
  or breathing loop (`Audio.nearestEnemy` skips it).
- Hints in `Tutorial` are lines from the story text (`LoreText`), with the device's control
  in brackets underneath: the story bible's "never lecture" rule, kept usable on every device.

Merged in from the cloud session (branch `claude/lucid-noether-kgfglb`, based on v1):

- Phone layout: `Ui` lays out for 830x400 with a minimum scale of 0.8 (a 705x338 phone now
  scales to about 0.85 instead of 0.55), every `Menus` window fits 800x380 and long text
  scrolls, the `Hud` top bar no longer overlaps at 830 wide. Not yet seen in Studio.
- Title backdrop pitches 25 degrees so dots reach the floor and ceiling. Not yet seen.
- `scripts/check.sh` is executable in git, so the CI workflow can run it.

### What is left after the slices land

1. Main session merges, runs `scripts/check.sh`, fixes whatever the linter and Studio find.
2. Studio playtest with the Dev commands (see `src/server/Dev.luau`): tiers 1 to 8, every
   lore room, recorders, pits, plates, lanterns, crouch, sweep, radar, phone layout.
3. Things never yet run by anyone: two real players together, real DataStore saves,
   the daily board with more than one entry.
4. Story text: done, see "Story in the build" below. What is left is the part of the story
   that needs new objects in the maze (see its open items).
5. Report to Vasco, then ask before pushing.

## Story in the build

The story thread's text ("The Understory", `docs/story/`) is now the game's text.
`src/shared/data/Lore.luau` no longer holds prose: it builds every note, tape, page and card
from `LoreText.luau` at load time, so regenerating `LoreText.luau` with the story thread's
`build_text.py` updates the game. `tests/LoreTests.luau` checks the wiring (every room has
three real notes, one tape per recorder, no stray placeholders, the finale on the last note).

| In the game | From the story |
| --- | --- |
| Lit rooms (ids unchanged) | office = The Night Desk, cistern = The Falls, breakroom = The Bunk Room, stairwell = The Lamp Room, landing = Relay Floor. Three notes each (the layouts have three spots). |
| Tier names and level cards | Two tiers to a floor: B3 The Annex, B4 The Flooded Wing, B5 The Overgrowth, B6 The Foundation; endless tiers are "Relay Floor N"; the daily is "Tonight's floor". |
| Maze recorders (12) | `rec.*`, three per floor, in story order, each with its own speaker. |
| Survey plates | The manual's pages 1 to 11 with the crew's margin notes; page 12 is in the Lamp Room. |
| Monster names | the Pacer, the Hush, the Echo, the Still (field guide shows the manual page, then the plain rule). |
| Radio (`client/Radio`, new) | Base reports on a new floor, after a catch, on a clear, at the Night Desk, now and then in the dark. Near a disguised Echo a false "Base?" gives directions; real Base never does. Nothing says so. |
| Tutorial hints | Staff notices and manual rules, with the control in brackets. |
| Finale | After page 12, Ines speaks (she counts your falls) and asks: climb the ladder or take the lamp. Each has its end card. "Take the lamp" carries on into the Relay as before; "Climb the ladder" ends that player's run and returns them to the title with their checkpoint kept (new `Choose` remote, validated and rate limited, accepted once). |

Open items, for Vasco to decide (not filled in):

- "Night Shift +": the bible says the run after climbing the ladder is harder. How much
  harder is not written anywhere, so climbing currently just returns you to the title.
- The story's objects in the maze: reveal objects (`rev.*`), lamp-bags, posters and signs
  (`sign.*`), the floor items and gates (fuse, valve wheel, rope, crank, lamp core), the
  secret alcove behind the Falls. They need world props and placement rules; the text exists.
- The bible introduces the Still on tier 7; `Tiers.luau` has the Stalker from tier 6.
- Lines not used yet: `note.bunk.letters`, `rev.desk.board`, `rev.falls.*`, `tip.*`, `item.*`.

## v2 design in one page

- The maze is **invisible**. Every maze part has `Transparency = 1` but still stops rays
  and feet. The only picture of a level is the dots, and dots show through walls.
- **Dots** are tiny Neon cubes, coloured by what they hit: wall, floor, ceiling, water
  (blue), friend (green), enemy (red), objective (gold), hazard (violet). World dots are
  permanent up to a budget (oldest reused first); friend and enemy dots fade in seconds.
  Dots are not stacked: one per grid cell, with a finer grid for close surfaces and items.
- **Left click** scatters a fast stream of dots in a cone. The **scroll wheel** narrows or
  widens the cone. Scattering is silent to monsters.
- **Right click** fires one **sweep**: a line of rays that travels top to bottom and draws a
  whole grid. It is loud (monsters hear it) and then recharges.
- **Crouch** makes you slow, silent, and unseen by monsters (they only see upright
  players). Wading through water is still heard.
- **Monsters are invisible** and roam the whole maze with short pauses. A scan only marks
  them with a few red dots that fade fast. You sense them by red footprints, breath mist,
  a red glow at the edges of the screen, and sound.
- **Lanterns** are real lights with a visible patch of floor and wall. **Recorders** are
  hidden objects: put enough dots on one and it shows itself, lights its corner, and plays
  the next line of the story. **Pits** drop you back to the level start. **Alarm plates**
  call everything nearby. Pit rims and plates scan violet.
- **The Cistern** is a lit waterfall room after tier 4.
- **Pulse Radar** is a bench upgrade: a ring of dots pulses out on its own every few seconds.

## Module contracts (client)

All client modules live in `src/client`. Each owner edits only their own files; if you need
something from another module that is not listed here, say so in your hand-back instead of
editing it. Everything tunable lives in `src/shared/Config.luau`.

### Facts every module can rely on

- Tags (`Config.Tags`): `friend`, `enemy`, `objective`, `hazard`, `water`, `echo`,
  `litZone`, `disguised`, `rescue`, `anomaly`, `sound`.
- Monsters: a Model tagged `enemy`, invisible, `PrimaryPart` named `Root` sitting on the
  floor at the monster's position (moved by the server about 15 times a second).
  Attributes: `Kind` (`"wanderer" | "listener" | "mimic" | "stalker"`), `Moving`, `Frozen`.
  A Mimic that is still pretending also has the `disguised` tag.
- Players' characters are tagged `friend`. Attributes: `Downed` (boolean), `Revive` (0..1).
- Stranded surveyors are Models tagged `rescue` (and `friend`).
- Server-made looping sounds are tagged `sound`.
- Remotes are listed in `src/shared/Net.luau`. New in v2: `Reveal` (client to server),
  `Echo (echoId, position, speaker, line)` and `Hazard (kind, position, userId)` with kind
  `"plate"` or `"pit"` (server to client). `ScanState` and `ScanRelay` changed shape.
- `State.server` (see `State.luau`) now has `sweepScale`, `echoes`, `echoesTotal`
  (`heatScale` is gone). `State.effects` is `Progression.Effects`: `sweepRechargeMul`,
  `shutterLevel`, `phosphorLevel`, `wideLens`, `radarLevel`, `pingLifetime`, `decoy`,
  `wayfinder`, `solesLevel`.
- `State.profile.settings` has `dotQuality` (`"auto" | "low" | "medium" | "high"`).

### `Dots` (main session)

```lua
Dots.spawned: number                      -- total dots ever landed this session
Dots.setPalette(name: string, wallTint: { number }?)
Dots.color(kind: DotRules.DotKind): Color3
Dots.folder(): Folder                     -- one stable folder holding every dot (exclude it from rays)
Dots.liveCount(): number
Dots.setBudget(count: number)             -- permanent-dot budget (see DotRules.budget)
Dots.add(position: Vector3, kind: DotRules.DotKind, distance: number): boolean
    -- Lands a dot. World kinds are permanent and packed one per grid cell (returns false
    -- when that cell already has one). "friend" and "enemy" fade on their own.
Dots.addLate(position: Vector3, kind: DotRules.DotKind, distance: number, delay: number)
Dots.mark(position: Vector3, kind: DotRules.DotKind, size: number, lifetime: number)
    -- A fading dot with an explicit size (studs) and lifetime (seconds): footprints,
    -- trails, rings. Never permanent, never packed.
Dots.setFrozen(value: boolean)
Dots.isFrozen(): boolean
Dots.clear()
Dots.start()
```

### `Lidar` (main session)

```lua
Lidar.enabled: boolean      -- set by Main: false on the title screen
Lidar.firing: boolean       -- the scatter stream is producing dots this frame
Lidar.sweeping: boolean     -- a sweep is travelling down the screen right now
Lidar.charge: number        -- 0..1; the sweep can fire at 1
Lidar.spread: number        -- cone half-angle in degrees (Config.Lidar.coneMinDeg .. max)
Lidar.echoProgress: number  -- 0..1 progress on the hidden recorder being scanned; 0 when none
Lidar.ignore(instance: Instance)                       -- never hit this with rays
Lidar.onBatch(listener: (count: number, meanDistance: number, enemy: boolean, friend: boolean, objective: boolean) -> ())
Lidar.onSweep(listener: () -> ())                      -- the local player's sweep fired
Lidar.onRadar(listener: () -> ())                      -- the Pulse Radar fired
Lidar.recharge()                                       -- a battery cell: sweep is ready now
Lidar.cast(look: CFrame, count: number, halfAngleDeg: number, params: RaycastParams)
    -- Rays from anywhere, no sound, no reporting: the title screen's backdrop.
Lidar.start()
```

Lidar reads `Input.firing`, `Input.crouching` and the actions `"sweep"`, `"spreadIn"`,
`"spreadOut"`, `"spreadCycle"`.

### `Input` (helper B)

```lua
Input.firing: boolean       -- held: left mouse, RT, touch SCAN (toggle on touch as in v1)
Input.sprinting: boolean    -- held: Left Shift, L3 (toggle), touch RUN
Input.crouching: boolean    -- Left Ctrl (hold), C (toggle), gamepad B (toggle), touch CROUCH (toggle)
Input.device: "keyboard" | "gamepad" | "touch"
Input.hint(action: string): string   -- actions: fire, sweep, spread, crouch, sprint, ping, interact
Input.onAction(name: string, listener: () -> ())
    -- one-shot actions: "sweep" (right mouse, F, LT, touch SWEEP), "spreadIn" (wheel up, Z,
    -- LB: narrower), "spreadOut" (wheel down, X, RB: wider), "spreadCycle" (touch SPREAD),
    -- "ping", "photo", "emote", "map"
Input.releaseAll()
Input.menuChanged()
Input.start()
```

Sprinting cancels crouching and crouching cancels sprinting. The v1 `focusing` field and the
`"lens"` action are gone.

### `Avatar` (helper B)

```lua
Avatar.wading: boolean
Avatar.moving: boolean
Avatar.crouching: boolean   -- crouch is actually applied (not downed, not in a lit room, no menu)
Avatar.start()
```

### `Hud` (helper D)

v1 API unchanged (`toast`, `titleCard`, `hint`, `fade`, `setVisible`, `photoNotice`,
`toggleMap`, `start`), plus:

```lua
Hud.dialogue(speaker: string, line: string)   -- a recorder speaks: typed out, then fades; queues
Hud.setAura(level: number)                    -- 0..1 red glow at the screen edges; called every frame
Hud.flash(color: Color3, seconds: number)     -- a quick full-screen tint that fades out
```

Hud reads `Lidar.charge`, `Lidar.sweeping`, `Lidar.spread`, `Lidar.echoProgress`,
`Avatar.crouching`, `State.server.echoes / echoesTotal`.

### `Audio` (helper C)

v1 API kept (`blip`, `sequence`, `click`, `pickup`, `levelCleared`, `relief`, `caught`,
`setLit`, `threat`, `start`) except `overheat`, which is gone. New:

```lua
Audio.nearestEnemy(): number                      -- studs to the nearest monster; math.huge when none
Audio.monsterStep(kind: string, position: Vector3) -- Presence calls this for each monster footprint
Audio.alarm(position: Vector3)                    -- an alarm plate went off there
Audio.fall()                                      -- the local player fell into a pit
Audio.echo(position: Vector3)                     -- a recorder revealed itself there
Audio.door()                                      -- the exit opened
```

Audio hooks `Lidar.onBatch`, `Lidar.onSweep` and `Lidar.onRadar` itself.

### `Presence` (helper C, new file)

```lua
Presence.start()
```

Footprints for monsters (red) and players (green), breath mist near monsters, the red aura
(`Hud.setAura`), and name markers over teammates that show through walls.

### `Effects` (helper C)

`Effects.pulse(strength, seconds)` and `Effects.start()` as in v1. Handles the `Caught`,
`Revived`, `PingMarker`, `EmoteShown`, `Objective`, `Echo` and `Hazard` remotes.

### `Menus`, `Ui`, `Title`, `Viewmodel`, `Atmosphere` (helper B), `Tutorial` (helper D)

Same entry points as v1 (`X.start()`, `Menus.open/close/isOpen/applyCosmetics`,
`Atmosphere.onZone/zone/forceDark/lit`, the `Ui` helpers).

## Verification

Only what has actually been run is listed as verified.

- Verified: the pure rules under Lune (67 tests, including a bot that plays every tier).
- Verified in Studio (v1 only, before the rework): the whole loop for one player on PC.
- Not yet verified for v2: anything in Studio.
- Never verified: two players at once, real DataStore saves, phone or gamepad hardware.
