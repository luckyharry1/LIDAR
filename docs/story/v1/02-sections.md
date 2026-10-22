# Sections: what each place is, how it feels, what happens

Tier numbers follow build-prompt.md (8 tiers + endless). Entity intro order: Wanderer T1, Listener T3, Mimic T5, Stalker T7. Line ids refer to `03-ingame-text.md`.

Vasco's direction applied everywhere: a **journey** (items, gates, varied terrain, secrets), **mostly breath, rarely terror** (encounters only sometimes), objects that **reveal themselves** when scanned enough (lighting nearby floor and wall, with a short bit of lore), small **lit spots** (lamp-bags), traps and pitfalls, blue water, and one vibrant lit waterfall safe area.

## Pacing and playtime (design targets, not measured)

From build-prompt.md: a small reward every 20 to 40 s, a level clear every 3 to 5 min. At ~3 to 4 min per level, tier 4 ends about **12 to 16 min** into a first run, so the Falls would be a long wait for a first exhale. Vasco (2026-10-13) likes the T4 Falls and wants small lore havens as clear breaks from monsters. So:

- **A lit break after every level**, alternating small and large:

| After | Break | Size |
|---|---|---|
| T1 | The Copy Room | haven (about 1 min, mini checkpoint, one lore drop) |
| T2 | The Night Desk | big lit room |
| T3 | The Dry Booth | haven |
| T4 | **The Falls** | big lit room (the main exhale, about 14 min in) |
| T5 | The Potting Shed | haven |
| T6 | The Bunk Room | big lit room |
| T7 | The Archive Nook | haven |
| T8 | The Lamp Room | finale |

- **Havens**: a single small lit room or nook, no enemies, a lamp, one readable lore drop, optional radio line, mini checkpoint. Ids: `card.haven.*`, `note.haven.*`, `radio.haven.1`.
- **Lit spots in the dark** (mid-level): `rev.nook.1` to `rev.nook.4`, lamp-bags that ignite when scanned enough. These are the "bag with the aura of a lightbulb" Vasco asked for. Place one every ~60 to 90 s of travel.
- Result: a lit break roughly every 3 to 4 min, a small lore drop every ~60 to 90 s, scares rare in between.
- If the Falls should come sooner, it can move to after T3 and the Dry Booth becomes the T4 haven; only the card order changes.

## Recurring devices

- **Lamp-bags** (`item.lampbag`): a bulb in a canvas sack. Crew breadcrumbs. Scan one enough and it ignites, lighting about 6 to 8 studs of floor and wall in warm amber. Hung at every important turn. Some are dead (no glow); a dead bag still reveals a name tag (`rev.*` flavour). Never use green for them (green means friend).
- **Reveal objects** (`rev.*`): visible only as dots. After enough dots land on them they light up (warm, their own radius) and show 1 to 3 lines (in-world: label, tag, writing on them). Each `rev.*` entry gives suggested colour and radius.
- **Recorders** (`rec.*`): hidden tape recorders, one per notable spot. Scanned enough, they click and play. Lines are short and start mid-thought.
- **Posters and signs** (`sign.*`): staff notices and graffiti. Readable when lit by dots or a lamp-bag.
- **Radio** (`radio.*`): "Base" (Ines). Real Base only reports. The Mimic's fake Base gives directions. That difference is the tell.
- **Traps and pitfalls**: alarm plates (a crew bell, stepping on a plate rings it and draws enemies; `sign.plate.*` warn obliquely), open drop shafts with yellow-painted edges (`sign.pit.*`), rotting floor over water, collapsed vents. Always telegraphed by an object or a sign. Fair, learnable.
- **Terrain variety**: carpet corridors and cubicles (Annex), ankle to knee blue water, pipes, catwalks and grating (Flooded Wing), roots, slopes, soil, glass ceilings with no sun (Overgrowth), stairwells, vents, ladders, raw concrete and high shelves (Foundation).

## Act I: The Annex (B3, tiers 1 to 2)

**What it is.** The office floor you would find upstairs, empty, after hours. Cubicles, a kitchenette, a meeting room, a copier. Carpet tile, drop ceiling. Familiar, then wrong: the corridors are one turn too long.

**Feel.** Small, forgiving, dry. The dark is almost polite. Tutorial energy without a tutorial: a poster on the wall of the first room (`sign.intake.*`) shows a pictogram of the rig and what its colours mean, in the language of a fire-exit diagram.

**Enemy.** Wanderer (the Pacer, Hollis). His keys jangle. He walks the same rounds, so a player who listens can learn his route. Linger briefly, then move on.

**Sound.** Dead fluorescent buzz that cuts off when you step in, a ceiling fan turning slowly, a far-off copier warming up with no one near it, keys. A phone rings once, somewhere, then never again.

