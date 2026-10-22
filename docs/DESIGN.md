# Design

How LIDAR plays, as built in v2. Every number here comes from `src/shared/Config.luau`,
`src/shared/data/` or the bot simulation; change them there, not here. The story and how the
game tells it are in `docs/LORE.md`. Why things are the way they are is in `docs/DECISIONS.md`.

## The idea

A co-op horror maze where you can only see what you measure. The maze is pitch black and its
walls are invisible. A LIDAR gun leaves tiny glowing dots wherever its rays land, and those
dots are the only picture of the level there will ever be. Monsters are invisible too: you
sense them by their marks, their breath and their sound, and you hide by being quiet.

Mostly breath, rarely terror: long stretches of careful exploring, one close encounter now
and then, and a warm lit room every two levels.

## Loops

- **A level (2 to 4 minutes):** scan to build a picture, find the exit (and the key when the
  exit is locked), pick up what is worth the detour, avoid or outwit what roams.
- **A floor (two levels):** each floor of the story has its own feel and introduces something
  new (see Tiers). After every second level comes a lit room.
- **A lit room:** the exhale. A checkpoint, three pieces of the story, and the workbench where
  Static buys upgrades.
- **A session:** a run through the floors to the Lamp Room and its choice; past it, endless
  Relay floors. The daily run is one shared seed per day with a leaderboard.

## The scanner

| | Scatter (hold) | Sweep (one shot) |
| --- | --- | --- |
| Input | Left mouse, RT, touch SCAN | Right mouse or F, LT, touch SWEEP |
| What it does | A stream of rays in a cone round the crosshair: 380 a second at first, up to 880 with Emitter. Reach 85 studs, up to 149 with Range Coil | A line of rays travels from the top of the view to the bottom (56 lines of 70 rays in 1.3 s, up to 90 x 114 with Sweep Grid) and draws a whole grid |
| Spread | 26 degrees half-angle by default; the scroll wheel narrows it to 8 or widens it to 40 (56 with Wide Lens) | 30 up, 36 down, 46 to each side |
| Noise | Quiet: heard about a third of a cell away | Loud: heard 4 cells away (less with Quiet Shutter) |
| Cost | Nothing: never fully blind | One battery charge in a level (free in the tutorial and in havens). The gun holds 3 (Capacitor adds more); a run starts with 1 (Spare Cell adds more) |

**Battery cells** are the only way to charge the sweep in a level. Each level hides 3 or 4 (2
deep in the Relay), the first near the start, the rest mostly in dead ends, so looking round a
corner pays. A cell gives 1 sweep, or 2 (about 3 in 10, drawn as a double cell). A cell that
does not fit pays 6 Static per charge instead. Charges carry from level to level within a run
and reset on a new run. The cell goes to whoever picks it up. Trickle Charger, late on the
bench, wins one charge back every 150 / 110 / 80 s while walking a level (slower on harder
tiers).

**Lures.** Unscanned cells, recorders, story objects and posters give off a few dim, slow
motes of warm light, one every few seconds, when the player is within 18 studs and nothing is in between: too faint to
read as a marker, just enough to pull the eye. The first ray that lands on the thing stops them
for good, and from then on the gold found-item pulse takes over (`client/Lure`) until the item
is picked up or revealed.

**Dots** are tiny Neon cubes coloured by what they hit: wall, floor, ceiling, water (blue),
friend (green), monster (red), objective (gold), hazard (violet). The world's dots are
permanent, up to a budget set by the DOT DETAIL setting (18,000 / 55,000 / 110,000, up to
twice that with Phosphor); when the budget is full the oldest dot moves. They are packed one per grid cell
(finer close up), so scanning the same wall twice costs nothing. People and monsters are only
marked briefly: friends' dots fade in 2.5 s, monsters' in 1.2 s, and only about a third of
the rays that cross a monster mark it. Glimpses, never a silhouette.

**Pulse Radar** (an upgrade) sends a ring of dots round the player every 8 s (5 s at level 2).

## Moving

| | Speed (studs/s) | Noise | Seen by the Pacer |
| --- | --- | --- | --- |
| Crouch | 5 | Quiet (a fifth of a cell), louder when wading | No |
| Walk | 10 | Heard close by | Yes, in its line of sight |
| Sprint | 17 | Heard 3 cells away | Yes |
| Lit room | 14 | - | - |

Wading through flooded cells is slower (x0.8) and loud even crouched. Jumping is off. Soft
Soles makes footsteps carry less far.

