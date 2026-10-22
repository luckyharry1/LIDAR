# LIDAR story bible: "The Understory"

Status: v1, 2026-10-13. Written for Vasco's Roblox LIDAR build. Companion files: `02-sections.md` (levels, feel, sound, items, gates) and `03-ingame-text.md` / `lore-text.json` / `LoreText.luau` (every line the game shows).

## Writing rule (Vasco, 2026-10-13): be indirect

The game never lectures the player. No "Welcome, press X to scan". Everything is learned from things that exist in the world:

- **Posters, notices, stencils, graffiti, sign-in sheets, labels.** Institutional text that was written for staff, not for the player, and says more than it means to.
- **Overheard dialogue.** Radio chatter, answering-machine tapes, recorders that start mid-sentence.
- **Half-finished notes, margin scribbles, crossed-out lines.** What is crossed out is the clue.
- **Objects that say it for themselves.** A mug with a name on it. Four mugs, one chipped.

Nobody explains the mystery. Each piece is a fragment from someone who thought the reader already knew. The player assembles it. Where a fact must be stated (a puzzle gate), it is stated as a procedure someone else wrote down.

Consequence for the build: tutorial prompts are **diegetic** (a stencilled poster in the first room, a pictogram on a door). If a plain UI hint is still needed for mobile, use the fallback `hint.*` lines, and keep them rare and short.

## The one-paragraph story

Under the Halden Building there is a stair that is not on the plans. Below it is the **Understory**: the place a building forgets. Corridors nobody checks, rooms nobody enters. It fills in the dark, and it rearranges where nobody is looking. Six survey crews went down to map it. They brought lamps. The lamps were not enough. Crew 1's chief, **Ines Calder**, built the **rig** (the LIDAR gun) on a new idea: you cannot light the Understory, but you can **remember** it. A dot stays where you looked. A mapped corridor holds still. You are **Crew 7**. Each time the dark takes you, you wake at the last lit room. The reason is the mystery, and Ines keeps it.

## The truth (for the writers; the player assembles it)

1. **The dark does not hunt. It forgets.** Anything unseen long enough stops being a person. The Understory fills the gap with whatever is left.
2. **The red things are surveyors who ran out of light.** The rig reads them red because red is what's left of someone nobody is looking at.
3. **Green is not a colour. Green is someone looking back.** Being scanned by a friend keeps you yourself. This is the co-op heart: you keep each other human by looking.
4. **Respawn is Ines.** She keeps the Lamp lit at the bottom. Every time the dark takes Crew 7, she pulls them back to the last lit room. The more lit rooms and mapped floor, the easier it is.
5. **Crew 7 has done this before.** The sign-in sheet says "IN (again)". A note in the player's own handwriting warns about the second door. The player is not the first attempt; they are the attempt that finally holds.
6. **The ending is a choice.** The ladder goes up (Pim made it out). Or you take the Lamp, so Crew 8 has somewhere to wake. The second option opens endless mode as **The Relay**: floors lit by other surveyors (the daily seed).

## Tone

Quiet. Tired. Wry. Staff-memo dry, then suddenly human. No gore, no named real-world references. People are lost, not dead; the book never says "dead". Fear comes from the gap between the tidy notice and what it implies.

Example of the register:

> WET FLOOR. (It is now.)

> Tea bags in a row on the shelf. One for every night someone stayed.

## Cast (all original)

| Who | Role | In the game |
|---|---|---|
| **Ines Calder** | Crew 1 chief surveyor, built the rig, keeps the Lamp | Voice on the radio ("Base"), margin notes signed `I.C.`, the NPC in the Lamp Room |
| **Joss Berrow** | Crew 1 rigger, invented the lamp-bags | Lamp-bag item, recorder in the Annex, cheerful skeptic |
| **Mr. Hollis** | Night custodian, first to report the stair | Becomes the **Wanderer** ("the Pacer"). Keys jangle. He is still doing his rounds |
| **Tobi Wren** | Crew 3 sound tech | Becomes the **Listener** ("the Hush"). Headphones, gain all the way up |
| **Ravi Anand** | Crew 2 signals | Invented the tap greeting. His voice is what the **Mimic** ("the Echo") wears |
| **Lena Sorrel** | Crew 2 climber | Cheer, hammocks, the Falls camp, rope |
| **Marlow Quill** | Crew 4 photographer | Becomes the **Stalker** ("the Still"). Camera on a tripod |
| **Pim Ashworth** | Crew 5 intern | **Made it out.** Mug, postcard. Proof the ladder works |
| **Seven** | Crew 7 callsign (the player or the party) | Never named. The radio only ever says "Seven" |

