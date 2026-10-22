# Progress

Living log of where the build is. Update it whenever a slice lands, so a fresh session can
pick up from exactly here.

Last updated: 14 Oct 2026. The v2 work is on the pushed branches `claude/project-thread-btlp2q`
and `claude/lucid-noether-kgfglb`; the local branch `claude/project-thread-btlp2q` is now
fast-forwarded to the second and carries the newest commits (not pushed). Nothing is merged
into `main` yet.

**Story places slice (cloud thread, 14 Oct 2026, branch `claude/story-places`, based on
`claude/lucid-noether-kgfglb`):** the lit havens, lamp-bags along the way, scan-to-reveal story
objects, posters, gate items and the secret alcove are written. See "Story places" below. None of
it has been run in Studio. `scripts/check.sh` could not run in full in the cloud (see there).

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
| Docs | `README`, `docs/DESIGN`, `LORE`, `ASSETS`, `TESTING`, `PUBLISHING`, `DECISIONS` | Written (cloud session). `docs/LORE.md` is generated: `lune run scripts/lore > docs/LORE.md`. |
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

### Studio playtest, 14 Oct (merged v2 build, one player, PC)

Verified in Studio: the title screen and its backdrop; Begin into the dark tutorial; scatter
(tiny permanent dots, laser fan), the sweep (grid, recharge bar), the first notice hints; the
radio line on arrival; tiers 1 to 8 all build with their pits, plates, recorders and lanterns
(counts printed per tier); a lantern shows a bag, a bulb and a lit patch of floor and wall in
the dark; a recorder reveals itself (`echo` dev command) with its line and a lit patch; the
red aura at the screen edges when the Pacer is close; being caught, the respawn and the
radio line after it; falling into a pit sends you back to the start with a toast; red
footprints are drawn; the Pacer roams with short pauses; every audio id loads; all five lit
rooms build. No script errors in the output.

