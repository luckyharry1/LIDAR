# Sections v2: the Levels, the camps and what each light shows

Pivot 2026-10-22. Tier numbers follow build-prompt.md (8 tiers + endless). Ids refer to `03-ingame-text.md`. Replaces v1 (`v1/02-sections.md`).

## Route at a glance

| Tier | Place | Surveyor to find | Gate | Enemy | Look key |
|---|---|---|---|---|---|
| 1 | **Level 0: Office Floor** | Joss (Supply Closet) | find a Cell | Pacer | `l0`, camp `c0` |
| 2 | Level 0 cont., **Outpost Zero (Night Desk)** | (radio comes alive) | Fuse | Pacer | `desk` |
| 3 | **Level 1: Flooded Wing** | Hana (Pump House) | Valve Wheel | Pacer, **Hush** | `l1`, camp `c1` |
| 4 | Level 1 cont., **The Falls** | Lena | Rope | Hush | `falls` |
| 5 | **Level 2: The Wards** | Ravi (Ward Station) | Brass Key | Hush, **Echo** | `l2`, camp `c2` |
| 6 | Level 2 cont., **The Dormitory** | (lore room) | Fuse, Crank | Echo | `dorm` |
| 7 | **Level 3: The Hollow** | Pim (Hollow Camp) | Rope, Lamp Core | Echo, **Still** | `l3`, camp `c3` |
| 8 | **Level 4: The Garage**, **The Lamp Room** | Ines (Lamp Room) | follow the chalk | all four | `l4`, `lamp` |
| endless | **The Relay** | the previous surveyor (ghost) | daily seed | all | rotating |

A lit stop follows every tier, as agreed. Small camps follow tiers 1, 3, 5 and 7; big lit rooms follow tiers 2, 4, 6 and 8. Every camp is a **person**, not an empty room, so the break comes with information.

## What the lights show (Vasco: "each part should illuminate a different backdrop and floor")

Rule: **a light shows its own area's backdrop.** When a lamp-bag, a POI or a camp lamp ignites, it paints a patch of that area's wall and floor on the nearby geometry and gives off that area's light colour. Walk from one lit patch to the next and you cross worlds.

| Look | Walls | Floor | Light | Sound | Props |
|---|---|---|---|---|---|
| `l0` Office | damp yellow wallpaper (Fabric) | stained brown-olive carpet (Carpet) | warm fluorescent yellow-white, flicker | dead buzz, fan, far copier, keys | cubicles, water cooler, vending machine, CRT/VCR |
| `c0` Supply Closet | patched plaster, shelves | pallets (WoodPlanks) | many bare bulbs, workshop yellow | scissors, whisper radio | lamp-bag workbench |
| `desk` Night Desk | clean wallpaper hung with maps | rug on carpet | banker's lamp, warm | kettle, ticking clock | radio, corkboard, cot |
| `l1` Flooded Wing | white-blue pool tile (Ceramic) | wet tile + **blue water** (45,120,200) | cold cyan with rippling reflections | drips, pump thud, rusted gate | valves, life rings, boilers, catwalks |
| `c1` Pump House | corroded pump steel | dry steel grating | warm work lamp on cold steel | pump thud, boiler hiss | gauges, chalk tallies, water-route chart |
| `falls` The Falls | mossy cavern stone, ferns | grass + flat stones round a basin | golden sun from nowhere + green bounce | waterfall, chimes, impossible birds | hammocks, string lights, camp stove, mural alcove |
| `l2` Wards | institutional pale green with white tile | grey-green linoleum, wax streaks | clinical teal-white, hard flicker | PA, squeaking wheels, call bell | gurneys, curtains, nurse station |
| `c2` Ward Station | ward green washed warm, curtains drawn | rugs on linoleum | amber table lamp | kettle, low cassette | blanket fort, unplugged radio |
| `dorm` Dormitory | cream over ward green, string lights | boards + rugs | many small warm lights | stove, clock | bunks, WHO IS STILL OUT board, Halden model |
| `l3` Hollow | dark violet cave rock, mineral veins | packed earth, spore pools | blue-violet glowcaps | drips, soft pulse, glass chimes | root curtains, rope bridges |
| `c3` Hollow Camp | cave alcove papered with Survey maps | planks over earth | warm lanterns against the blue | cranked radio, mugs | bedrolls, seed tray |
| `l4` Garage | raw concrete, yellow stripes, level numbers | asphalt with painted bays | orange sodium | ramp wind, distant tyre squeal, shutter | tarped shapes, ticket machine, drop shafts |
| `lamp` Lamp Room | brass and timber, shelves of lamp-bags | worn boards, chalk ring | warm white gold, steady | the Lamp's hum, wind in the shaft | the Lamp, chalkboard, ladder |