Never name the player. Use "Seven" on the radio and on forms.

## The Field Manual (the Backrooms-style instruction device)

The classic found-guide feel: a thin stapled booklet, *Survey of the Understory, Rev. 7*. Numbered rules, printed in a bureaucratic voice, with **handwritten margin notes** from crew correcting, contradicting or warning. The printed text teaches the mechanic obliquely; the margin note adds the fear or the heart.

Delivery: five pages are on the wall posters and the first desk (so the player learns by seeing). Later pages are found items (`item.page`). Collecting pages is a side objective and the lore collectible. Rule 12 is the last page, in Ines's hand, and is found in the Lamp Room.

The rules (full text in `03-ingame-text.md`) teach, in order: you wake in the dark; the rig makes memory not light; white/green/red; every pulse is a sound; do not run toward sounds; the radio only reports; tap greeting (two taps, wait, one); lamp-bags are breadcrumbs; follow the water; some things move only unwatched; if the dark takes you, you wake at the last lit room; someone has to keep the lamp.

## Structure: acts and lit rooms

| Act | Floors / tiers | Section | Lit room after |
|---|---|---|---|
| I | B3, tiers 1 to 2 | **The Annex** (office floor after hours) | **The Night Desk** |
| II | B4, tiers 3 to 4 | **The Flooded Wing** (pipes, blue water) | **The Falls** (the vibrant waterfall safe area) |
| III | B5, tiers 5 to 6 | **The Overgrowth** (greenhouse atrium gone wild) | **The Bunk Room** (crew quarters) |
| IV | B6, tiers 7 to 8 | **The Foundation** (the first floor ever built) | **The Lamp Room** (finale) |
| After | endless | **The Relay** | The Lamp (daily seed lit rooms) |

Pacing rule from Vasco's notes: mostly breath, rarely terror. Sections build tension through the dark and ambience; a **close encounter happens only sometimes** and is the scare. Lit rooms are the exhale. The Falls is the biggest exhale and sits at the end of Act II.

## Mystery threads (what the player pieces together)

1. **The stair that isn't on the plans.** Hollis's tape; the sign-in sheet; the missing floor count on a lift panel.
2. **Six crews, seven attempts.** Crew 6 "held at surface". Crew 7 "(again)". Who is "again"?
3. **What the entities were.** Each has a name, a voice, an object. The player learns it from their things before ever reading the Manual. The Manual entry comes later and is sadder.
4. **Why the radio never gives directions.** Because the Echo does. Real Base counts and reports. The player hears both and learns which to trust (also a Mimic tell).
5. **Who keeps the lamp?** Ines, on the radio all along. Revealed in the Lamp Room, but foreshadowed by the margin notes and the pulled-back respawns.
6. **Pim.** The only proof of an exit. Mug early, postcard late.

## Payoff (Lamp Room)

Ines is alive, tired, lit, green. She does not explain much. She says the dots held, that the map is whole, that you fell {deaths} times and she pulled you back each time, and that the ladder goes up. Pim's postcard is pinned above it. Then the choice. The last page of the Manual, Rule 12, is in her hand: *Someone has to keep the lamp.*

Endings, see `03-ingame-text.md`:

- **End: Up.** Daylight and sound. Credits-style card: "The Understory: mapped." The next run is "Night Shift +", harder, same story.
- **End: Stay.** You take the Lamp. Endless mode, The Relay.

## For the co-op version

Everything above works for 1 to 4. The ethos of the tone: **being seen is what keeps you real.** Suggested light touches (build's call):

- A friend scanning you leaves green dots on you; the Manual margin says so: "Green is someone looking back."
- The tap greeting (ping wheel: two taps, a beat, one tap) is a real friendly signal. The Mimic does the two but skips the beat.
- Lit-room signage and the Guest Book at the Falls acknowledge crews: "Crew 7: 3 in party."