Fixed during the playtest: dots were far too large close up (now 0.02 stud base, smaller
near grids, larger budgets); crouching and scattering were silent (now quiet, never silent,
per Vasco's note that a silent crouch can be cheesed); lit rooms were blown out because
the dev command stacked rooms (it now removes the old one) and the ambient was too high.

Not verified: two players, real saves, phone and gamepad, the sweep with Pulse Radar, the
Mimic, the Listener and the Still live, the Lamp Room finale, completing a level through its
exit door by hand, sound itself (loaded but not listened to), the title in 830x400.

Vasco's latest direction (not built yet): havens, the Falls included, become dark spots in
the maze with one object that reveals itself, instead of separate lit rooms; the havens
thread owns that (`claude/story-places`). The lit-room look was therefore not tuned further.

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
- The bible introduces the Still on tier 7; `Tiers.luau` has the Stalker from tier 6.
- Lines not used yet: `note.bunk.letters`, `rev.desk.board`, `rev.falls.hammock`, `rev.bunk.*`,
  `rev.lamp.*` placed as props, `tip.*`, `item.*` other than the gate items. (`rev.desk.mugs` is the
  Night Desk's first note; `rev.falls.behind` is now the Falls' fourth note.)
- Tapes play in story order, one per recorder revealed, but tiers 1 to 4 have one recorder
  each while every floor has three tapes, so some tapes play a floor late (Hollis's Annex
  tape on B4). Recorders 1, 2, 1, 2, ... per tier would line them up; that is a change to
  `Tiers.luau`, so it is left for you.
- Balance, from the bot simulation (`docs/DESIGN.md`, "What to tune first"): tier 7, the only
  tier with two Wanderers, averages about four catches per run against about one elsewhere.

## Story places (cloud thread; not yet seen in Studio)

Everything below is code and data only. It type-checks (`luau-lsp`, no new complaints), formats
(`stylua`), passes the Lune tests (79) and builds with Rojo, but **none of it has been run or
looked at in Studio**. Expect a first round of fixes there: sizes, positions, light ranges.

| Piece | Where | What it does |
| --- | --- | --- |
| Havens | `Tiers.loreRoomAfter`, `Lore.rooms`, `LoreRooms.LAYOUTS`, `StoryKits` | A lit, monster-free break after every level. Odd tiers get a small haven (Copy Room T1, Dry Booth T3, Potting Shed T5, Archive Nook T7: 20 to 22 studs wide, a lamp, a bench, one page); even tiers keep the big rooms (Night Desk, Falls, Bunk Room, Lamp Room). Each is a checkpoint (the existing `enterLore` logic). Base says one line the first time you enter a haven (`radio.haven.1`, `client/Radio`). |
| Secret alcove | `LoreRooms.buildWaterfall`, cistern layout | A niche in the rock behind the Falls (walk through the water sheet): a chalk drawing of the building and a fourth note, `rev.falls.behind`. |
| Lamp-bags | `LevelPlan` (`lamps`, `nooks`), `World.buildLamps` | 2 to 4 per level (`Tiers.lamps`), the first near the start, the rest at even steps along the shortest route, so one is met about every minute. Four variants (`rev.nook.1` to `4`): mug, stool, plain, and a burnt-out one (never on the first two tiers, never the first bag) that is invisible until scanned. Scanning a lit bag says its tag line. |
| Hidden story objects | `data/Places.luau`, `LevelPlan.reveals`, `World.buildReveals`, `StoryKits` | Two per tier from tier 1 to 8 (one on tier 6): desk lamp, whiteboard, kettle and tea bags, coat, headphones, valve station, dinghy, life ring, grow light, tap-code plate, camp stove, chalk arrows, camera, cornerstone. Invisible; scanned enough (`Config.Lidar.echoRevealHits` dots) they appear, light their corner (glow colour and radius from the story text) and say their lines through `Hud.dialogue`. They count on the HUD as `HIDDEN n/m` (was RECORDERS). |
| Posters and stencils | `Places.tiers[n].signs`, `Props.sign`, `World.buildSigns` | The story's `sign.*` and `rule.09`, as paper on a wall with the text printed on it. Hidden like the objects; scanned, they get a small light of their own and also say their text. `at` puts a sign at the start, the exit, a pit, a plate, or anywhere. A sign for a trap the level lacks is left out. |
| Gate items | `Tiers.gate`, `World.buildGateItem`, `World.gate` | The key objective is the story's item per tier: fuse (T2), valve wheel (T3), rope (T4), crank (T5), fuse (T6), lamp core (T7), brass key (T8 and endless). Tiers 2, 3 and 5 now have locked exits (they were open); tier 1 stays open. `State.server.gateName` carries the name; the HUD says "FUSE NEEDED". |
| Dark havens | `Lore.Room.dark`, `LoreRooms.darken/buildDetail`, `Director.onReveal`, `client/Atmosphere` | Per Vasco (14 Oct): the havens (Copy Room, Night Desk, Dry Booth, Falls, Potting Shed, Bunk Room, Archive Nook) are not lit rooms any more. They are still a separate chamber after each level, but built in the dark like the maze: every part draws nothing and every light is off, until the room's one standout object (its lamp, or the waterfall in the Falls) is scanned `echoRevealHits` dots (echo id 60, `LoreRooms.BEACON_ID`). Then the parts within `LAMP_REACH` (22 studs; `FALLS_REACH` 48) of it come back, with their lights, and the title card shows. The Lamp Room (finale) and the Relay landing stay lit. Not yet done: haven inside the maze itself (the alternative: place the beacon in a maze dead end and skip the chamber). Each room also gets a detailed floor and walls (`buildDetail`: tiles, stains, puddles, cracks, rubble, paper or roots, footprints toward the exit; wall streaks, soaks, claw marks, handprints, peeling, pipe, cables), so the lit patch around the object says where you are. Check in Studio: part count, dot hits on the detail, the 60 echo id on a client that scans a level object with the same id, flicker tube staying off while dark. |
| Hidden things in code | `World.Echo.kind` | `recorder`, `reveal`, `sign`, `nook` share one pipeline (the old recorder one): a tag, an `EchoId`, the client's dot count, the `Reveal` remote, `World.revealEcho`. Ids run in that order. A recorder still plays the next tape; the others say their own lines (empty speaker). |

Placeholders and open points:

- No placeholder lines: every line comes from `LoreText`. The copy of `LoreText.luau` in
  `src/shared/data` is the story thread's newer one (adds `*.haven.*`, `rev.nook.*`,
  `radio.haven.1`); `docs/story` is synced from `/mnt/project-files/lidar-game/story` too.