Exact colours and Roblox materials are in `lore-text.json` / `LoreText.luau` under `looks` (`LoreText.look("l1")`). They are suggestions; match what the build can render.

### Light sensitivity (Vasco: "lights should light up right away when scanned")

The text and look data assume this behaviour:

1. **First dot ignites.** A lamp-bag, POI, tape screen or camp lamp lights on the first dot that lands on it, or any dot within `igniteReach` (about 6 to 10 studs) of its visible bulb or screen. Not 140.
2. **Fade-in ~0.35 s**, not a pop. A tiny audio tick per ignition, pitched to the area.
3. **Always findable.** The bulb or screen itself is a faint ember the rig can sense (a "scan magnet": larger collision shape than the visual) so a casual sweep that passes near catches it.
4. **Lit stays lit** for the rest of the Level.

## Level and camp details

### Level 0: The Office Floor (tiers 1 to 2)

**Tells the player:** this is the Backrooms; here is how the rig works; people are alive down here.
**First room:** a CRT and VCR on a cart, already loaded with Tape 1. The first dots on the screen light it (instant), and it offers to play (`poi.l0.vcr`, `tape.orientation`). Bulletin `plaque.l0` on the wall. HUD goal `goal.l0`.
**POIs (6):** the Halden badge (`poi.l0.desk`), the whiteboard (`poi.l0.whiteboard`), Hollis's coat (`poi.l0.coat`), the copier with the failed exit guesses (`poi.l0.copier`), the vending machine (`poi.l0.vending`), the exit sign pointing at a wall (`poi.l0.sign`).
**Recorders:** `rec.l0.1` to `rec.l0.3`. **Tape:** `tape.halden` (break room), `tape.hollis` (security booth).
**Enemy:** the Pacer. Keys jangle. He lingers briefly at a scan, then moves on. Vasco's rule: never stand still.
**Sound:** buzz, fan, copier warm-up, keys. A phone rings once.
**Pit:** one open lift shaft with a painted edge (`thought.pit`).

**Camp: Joss's Supply Closet (after tier 1).** Find the green dot. `npc.joss` explains Levels, fading, time, gives lamp-bags, points to the fuse and Hana. Camp POIs: `poi.c0.bench`, `poi.c0.map`.
**Night Desk (after tier 2).** Radio and sign-in sheet, a corkboard with some photos face down. `radio.first` is Ines's first call. Handset becomes usable here. POIs: `poi.desk.radio`, `poi.desk.signin`, `poi.desk.board`.

### Level 1: The Flooded Wing (tiers 3 to 4)

**Tells the player:** fading, the Hush, sound as risk, follow the water.
**Look:** pool tile, **blue water**, pipes, catwalks, drains. Terrain changes: ankle to knee depth, pipe balance, catwalk over a deep channel.
**POIs (6):** life ring (`poi.l1.lifering`), pump log (`poi.l1.pumplog`), Tobi's headphones (`poi.l1.headphones`), dinghy (`poi.l1.dinghy`), valve station (`poi.l1.valve`), chalk tally (`poi.l1.tally`).
**Recorders:** `rec.l1.1` to `rec.l1.3`. **Tape:** `tape.tobi` (pump room).
**Enemy:** the Hush. It roams and loses the thread if two sounds are far apart; walking is safe, running and scanning near it is not.
**Traps:** weak drain gratings, alarm plates by the pump room.

**Camp: Hana's Pump House (after tier 3).** `npc.hana` explains the water route, the Hush and the valve wheel. POI: `poi.c1.chart`.
**The Falls (after tier 4).** The big, bright exhale. Full colour, the most colourful place in the game. `npc.lena` explains Refuges, the roster, the respawn, and the Brass Key. POIs: `poi.falls.names`, `poi.falls.behind` (hidden mural of every Level and the dotted line to the exit), `poi.falls.guestbook`. Recorders `rec.falls.1` and `rec.falls.2`. Plaque `plaque.falls`.

### Level 2: The Wards (tiers 5 to 6)