## Monsters

All four are invisible and roam the whole level with short pauses. You sense them by red
footprints that fade over 12 s (each with a footstep sound), pale breath close to them, a red
glow at the screen edges as one comes near, a heartbeat and breathing that rise, and their own
sounds. The manual's names are in brackets; the plain rule is what the field guide and the
catch message say.

| Monster | Rule | Roams | Hunts | Chases | Senses |
| --- | --- | --- | --- | --- | --- |
| Wanderer (the Pacer) | Slow. It sees you standing or walking in its line of sight and hears running. Crouch and it loses you. | 5 | 6.5 | 8.8 | Sight 2.4 cells, hearing x1 |
| Listener (the Hush) | Blind and fast. It hunts running, footsteps close by and the sweep. Crouch to move in silence. | 4.5 | 13 | 13 | Hearing x1.6 |
| Mimic (the Echo) | It marks green until you are close. Its dots land late and it never taps on the wall. | sits | - | 14.5 | Reveals within about a cell |
| Stalker (the Still) | It only moves while no scanner points at it. Keep your dots on it and it withdraws. | - | 12 | 12 | Pinned by a scan up to 7 cells |

A disguised Mimic gives nothing away: no footprints, breath, aura or heartbeat. Real stranded
surveyors tap on the wall (two taps, a wait, one); near a disguised Mimic only, a false Base
on the radio gives directions, which real Base never does. Being caught downs you while a
teammate is still standing; when the last one standing is caught, the whole party starts the
level again (a quick reset, not a wipe). A fresh respawn is ignored for 5 s.

## Hazards and helpers

| | What it is | How you spot it |
| --- | --- | --- |
| Pit | A hole in the floor with a ledge round it; falling in puts you back at the start and is heard 3 cells away | The rim scans violet |
| Alarm plate | Stepping on it rings a bell heard 5 cells away for 3 s; it re-arms after 12 s | Scans violet |
| Flooded cells | Ankle-deep water: slow and loud | Scans blue |
| Lantern | A real light: a patch of ordinary floor and wall, about one cell | You can see it |
| Hidden recorder | Put 140 dots on it and it reveals itself, lights its corner and plays the next tape | Gold, and a progress bar under the crosshair |
| Battery cell | Recharges the sweep; pays Static | Gold |
| Key | Opens a locked exit | Gold |
| Stranded surveyor | Taps on the wall; reaching them pays Static and a green trail of dots leads to the exit | Green, on time |
| Manual page | One per run at most; a page of the story's manual; pays Static | Gold |

## Tiers

Two tiers to a floor. Past tier 8, endless Relay floors grow from the last row (bigger mazes,
more monsters, faster, the sweep slower to recharge) with a lit landing every third floor.

| Tier | Floor | Size | Monsters | Locked exit | Flooded | Lanterns | Recorders | Pits | Plates | Sweep recharge | Static | Lit room after |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | The Annex | 5x5 | wanderer | no | 0% | 1 | 1 | 0 | 0 | x0.80 | 30 | |
| 2 | The Annex | 5x6 | wanderer | no | 0% | 1 | 1 | 1 | 0 | x0.90 | 40 | Night Desk |
| 3 | The Flooded Wing | 6x6 | wanderer, listener | no | 0% | 1 | 1 | 1 | 1 | x1.00 | 55 | |
| 4 | The Flooded Wing | 6x7 | wanderer, listener | yes | 18% | 2 | 1 | 1 | 1 | x1.00 | 70 | The Falls |
| 5 | The Overgrowth | 7x7 | wanderer, listener, mimic | no | 8% | 2 | 2 | 2 | 1 | x1.05 | 85 | |
| 6 | The Overgrowth | 7x8 | wanderer, mimic, stalker | yes | 8% | 2 | 2 | 2 | 2 | x1.10 | 100 | Bunk Room |
| 7 | The Foundation | 8x8 | wanderer x2, mimic, stalker | yes | 12% | 2 | 2 | 2 | 2 | x1.15 | 120 | |
| 8 | The Foundation | 8x9 | wanderer, listener, mimic, stalker | yes | 12% | 3 | 2 | 3 | 2 | x1.20 | 150 | Lamp Room |

Mazes are cells of 14 studs with 11-stud walls; the exit is the cell farthest from the start.

## Co-op