- Not built: `rev.desk.board`, `rev.falls.hammock`, `rev.bunk.*` and `rev.lamp.postcard` as props
  (the lit rooms read their notes at prompts instead); the Bunk Room's model that lights per
  floor; the Falls guest book already signs in whoever is there. Items other than the gates
  (chalk, tea, photographs, glow stick, flash bulb, map) have no pickups yet.
- Tier 8's exit is still locked (the story says "no gate"); it uses the brass key.
- Things to look at first in Studio: (1) a poster's text rendering on a transparent part and its
  `SurfaceGui` light; (2) each reveal kit's size and facing against a wall (`lookAt` convention in
  `Props`); (3) the niche behind the Falls; walking through the water sheet; (4) small havens'
  doors, prompts and the `LitZone` size; (5) dead lamp-bags appearing on scan; (6) the number of
  gold dots from reveal objects on the HUD; (7) light ranges (`GLOW_RANGE_PER_RADIUS` in `World`).
- Dev commands (`src/server/Dev.luau`): `lore copyroom`, `lore drybooth`, `lore pottingshed`,
  `lore archivenook` to visit a haven; `echo` reveals the next hidden thing in order; `lights on`
  to see the layout of a level; `tier N`.

How this slice was checked without Studio: `stylua --check`, `lune run tests/run` (79 passing,
including new tests for lamp-bag spread and variants, and for every sign and hidden object
resolving to story text), `rojo build`, and `luau-lsp analyze` against Roblox's types
(`scripts/typecheck.sh`), which reports nothing new. `selene` could not run in the cloud (it needs
Roblox's API dump from the internet); run `scripts/check.sh` on the PC before merging.

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
- Not yet verified for v2: anything in Studio (including the story places slice above).
- Never verified: two players at once, real DataStore saves, phone or gamepad hardware.

## Immersion and transitions (22 Oct, cloud thread; nothing seen in Studio)
- Restart bug: the client only wiped dots and marks when the tier or seed changed, so a restart
  landing on the same tier and seed (the daily level, a haven left for the title) kept the old
  picture. The server now sends `epoch` (bumped in `beginLevel`, `enterLore`, `endRunIfEmpty` and
  the finale's return to the title) and `State` treats an epoch change as a new level.
- `client/Immersion` (new): exit fades to black over 2.4 s with the sound dulled (lowpass on the
  Lidar sound group), the next place comes up over 2.2 s with a low hit (haven: soft falling
  phrase); a 9 s timeout lifts a black that never ends. Each floor has a mood: colour grade
  (`Atmosphere.setTint`), ambience pitch, drip level and reverb (`Audio.setMood`; lit rooms use a
  living-room reverb). The view narrows up to 7 degrees as a monster closes in.
- Check in Studio: that the fade covers the teleport, the title card still shows after the
  fade-in, tint strength, reverb not too wet, FOV narrowing not nauseating, `Hud.fade` shared with
  the caught flash.
- Second pass (22 Oct): `Immersion` also does (a) found points of interest (`Lidar.onPoi`, objective
  dots) pulse a rising gold ring and a faint tone every 2.6 s while within 90 studs (nearest 5);
  (b) distant wrong sounds (`Audio.wrong`: door slam, running steps, tick crackle, bump) from a
  random bearing 35-70 studs away, every 22-45 s, 6-12 s when a monster is near; (c) point and spot
  lights within 45 studs stutter and cut out as threat rises (re-collected every 4 s); (d) 3% of
  the local scan's dots flare at 2.6x size for 0.3 s as they land. Not built: the walkable
  stairwell between levels (needs a new member stage and a corridor model; best done with Studio).
- Level start dark (22 Oct, Vasco): lanterns, lamp-bags and the floor/wall patches around them
  (the level's `Lit` model) were visible from the start. `Immersion.concealLevelLights` now hides
  them on arrival (1 s and 3 s, while the level streams in) and `Lidar.onSeen` brings back
  everything within 16 studs of a part the local gun lands on, with its lights. Client only;
  a teammate's scan reveals them for you too (relayed rays go through `Lidar.onSeen`). Revealed recorders still light up as before.

## Stairwell between places (22 Oct, cloud thread; nothing seen in Studio)
- `server/Passage.luau` builds a 7-wide flight of 28 steps (0.9 drop, 2.6 run) with landings, side
  and end walls and a sloped ceiling at (0, 0, -1500), all invisible like the maze, with one dim
  warm lamp (objective-tagged, so a scan shows it gold) on the end wall at the bottom.
- `Director.walkPassage(next)`: after a level's exit (and after a haven's "Continue") the party
  gets stage `passage`, is placed at the top, and walks down. Someone reaching the bottom (5 studs
  of `endPosition`) sends the "exit" objective (client fades to black, sound dulls), then after
  `transitionSeconds` `next()` builds the haven or the next level and everyone is carried on.
  A 150 s cap carries on a party that never reaches the bottom; `endRunIfEmpty` frees the model.
  Late joiners wait (phase stays `transition`).
- New stage `passage`: Lidar, Viewmodel, Presence and Immersion accept it; Immersion gives it a
  cave reverb. No enemies or hazards run there.
- Check in Studio: stairs climbable at 0.9 rise (the Humanoid should step them), nobody stuck on
  the top landing, the lamp visible from the stairs, the bottom trigger firing, leaving mid-walk,
  two players with one far behind, the 3 s black at the end of the walk.
- Doorways (22 Oct, Vasco: "there's still the exit door"): the level exit and the haven's way on
  are open doorways now. `Director.watchDoorway` polls who stands within 2.5 studs in front of the
  door panel; walking in starts the leave (no prompt). A locked level exit toasts at most every
  4 s. The level door lost its handle and no longer collides; the haven's exit panel is a black
  gap that does not collide. The step through takes 1 s (`DOORWAY_LEAVE_SECONDS`, also the wait
  at the bottom of the stairwell) and the client fade-out is 0.8 s.
- Red aura with no monster near (Vasco): the aura, heartbeat, sting, FOV narrowing and light
  flicker used the straight line, so a monster in the next corridor through a wall counted as
  close. `client/Reach.distance` now uses the walk through the maze (BFS over open sides from the
  player's cell, cached per cell); same or next cell keeps the straight line.
- Lamp patches (Vasco): a lamp lit the floor and every closed wall of its cell with hard edges.
  `World.buildPatch` now paints the floor and only the wall nearest the light, each as an
  invisible part with a lit SurfaceGui (CanvasGroup + two UIGradients) that fades to nothing at
  the edges and up the wall. Client concealment also switches these SurfaceGuis. Check the
  look in Studio (PixelsPerStud 6, fade stops in `PATCH_EDGE_FADE`/`PATCH_WALL_FADE`).
- Light stutter (Vasco: pulses did not sync with sound): the continuous sine flicker is gone.
  Near a monster, one nearby light at a time stutters (off/on pattern, 0.8-4 s apart by threat)
  and every cut and catch plays `Audio.spark` from that bulb. Also fixed: the light refresh
  could record a dimmed brightness as the light's base.
