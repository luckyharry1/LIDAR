#!/usr/bin/env python3
"""Single source of truth for LIDAR in-game text.

Run:  python3 build_text.py
Writes (next to this file): lore-text.json, LoreText.luau, 03-ingame-text.md
Edit the ENTRIES list below, not the outputs.

Entry fields: id, kind, section, where, lines (list of short strings),
optional: speaker, title, glow (reveal only), note (builder note).
Placeholders: {deaths} {floor} {n} {party}. Strings are ASCII only.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MAX_LINE = 90

E = []


def add(id, kind, section, where, lines, speaker=None, title=None, glow=None, note=None):
    d = {"id": id, "kind": kind, "section": section, "where": where, "lines": lines}
    if speaker:
        d["speaker"] = speaker
    if title:
        d["title"] = title
    if glow:
        d["glow"] = glow
    if note:
        d["note"] = note
    E.append(d)


def warm(r):
    return {"color": "amber", "radius": r}


# ---------------------------------------------------------------- Field Manual
# Printed rule + handwritten margin. lines[0] printed, lines[1] margin (if any).
M = "Field Manual page"
add("rule.01", "rule", "any", "Manual p1 and the poster in the first room",
    ["1. Personnel will wake in low light.", "This is normal."], note="margin = line 2 of the printed rule is fine to omit")
add("rule.02", "rule", "any", "Manual p2",
    ["2. The rig does not produce light.", "It produces a record.", "margin: a dot stays where you looked. -J.B."])
add("rule.03", "rule", "any", "Manual p3, colour key poster in the first room",
    ["3. White: structure. Green: crew.", "Red: unaccounted for."])
add("rule.04", "rule", "any", "Manual p4",
    ["4. Every pulse is audible.", "Quiet is a resource. Budget it.", "margin: ask Tobi. -I.C."])
add("rule.05", "rule", "any", "Manual p5",
    ["5. Do not run toward a sound", "you cannot place."])
add("rule.06", "rule", "any", "Manual p6",
    ["6. Base reports. Base counts.", "Base does not give directions.", "margin: she means it. -I.C."])
add("rule.07", "rule", "any", "Manual p7",
    ["7. Crew greet with two taps.", "Then wait. Then one.", "margin: anything that skips the wait is not crew. -R.A."])
add("rule.08", "rule", "any", "Manual p8",
    ["8. If a bag is glowing,", "someone wanted it found.", "margin: that was me. -J.B."])
add("rule.09", "rule", "any", "Manual p9, Flooded Wing wall poster",
    ["9. Follow the water.", "It always ends somewhere lit.", "margin: nobody believed it. it was true. -L.S."])
add("rule.10", "rule", "any", "Manual p10",
    ["10. Some things move only when unobserved.", "margin: watch, then step. never stare. -M.Q."])
add("rule.11", "rule", "any", "Manual p11 (Bunk Room)",
    ["11. Personnel who fail to return", "will wake at the last lit room.", "margin: that is not luck.", "margin: it is her. -T.W."])
add("rule.12", "rule", "lamp", "Manual p12, handwritten, Lamp Room",
    ["12. Someone has to keep the lamp."], speaker="Ines Calder")

# ----------------------------------------------------------- Intake (tutorial)
add("sign.intake.1", "sign", "annex", "Poster, first room, beside the rig table",
    ["STAFF NOTICE", "If lights are out: remain calm,", "locate the rig, and look."],
    note="Replaces any 'press X' prompt. A pictogram of the rig with a cone and dots accompanies it.")
add("sign.intake.2", "sign", "annex", "Poster, first room, colour key",
    ["WHITE  structure", "GREEN  crew", "RED    unaccounted for"],
    note="Pictogram dots in the three colours. Reads like a fire-exit diagram.")
add("sign.intake.3", "sign", "annex", "Stencil above the first door",
    ["EXIT B3", "(two flights down)"], note="Gives the first goal without a prompt.")
add("sign.intake.4", "sign", "annex", "Sticker on the rig table",
    ["PROPERTY OF SURVEY 7.", "RETURN TO LAMP ROOM."])
add("sign.intake.5", "sign", "annex", "Pictogram poster, hand with fingers and a trigger icon",
    ["HOLD TO RECORD."], note="Mobile: icon of a thumb on the on-screen button.")

# ---------------------------------------------------------------------- Annex
add("sign.annex.1", "sign", "annex", "Arrow sign in a cubicle hallway, pointing at a wall",
    ["EXIT ->", "(the arrow points at a wall)"], note="Second line is a pencilled note under the sign.")
add("sign.annex.2", "sign", "annex", "Whiteboard / meeting room bulletin",
    ["MEETING MOVED TO B3", "ATTENDANCE: MANDATORY", "ATTENDEES: 6 of 7"])
add("sign.annex.3", "sign", "annex", "Break room fridge note",
    ["WHOEVER KEEPS TAKING THE LAST TEA:", "WE CAN HEAR YOU."], note="Light humour before the dark turns.")
add("sign.annex.4", "sign", "annex", "Copier",
    ["OUT OF PAPER.", "PLEASE STOP COPYING THE SAME PAGE."])
add("rec.annex.1", "recorder", "annex", "Hidden in a desk drawer in a cubicle, tier 1 to 2",
    ["Day one. Hollis was right.", "There is a stair under B3.", "It is not on any plan.", "We brought lamps. Joss thinks they will do."],
    speaker="Ines Calder, Crew 1")
add("rec.annex.2", "recorder", "annex", "Taped under a table in the break room",
    ["Lamp-bags work. Bulb, cell, sack.", "Hang one at every turn, you find your way home.", "Ines says the walls move when we are not looking.", "I say prove it."],
    speaker="Joss Berrow, Crew 1")
add("rec.annex.3", "recorder", "annex", "Answering-machine tape on a front-desk phone",
    ["Hollis, nights. Doing my rounds.", "Fourth floor lights are out again.", "Fifth too. I will just check the stairs.", "Back in a minute."],
    speaker="Mr. Hollis")
add("rev.annex.lamp", "reveal", "annex", "Desk lamp on an abandoned cubicle desk",
    ["A desk lamp.", "Still warm."], glow=warm(8))
add("rev.annex.whiteboard", "reveal", "annex", "Whiteboard in a meeting room",
    ["SURVEY RULES v1", "1. Do not go alone.", "(someone struck out ALONE)"], glow=warm(6))
add("rev.annex.kettle", "reveal", "annex", "Kettle on its side, row of tea bags",
    ["Tea bags in a row on the shelf.", "One for every night someone stayed."], glow=warm(5))
add("rev.annex.coat", "reveal", "annex", "Coat on a hook, name tag HOLLIS",
    ["A custodian's coat.", "The pocket is empty.", "Whatever he carried, he took."], glow=warm(5))
add("sign.pit.1", "sign", "annex", "Yellow paint at an open lift shaft",
    ["MIND THE EDGE.", "(there is no floor)"], note="Painted edge, felt before seen.")

# ----------------------------------------------------------------- Night Desk
add("note.desk.signin", "note", "desk", "Sign-in sheet clipped to the desk",
    ["SIGN-IN  B3", "CREW 1  IN", "CREW 2  IN", "CREW 3  IN", "CREW 4  IN", "CREW 5  IN", "CREW 6  HELD AT SURFACE", "CREW 7  IN (again)"],
    note="Crew 7's line is in a different pen, as if filled in many times.")
add("note.desk.self", "note", "desk", "Torn note under the lamp",
    ["The second door is wrong.", "Take the third.", "- 7"],
    note="Same handwriting as the sign-in sheet. Do not comment on it.")
add("rev.desk.mugs", "reveal", "desk", "Mug rack with seven mugs",
    ["Seven mugs.", "Six are stained.", "The seventh is clean."], glow=warm(6))
add("sign.desk.waterline", "sign", "desk", "Poster by the stair down",
    ["B4: MECHANICAL", "WATERLINE MARKED IN RED", "(it has been repainted)"])
add("radio.desk.1", "radio", "desk", "Radio on the desk, first time",
    ["Base to Seven. Lamp is holding.", "Base to Seven. Floor B3 is quiet."], speaker="Base")
add("rev.desk.board", "reveal", "desk", "Corkboard of crew photos",
    ["SIX CREWS", "A seventh frame is empty.", "Someone left a pin in it."], glow=warm(6))

# --------------------------------------------------------------- Flooded Wing
add("sign.flood.1", "sign", "flood", "Floor sign at the water's edge",
    ["WET FLOOR.", "(it is now)"])
add("sign.flood.2", "sign", "flood", "Stencil above a pump room door",
    ["DO NOT LINGER IN THE WATER."], note="Never say why.")
add("sign.flood.grate", "sign", "flood", "Chain hung across a rusted drain grating",
    ["DRAIN B4-7", "LOAD LIMIT: A PERSON, ONCE"], note="Warns of a grating that gives way.")
add("sign.plate.1", "sign", "flood", "Small bell by a floor plate",
    ["PLEASE DO NOT STEP ON THE PLATE.", "- Crew 2"], note="Alarm plate trap. The bell is crew 2's early warning, rings and draws enemies.")
add("rec.flood.1", "recorder", "flood", "Wedged in a pipe bracket",
    ["Tobi Wren, sound.", "I can hear the building thinking.", "Gain up. It is so quiet down here.", "If I do not talk, nothing hears me."],
    speaker="Tobi Wren, Crew 3")
add("rec.flood.2", "recorder", "flood", "On a catwalk rail",
    ["I stopped talking. It is better.", "I can hear everyone breathing, far off.", "If I just stay very still", "they walk right past."],
    speaker="Tobi Wren, Crew 3", note="Plays near a Listener lair for atmosphere.")
add("rec.flood.3", "recorder", "flood", "Inside the boiler room",
    ["Joss, boiler room.", "The water was not here yesterday.", "Or it was here, and we were not looking.", "Ines has a theory. It is not a nice one."],
    speaker="Joss Berrow, Crew 1")
add("rev.flood.boat", "reveal", "flood", "Half-sunk rubber dinghy",
    ["A dinghy. Crew 2 paddled this far.", "The oars are gone.", "So is the third seat."], glow=warm(7))
add("rev.flood.lifering", "reveal", "flood", "Life ring painted B3",
    ["LIFE RING  B3.", "Hung before the water came.", "Who knew?"], glow=warm(6))
add("rev.flood.headphones", "reveal", "flood", "Headphones draped on a pipe",
    ["Headphones. Gain all the way up.", "He would not leave them."], glow=warm(5))
add("rev.flood.valve", "reveal", "flood", "Large valve wheel station",
    ["A valve wheel station.", "The wheel is missing.", "A wheel-shaped clean patch in the dust."], glow=warm(6))

# ---------------------------------------------------------------------- Falls
add("rec.falls.1", "recorder", "falls", "Hidden by the hammocks, on a ledge",
    ["Day forty. I stopped counting.", "We found a place the dark cannot rewrite.", "Everyone remembers it the same way.", "That is the trick. Everyone has stood here."],
    speaker="Ines Calder, Crew 1")
add("rec.falls.2", "recorder", "falls", "Under the camp stove",
    ["Hammocks up. Soup on.", "First hot meal in a month.", "Ravi plays the one song he knows. Badly.", "I did not know I could miss a sound this much."],
    speaker="Lena Sorrel, Crew 2")
add("note.falls.guestbook", "note", "falls", "Guest Book on a stone",
    ["GUEST BOOK", "{party}", "Everyone signs. Nobody says what for."],
    note="Optional: fill {party} with real player names who reached the Falls. Static fallback: 'Crew 7 signed here.'")
add("rev.falls.behind", "reveal", "falls", "Hidden alcove behind the waterfall",
    ["A chalk drawing of the whole building.", "Stairs at the bottom. Falls near the top.", "A circle, at the very bottom. LAMP."], glow={"color": "warm white", "radius": 10})
add("rev.falls.hammock", "reveal", "falls", "Hammock with a name stitched on",
    ["L. SORREL.", "She slept better here than anywhere."], glow=warm(6))
add("sign.falls.1", "sign", "falls", "Hand-painted wooden sign",
    ["THE FALLS", "(probably not on any plan)"])

# ----------------------------------------------------------------- Overgrowth
add("sign.over.1", "sign", "over", "Tag on a living plant",
    ["PLEASE WATER ME.", "- P."])
add("sign.over.2", "sign", "over", "Greenhouse notice",
    ["STAFF MUST NOT FEED THE PLANTS.", "THEY HAVE BEEN FED."])
add("sign.plate.2", "sign", "over", "Bell hung in the roots",
    ["TWO TAPS. WAIT. ONE.", "(or step around)"], note="Alarm plate in a root passage. Reinforces the greeting.")
add("sign.pit.2", "sign", "over", "Rope and yellow paint at a sinkhole",
    ["ROPE REQUIRED.", "ROPE NOT PROVIDED."], note="Rope item solves it.")
add("rec.over.1", "recorder", "over", "Under a greenhouse bench",
    ["Ravi, signals.", "Two taps, a breath, one tap.", "It was just a greeting.", "Now I cannot stop hearing the first two."],
    speaker="Ravi Anand, Crew 2")
add("rec.over.2", "recorder", "over", "In a planter",
    ["It taps back perfectly.", "It does not get the pause.", "It never waits for the pause.", "That is how you know."],
    speaker="Ravi Anand, Crew 2")
add("rec.over.3", "recorder", "over", "Camp stove, cold",
    ["Pim, intern. Crew 5.", "Everyone says there is no way out.", "I keep finding drafts. A draft means a door.", "If I am not here tomorrow, I found it."],
    speaker="Pim Ashworth, Crew 5")
add("rev.over.greenhouse", "reveal", "over", "Grow light and one live plant",
    ["One grow light, still humming.", "One plant, still green.", "Someone waters it."], glow={"color": "pale green-white", "radius": 8},
    note="Pale light, not the green of friends.")
add("rev.over.tapcode", "reveal", "over", "Brass plate on a pillar",
    ["Two taps. Wait. One.", "Cut into brass, so it would last.", "A greeting."], glow=warm(5))
add("rev.over.camp", "reveal", "over", "Cold camp stove with four mugs",
    ["Four mugs.", "Three are chipped.", "One says PIM."], glow=warm(6))

# ------------------------------------------------------------------- Bunk Room
add("rec.bunk.1", "recorder", "bunk", "On the stove shelf, plays on interaction",
    ["Theory.", "The Understory is what a building forgets.", "Rooms nobody enters. Halls nobody checks.", "It fills with whatever is left.", "We are not hunted. We are forgotten.", "Green is not a colour. Green is someone looking back."],
    speaker="Ines Calder, Crew 1")
add("note.bunk.board", "note", "bunk", "Corkboard: WHO'S STILL OUT",
    ["WHO'S STILL OUT", "HOLLIS  rounds", "WREN  listening", "ANAND  tapping", "QUILL  watching", "ASHWORTH  (circled)"],
    note="Lines are crossed out in varying pens, 'ASHWORTH' is circled in green.")
add("note.bunk.letters", "note", "bunk", "Letters pinned to a bunk",
    ["Dear Mum. We are fine. The pay is good.", "I cannot tell you where. It is quiet here.", "Dear Mum. We are fine."],
    note="Repeated opening is intentional.")
add("note.bunk.pim", "note", "bunk", "Folded note under a bunk",
    ["Gone to find the ladder.", "Left my mug for luck.", "- P."])
add("rev.bunk.model", "reveal", "bunk", "Model of the Halden Building",
    ["A model of the building.", "Each floor lit. One, at the bottom, is not.", "A match sits beside it."], glow=warm(7))
add("rev.bunk.door", "reveal", "bunk", "Stencilled CREW door in the dark",
    ["CREW QUARTERS.", "Knock twice. Wait. Once."], glow=warm(5))
add("rev.bunk.calendar", "reveal", "bunk", "Wall calendar",
    ["Every day circled.", "Past the printed month.", "Past the year."], glow=warm(5))

# ------------------------------------------------------------------ Foundation
add("sign.found.1", "sign", "found", "Entrance stencil",
    ["CLEARANCE: NONE.", "NOBODY SAYS WHO SET THIS."])
add("sign.found.2", "sign", "found", "Graffiti on a pillar",
    ["KEEP LOOKING."], note="Stalker-zone graffiti.")
add("sign.found.3", "sign", "found", "Tape on concrete",
    ["SHH"], note="Listener-zone graffiti, anywhere.")
add("sign.plate.3", "sign", "found", "Chalk under a floor plate",
    ["NOT HERE.", "- I.C."])
add("sign.pit.3", "sign", "found", "Wall of a drop shaft",
    ["MARKED EDGE.", "JOSS PAINTED THE EDGE SO YOU WOULD FEEL IT FIRST."])
add("rec.found.1", "recorder", "found", "On a pillar in the Foundation hall",
    ["Last descent. I know where the Lamp goes.", "The Foundation is the first floor they built.", "Before the plan. Before the paper.", "It is not cruel. It is empty. Empty gets hungry for company."],
    speaker="Ines Calder, Crew 1")
add("rec.found.2", "recorder", "found", "Tucked into the camera case",
    ["Quill, photography.", "Flash only works when it is not looking.", "Forty frames of the corridor.", "In frame thirty it is closer."],
    speaker="Marlow Quill, Crew 4")
add("rec.found.3", "recorder", "found", "On a chalk-marked shelf",
    ["Keep watching. Then step.", "Never stare. It learns the stare.", "If you hear a shutter, do not turn.", "Wait for the second click."],
    speaker="Marlow Quill, Crew 4")
add("rev.found.camera", "reveal", "found", "Camera on a tripod facing the hall",
    ["A camera on a tripod, facing the corridor.", "The shutter is half pressed.", "Quill never finished the shot."], glow={"color": "cold white", "radius": 7})
add("rev.found.stone", "reveal", "found", "Cornerstone",
    ["FOUNDATION STONE.", "The first thing built.", "Nobody remembers who laid it."], glow=warm(8))
add("rev.found.chalk", "reveal", "found", "Chalk arrow trail",
    ["Chalk arrows. Fresh.", "I.C."], glow=warm(6))

# -------------------------------------------------------------- Lamp Room / end
add("card.lamp", "card", "lamp", "Title card entering the Lamp Room", ["THE LAMP ROOM", "someone kept it on"], title="The Lamp Room")
add("rev.lamp.postcard", "reveal", "lamp", "Postcard pinned above the ladder",
    ["POSTCARD", "The surface is loud.", "Bring the others.", "- Pim"], glow=warm(8))
add("npc.ines.1", "npc", "lamp", "Ines, on entering", ["Seven. Good.", "The dots held."], speaker="Ines")
add("npc.ines.2", "npc", "lamp", "Ines, second line",
    ["Every time the dark took you,", "I pulled you back to the last light."], speaker="Ines")
add("npc.ines.3", "npc", "lamp", "Ines, variant with deaths > 0",
    ["{deaths} times.", "Each night a little further."], speaker="Ines")
add("npc.ines.3z", "npc", "lamp", "Ines, variant with deaths == 0",
    ["You never fell.", "That is not luck. That is care."], speaker="Ines")
add("npc.ines.4", "npc", "lamp", "Ines, third line",
    ["The whole map held tonight.", "Look. All of it."], speaker="Ines")
add("npc.ines.5", "npc", "lamp", "Ines, pointing up",
    ["The ladder goes up.", "Pim made it. So can you."], speaker="Ines")
add("npc.ines.6", "npc", "lamp", "Ines, last line before the choice",
    ["Or sit with me a while.", "Someone has to keep the lamp."], speaker="Ines")
add("choice.up", "choice", "lamp", "Dialogue choice 1", ["Climb the ladder."])
add("choice.stay", "choice", "lamp", "Dialogue choice 2", ["Take the lamp."])
add("end.up", "ending", "lamp", "End card, climbing",
    ["The air changes first.", "Then sound. Then a colour you forgot.", "Up here, it is morning.", "THE UNDERSTORY: MAPPED"],
    note="Offers the next run: 'Night Shift +'.")
add("end.stay", "ending", "lamp", "End card, keeping the lamp",
    ["The lamp is heavier than it looks.", "Down here, the dark is only unfinished.", "Somebody will wake and need a light.", "THE RELAY"],
    note="Unlocks endless mode.")
add("npc.pim.recording", "recorder", "lamp", "Pinned recorder by the ladder",
    ["It works. I'm out.", "I can hear traffic.", "Tell Ines the lamp worked. Tell her thank you."],
    speaker="Pim Ashworth")

# ----------------------------------------------------------------------- Radio
add("radio.base.1", "radio", "any", "Radio, idle in a lit room", ["Base to Seven. Lamp is holding."], speaker="Base")
add("radio.base.2", "radio", "any", "Radio, new floor", ["Base to Seven. Floor {floor}. Counting."], speaker="Base")
add("radio.base.3", "radio", "any", "Radio, randomly in the dark", ["Base to Seven. I can see you."], speaker="Base")
add("radio.base.4", "radio", "any", "Radio, randomly in the dark", ["Base to Seven.", "One. Two. Three. Still here."], speaker="Base")
add("radio.base.5", "radio", "any", "Radio, after a level clear", ["Base to Seven. Logged."], speaker="Base")
add("radio.back.1", "radio", "any", "Radio, on respawn", ["Welcome back. Breathe.", "You are lit."], speaker="Base")
add("radio.back.2", "radio", "any", "Radio, on respawn", ["Back at the last lamp. Good."], speaker="Base")
add("radio.back.3", "radio", "any", "Radio, on respawn", ["Easy. Easy. Count with me."], speaker="Base")
add("radio.fake.1", "radio", "over", "Radio near the Mimic ONLY", ["Seven. This way.", "Come toward my voice."], speaker="Base?", note="Real Base never gives directions. The fake does. This is the tell.")
add("radio.fake.2", "radio", "over", "Radio near the Mimic ONLY", ["Put the rig down, Seven.", "It is safe here."], speaker="Base?")
add("radio.fake.3", "radio", "over", "Radio near the Mimic ONLY", ["Base to Seven. Turn left.", "Left. Now."], speaker="Base?")
add("radio.fake.4", "radio", "over", "Radio near the Mimic ONLY", ["Two taps.", "(tap tap) ...Seven?"], speaker="Base?", note="It skips the beat.")

# ---------------------------------------------------------------- Entity pages
add("ent.wanderer", "entity", "annex", "Manual page unlocked on first sighting",
    ["THE PACER", "Walks the same rounds every night.", "Keys on a ring.", "margin: he was a custodian. he is still working. -I.C."],
    note="In-game name shown to the player: 'the Pacer'. Spec name: Wanderer.")
add("ent.listener", "entity", "flood", "Manual page unlocked on first sighting",
    ["THE HUSH", "No eyes. Hears everything.", "Pulses and footsteps draw it.", "margin: walk. do not run. do not ping. -T.W."],
    note="Spec name: Listener.")
add("ent.mimic", "entity", "over", "Manual page unlocked on first sighting",
    ["THE ECHO", "Reads as crew. Answers every call.", "margin: it cannot wait. -R.A."],
    note="Spec name: Mimic.")
add("ent.stalker", "entity", "found", "Manual page unlocked on first sighting",
    ["THE STILL", "Moves when it is not seen.", "margin: watch, then step. never stare. -M.Q."],
    note="Spec name: Stalker.")

# ---------------------------------------------------------------- Title cards
add("card.annex", "card", "annex", "Level card B3", ["B3", "THE ANNEX", "offices after hours"], title="The Annex")
add("card.desk", "card", "desk", "Lit room card", ["THE NIGHT DESK", "still on"], title="The Night Desk")
add("card.flood", "card", "flood", "Level card B4", ["B4", "THE FLOODED WING", "mind the waterline"], title="The Flooded Wing")
add("card.falls", "card", "falls", "Lit room card", ["THE FALLS", "somebody remembered this"], title="The Falls")
add("card.over", "card", "over", "Level card B5", ["B5", "THE OVERGROWTH", "please water me"], title="The Overgrowth")
add("card.bunk", "card", "bunk", "Lit room card", ["THE BUNK ROOM", "knock twice"], title="The Bunk Room")
add("card.found", "card", "found", "Level card B6", ["B6", "THE FOUNDATION", "before the plan"], title="The Foundation")
add("card.relay", "card", "relay", "Endless floor card", ["RELAY FLOOR {n}", "lit once before"], title="The Relay")
add("card.relay.daily", "card", "relay", "Daily seed card", ["TONIGHT'S FLOOR", "same for everyone"], title="Daily")
add("sign.relay.1", "sign", "relay", "Poster on a Relay floor", ["IF YOU CAN READ THIS,", "SOMEONE LIT IT FIRST."])
add("sign.relay.2", "sign", "relay", "Poster on a Relay floor", ["THANK YOU, TWO NIGHTS AGO."])
add("sign.relay.3", "sign", "relay", "Poster on a Relay floor", ["CREW 8: THE KETTLE WORKS.", "TEA IS IN THE TIN."])

# ---------------------------------------------------------------- Items
for iid, name, desc, where in [
    ("cell", "Battery Cell", ["Hums when it is full."], "Annex T1 and everywhere"),
    ("lampbag", "Lamp-Bag", ["A bulb in a canvas sack.", "J.B. 3/7"], "Breadcrumb item, all floors"),
    ("key", "Brass Key", ["Stamped B3.", "Fits something below."], "Annex/Flooded gate"),
    ("fuse", "Fuse", ["Not blown. Just waiting."], "Annex T2 and Overgrowth T6"),
    ("valve", "Valve Wheel", ["Heavy, slick, missing from somewhere."], "Flooded T3"),
    ("chalk", "Chalk", ["White. Marks stay."], "Annex, optional"),
    ("tea", "Cold Tea", ["Sweet, strong, cold.", "Steadies the hands."], "Falls and side rooms"),
    ("rope", "Rope", ["Joss's knots. They hold."], "Flooded T4 and Overgrowth T6"),
    ("crank", "Skylight Crank", ["Opens something high above."], "Overgrowth T5"),
    ("core", "Lamp Core", ["Glass, faintly lit.", "Carry it gently."], "Foundation T7"),
    ("page", "Manual Page", ["Torn from the booklet."], "Collectible, all floors"),
    ("flashbulb", "Flash Bulb", ["Quill's last spare."], "Foundation, one flash"),
    ("photo", "Photograph", ["Crew 1, smiling.", "Before."], "Collectible"),
    ("mug", "Pim's Mug", ["Chipped.", "PIM, in marker."], "Overgrowth camp"),
    ("headphones", "Headphones", ["Warm. Gain all the way up."], "Flooded Wing, one"),
    ("map", "Pencil Map", ["Half a floor, in Ines's hand."], "Foundation"),
    ("glowstick", "Glow Stick", ["Snap it. Twenty seconds of amber."], "Any, consumable"),
    ("badge", "Crew Badge", ["Crew 7.", "The photo is a smudge."], "Night Desk"),
]:
    add("item." + iid, "item", "any", where, [name + ": " + " ".join(desc)], title=name,
        note="Name is lines[0] before the colon; description follows it.")

# ---------------------------------------------------------------- Hints (fallback, only if needed)
HINTS = [
    ("fire", "Hold to record.", "Fallback only; prefer sign.intake.*"),
    ("mobile", "Thumb on the button.", "Mobile only"),
    ("door", "Doors open to those who looked.", "Fallback"),
    ("pickup", "Take what is left for you.", "Fallback"),
    ("tap", "Two taps. Wait. One.", "Ping wheel greeting"),
    ("heat", "The rig runs warm.", "Overheat"),
    ("water", "Water carries sound.", "Entering water"),
    ("pit", "Mind the edge.", "Near a drop"),
    ("plate", "Something is listening to the floor.", "Near a plate"),
    ("recorder", "A click. A tape starts.", "Recorder activates"),
    ("lamp", "A bag begins to glow.", "Lamp-bag ignites"),
    ("manual", "A page, torn from the booklet.", "Manual page picked up"),
]
for h, text, where in HINTS:
    add("hint." + h, "hint", "any", where, [text], note="Optional fallback. Keep rare.")

# ---------------------------------------------------------------- Loading tips (rumour style)
TIPS = [
    "Crew 3 says the water remembers.",
    "Green is someone looking back.",
    "The lamp is on.",
    "The second door is wrong.",
    "If you hear keys, wait.",
    "Quiet costs nothing.",
    "Base counts. Base does not command.",
    "Tea bags in a row. Count them.",
    "It cannot wait.",
    "Chalk arrows are fresh.",
]
for i, t in enumerate(TIPS, 1):
    add("tip.%02d" % i, "tip", "any", "Loading screen / respawn screen", [t])

# ---------------------------------------------------------------- Ping wheel labels
for pid, label in [("here", "Here"), ("wait", "Wait"), ("danger", "Danger"), ("item", "Found"), ("tap", "Two taps")]:
    add("ping." + pid, "system", "any", "Ping wheel label", [label])


# ---------------------------------------------------------------- Small havens (lit break after tiers 1, 3, 5, 7)
add("card.haven.copy", "card", "annex", "Haven card after tier 1", ["THE COPY ROOM", "the machine is still warm"], title="The Copy Room")
add("note.haven.copy", "note", "annex", "Page in the copier tray, Copy Room",
    ["A page, still warm from the machine.", "A map of the corridor just left.", "Drawn from the other side."])
add("card.haven.booth", "card", "flood", "Haven card after tier 3", ["THE DRY BOOTH", "pump house, lamp on"], title="The Dry Booth")
add("note.haven.booth", "note", "flood", "Shift log on the booth wall",
    ["SHIFT LOG  PUMP HOUSE", "Water level: up.", "Water level: up.", "Water level: we stopped writing it down."])
add("card.haven.shed", "card", "over", "Haven card after tier 5", ["THE POTTING SHED", "a lantern, a bench, a window"], title="The Potting Shed")
add("note.haven.shed", "note", "over", "Seed packets on the bench",
    ["Seed packets, labelled in a careful hand.", "TOMATO. BEAN. SOMETHING ELSE.", "Someone planted all three."])
add("card.haven.nook", "card", "found", "Haven card after tier 7", ["THE ARCHIVE NOOK", "one lamp between the shelves"], title="The Archive Nook")
add("note.haven.nook", "note", "found", "Card index with one drawer open",
    ["Card index, one drawer open.", "Every card says SEEN.", "The last one says SEEN BY: ____."])
add("radio.haven.1", "radio", "any", "Radio in any small haven", ["Base to Seven. Rest.", "I have you."], speaker="Base")
add("rev.nook.1", "reveal", "any", "Lamp-bag on a hook, mug beneath it (mid-level lit spot)",
    ["A lamp-bag on a hook.", "A mug beneath it. Still warm."], glow=warm(6))
add("rev.nook.2", "reveal", "any", "Lamp-bag over a folding stool",
    ["A stool. A bag of light.", "Somebody sat here and waited."], glow=warm(6))
add("rev.nook.3", "reveal", "any", "Lamp-bag taped to a corner",
    ["J.B. 3/7.", "He hung one at every turn."], glow=warm(7))
add("rev.nook.4", "reveal", "any", "Lamp-bag with a tag, burnt out",
    ["The bulb is dead.", "The tag reads: KEEP GOING."], glow={"color": "dim amber", "radius": 4})


# ---------------------------------------------------------------- Output
def validate():
    ids = set()
    ok = True
    for e in E:
        if e["id"] in ids:
            print("DUPLICATE", e["id"])
            ok = False
        ids.add(e["id"])
        for ln in e["lines"]:
            if not ln.isascii():
                print("NON-ASCII", e["id"], ln)
                ok = False
            if len(ln) > MAX_LINE:
                print("LONG", e["id"], len(ln))
                ok = False
    return ok


def luau_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    if not validate():
        sys.exit(1)
    with open(os.path.join(HERE, "lore-text.json"), "w") as f:
        json.dump({"entries": E}, f, indent=1)
        f.write("\n")
    out = ["--!strict", "-- Generated by build_text.py. Do not edit by hand.", "export type Entry = {", "\tid: string,", "\tkind: string,", "\tsection: string,", "\twhere: string,", "\tlines: { string },", "\tspeaker: string?,", "\ttitle: string?,", "\tglow: { color: string, radius: number }?,", "\tnote: string?,", "}", "", "local entries: { Entry } = {"]
    for e in E:
        parts = ["id = " + luau_str(e["id"]), "kind = " + luau_str(e["kind"]), "section = " + luau_str(e["section"]), "where = " + luau_str(e["where"])]
        parts.append("lines = { " + ", ".join(luau_str(x) for x in e["lines"]) + " }")
        if "speaker" in e:
            parts.append("speaker = " + luau_str(e["speaker"]))
        if "title" in e:
            parts.append("title = " + luau_str(e["title"]))
        if "glow" in e:
            parts.append("glow = { color = %s, radius = %d }" % (luau_str(e["glow"]["color"]), e["glow"]["radius"]))
        if "note" in e:
            parts.append("note = " + luau_str(e["note"]))
        out.append("\t{ " + ", ".join(parts) + " },")
    out += ["}", "", "local byId: { [string]: Entry } = {}", "for _, e in entries do", "\tbyId[e.id] = e", "end", "", "local LoreText = {}", "LoreText.entries = entries", "", "function LoreText.get(id: string): Entry?", "\treturn byId[id]", "end", "", "function LoreText.ofKind(kind: string): { Entry }", "\tlocal r = {}", "\tfor _, e in entries do", "\t\tif e.kind == kind then", "\t\t\ttable.insert(r, e)", "\t\tend", "\tend", "\treturn r", "end", "", "return LoreText", ""]
    with open(os.path.join(HERE, "LoreText.luau"), "w") as f:
        f.write("\n".join(out))
    # markdown
    sec_names = {"any": "Any floor", "annex": "Annex (B3, T1-2)", "desk": "Night Desk (lit)", "flood": "Flooded Wing (B4, T3-4)", "falls": "The Falls (lit)", "over": "Overgrowth (B5, T5-6)", "bunk": "Bunk Room (lit)", "found": "Foundation (B6, T7-8)", "lamp": "Lamp Room (finale)", "relay": "The Relay (endless)"}
    kind_order = ["rule", "sign", "recorder", "reveal", "note", "radio", "npc", "choice", "ending", "entity", "card", "item", "hint", "tip", "system"]
    md = ["# In-game text", "", "Generated by `build_text.py` from the same data as `lore-text.json` and `LoreText.luau`. Do not edit this file; edit the script.", "", "Placeholders: `{deaths}` `{floor}` `{n}` `{party}`. Lines are separate lines of the same message.", ""]
    for k in kind_order:
        items = [e for e in E if e["kind"] == k]
        if not items:
            continue
        md.append("## " + k)
        md.append("")
        md.append("| id | section | where | text |")
        md.append("|---|---|---|---|")
        for e in items:
            txt = "<br>".join(e["lines"])
            spk = (e.get("speaker", "") + ": ") if e.get("speaker") else ""
            gl = ""
            if "glow" in e:
                gl = " *(glow: %s, r=%s)*" % (e["glow"]["color"], e["glow"]["radius"])
            nt = (" *Note: " + e["note"] + "*") if e.get("note") else ""
            md.append("| `%s` | %s | %s | %s%s%s%s |" % (e["id"], sec_names.get(e["section"], e["section"]), e["where"], spk, txt, gl, nt))
        md.append("")
    with open(os.path.join(HERE, "03-ingame-text.md"), "w") as f:
        f.write("\n".join(md))
    print("entries:", len(E))


if __name__ == "__main__":
    main()