**Journey / gates.** T1: find the door out by scanning; a Cell (`item.cell`) is the first reward. T2: a **Fuse** (`item.fuse`) is needed to power the breaker for the exit door. Optional: **Chalk**, a lamp-bag, a Manual page.

**Story beat.** Hollis's tape (`rec.annex.3`). Joss on lamp-bags (`rec.annex.2`). Ines's first log (`rec.annex.1`). The coat with the missing keys (`rev.annex.coat`). The first hint that the player has been here before comes at the end of the Annex.

**Pitfall.** One open lift shaft (T2), painted yellow at the edge.

### The Night Desk (lit room after tier 2)

A pool of warm lamplight in the dark: a banker's lamp, a desk, a kettle, a cot, a corkboard, the **radio** (first time you hear Base). The first exhale. Checkpoint and bench.

- Sign-in sheet (`note.desk.signin`): Crew 7 "IN (again)". Players will notice. Nobody explains.
- Note in the player's handwriting (`note.desk.self`): "second door is wrong".
- Mug rack with seven names; the seventh mug is clean (`rev.desk.mugs`).
- Radio: `radio.base.01`, the first call.
- Posters for the next floor: `sign.desk.waterline`.

## Act II: The Flooded Wing (B4, tiers 3 to 4)

**What it is.** The mechanical floor under the offices. Pipes, drains, boiler rooms, a corridor that is half a canal. The water is **blue**, the one colour in the dark. It is lit from beneath by faint blue (the rig's dots on water glint blue-white; build's call).

**Feel.** Dripping, echo, claustrophobia, moving through terrain: ankle-deep, knee-deep, pipes to balance on, catwalks over a deep channel.

**Enemy.** Listener (the Hush, Tobi). Blind, hunts by sound. Headphones left on a pipe (`rev.flood.headphones`). Pinging and running draw it, so this floor teaches noise as a cost. Vasco's note: the Listener must **move** and roam (not stand still), and a pair of players should not be able to ping-pong it forever (it loses the thread if two sounds are far apart; builder tunes).