**Tells the player:** the Echo, the tap greeting, what Ravi knows about the scanner.
**Look:** pale green, linoleum, gurneys, curtains, a PA with no speaker. Cold teal-white light.
**POIs (6):** PA (`poi.l2.pa`), patient chart (`poi.l2.chart`), tap-code plate (`poi.l2.tapcode`), gurney (`poi.l2.gurney`), cut call bell (`poi.l2.bell`).
**Recorders:** `rec.l2.1` to `rec.l2.3`. **Tape:** `tape.ravi` (day room).
**Enemy:** the Echo. Green until close; skips the breath. Fake radio: `radio.fake.1` to `radio.fake.4`, only near it.

**Camp: Ward Station (after tier 5).** Knock two taps, a breath, one (`npc.ravi`). Ravi explains the Echo and that the rig came from Pike's unit.
**The Dormitory (after tier 6).** Quiet, sad lit room. Ines's theory (`rec.l2.3` is hidden in Level 2; the Dormitory has the board, letters and the Halden model). Fifteen floors, plans say fourteen (`rev.dorm.model`).

### Level 3: The Hollow (tier 7)

**Tells the player:** light is food; the Still; the Halden is everywhere.
**Look:** violet cave, glowing minerals, roots, rope bridges. Blue-violet light.
**POIs (4):** Halden door frame in rock (`poi.l3.doorframe`), glowing vein (`poi.l3.crystal`), Quill's camera (`poi.l3.camera`), rope bridge (`poi.l3.bridge`).
**Recorders:** `rec.l3.1` to `rec.l3.3`. **Tape:** `tape.quill` (projector).
**Enemy:** the Still. Never stare, never look away.

**Camp: Hollow Camp (after tier 7).** `npc.pim` on lanterns, the Still, the Lamp Core. POI: `poi.c3.mugs`.

### Level 4: The Garage (tier 8)

**Tells the player:** the whole truth is at the bottom.
**Look:** concrete, sodium light, ramps, boom gate. All four enemies appear.
**POIs (5):** cornerstone (`poi.l4.stone`), ticket machine with Theo's entry time (`poi.l4.ticket`), chalk arrows (`poi.l4.chalk`), Pike's table and camcorder (`poi.l4.pike`), drop shaft wall (`poi.l4.pit`). **Recorder** `rec.l4.1`. **Tape:** `tape.pike`.

**The Lamp Room (finale).** `npc.ines`, then `choice.up` (cutscene `end.up`) or `choice.stay` (`end.stay`, starts The Relay). POIs: the Lamp, the chalkboard of the whole point cloud, the ladder.

### The Relay (endless)

Each floor is "lit by the last person to pass". Posters `sign.relay.*`. Daily seed card `card.relay.daily`. Lit rooms carry a recorded line from the previous surveyor (a past player's name when available). New Levels (a school, a mall, a pool, a station) plug in as new `looks` plus a camp plus a bulletin.

## Pacing (unchanged from v1 plus what's new)

- A lit stop after every tier, alternating small camp and big room.
- A small lit lamp-bag every ~60 to 90 s of travel; each ignites on the first dot (see above).
- A POI roughly every 45 to 60 s; each carries one Theo thought.
- A close encounter at most once per ~3 to 4 minutes, and only sometimes. Announce by sound first.
- One tape per Level is the expected "cutscene" beat; the opening and endings are full cutscenes.

## Item and gate summary

| Tier | Gate | Source |
|---|---|---|
| 1 | Cell | Level 0, first reward |
| 2 | Fuse | Joss points to the breaker room |
| 3 | Valve Wheel | boiler room; Hana says where |
| 4 | Rope | Hana's camp; crosses the gap to the Falls |
| 5 | Brass Key | Lena, at the Falls |
| 6 | Fuse (2nd), Crank | Dormitory; Ravi says where |
| 7 | Lamp Core | Pim, last bay |
| 8 | none (follow the chalk) | |

## Existing mechanics this plugs into (code, not part of the writing)

- PR #7 (stairwell, surveyors walking you out, Mimic gate) is not yet in main; the camp scenes above fit directly into "surveyors walk you out" as the dialogue that plays during the walk. `npc.*` scenes are written so they can play while a surveyor walks.
- The build's hidden-object system (`echoRevealHits`) maps to the "first dot ignites" rule: set the reveal threshold for lamps, camp lamps, POIs and tape screens to 1 to 3 dots.
- Story kits and `LoreRooms` use `Lore.luau`; the old ids (`rec.annex.*` etc.) are retired. See `README.md` for the id map.