Up to 4 players. Everyone sees everyone's dots: teammates' scanners are redrawn locally from
a few numbers the server relays, so no dot is ever sent over the network. Teammates' names
show through walls up to 400 studs, and they leave green footprints. A caught player is downed
while someone is still standing; a teammate stands close and scans them for 3 s to get them up,
and a monster that downs someone pauses for 4 s so it cannot camp. Pings (G, Y, touch PING)
mark a spot for 12 s; with Echo Beacon they also lure things that listen. The emote wheel
says Here, Wait, Go, Danger or Thanks.

## Economy

**Static** is earned by clearing levels (30 at tier 1 to 150 at tier 8, more on Relay floors),
x1.3 for a clear without being caught, plus 5 per cell, 30 per surveyor, 10 per recorder, 8
per lit-room note read for the first time, 50 for the first daily clear, and a visit streak
(10 to 60). It is spent at the workbench:

| Upgrade | Levels | Effect |
| --- | --- | --- |
| Emitter | 5 | Scatter +100 dots a second per level (380 to 880) |
| Range Coil | 4 | Reach +16 studs per level (85 to 149) |
| Sweep Grid | 3 | A finer sweep grid (56 x 70 up to 90 x 114) |
| Phosphor | 4 | The world holds 25% more dots per level |
| Capacitor | 4 | The gun holds one more sweep charge |
| Spare Cell | 2 | Start every run with one more charge |
| Trickle Charger | 3 | Wins back a charge while walking a level (150 / 110 / 80 s) |
| Quiet Shutter | 3 | The sweep is quieter |
| Wide Lens | 1 | The spread opens to 56 degrees |
| Pulse Radar | 2 (switchable) | A ring of dots pulses out on its own |
| Echo Beacon | 3 | Pings last longer and lure listeners |
| Wayfinder | 2 | A needle to the exit once scanned, then a map of what you scanned |
| Soft Soles | 3 | Footsteps carry less far |

Cosmetics (dot tints, gun housings) cost 80 to 100 and never affect play. Maxing the scanner
and battery rows costs about 3,100 Static. A full clean run to the Lamp Room pays about 1,000,
an early run that dies on tier 3 or 4 about 150 to 250, so a new player buys something after
nearly every run and maxes the scanner after many. What could be sold, and
what never should be, is in `docs/MONETIZATION.md`.

## What to tune first

The bot simulation (`lune run scripts/simstats 40`) plays every tier against the real monster
state machines. Its latest results, on the v2 rules:

| Tier | Clear rate | Mean time to clear (s) | Mean catches per run | Deadlocks |
| --- | --- | --- | --- | --- |
| 1 | 100% | 34 | 0.05 | 0 |
| 2 | 100% | 61 | 0.93 | 0 |
| 3 | 100% | 51 | 0.15 | 0 |
| 4 | 100% | 64 | 0.42 | 0 |
| 5 | 100% | 65 | 0.50 | 0 |
| 6 | 100% | 88 | 0.90 | 0 |
| 7 | 98% | 154 | 3.92 | 0 |
| 8 | 100% | 133 | 0.93 | 0 |
| 9 | 100% | 153 | 1.27 | 0 |
| 10 | 98% | 217 | 2.65 | 0 |
| 11 | 100% | 191 | 2.05 | 0 |

What stands out, as measurements rather than verdicts (the bot is not a person):

- **Tier 7 is the spike.** About four catches per run against one on its neighbours. It is
  the only tier with two Wanderers, and `scripts/simcauses 7 40` puts every one of its 157
  catches in 40 runs on them (144 while the bot was evading). Its Wanderer count and speed
  scale are the first knobs to look at.
- **Tier 2 catches more than tier 3** (0.93 against 0.15), all by the Wanderer while
  evading; tier 2 is a narrow 5x6 maze with the same single Wanderer as tier 1.
- **Recorders per floor do not match tapes per floor.** Each floor has three tapes, but tiers
  1 to 4 have one recorder each, so a player who finds every recorder hears Hollis's Annex
  tape on B4 and two Flooded Wing tapes on B5. One recorder on the first tier of each floor
  and two on the second (1, 2, 1, 2, ...) would line them up with the same twelve in all.

Then, from playtests rather than the bot: the dot budget on phones (DOT DETAIL), how often
the sweep is needed (cells per tier in `Tiers.luau`, `Config.Battery`), the base scanner
(`Config.Lidar.dotsPerSecond`, `baseRange`), and how loud each action is
(`Config.Noise`).