**Sound.** Drips with long reverb, a slow pump thudding, a rusted gate swinging, muffled someone-whispering in the pipes (the building carrying Tobi's last words), splashing that is not yours.

**Journey / gates.** T3: Valve Wheel (`item.valve`) to drain the channel and open the way. T4: follow the water downstream/up to the lit room. Item: Rope (`item.rope`), Cold Tea (`item.tea`), lamp-bags. Rule 9 on the wall: "Follow the water."

**Pitfall.** Drain gratings that give way (`sign.flood.grate`). Alarm plates by the pump room.

**Story beat.** Tobi's tapes (`rec.flood.*`). The dinghy (`rev.flood.boat`). The life ring painted B3 (`rev.flood.lifering`).

### The Falls (lit room after tier 4) , the vibrant waterfall safe area

The big exhale. A vast cavern atrium; a skylight shaft high above pours water down into a bright, shallow basin, lit by warm sun from nowhere and bioluminescent moss. Hammocks, strings of lights, a camp stove, a guitar with one string missing, flowers. Full colour. **Friends appear in full colour here.** Checkpoint, bench, shop.

The water is the same water that ran through the Flooded Wing: following it was the correct instruction (Rule 9) , nobody said so.

Why it is safe (the story, but the player only finds fragments): **Everyone remembers a place like this.** The dark cannot rewrite a memory that every crew shares (`rec.falls.1`). That is the crew's first working theory, and it is the first time the mystery becomes hopeful.

- Camp: Lena's recorder (`rec.falls.2`), hammocks (`rev.falls.hammock`).
- **Guest Book** (`note.falls.guestbook`): lists real player names who reached the Falls (client-side, from the party and friends; optional). If the build skips it, use the static lines.
- **Behind the waterfall** a hidden alcove with a chalk mural of the building (`rev.falls.behind`): a secret reward, where Ines drew where the Lamp should go.
- Sound: water, wind chimes, a distant dripping that is clearly comforting, birds that cannot exist. Then, rarely, one far note of the dark, to remind you.

## Act III: The Overgrowth (B5, tiers 5 to 6)

**What it is.** An old botanical atrium, long unattended. Roots through the floor, tiled planters, glass roof with nothing behind it, vines through the ceilings. Soil and uneven ground. Cracked greenhouse benches for cover. The overgrowth is not alive in a friendly way.

**Feel.** Rustling, uneven, close. The dark is wetter and breathes. More of an adventure: ramps up root-mounds, climbing over benches, crawling vents.

**Enemy.** Mimic (the Echo): green dots (looks like a friend) until close; wears Ravi's voice. Fake Base lines (`radio.fake.*`) occur only near it. A tell: it taps twice but never waits for the beat (`rev.over.tapcode`). **Use sparingly.**

**Sound.** Rustle that stops when you stop, birdsong with something wrong in it, creaking glass, a laugh that is almost Ravi's, a slow wet tap-tap.

**Journey / gates.** T5: Skylight Crank (`item.crank`) opens the glass roof lift. T6: Elevator Fuse (`item.fuse`) powers the service lift to the Bunk Room. Photographs, Pim's mug (`item.mug`), pages. Alarm plates, hidden among roots (`sign.plate.2`).

**Pitfall.** Sinkholes under rotted planters; rope bridges over a dark drop (rope item useful).

**Story beat.** Ravi's tapes (`rec.over.*`). Pim's camp (`rev.over.camp`). The one living plant (`rev.over.greenhouse`): someone still waters it.

### The Bunk Room (lit room after tier 6)

Crew quarters. A warm, low room: bunks, string lights, a stove, a corkboard titled WHO'S STILL OUT with names crossed or circled, a cup of cold tea, a calendar with every day circled. Not the exhale of the Falls: this is the **quiet, sad one**. Checkpoint and bench.

- Ines's log (`rec.bunk.1`): the theory, "We aren't hunted. We're forgotten." Green is someone looking back.
- Letters home (`note.bunk.letters`), Pim's note (`note.bunk.pim`): a promise to find the ladder.
- The model of the Halden Building (`rev.bunk.model`): each floor lights when you have scanned it in play (build can reflect progress).

## Act IV: The Foundation (B6, tiers 7 to 8)

**What it is.** The first floor ever laid, before the plans. Raw concrete, immense pillars, archive shelves that never end, high catwalks. No decor. The most empty place. It is not hostile; it is hungry for company.

**Feel.** Dread rather than jump scares. Long sightlines that you can't use. Long stretches of silence that make the next sound enormous.

**Enemy.** Stalker (the Still, Quill). Moves when you don't look at it; stops when you do. Chalk arrows and Marlow's camera (`rev.found.camera`). Wanderer, Listener and Mimic all return in higher density on T8.

**Sound.** Wind in vents, a camera shutter, footsteps that stop when yours stop, the long hum of the Lamp heard from far away through concrete (a **beacon** , the destination, the thing you walk toward).

**Journey / gates.** T7: Lamp Core (`item.core`) , the thing Ines needs. T8: the long walk to the Lamp, with chalk arrows leading in. Items: Flash Bulb (`item.flashbulb`), Pencil Map, pages.

**Pitfall.** Big drop shafts (build's biggest pits), plate corridors, a catwalk that tilts.

**Story beat.** Quill's tapes (`rec.found.*`). Ines's last descent (`rec.found.1`). The cornerstone (`rev.found.stone`).

### The Lamp Room (finale, after tier 8)

The brightest lit room. A tall circular chamber, a great brass Lamp at the centre, shelves of old lamp-bags, rope ladder going up into daylight (the first real light), Ines sitting at a desk, green. Pim's postcard pinned. See `npc.ines.*`, `end.*`. Choice: up, or keep the lamp.

## After: The Relay (endless mode)

Procedural floors named **Relay Floor {n}**. Posters on every floor from earlier surveyors (rotated from `sign.relay.*`). Each Relay Floor has a lit room with a short log from "the surveyor before you" , a nameless voice or a daily-seed ghost. The daily challenge seed is "tonight's floor" (`card.relay.daily`). The tone: continuity, not despair. Someone lit this before you; you light it for someone else.

## Scare beats (sparing, per Vasco)

Rule of thumb: one **close encounter** per section at most, never more than one per ~3 to 4 minutes, and only sometimes. Announce it with sound before sight: the ambience drops, the fake Base speaks, keys stop. A scare is something that was always possible, finally noticed.

| Section | Signature scare | Build note |
|---|---|---|
| Annex | Keys stop, then a dot at arm's length | Wanderer lingers, then leaves |
| Flooded | The water goes quiet, one splash | Listener turns toward the last ping |
| Overgrowth | Green friend dot that taps twice and does not wait | Mimic reveal when it breaks the beat |
| Foundation | You look away; the corridor dot is closer | Stalker rule felt, not told |

## Item and gate summary (journey)

| Tier | Section | Gate / key item | Why |
|---|---|---|---|
| 1 | Annex | Cell | first reward, teaches the rig refill |
| 2 | Annex | Fuse | powers the exit breaker |
| 3 | Flooded | Valve Wheel | drains the channel |
| 4 | Flooded | Rope | cross the gap to the Falls |
| 5 | Overgrowth | Skylight Crank | opens the roof lift |
| 6 | Overgrowth | Fuse (2nd) | service lift to the Bunk Room |
| 7 | Foundation | Lamp Core | needed at the Lamp |
| 8 | Foundation | none (walk to the beacon) | the final test is the Stalker and the dark |

The build can reshuffle gates; keep each gate's item description and reveal lines attached to its object.
