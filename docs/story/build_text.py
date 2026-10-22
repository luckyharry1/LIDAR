#!/usr/bin/env python3
"""Single source of truth for LIDAR in-game text, v2 (Backrooms pivot, 2026-10-22).

Run:  python3 build_text.py
Writes (next to this file): lore-text.json, LoreText.luau, 03-ingame-text.md,
       04-cutscenes-and-tapes.md
Edit the data below, not the outputs.

Entry fields: id, kind, section, where, lines, optional speaker, title, glow, note,
              thought (Theo's reaction line, subtitled and ideally voiced), look (key in LOOKS),
              vo (voice + delivery).
Scenes (cutscenes, tapes, dialogue): id, kind, title, where, trigger, beats.
  beat = {sp, line} spoken, or {shot} a picture/sound direction.
Looks: per-area backdrop spec the builder uses when a light ignites.
Placeholders: {deaths} {floor} {n} {party}. ASCII only.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MAX_LINE = 100

E = []
SCENES = []

# ------------------------------------------------------------------ looks
# What a light reveals. Every area has its own wall, floor, light and sound so no two areas
# share a vibe. A light ignites on the FIRST dot that lands on it (or within `igniteReach` of
# it) and fades in over `fadeIn` seconds. It paints a patch of this backdrop on the nearby
# walls and floor out to `radius` studs.
LOOKS = {
    "l0": {
        "name": "Level 0: The Office Floor",
        "walls": {"material": "Fabric", "color": [214, 188, 92], "note": "damp yellow wallpaper, vertical stripe, peeling at the seams"},
        "floor": {"material": "Carpet", "color": [112, 96, 58], "note": "stained brown-olive carpet tile, water ring marks"},
        "ceiling": "drop-ceiling tiles, one missing every few cells",
        "light": {"color": [255, 226, 150], "kind": "fluorescent buzz, warm, flicker"},
        "sound": "dead fluorescent buzz, ceiling fan, far copier warming up, keys",
        "props": "cubicles, water cooler, vending machine, CRT and VCR",
    },
    "l1": {
        "name": "Level 1: The Flooded Wing",
        "walls": {"material": "Ceramic", "color": [200, 226, 232], "note": "white-blue pool tile, grout lines, rust streaks"},
        "floor": {"material": "Ceramic", "color": [150, 190, 205], "note": "wet tile; water is blue (45,120,200) ankle to knee"},
        "ceiling": "low pipes and conduit, condensation drips",
        "light": {"color": [150, 230, 255], "kind": "cold cyan, rippling reflections on the ceiling"},
        "sound": "echoing drips, slow pump thud, rusted gate, splashes that are not yours",
        "props": "valve stations, life rings, boilers, catwalks, dinghy",
    },
    "falls": {
        "name": "The Falls (Refuge)",
        "walls": {"material": "Rock", "color": [96, 120, 84], "note": "mossy cavern stone, ferns, hanging vines"},
        "floor": {"material": "LeafyGrass", "color": [96, 150, 70], "note": "grass and flat stones round a shallow basin"},
        "ceiling": "open shaft, golden light pours down with the water",
        "light": {"color": [255, 236, 170], "kind": "warm sun from nowhere plus green bounce; the most colourful place in the game"},
        "sound": "waterfall, wind chimes, birds that cannot exist, guitar with one string missing",
        "props": "hammocks, string lights, camp stove, mural wall behind the falls",
    },
    "l2": {
        "name": "Level 2: The Wards",
        "walls": {"material": "SmoothPlastic", "color": [170, 200, 184], "note": "institutional pale green, white tile dado, scuffs from gurney rails"},
        "floor": {"material": "Plastic", "color": [122, 150, 136], "note": "grey-green hospital linoleum, long wax streaks"},
        "ceiling": "acoustic tile, a flickering strip light, a PA speaker",
        "light": {"color": [214, 255, 240], "kind": "clinical teal-white, hard flicker"},
        "sound": "PA with no one speaking, squeaking wheels, a call bell, wet tap-tap",
        "props": "gurneys, curtains on rails, nurse station, charts, wheelchairs",
    },
    "c2": {
        "name": "Ward Station (Ravi's camp)",
        "walls": {"material": "SmoothPlastic", "color": [200, 214, 200], "note": "same ward green but washed warm by a table lamp and curtains drawn"},
        "floor": {"material": "Plastic", "color": [150, 150, 132], "note": "rugs thrown over the linoleum"},
        "ceiling": "curtain rail turned into a hanging line of lamp-bags",
        "light": {"color": [255, 214, 150], "kind": "warm amber table lamp, soft"},
        "sound": "kettle, a cassette player turned very low",
        "props": "nurse station fort, mattress pile, radio unplugged on purpose",
    },
    "l3": {
        "name": "Level 3: The Hollow",
        "walls": {"material": "Rock", "color": [62, 52, 84], "note": "dark violet cave rock, mineral veins, roots through a Halden door frame"},
        "floor": {"material": "Ground", "color": [86, 66, 52], "note": "packed earth, root ridges, shallow pools of glowing spores"},
        "ceiling": "stalactites, hanging root curtains",
        "light": {"color": [130, 150, 255], "kind": "blue-violet bioluminescence; glowcaps pulse slowly"},
        "sound": "dripping stone, soft pulsing hum, breath that is the cave, glass-bell chimes",
        "props": "glowcap clusters, crystal veins, rope bridges, Pim's lantern line",
    },
    "l4": {
        "name": "Level 4: The Garage",
        "walls": {"material": "Concrete", "color": [128, 128, 134], "note": "raw poured concrete, yellow stripes, level numbers stencilled"},
        "floor": {"material": "Asphalt", "color": [76, 76, 82], "note": "painted bays and arrows, oil stains, ramps down"},
        "ceiling": "exposed beams, sodium lamps, pipes",
        "light": {"color": [255, 170, 70], "kind": "orange sodium, flat, buzzing"},
        "sound": "wind down the ramps, tyre squeal in the distance, a shutter click, the Lamp's hum far below",
        "props": "parked shapes under tarps, ticket machine, boom gate, drop shafts",
    },
    "lamp": {
        "name": "The Lamp Room",
        "walls": {"material": "Wood", "color": [140, 104, 66], "note": "brass and timber, shelves of lamp-bags, Pike's old survey table"},
        "floor": {"material": "WoodPlanks", "color": [160, 120, 78], "note": "worn boards, a rug, chalk circle round the Lamp"},
        "ceiling": "domed, open to a ladder shaft with a thread of daylight",
        "light": {"color": [255, 240, 200], "kind": "warm white gold from the Lamp, steady, no flicker"},
        "sound": "the Lamp's low hum, wind in the shaft, a kettle",
        "props": "the Lamp, desk, chalkboard of the whole point cloud, ladder",
    },
    "desk": {
        "name": "Outpost Zero (the Night Desk)",
        "walls": {"material": "Fabric", "color": [190, 168, 100], "note": "the same L0 wallpaper, but clean and hung with maps and photos"},
        "floor": {"material": "Carpet", "color": [140, 112, 74], "note": "a rug laid over the carpet"},
        "ceiling": "plain, one banker's lamp",
        "light": {"color": [255, 214, 140], "kind": "banker's lamp, warm"},
        "sound": "kettle, ticking clock, the radio hiss",
        "props": "desk, radio, corkboard of crews, cot, kettle",
    },
    "c0": {
        "name": "Supply Closet (Joss's camp)",
        "walls": {"material": "Plaster", "color": [200, 190, 150], "note": "cramped, shelves of canvas and bulbs, wallpaper scraps patched over holes"},
        "floor": {"material": "WoodPlanks", "color": [130, 100, 66], "note": "pallets used as flooring"},
        "ceiling": "bare bulbs on cords",
        "light": {"color": [255, 224, 150], "kind": "many bare bulbs, workshop yellow"},
        "sound": "snip of scissors, a radio playing music at a whisper",
        "props": "lamp-bag workbench, rack of bulbs, a cot",
    },
    "c1": {
        "name": "The Pump House (Hana's camp)",
        "walls": {"material": "CorrodedMetal", "color": [110, 130, 128], "note": "pump house steel, wheels, gauges"},
        "floor": {"material": "DiamondPlate", "color": [96, 106, 108], "note": "dry steel grating above the water"},
        "ceiling": "pipes sweating, one hanging lamp",
        "light": {"color": [255, 230, 190], "kind": "yellow work lamp against cold steel"},
        "sound": "pump thud, hiss of a boiler, a radio kettle",
        "props": "water gauges, tally marks in chalk, a chart of the water's route",
    },
    "c3": {
        "name": "The Hollow Camp (Pim's)",
        "walls": {"material": "Rock", "color": [78, 70, 96], "note": "cave alcove wallpapered with Survey maps"},
        "floor": {"material": "Ground", "color": [102, 84, 64], "note": "soft earth, planks laid in a path"},
        "ceiling": "strings of lamp-bags like fireflies",
        "light": {"color": [255, 200, 130], "kind": "warm lanterns that contrast the blue cave"},
        "sound": "a hand-cranked radio, mugs clinking",
        "props": "bedrolls, a seed tray, ladder stubs",
    },
    "dorm": {
        "name": "The Dormitory (lit room after tier 6)",
        "walls": {"material": "SmoothPlastic", "color": [210, 200, 188], "note": "ward green painted over with cream, string lights"},
        "floor": {"material": "WoodPlanks", "color": [150, 118, 82], "note": "beds pushed together, rugs"},
        "ceiling": "string lights",
        "light": {"color": [255, 210, 150], "kind": "low warm, many small lights"},
        "sound": "stove, quiet breathing, a clock",
        "props": "bunks, corkboard WHO IS STILL OUT, calendar, model of the Halden",
    },
}

# Voice casting. Delivery direction for whoever records or generates voice.
VOICES = {
    "Theo": "late 20s to early 30s, tired, dry humour that cracks under pressure; speaks to himself, never to camera",
    "Ines": "50s to 60s, calm, low, unhurried; teacher voice; never raises it; radio filter on Base lines",
    "Joss": "40s, warm, fast, jokes to cover nerves; workshop clatter behind him",
    "Hana": "30s, flat, practical, short sentences; hates speeches",
    "Lena": "30s, generous, loud-quiet; sounds like she just laughed",
    "Ravi": "20s, whispery, jumpy; keeps glancing at the radio",
    "Pim": "late teens or 20, bright, too hopeful; tries not to sound scared",
    "Hollis": "60s, gentle night-guard patter; professional; fades to a murmur",
    "Tobi": "30s, soft, careful; each tape quieter than the last",
    "Quill": "40s, deliberate, precise; sentences end like shutter clicks",
    "Pike": "late 20s, 1994, cheerful engineer's voice that stays cheerful through the worst thing",
    "Announcer": "1994 corporate promo voice, smooth, bright, slightly too slow",
    "Echo": "a copy of Ravi's voice but missing the pauses; speaks half a beat early",
    "Base?": "Ines's radio voice, but with no static artefacts and no questions: only commands",
}


def add(id, kind, section, where, lines, speaker=None, title=None, glow=None, note=None,
        thought=None, look=None, vo=None):
    d = {"id": id, "kind": kind, "section": section, "where": where, "lines": lines}
    for k, v in (("speaker", speaker), ("title", title), ("glow", glow), ("note", note),
                 ("thought", thought), ("look", look), ("vo", vo)):
        if v:
            d[k] = v
    E.append(d)


def scene(id, kind, title, where, trigger, beats, note=None, look=None):
    out = []
    for b in beats:
        if b[0] == "~":
            out.append({"shot": b[1]})
        else:
            out.append({"sp": b[0], "line": b[1]})
    d = {"id": id, "kind": kind, "title": title, "where": where, "trigger": trigger, "beats": out}
    if note:
        d["note"] = note
    if look:
        d["look"] = look
    SCENES.append(d)


def warm(r, look=None):
    g = {"color": "amber", "radius": r}
    if look:
        g["look"] = look
    return g


# ===================================================================== THE GOAL
# HUD objective text. Plain, direct: the player always knows what to do next.
add("goal.l0", "goal", "l0", "HUD objective, Level 0", ["Find the surveyors. Start with Joss."])
add("goal.l0b", "goal", "l0", "HUD objective, after Joss", ["Find the fuse. Go down."])
add("goal.l1", "goal", "l1", "HUD objective, Level 1", ["Find Hana at the pump house."])
add("goal.l1b", "goal", "l1", "HUD objective, after Hana", ["Follow the water to the Falls."])
add("goal.falls", "goal", "falls", "HUD objective, Falls", ["Talk to Lena. Rest."])
add("goal.l2", "goal", "l2", "HUD objective, Level 2", ["Find Ravi. Do not answer the voices."])
add("goal.l3", "goal", "l3", "HUD objective, Level 3", ["Find Pim in the Hollow."])
add("goal.l4", "goal", "l4", "HUD objective, Level 4", ["Follow the chalk arrows down to the Lamp."])
add("goal.lamp", "goal", "lamp", "HUD objective, Lamp Room", ["Speak to Ines."])

# ===================================================================== SURVEY RULES (posters, plain)
add("rule.01", "rule", "any", "Survey Handbook p1; poster in the first room",
    ["1. You have entered the Backrooms.", "Do not panic. Everyone does it once."])
add("rule.02", "rule", "any", "Handbook p2",
    ["2. The Backrooms are made of forgotten places.", "Offices, pools, wards, caves. Each one is a Level."])
add("rule.03", "rule", "any", "Handbook p3",
    ["3. Your scanner does not make light. It makes a record.", "A dot stays where you looked. Mapped space holds still."])
add("rule.04", "rule", "any", "Handbook p4; colour key poster",
    ["4. White dots: structure. Green dots: people.", "Red dots: something that was a person and is not now."])
add("rule.05", "rule", "any", "Handbook p5",
    ["5. Every scan is a noise. Some things listen for it.", "margin: Walk. Do not run. -T.W."])
add("rule.06", "rule", "any", "Handbook p6",
    ["6. Never run toward a sound you cannot place."])
add("rule.07", "rule", "any", "Handbook p7",
    ["7. Radio: Base will ask what you see.", "Base will never tell you to come to her.",
     "margin: If it says come to me, it is not Base. -R.A."])
add("rule.08", "rule", "any", "Handbook p8",
    ["8. Crew greet with two taps, a breath, then one.", "margin: It can copy the taps. It cannot copy the breath. -R.A."])
add("rule.09", "rule", "any", "Handbook p9",
    ["9. Lamps wake when scanned. Scan every lamp you find.", "margin: A bag that glows was hung by a friend. -J.B."])
add("rule.10", "rule", "any", "Handbook p10",
    ["10. Stay where someone can see you.", "A person nobody sees starts to fade.", "margin: Green is someone looking back. -I.C."])
add("rule.11", "rule", "any", "Handbook p11; Falls wall",
    ["11. Exits exist. We have not found one.", "Keep mapping."])
add("rule.12", "rule", "lamp", "Handbook p12, handwritten, Lamp Room",
    ["12. Someone has to keep the lamp."], speaker="Ines Calder")

# ===================================================================== LEVEL PLAQUES (Survey Bulletins)
add("plaque.l0", "plaque", "l0", "Bulletin on the first-room wall; level title card follows",
    ["SURVEY BULLETIN", "LEVEL 0: THE OFFICE FLOOR", "What: a forgotten workplace, after hours.", "Hazards: the Pacer. You will hear keys.",
     "Survey: 40% mapped. Exit: not found."],
    thought="Level zero. So there are more.", look="l0")
add("plaque.l1", "plaque", "l1", "Bulletin at the stair down; level title card follows",
    ["SURVEY BULLETIN", "LEVEL 1: THE FLOODED WING", "What: drowned utilities. The water is safe to wade.", "Do not linger in it.",
     "Hazards: the Hush. It hears everything.", "Survey: 25% mapped. Exit: not found."],
    thought="Wade, don't linger. Fine. I'll be quick.", look="l1")
add("plaque.falls", "plaque", "falls", "Painted board at the Falls entrance",
    ["REFUGE: THE FALLS", "No hostiles. No fading.", "Everyone rests here.", "Survey camp: Lena Sorrel."], look="falls")
add("plaque.l2", "plaque", "l2", "Bulletin at the ward doors; level title card follows",
    ["SURVEY BULLETIN", "LEVEL 2: THE WARDS", "What: an abandoned hospital.", "Hazards: the Echo. It answers back.",
     "Do not answer voices.", "Survey: 15% mapped. Exit: not found."],
    thought="A hospital. Great. Dark, empty, and it answers back.", look="l2")
add("plaque.l3", "plaque", "l3", "Bulletin at the cave mouth; level title card follows",
    ["SURVEY BULLETIN", "LEVEL 3: THE HOLLOW", "What: a cave that grows around what it holds.",
     "Do not touch the glow.", "Hazards: the Still. It moves when you look away.", "Survey: 8% mapped. Exit: not found."],
    thought="A cave inside a building inside whatever this is.", look="l3")
add("plaque.l4", "plaque", "l4", "Bulletin on a concrete pillar; level title card follows",
    ["SURVEY BULLETIN", "LEVEL 4: THE GARAGE", "What: a parking structure that only goes down.", "The bottom is the Lamp.",
     "Hazards: all of them.", "Survey: 3% mapped. Exit: not found."],
    thought="Down. Always down. And all of them, at once.", look="l4")

# ===================================================================== THEO'S JOURNAL (first person, plain)
J = "Theo's journal (unlocks as learned)"
add("journal.01", "journal", "any", J + ": on waking", ["Halden Building, floor 3. I put my hand on the wall and there was no wall.",
    "Now I am somewhere yellow and wet. Scanner still works. Start there."])
add("journal.02", "journal", "l0", J + ": after the orientation tape", ["The Backrooms. A place made of forgotten places.",
    "Offices, pools, wards, caves. Each one a Level. You walk out of one and into the next."])
add("journal.03", "journal", "l0", J + ": after the orientation tape", ["The scanner makes a record, not light.",
    "Dots stay. Mapped space holds still. The rest moves."])
add("journal.04", "journal", "l0", J + ": after Joss", ["Joss Berrow. Rigger. Thirty years in the Survey, if time even counts here.",
    "Gave me lamp-bags. Scan a bag and it wakes up."])
add("journal.05", "journal", "l0", J + ": after the Halden tape", ["The Halden Building had a door on floor 3 that was not on the plan.",
    "A man in a Corbel and Pike jacket stood next to it in 1994. That is my company."])
add("journal.06", "journal", "l0", J + ": after the Hollis tape", ["Hollis, night security. Still doing his rounds. Nobody can see him, so he fades.",
    "That is what fading is. Nobody sees you, so you stop being you."])
add("journal.07", "journal", "l1", J + ": after Hana", ["Hana Osei, hydrologist. The water leads to the Falls.",
    "Tobi Wren went quiet so nothing would hear him. Now nothing can. He is the Hush."])
add("journal.08", "journal", "falls", J + ": after Lena", ["The Falls is a Refuge. Everyone remembers a place like it, so the dark cannot rewrite it.",
    "Five Crews went down. The wall of names has thirty-one on it. I am not on it yet."])
add("journal.09", "journal", "l2", J + ": after Ravi", ["Ravi Anand. The Echo copies his voice. It cannot copy the pause.",
    "The scanner head in the Survey's rig is from Corbel and Pike. Serial 0007. Mine is 0041."])
add("journal.10", "journal", "l3", J + ": after Pim", ["Pim Ashworth, youngest in the Survey. Keeps the Hollow lit for whoever comes next.",
    "Quill is the Still. He took forty photographs of it. In the thirtieth it was closer."])
add("journal.11", "journal", "l4", J + ": after the Pike tape", ["Anselm Pike, Corbel and Pike, 1994. First one through. Unit 0007.",
    "He says a true scan of the real floor will match the cloud. I have forty-one."])
add("journal.12", "journal", "lamp", J + ": after Ines", ["A forgotten place stops belonging to the world. Halden was empty ten years.",
    "I was the last to look at it, forty-one times. That is why it let me in, and why I can leave."])

# ===================================================================== THOUGHTS (Theo, direct)
T = "Theo thought (subtitle + voice)"
for tid, where, line, vo in [
    ("wake", "Right after the opening cutscene", ["Okay. Okay. Scanner still works. Hands still work.", "This is not floor three."], "shaky, whispered"),
    ("firstdot", "First time a dot lands", ["Dots. They stay where I look. So I can see by remembering."], "surprised, quiet"),
    ("firstwall", "First time a wall fills in", ["That is a wall. A real one. I can build a map out of this."], "relieved, whispered"),
    ("lampwake", "First lamp-bag wakes", ["Lamp-bag. It lit the second I scanned it. Somebody wanted me to find this."], "grateful"),
    ("lamplight", "Any lamp wakes (rotate)", ["The wall's yellow. The floor's carpet. This place is a real place."], "calm"),
    ("keys", "Pacer first heard", ["Keys. Someone is walking a round. I should not be where they are walking."], "tense, whisper"),
    ("hush", "Hush first heard", ["It's listening. I can hear it listening. Don't scan. Don't breathe."], "very quiet"),
    ("echo", "Echo first heard", ["That voice is wrong. Too early, no pauses. Do not answer."], "whisper"),
    ("still", "Still first noticed closer", ["It was over there. Now it's over here. Do not look away. Do not stare."], "controlled"),
    ("respawn.first", "First time Theo wakes at a lamp after being caught", ["I woke up at the lamp. Something pulled me back. I'm not testing that twice."], "shaky"),
    ("respawn.ines", "Respawn after Lena has explained", ["Ines, again. Thank you. I'll try to fall less."], "rueful"),
    ("pit", "Near a pit for the first time", ["Painted edge. Somebody didn't want the next person to fall."], "careful"),
    ("plate", "Near an alarm plate for the first time", ["A plate and a bell. Something listens to the floor. Step around."], "careful"),
    ("water", "First time in the water", ["Ankle deep. Cold. It's blue. It has to come from somewhere."], "curious"),
    ("falls", "First step into the Falls", ["Colour. Real colour. I forgot what it looked like."], "awed"),
    ("tapes", "First tape picked up", ["A tape. Somebody wanted to be found. I should watch it."], "thoughtful"),
    ("surveyor", "First time a green dot is a surveyor", ["Green. A person. A real one. Don't scare them. Don't be scared."], "hopeful"),
    ("heat", "Scanner overheating", ["Scanner's getting hot. Ease off. Stay quiet."], "quiet"),
    ("fading", "First time he sees a red dot he recognises as a former surveyor", ["That red used to be a person. Ines said so. I didn't believe it until now."], "grim"),
    ("lamp.near", "Hearing the Lamp hum far below", ["There's a hum. Steady. That's not a monster. That's a light."], "drawn"),
]:
    add("thought." + tid, "thought", "any", where, line, speaker="Theo", vo=VOICES["Theo"] + "; " + vo)

# ===================================================================== POIs (each one explains something)
# lines: what is written on or said by the object. thought: Theo's reaction. look: which backdrop the light shows.
def poi(id, section, where, lines, thought, look, radius=8, note=None):
    add(id, "poi", section, where, lines, thought=thought, look=look, glow={"color": "amber", "radius": radius, "look": look}, note=note)

# --- Level 0
poi("poi.l0.vcr", "l0", "CRT and VCR on a cart in the first room: orientation tape inserted",
    ["SURVEY ORIENTATION. TAPE 1 OF 9.", "PRESS PLAY."], "A tape already loaded. Somebody left this for whoever came through.", "l0", 9,
    "Plays tape.orientation on interact.")
poi("poi.l0.desk", "l0", "Desk with a Halden Building staff badge and a nameplate",
    ["HALDEN BUILDING. A. PIKE.", "Corbel & Pike Surveying.", "Valid: 1994."], "Halden. Corbel and Pike. That is my company. This is a 1994 badge.", "l0")
poi("poi.l0.whiteboard", "l0", "Whiteboard in a meeting room",
    ["DAY 3.", "WALLS MOVED WHILE WE SLEPT.", "NEVER SLEEP UNLIT.", "MAP EVERYTHING."], "Walls move when nobody looks. That's the whole reason for the dots.", "l0")
poi("poi.l0.coat", "l0", "Coat on a hook; security badge; clipboard",
    ["HOLLIS, J. NIGHT SECURITY.", "Round log: 11,284.", "Last entry: ALL QUIET."], "Eleven thousand rounds. That isn't a shift. That's years of walking.", "l0")
poi("poi.l0.copier", "l0", "Copier jammed on a page",
    ["EXIT GUESSES:", "1. stairs - no  2. lift - no  3. roof - no ...", "14. the door at the end of floor 3 - ???"],
    "Fourteen guesses. All crossed out. 'The door at the end of floor three.' That's mine.", "l0",
    note="Replaces the old Copy Room. The copier now holds the Survey's list of failed exit guesses.")
poi("poi.l0.vending", "l0", "Vending machine, stocked with identical cans",
    ["TEA", "TEA", "TEA", "TEA", "(coins in the tray: one token, HALDEN STAFF)"], "Every slot is tea. Someone stocks this. The tray has a staff token.", "l0")
poi("poi.l0.sign", "l0", "Arrow sign in a hallway pointing at a wall",
    ["EXIT ->", "(pencilled below) it does not go anywhere"], "The exit sign points at a wall. Of course it does.", "l0")

# --- Joss's Supply Closet
poi("poi.c0.bench", "c0", "Lamp-bag workbench",
    ["LAMP-BAGS. 41 TODAY.", "J.B."], "He makes them by hand. The cheerful kind of crazy.", "c0", 7)
poi("poi.c0.map", "c0", "Pinned map of Level 0",
    ["LEVEL 0. HOLLIS ROUTE IN RED.", "STAIR DOWN: NEEDS A FUSE."], "Pacer's route is on the map. And the way down.", "c0")

# --- Outpost Zero / Night Desk
poi("poi.desk.radio", "desk", "Radio on the desk",
    ["SURVEY HANDSET. CHANNEL 1.", "Base answers if you speak."], "A handset. If someone's out there, I can reach her.", "desk", 7)
poi("poi.desk.signin", "desk", "Sign-in sheet clipped to the desk",
    ["SURVEY SIGN-IN", "CREW 1  IN", "CREW 2  IN", "CREW 3  IN", "CREW 4  IN", "CREW 5  IN", "CREW 6  IN", "CREW 7  IN  (blank)"],
    "Seven crews. Mine is the seventh. The name line is blank.", "desk")
poi("poi.desk.board", "desk", "Corkboard of crew photographs",
    ["SIX CREWS.", "Thirty-one names.", "Some photos are turned face down."], "Face down. That's how you hide the ones who faded.", "desk")

# --- Level 1
poi("poi.l1.lifering", "l1", "Life ring painted HALDEN B3",
    ["LIFE RING. HALDEN B3.", "Hung 1996, after the flood."], "The Halden's basement flooded in '96. This is that basement. Forgotten, then drowned.", "l1")
poi("poi.l1.pumplog", "l1", "Pump house log taped to a pipe",
    ["WATER LEVEL: UP.", "UP.", "UP.", "FOLLOW IT UPSTREAM. IT ENDS SOMEWHERE LIT. -H.O."], "Follow the water upstream. Okay. That's a plan.", "l1")
poi("poi.l1.headphones", "l1", "Headphones on a pipe with a sticky note",
    ["TOBI WREN. SOUND.", "Do not call out. Do not answer if it calls.", "Gain all the way up."], "Tobi's. If he left these, he's the thing that's listening now.", "l1")
poi("poi.l1.dinghy", "l1", "Half-sunk rubber dinghy",
    ["CREW 2. B1.", "Hana went ahead on foot.", "Oars lost. Third seat lost."], "Crew 2 tried to paddle. They lost a seat. That's a polite way to say it.", "l1")
poi("poi.l1.valve", "l1", "Valve station with the wheel missing",
    ["MAIN VALVE B4.", "WHEEL REMOVED FOR SAFETY.", "(by whom?)"], "Wheel's gone. I need the wheel to drain the channel.", "l1")
poi("poi.l1.tally", "l1", "Chalk tally on a wall",
    ["DAY 1 ||||", "DAY 2 ||||", "WATER STOPPED RISING AT 40.", "THEN IT STARTED FALLING."], "Hana counted the water. She's been here a long time.", "l1")

# --- Pump House (Hana)
poi("poi.c1.chart", "c1", "Hand-drawn chart of the water's route",
    ["WATER ROUTE", "Wing -> Channel -> Shaft -> THE FALLS", "Gate: valve wheel. Rope for the gap."], "She mapped the whole route. All I have to do is not die on it.", "c1")

# --- The Falls
poi("poi.falls.names", "falls", "Wall of names",
    ["SURVEY ROSTER", "31 names.", "9 crossed out. 4 marked FADING.", "(a space at the bottom: THEO?)"], "My name, on a wall nobody wrote it on yet. They're expecting me.", "falls")
poi("poi.falls.behind", "falls", "Alcove behind the waterfall: mural of every Level in a stack",
    ["LEVEL 0 office", "LEVEL 1 flooded", "LEVEL 2 wards", "LEVEL 3 hollow", "LEVEL 4 garage", "THE LAMP", "(line to the top, dotted: ?)"],
    "Stack of Levels. And a dotted line going up. That's the exit nobody's found.", "falls", 10)
poi("poi.falls.guestbook", "falls", "Guest Book on a stone",
    ["GUEST BOOK", "{party}", "Everyone signs. Nobody says what for."], "Everyone signs. That's how you know you're still here.", "falls")

# --- Level 2
poi("poi.l2.pa", "l2", "PA speaker above a nurse station",
    ["(PA, crackling) Staff to Ward C.", "Staff to Ward C.", "(a pause) ...Staff to Ward C."], "Someone is paging staff to a ward that doesn't exist. Or does.", "l2")
poi("poi.l2.chart", "l2", "Patient chart on a bed",
    ["PATIENT: UNKNOWN.", "ADMITTED: ____", "CONDITION: FORGOTTEN."], "Every chart says unknown. Nobody remembers who they were treating.", "l2")
poi("poi.l2.tapcode", "l2", "Brass plate on a pillar",
    ["TWO TAPS. A BREATH. ONE.", "CREW GREETING.", "(scratched below) IT CANNOT BREATHE."], "A greeting. Two taps, a breath, one. The thing that answers cannot breathe.", "l2")
poi("poi.l2.gurney", "l2", "Gurney with Survey straps",
    ["SURVEY STRETCHER 4.", "Used twice.", "Used once to carry someone out. Used once to carry someone in."], "They carried someone in. I don't want to know who.", "l2")
poi("poi.l2.bell", "l2", "Call bell on a wire",
    ["CALL BELL. RING FOR ASSISTANCE.", "(someone has cut the wire)"], "Cut the wire. Nobody wants the thing to know where they are.", "l2")

# --- Ravi's Ward Station
poi("poi.c2.radio", "c2", "Unplugged radio on a stool",
    ["SURVEY HANDSET. UNPLUGGED.", "It has my voice, so I keep it dead. -R.A."], "He unplugged the radio because the Echo uses it. That's careful.", "c2")

# --- Level 3
poi("poi.l3.doorframe", "l3", "Halden door frame grown into cave rock",
    ["HALDEN BLDG. FLOOR 3.", "The door is open. There is only rock on the other side."], "A Halden door frame inside a cave. Pieces of the real building are everywhere down here.", "l3")
poi("poi.l3.crystal", "l3", "Glowing mineral vein",
    ["DO NOT TOUCH THE GLOW.", "It gives light. It takes warmth. It takes light back."], "The glow feeds on light. Which means a lamp-bag is bait.", "l3")
poi("poi.l3.camera", "l3", "Camera on a tripod facing the passage",
    ["Q. QUILL. PHOTOGRAPHY.", "Shutter half pressed. Never finished."], "He was in the middle of a shot. He never took it.", "l3")
poi("poi.l3.bridge", "l3", "Rope bridge over a drop",
    ["ROPE BRIDGE. ONE AT A TIME.", "DO NOT LOOK BACK."], "One at a time. Don't look back. I'm already regretting this.", "l3")

# --- Pim's Hollow Camp
poi("poi.c3.mugs", "c3", "Row of mugs on a ledge",
    ["FOUR MUGS.", "P.A.  L.S.  R.A.  H.O.", "A fifth hook, empty."], "Four mugs and a fifth hook. They're waiting for someone to fill it.", "c3")

# --- Level 4
poi("poi.l4.stone", "l4", "Cornerstone",
    ["HALDEN BUILDING. 1994.", "Nothing here is older than this stone.", "Every Level hangs from it."], "Everything hangs from the Halden. The whole Backrooms is built on top of it.", "l4", 9)
poi("poi.l4.ticket", "l4", "Ticket machine at a boom gate",
    ["ENTERED: TUE 11:42 PM", "EXIT: _____", "(machine will not print an exit time)"], "Eleven forty-two. That's when I walked in. It's been tracking me.", "l4")
poi("poi.l4.chalk", "l4", "Chalk arrows leading downward",
    ["Fresh chalk arrows.", "I.C."], "Fresh chalk. She walked this recently. She's close.", "l4")
poi("poi.l4.pike", "l4", "Folding table with a camcorder, unit 0007, and a tape",
    ["UNIT 0007. CORBEL & PIKE.", "TAPE 9 OF 9. FOR WHOEVER BRINGS THE REAL FLOOR."], "Unit zero zero zero seven. Mine is zero zero four one. He's the first. The last tape is for me.", "l4", 9,
    "Plays tape.pike on interact.")
poi("poi.l4.pit", "l4", "Wall of a drop shaft",
    ["MARKED EDGE.", "JOSS PAINTED THE EDGE SO YOU WOULD FEEL IT FIRST."], "He painted the edge so you'd feel it first. He thought of that.", "l4")

# --- Lamp Room
poi("poi.lamp.lamp", "lamp", "The Lamp",
    ["THE LAMP.", "Nobody built it. Pike lit it. Ines keeps it."], "That's the Lamp. All the Levels hang off that.", "lamp", 14)
poi("poi.lamp.board", "lamp", "Chalkboard of the whole point cloud",
    ["EVERY SCAN OF EVERY SURVEYOR.", "ALL OF THIS.", "(a gap the shape of a corridor)"], "The whole Survey's work on one board. And one gap that's the exact shape of floor three.", "lamp")
poi("poi.lamp.ladder", "lamp", "Ladder shaft with a thread of daylight",
    ["UP.", "NOBODY HAS CLIMBED IT.", "NOBODY HAS HAD A TRUE SCAN."], "A thread of real daylight. First I've seen.", "lamp", 9)

# ===================================================================== RECORDERS (hidden, clear, short)
add("rec.l0.1", "recorder", "l0", "Hidden in a desk drawer, Level 0",
    ["Ines Calder. Day one of the Survey.", "The floor above is condemned. We walked into the wall and we are not coming out.",
     "We call this the Backrooms. Every place somebody forgot ends up here."], speaker="Ines Calder")
add("rec.l0.2", "recorder", "l0", "Taped under a break-room table, Level 0",
    ["Joss. Lamp-bags work. A bulb, a cell, a canvas sack.", "Hang one at every turn and scan it and it wakes up.",
     "Mapped space holds still. That's the trick. The rest drifts."], speaker="Joss Berrow")
add("rec.l0.3", "recorder", "l0", "Answering machine on the front desk, Level 0",
    ["Hollis, nights. Round eleven thousand. All quiet.", "Funny. I do not see the other guards any more.",
     "Hello? Does anyone see me? Hello?"], speaker="Mr. Hollis")
add("rec.l1.1", "recorder", "l1", "Wedged in a pipe bracket, Level 1",
    ["Tobi Wren, sound. I can hear the building thinking.", "If I stay quiet, nothing hears me.",
     "I am going to try that for a while."], speaker="Tobi Wren")
add("rec.l1.2", "recorder", "l1", "On a catwalk rail, Level 1",
    ["I stopped talking. It is better.", "I can hear everyone breathing, very far off.",
     "I cannot tell if anyone can hear me. I do not mind."], speaker="Tobi Wren", note="Plays near a Hush lair.")
add("rec.l1.3", "recorder", "l1", "In the boiler room, Level 1",
    ["Hana. The water was not here yesterday.", "It was here. We just were not looking.",
     "That is the Backrooms for you. What nobody looks at, changes."], speaker="Hana Osei")
add("rec.falls.1", "recorder", "falls", "On a ledge by the hammocks, Falls",
    ["Ines. Day forty. I stopped counting.", "We found a place the dark cannot rewrite.",
     "Everyone remembers a waterfall. That is why it holds."], speaker="Ines Calder")
add("rec.falls.2", "recorder", "falls", "Under the camp stove, Falls",
    ["Lena. Hammocks up. Soup on.", "First hot meal in a month.", "Ravi plays the one song he knows. Badly. I love it."], speaker="Lena Sorrel")
add("rec.l2.1", "recorder", "l2", "Under a bench, Level 2",
    ["Ravi. Two taps, a breath, one tap.", "It was just a greeting. Now something taps back.",
     "It does the two. It does not do the breath."], speaker="Ravi Anand")
add("rec.l2.2", "recorder", "l2", "In a linen trolley, Level 2",
    ["It sounds like me. It learned me in an afternoon.", "I said 'hello?' to see. It said 'hello?' first.",
     "I keep the radio off now."], speaker="Ravi Anand")
add("rec.l2.3", "recorder", "l2", "Nurse station drawer, Level 2",
    ["Ines. Theory.", "The Backrooms are what a world forgets.", "We are not hunted. We are forgotten. There is a difference, and it matters."],
    speaker="Ines Calder")
add("rec.l3.1", "recorder", "l3", "In a root hollow, Level 3",
    ["Pim. I found a draft.", "A draft means a door. Everyone laughed.", "I will keep the lantern lit anyway."], speaker="Pim Ashworth")
add("rec.l3.2", "recorder", "l3", "Camera case, Level 3",
    ["Quill. The thing only moves when I am not looking.", "So I look. Forty frames.", "In frame thirty it is closer. Do not stare. It learns the stare."],
    speaker="Marlow Quill")
add("rec.l3.3", "recorder", "l3", "Chalk-marked shelf, Level 3",
    ["Watch it. Then step. Never stare.", "If you hear a shutter, do not turn.", "Wait for the second click."], speaker="Marlow Quill")
add("rec.l4.1", "recorder", "l4", "On a pillar, Level 4",
    ["Ines. Last descent. I know where the Lamp must go.", "The Garage is the first Level that ever formed.",
     "It is not cruel. It is empty. Empty gets hungry for company."], speaker="Ines Calder")

# ===================================================================== RADIO (voiced, direct)
# Base = Ines. Real Base asks what you see and gives plain guidance. Fake Base commands and
# never asks. Every line is recorded/voiced; the text is the subtitle.
def radio(id, section, where, lines, who="Base", note=None, vo_extra=""):
    add(id, "radio", section, where, lines, speaker=who,
        vo=VOICES["Ines"] if who == "Base" else VOICES["Base?"] + vo_extra, note=note)

radio("radio.first", "desk", "First call after picking up the handset",
      ["Base to Theo. Can you hear me?", "I heard your scanner come online. I am Ines. Tell me what you see."],
      note="Her first words. She uses Theo's name because she saw it on the scanner's status screen.")
radio("radio.l0", "l0", "Level 0 start (after Outpost Zero)",
      ["Base to Theo. Level 0. Keys are the Pacer. Wait for them to pass.", "Find Joss at the supply closet. He has what you need."])
radio("radio.l1", "l1", "Level 1 start",
      ["Base to Theo. Level 1. The water is safe to wade. Do not stay in it.", "Find Hana at the pump house. Follow the water upstream."])
radio("radio.l2", "l2", "Level 2 start",
      ["Base to Theo. Level 2. Something here wears our voices.", "If I say come to me, do not come. Find Ravi."])
radio("radio.l3", "l3", "Level 3 start",
      ["Base to Theo. Level 3. Do not touch the glow.", "Find Pim. Watch for the Still. Watch, then step."])
radio("radio.l4", "l4", "Level 4 start",
      ["Base to Theo. Level 4. Follow the chalk. I will be at the bottom.", "I have been waiting a very long time to say that."])
radio("radio.idle.1", "any", "Random, dark, calm", ["Base to Theo. Tell me what you see."])
radio("radio.idle.2", "any", "Random, dark, calm", ["Base to Theo. I can see your dots from here. You are doing well."])
radio("radio.idle.3", "any", "Random, dark, calm", ["Base to Theo. Count with me. One. Two. Three. Still here."])
radio("radio.clear", "any", "After a level clear", ["Base to Theo. Logged. Rest if you find a lamp."])
radio("radio.back.1", "any", "Respawn at a lamp", ["Welcome back, Theo. Breathe. You are lit."])
radio("radio.back.2", "any", "Respawn at a lamp", ["I have you. I always do. Rest a moment."])
radio("radio.back.3", "any", "Respawn at a lamp", ["Easy. Count with me. One. Two. Three."])
radio("radio.surveyor.near", "any", "A surveyor is within ~30 studs, unseen", ["Base to Theo. Green dots ahead. Say hello. Two taps, a breath, one."])
radio("radio.fake.1", "l2", "Near the Echo ONLY", ["Theo. This way. Come to me."], who="Base?",
      note="Real Base never says 'come to me'. Plays slightly before the real radio click.")
radio("radio.fake.2", "l2", "Near the Echo ONLY", ["Put the scanner down. It is safe. Come to me."], who="Base?")
radio("radio.fake.3", "l2", "Near the Echo ONLY", ["Turn left. Left. Now. Come to me."], who="Base?")
radio("radio.fake.4", "l2", "Near the Echo ONLY", ["Tap tap. Theo?"], who="Base?",
      note="Skips the breath between the two taps and the one.")

# ===================================================================== ENTITY NOTES (plain, from the Survey)
add("ent.wanderer", "entity", "l0", "Journal page on first sighting",
    ["THE PACER", "Former night security (Mr. Hollis). Walks his rounds with his keys.",
     "Lingers a moment where it hears or sees. Then moves on.", "He does not know he is off shift."],
    thought="The Pacer. A man doing his job long after the job ended.")
add("ent.listener", "entity", "l1", "Journal page on first sighting",
    ["THE HUSH", "Former sound technician (Tobi Wren). Went quiet; the Backrooms made it true.",
     "No eyes. It hears scans and footsteps. Walk, do not run, do not ping near it."],
    thought="The Hush. He's still listening for someone to answer.")
add("ent.mimic", "entity", "l2", "Journal page on first sighting",
    ["THE ECHO", "Copies voices and radios. Reads as a friend until you are near it.",
     "It does the two taps but not the breath. Never answer it."],
    thought="The Echo. It's got Ravi's voice. I'm not answering it.")
add("ent.stalker", "entity", "l3", "Journal page on first sighting",
    ["THE STILL", "Former photographer (Marlow Quill). Moves only when unseen.",
     "Watch it. Then step. Never stare."],
    thought="The Still. He's closer every time I blink.")

# ===================================================================== ITEMS (plain use)
ITEMS = [
    ("cell", "Battery Cell", "Recharges the scanner.", "Level 0 and everywhere"),
    ("lampbag", "Lamp-Bag", "A bulb in a canvas sack. Scan it and it wakes.", "Joss gives you these"),
    ("fuse", "Fuse", "Powers the breaker for the stairwell door.", "Level 0 (tier 2) and Level 2 (tier 6)"),
    ("valve", "Valve Wheel", "Fits the main valve. Drains the channel on Level 1.", "Level 1 (tier 3)"),
    ("rope", "Rope", "Crosses a gap. Joss knots every one himself.", "Level 1 (tier 4), Level 3"),
    ("key", "Brass Key", "Stamped HALDEN B3. Opens the Ward doors.", "Falls gate"),
    ("crank", "Skylight Crank", "Opens the lift to the Hollow.", "Level 2 (tier 6)"),
    ("core", "Lamp Core", "A glass core that glows faintly. Ines needs it.", "Level 4 (tier 7)"),
    ("tape", "Videotape", "A tape from a surveyor. Watch it at the nearest screen.", "Collectible"),
    ("page", "Handbook Page", "Torn from the Survey Handbook.", "Collectible"),
    ("chalk", "Chalk", "Marks stay. Mark your route.", "Level 0, optional"),
    ("tea", "Cold Tea", "Steadies your hands. Cools the scanner.", "Camps and side rooms"),
    ("flashbulb", "Flash Bulb", "One bright flash. Stuns the Still for a moment.", "Level 3, one"),
    ("glowstick", "Glow Stick", "Snap it. Twenty seconds of light.", "Any, consumable"),
    ("mug", "Pim's Mug", "Chipped. PIM in marker. Proof he made it this far.", "Level 3"),
    ("scanner41", "Scanner Unit 0041", "Your scanner. The real floor is still on it.", "Starts with you"),
]
for iid, name, desc, where in ITEMS:
    add("item." + iid, "item", "any", where, [name + ": " + desc], title=name,
        note="Name is before the colon; use text after it.")

# ===================================================================== TIPS & PING WHEEL
for i, t in enumerate([
    "Scan every lamp. Light only reaches what you have mapped.",
    "Green means a person. Say hello. Two taps, a breath, one.",
    "Keys mean the Pacer. Wait for them to pass.",
    "If the radio says come to me, do not.",
    "Do not look away from the Still. Do not stare at it either.",
    "Walk near the Hush. Running is a shout.",
    "Surveyors know things. Find them.",
    "The water leads to the Falls.",
    "Videotapes explain what happened. Watch them.",
    "Stay in sight of someone. The unseen fade.",
], 1):
    add("tip.%02d" % i, "tip", "any", "Loading screen or respawn screen", [t])
for pid, label in [("here", "Here"), ("wait", "Wait"), ("danger", "Danger"), ("item", "Found"), ("tap", "Two taps")]:
    add("ping." + pid, "system", "any", "Ping wheel label", [label])

# ===================================================================== TITLE CARDS
add("card.l0", "card", "l0", "Level card", ["LEVEL 0", "THE OFFICE FLOOR", "a forgotten workplace"], title="The Office Floor", look="l0")
add("card.c0", "card", "c0", "Camp card", ["SURVEY CAMP", "THE SUPPLY CLOSET", "Joss Berrow"], title="The Supply Closet", look="c0")
add("card.desk", "card", "desk", "Lit room card", ["OUTPOST ZERO", "THE NIGHT DESK", "the radio works here"], title="The Night Desk", look="desk")
add("card.l1", "card", "l1", "Level card", ["LEVEL 1", "THE FLOODED WING", "the water is blue"], title="The Flooded Wing", look="l1")
add("card.c1", "card", "c1", "Camp card", ["SURVEY CAMP", "THE PUMP HOUSE", "Hana Osei"], title="The Pump House", look="c1")
add("card.falls", "card", "falls", "Refuge card", ["REFUGE", "THE FALLS", "everyone remembers a place like this"], title="The Falls", look="falls")
add("card.l2", "card", "l2", "Level card", ["LEVEL 2", "THE WARDS", "an abandoned hospital"], title="The Wards", look="l2")
add("card.c2", "card", "c2", "Camp card", ["SURVEY CAMP", "THE WARD STATION", "Ravi Anand"], title="The Ward Station", look="c2")
add("card.dorm", "card", "dorm", "Lit room card", ["THE DORMITORY", "the Survey sleeps here"], title="The Dormitory", look="dorm")
add("card.l3", "card", "l3", "Level card", ["LEVEL 3", "THE HOLLOW", "a cave that grows round what it holds"], title="The Hollow", look="l3")
add("card.c3", "card", "c3", "Camp card", ["SURVEY CAMP", "THE HOLLOW CAMP", "Pim Ashworth"], title="The Hollow Camp", look="c3")
add("card.l4", "card", "l4", "Level card", ["LEVEL 4", "THE GARAGE", "the way down"], title="The Garage", look="l4")
add("card.lamp", "card", "lamp", "Lit room card", ["THE LAMP ROOM", "someone kept it on"], title="The Lamp Room", look="lamp")
add("card.relay", "card", "relay", "Endless floor card", ["THE RELAY", "FLOOR {n}", "someone lit this before you"], title="The Relay")
add("card.relay.daily", "card", "relay", "Daily seed card", ["TONIGHT'S FLOOR", "the same for everyone"], title="Daily")
add("sign.relay.1", "sign", "relay", "Poster on a Relay floor", ["IF YOU CAN READ THIS,", "SOMEONE LIT IT FIRST."])
add("sign.relay.2", "sign", "relay", "Poster on a Relay floor", ["THANK YOU, TWO NIGHTS AGO."])
add("sign.relay.3", "sign", "relay", "Poster on a Relay floor", ["CREW 8: THE KETTLE WORKS.", "TEA IS IN THE TIN."])

# ===================================================================== CHOICES, NOTES (misc)
add("choice.up", "choice", "lamp", "Dialogue choice 1", ["Climb the ladder."])
add("choice.stay", "choice", "lamp", "Dialogue choice 2", ["Take the lamp."])
add("note.dorm.board", "note", "dorm", "Corkboard: WHO IS STILL OUT",
    ["WHO IS STILL OUT", "HOLLIS  rounds  (the Pacer)", "WREN  listening  (the Hush)", "QUILL  watching  (the Still)",
     "ANAND  alive, hiding", "ASHWORTH  alive, keeping a lamp"],
    note="First three are crossed out in pencil. The last two are circled in green.")
add("note.dorm.letters", "note", "dorm", "Letters pinned to a bunk",
    ["Dear Mum. We are fine. The pay is good.", "I cannot say where. It is quiet here.", "Dear Mum. We are fine."])
add("rev.dorm.model", "reveal", "dorm", "Model of the Halden Building",
    ["The Halden Building, fifteen floors.", "The plans in the lobby said fourteen.", "The fifteenth is lit. A match sits beside it."],
    glow=warm(7, "dorm"), look="dorm", thought="Fifteen floors. The plans said fourteen. I walked floor three, and I counted wrong.")

# ===================================================================== SCENES
# --- OPENING CUTSCENE (plays on New Game; skippable on repeat)
scene("cs.open", "cutscene", "The Halden Building", "New Game start", "Automatic, once per profile; skippable after first view", [
    ("~", "Black. A single office-night sound: ventilation, a clock, a sprung chair."),
    ("Theo", "Tuesday, eleven forty-two p.m. Halden Building, floor three."),
    ("Theo", "Corbel and Pike want a full point cloud before the demolition crew arrives."),
    ("~", "Slow track across an empty condemned office floor. Dust. A tripod-mounted scanner sweeps; red laser dots build the room. The sweep is exactly the player's gun, on a bigger scale."),
    ("Theo", "Ten years empty. Nobody has walked this floor but me."),
    ("~", "Scanner screen: SCAN 41 OF 41 COMPLETE. Theo lets out a breath."),
    ("Theo", "That's the last one. Pack it up. Go home."),
    ("~", "Theo unplugs the tripod, steps backward, and leans a hand on the far wall. His hand sinks in. The wall is not there."),
    ("Theo", "Wait. That's not--"),
    ("~", "The floor goes soft. Fluorescents flare and die. Cut to black. A low electrical hum. Title card: LIDAR."),
    ("~", "Wake. Fluorescent buzz. Theo's POV, blurred, then slowly sharp: damp yellow wallpaper, wet carpet. His handheld scanner is in his hand."),
    ("Theo", "Okay. Okay. Scanner still works. Hands still work."),
    ("Theo", "This is not floor three."),
    ("Theo", "Don't panic. Scan the room. Find a door."),
], note="~35 to 45 seconds. Ends on the first playable frame with the scanner raised; no black gap.", look="l0")

# --- TAPE 1: ORIENTATION (the clear opening explanation)
scene("tape.orientation", "tape", "Survey Orientation (Tape 1 of 9)", "CRT/VCR in the first room (poi.l0.vcr); lit and playable on the first dot", "Interact; auto-offers at 20 seconds idle", [
    ("~", "CRT static. A woman at a desk with a banker's lamp. Camcorder angle, slightly too low. Wall maps behind her."),
    ("Ines", "Hello. If you are watching this, you came through a wall. Everyone does."),
    ("Ines", "My name is Ines Calder. I run the Survey. We map the Backrooms so that people like you can find their way."),
    ("Ines", "The Backrooms are a set of places that were forgotten. An office nobody visits. A pool nobody swims in. A ward nobody staffs."),
    ("Ines", "When a place is forgotten long enough, it stops belonging to the world. It ends up here."),
    ("Ines", "Each place is a Level. They do not connect like a building does. You walk out of one, and you are in the next."),
    ("Ines", "The dark is the first danger. Light does not carry here. So the Survey built the scanner you are holding."),
    ("Ines", "It does not make light. It makes a record. Where you scan, the dots stay, and mapped space holds still."),
    ("Ines", "White is structure. Green is people. Red is anything that used to be a person and is not now."),
    ("Ines", "Some of them were surveyors. Be kind to them, and do not stand near them."),
    ("Ines", "Find my people. They camp at every Level. Each of them knows something you need."),
    ("Ines", "And find the way out. We have never found one. But the scanner says there is a shape in the dark that matches the real world."),
    ("Ines", "To prove it, I would need a true measurement of a real place. We have never had one. If you have one, I would very much like to meet you."),
    ("~", "She reaches forward. The tape cuts to static."),
    ("Theo", "A true measurement of a real place."),
    ("Theo", "Forty-one scans of floor three. They are on this unit."),
    ("Theo", "Okay. Find the surveyors. Find Ines."),
], note="~60 to 75 seconds with beats; keep skippable. Journal entries 02 and 03 unlock.", look="l0")

# --- TAPE 2: HALDEN PROMO
scene("tape.halden", "tape", "Halden Building: Where Tomorrow Works", "VCR in the Level 0 break room", "Interact", [
    ("~", "A promo VHS from 1994, saturated colour. Fast pans of a glass lobby, escalators, an atrium with a fountain."),
    ("Announcer", "Halden Building. Fifteen floors of tomorrow."),
    ("~", "Ribbon cutting. A young man in a Corbel and Pike survey jacket holds a scanner and waves."),
    ("Announcer", "Surveyed to the millimetre by Corbel and Pike."),
    ("~", "Camera drifts down a corridor, floor three. At the very end is a door that is not on any plan. It is slightly open. Light is coming out of it."),
    ("Announcer", "From the lobby to floor... three..."),
    ("~", "Tape glitches. Static. End."),
    ("Theo", "Fifteen floors. The plan I was given had fourteen."),
    ("Theo", "That door is on floor three. That is my floor."),
], look="l0")

# --- TAPE 3: HOLLIS
scene("tape.hollis", "tape", "Security Camera 4 (night)", "Monitor in the Level 0 security booth", "Interact", [
    ("~", "Grey security footage. A man in a security jacket, keys on his belt, walks the corridor with a flashlight."),
    ("Hollis", "Round one. All quiet."),
    ("~", "Time jumps. Same corridor. The carpet is wetter."),
    ("Hollis", "Round four hundred. Lights out on three. All quiet."),
    ("~", "Time jumps. The man is a little translucent. The footage loses detail where he stands."),
    ("Hollis", "Round eleven thousand. Funny. I do not see the other guards any more."),
    ("Hollis", "Is anyone there? Can anyone see me?"),
    ("~", "The man stops. Looks straight into the camera. The footage keeps going, but he is gone from the frame. Keys, faint, continue."),
    ("Theo", "Nobody saw him, so he started to disappear."),
    ("Theo", "That is what fading is. Keep somebody in sight."),
], look="l0")

# --- TAPE 4: TOBI
scene("tape.tobi", "tape", "Walkman Diary: T. Wren", "Cassette player in the Level 1 pump room", "Interact", [
    ("~", "A cassette player on a shelf, red record light. Water dripping in the background, very close to the mic."),
    ("Tobi", "Tobi Wren. I can hear the building thinking."),
    ("Tobi", "I have worked out that it hears us. Every scan. Every step."),
    ("Tobi", "So I stopped. If I stay silent, maybe nothing hears me."),
    ("~", "Longer silence. Dripping. A faint, patient breath."),
    ("Tobi", "It worked. I could not hear anyone, and nobody could hear me."),
    ("Tobi", "That's the problem."),
    ("Theo", "He went quiet so nothing would find him. Then nothing could."),
    ("Theo", "Walk. Do not run. Do not ping near the Hush."),
], look="l1")

# --- TAPE 5: RAVI
scene("tape.ravi", "tape", "Ravi's Demonstration", "TV in the Level 2 day room", "Interact", [
    ("~", "A ward day room. Ravi, nervous, sits close to the camera. A radio on the table."),
    ("Ravi", "Okay. This is the Echo. It copies voices."),
    ("Ravi", "Watch. Two taps. A breath. One."),
    ("~", "He taps the table. Silence. Then, from the dark behind the camera, two taps. No breath. One tap."),
    ("Echo", "Ravi? Ravi? Ravi?"),
    ("Ravi", "That is my voice. It learned me in an afternoon."),
    ("Ravi", "It can copy the words. It can copy the taps. It cannot wait."),
    ("Ravi", "So if you hear me and I do not wait, it is not me."),
    ("Theo", "It doesn't breathe. That is the tell."),
], look="l2")

# --- TAPE 6: QUILL
scene("tape.quill", "tape", "Contact Sheet: M. Quill", "Projector in the Level 3 cave", "Interact", [
    ("~", "A slide projector throws images on the cave wall: a corridor, frame by frame."),
    ("Quill", "Frame one. Empty corridor."),
    ("Quill", "Frame ten. Empty."),
    ("Quill", "Frame thirty. A shape at the far end."),
    ("~", "A shape at the end of the corridor, drawn closer in each frame."),
    ("Quill", "It moves when I do not look. So I look."),
    ("Quill", "But if I stare, it learns the stare."),
    ("Quill", "Watch it. Then step. Never stare. Remember."),
    ("Theo", "Watch it, then step. Do not stare. Got it."),
], look="l3")

# --- TAPE 7: PIKE (the key reveal)
scene("tape.pike", "tape", "Tape 9 of 9: A. Pike", "Camcorder on the folding table in the Garage", "Interact", [
    ("~", "A young man in a Corbel and Pike jacket. Same face as the ribbon-cutting. Sodium light. A small lamp beside him."),
    ("Pike", "Day one. I am Anselm Pike. I was scanning the Halden before it opened."),
    ("Pike", "I scanned the wall at the end of floor three, and the wall opened."),
    ("Pike", "I have walked down for what feels like a week. I found a light in the dark. I called it the Lamp."),
    ("Pike", "I do not know who built this place. I know it hangs from the Halden. Everything does."),
    ("Pike", "Here is what I think. The Backrooms is a point cloud of forgotten places, and it has a shape."),
    ("Pike", "If anybody ever brings a true scan of the real floor three, the shape will match, and a door will open."),
    ("Pike", "That is the exit. That is all I know."),
    ("Pike", "If you are watching this: the Lamp is at the bottom. Bring me the real floor."),
    ("Theo", "He was the first. Unit zero zero zero seven. And I have the real floor."),
    ("Theo", "Down to the Lamp."),
], look="l4")

# --- DIALOGUE: JOSS (Supply Closet, after tier 1)
scene("npc.joss", "dialogue", "Joss Berrow", "Supply Closet (c0), after tier 1", "Walk up to the green dot; scene plays; he hands over lamp-bags", [
    ("Joss", "Whoa. Easy. Easy. You are real. Green dots, good. Sit."),
    ("Theo", "Where am I?"),
    ("Joss", "The Backrooms. First of us named it. Do not ask why the name stuck."),
    ("Joss", "Every Level is a place somebody forgot. This one is an office floor. The rest get stranger."),
    ("Theo", "How do I get out?"),
    ("Joss", "Exits are where a Level touches the real world. Thirty years, no exit. Ines says she is close."),
    ("Theo", "Thirty years? I have been gone minutes."),
    ("Joss", "Time does not line up down here. Do not trust your watch."),
    ("Joss", "Take these. Lamp-bags. Hang one at every turn. Scan it, it wakes up. Light only reaches what is mapped."),
    ("Joss", "Listen for keys. That is Hollis. Old night guard. Still on his round. Wait for him to pass."),
    ("Joss", "The way down needs a fuse. Breaker room, past the vending machines. Then find Hana at the pump house."),
    ("Theo", "Thanks, Joss."),
    ("Joss", "Do not thank me. Hang the bags."),
], note="Gives: lamp-bags, the radio frequency. Journal 04. Unlocks goal.l0b.", look="c0")

# --- DIALOGUE: HANA (Pump House, after tier 3)
scene("npc.hana", "dialogue", "Hana Osei", "Pump House (c1), after tier 3", "Walk up", [
    ("Hana", "You are the new one."),
    ("Theo", "Theo."),
    ("Hana", "Hana. Sit. Do not talk much. Water carries."),
    ("Hana", "Level 1 was the Halden's basement. Flooded in ninety-six. Forgotten, then drowned, then dropped here."),
    ("Theo", "Where does the water go?"),
    ("Hana", "Upstream, a shaft. At the top, the Falls. Follow it. Always follow it."),
    ("Hana", "You heard the thing in the pipes. That is Tobi. He went quiet. Now he is the Hush."),
    ("Theo", "He is the monster?"),
    ("Hana", "He was a person who stopped being heard. The scanner reads that as red. It is not wrong."),
    ("Hana", "Walk past him. Do not run. Do not ping. He will not forget you if you do."),
    ("Hana", "The valve wheel is in the boiler room. Take it, drain the channel, take the rope for the gap."),
    ("Hana", "Then Lena. At the Falls. She will tell you the rest."),
], note="Gives: pencil map, rope hint. Journal 07.", look="c1")

# --- DIALOGUE: LENA (Falls, after tier 4)
scene("npc.lena", "dialogue", "Lena Sorrel", "The Falls, after tier 4", "Walk up to the camp", [
    ("Lena", "Theo. We heard you coming a day ago. Come in. Eat."),
    ("Theo", "This place is..."),
    ("Lena", "Real. Yes. The Falls is a Refuge. Everyone remembers a place like it, so the dark cannot rewrite it."),
    ("Lena", "That's what holds us together. A memory everyone shares."),
    ("Theo", "Joss said thirty years."),
    ("Lena", "Joss is generous. Time here is a rumour."),
    ("Lena", "Five Crews went down before you. Six, if you count Crew 6, who never reached the Falls."),
    ("Lena", "Some of them walk the Levels now. Not themselves. You have met Hollis. You will meet more."),
    ("Theo", "Ines said the scanner has a shape to match. What does that mean?"),
    ("Lena", "Ask her. She has been keeping something from the rest of us, and I think it is hope."),
    ("Lena", "Take the Brass Key. It opens the doors on Level 2. Ravi's camp is behind them. Do not answer the voices."),
    ("Lena", "And Theo. When the dark takes you, you wake at the last lamp. That is her."),
    ("Theo", "Ines?"),
    ("Lena", "She keeps a Lamp at the bottom. When you fall, she pulls you back to the nearest light. It costs her. Fall less."),
], note="Gives: Brass Key, the respawn explanation. Journal 08. Unlocks thought.respawn.ines.", look="falls")

# --- DIALOGUE: RAVI (Ward Station, after tier 5)
scene("npc.ravi", "dialogue", "Ravi Anand", "Ward Station (c2), after tier 5", "Tap twice at the curtain, wait, tap once; scene plays", [
    ("Ravi", "(whisper) Two taps. A breath. One. Good. You waited. Come in."),
    ("Ravi", "You are Theo. Lena's radio said. I keep mine unplugged."),
    ("Theo", "Because of the Echo?"),
    ("Ravi", "It has my voice. If it speaks on a radio, you will think it is me. Or Ines."),
    ("Ravi", "Rule seven. Base asks what you see. Base never says come to me."),
    ("Theo", "What is it?"),
    ("Ravi", "The Wards is where voices end up. People who answered the wrong call. Someone who was nobody's patient."),
    ("Ravi", "I do not know what it was. I know it learns."),
    ("Theo", "Joss said the Survey's scanner came from somewhere."),
    ("Ravi", "From Corbel and Pike. The head of a survey unit, serial zero zero zero seven. Ines found it in the Garage."),
    ("Theo", "Zero zero zero seven. Mine is zero zero four one."),
    ("Ravi", "Then you know what you are carrying."),
    ("Ravi", "The crank for the lift is in the Dormitory. Take it. The Hollow is up. Pim keeps a light there."),
], note="Gives: crank location, scanner serial hook. Journal 09.", look="c2")

# --- DIALOGUE: PIM (Hollow Camp, after tier 7)
scene("npc.pim", "dialogue", "Pim Ashworth", "Hollow Camp (c3), after tier 7", "Walk up", [
    ("Pim", "Theo! You made it. Nobody makes it. Come sit."),
    ("Pim", "I keep the lanterns lit so people can find the camp. It's not much of a job. I love it."),
    ("Theo", "You are the youngest in the Survey."),
    ("Pim", "I came in nineteen. I don't know how old I am. Does it matter?"),
    ("Pim", "I found a draft once. It's why I stayed. A draft means air from somewhere else."),
    ("Theo", "The Still. Quill."),
    ("Pim", "Yes. Marlow. He moves when nobody looks. Watch, then step. Never stare."),
    ("Pim", "He used to photograph the Hollow. He thought if he looked at it enough, it would hold still."),
    ("Theo", "Did it?"),
    ("Pim", "It held still around him. That's why he can't leave."),
    ("Pim", "Ines is at the bottom. Garage. Follow the chalk. Take the Lamp Core from the shelf at the last bay."),
    ("Pim", "See you up there, Theo. I mean it."),
], note="Gives: the Lamp Core clue, flash bulb. Journal 10.", look="c3")

# --- DIALOGUE: INES (Lamp Room, finale)
scene("npc.ines", "dialogue", "Ines Calder", "The Lamp Room, after tier 8", "Walk up to the green dot", [
    ("~", "A tall dome. A great brass Lamp. A woman at a desk looks up. Green dot, steady. Her eyes find Theo's scanner first."),
    ("Ines", "Theo. Good. The dots held."),
    ("Theo", "Ines. You pulled me back."),
    ("Ines", "{deaths} times. Each night, a little further."),
    ("Ines", "You never fell. That is not luck. That is care."),
    ("Theo", "I have forty-one scans of the real floor three."),
    ("Ines", "I know. I watched you collect them on the status screen. Come, put the unit to the board."),
    ("~", "Theo places his scanner on the chalkboard rig. The board fills with white dots: every scan the Survey ever made. A gap, the shape of a corridor, glows."),
    ("Ines", "The Backrooms is made of forgotten places. A place nobody looks at stops belonging to the world."),
    ("Ines", "The Halden was empty ten years. You were the last to look at it, and you looked forty-one times."),
    ("Ines", "That is why the wall let you in. And why you can leave."),
    ("~", "The unit's scan slides into the gap. A line of light runs up the ladder shaft. A real door, edges of daylight."),
    ("Ines", "The ladder goes up. Pike was right."),
    ("Ines", "Or sit with me. Someone has to keep the lamp. Someone has to keep looking."),
    ("~", "Two choices. Climb, or take the lamp."),
], note="Ends with choice.up / choice.stay. Journal 12.", look="lamp")

# --- ENDINGS
scene("end.up", "cutscene", "Up", "After choice.up", "Cutscene, then credits card", [
    ("~", "Theo climbs. The air changes first: cold, clean, damp with rain."),
    ("~", "A door. He steps through. Halden Building, floor three, early light. The wall is a wall."),
    ("Theo", "It's morning."),
    ("~", "He checks his phone. Time: 11:43 PM. One minute after he leaned on the wall."),
    ("Theo", "One minute."),
    ("~", "He looks at the plaque in the stairwell: HALDEN BUILDING. FIFTEEN FLOORS."),
    ("Theo", "Fifteen."),
    ("~", "Behind him, the scanner chimes. SCAN 42 OF 42 BEGINNING. Nobody pressed anything."),
    ("~", "Card: THE BACKROOMS: MAPPED. Credits. Next run: Night Shift +."),
], note="The stinger: fifteen floors, and a scan starting by itself. Keeps the mystery open.", look="lamp")
scene("end.stay", "cutscene", "The Lamp", "After choice.stay", "Cutscene, then The Relay begins", [
    ("~", "Theo takes the Lamp's handle. It is heavier than it looks. Ines lets go."),
    ("Ines", "It listens to whoever is looking at it. That is the whole trick."),
    ("Theo", "Somebody will wake up scared in an office tomorrow. I would want a light."),
    ("~", "The ladder is still there. He does not climb it."),
    ("~", "Card: THE RELAY. Floor 1. Each floor is lit by the last person to pass it."),
], note="Starts endless mode. The daily seed is tonight's floor.", look="lamp")


# ===================================================================== LEGACY (v1 ids)
# The running build still asks for v1 ids. They stay available, marked legacy, until the build
# thread migrates each caller to the v2 ids. Not listed in 03-ingame-text.md.
def load_legacy():
    path = os.path.join(HERE, "v1", "lore-text.json")
    if not os.path.exists(path):
        return
    have = {e["id"] for e in E} | {s["id"] for s in SCENES}
    with open(path) as f:
        for e in json.load(f)["entries"]:
            if e["id"] not in have:
                e = dict(e)
                e["legacy"] = True
                E.append(e)


load_legacy()


# ===================================================================== OUTPUT
def validate():
    ids = set()
    ok = True
    for e in E + SCENES:
        if e["id"] in ids:
            print("DUPLICATE", e["id"])
            ok = False
        ids.add(e["id"])
    strings = []
    for e in E:
        for ln in e["lines"]:
            strings.append((e["id"], ln))
        if "thought" in e:
            strings.append((e["id"] + ".thought", e["thought"]))
    for s in SCENES:
        for b in s["beats"]:
            strings.append((s["id"], b.get("line") or b.get("shot")))
    for i, ln in strings:
        if not ln.isascii():
            print("NON-ASCII", i, ln)
            ok = False
        if len(ln) > 260 or (i.split(".")[0] not in ("cs", "tape", "npc", "end") and len(ln) > MAX_LINE):
            print("LONG", i, len(ln))
            ok = False
    return ok


def luau_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def luau_val(v, indent=0):
    pad = "\t" * (indent + 1)
    end = "\t" * indent
    if isinstance(v, str):
        return luau_str(v)
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, list):
        if all(not isinstance(x, (dict, list)) for x in v):
            return "{ " + ", ".join(luau_val(x) for x in v) + " }"
        return "{\n" + "".join(pad + luau_val(x, indent + 1) + ",\n" for x in v) + end + "}"
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            key = k if k.isidentifier() else "[" + luau_str(k) + "]"
            parts.append(key + " = " + luau_val(x, indent + 1))
        if all(not isinstance(x, (dict, list)) or isinstance(x, list) and all(not isinstance(y, (dict, list)) for y in x) for x in v.values()):
            return "{ " + ", ".join(parts) + " }"
        return "{\n" + "".join(pad + p + ",\n" for p in parts) + end + "}"
    raise TypeError(type(v))


def main():
    if not validate():
        sys.exit(1)
    data = {"entries": E, "scenes": SCENES, "looks": LOOKS, "voices": VOICES}
    with open(os.path.join(HERE, "lore-text.json"), "w") as f:
        json.dump(data, f, indent=1)
        f.write("\n")

    out = ["--!strict", "-- Generated by build_text.py (v2, Backrooms pivot). Do not edit by hand.",
           "export type Entry = {", "\tid: string,", "\tkind: string,", "\tsection: string,", "\twhere: string,", "\tlines: { string },",
           "\tspeaker: string?,", "\ttitle: string?,", "\tglow: { color: string, radius: number, look: string? }?,", "\tnote: string?,",
           "\tthought: string?,", "\tlook: string?,", "\tvo: string?,", "\tlegacy: boolean?,", "}",
           "export type Beat = { sp: string?, line: string?, shot: string? }",
           "export type Scene = { id: string, kind: string, title: string, where: string, trigger: string, beats: { Beat }, note: string?, look: string? }",
           "", "local entries: { Entry } = {"]
    for e in E:
        parts = ["id = " + luau_str(e["id"]), "kind = " + luau_str(e["kind"]), "section = " + luau_str(e["section"]),
                 "where = " + luau_str(e["where"]), "lines = " + luau_val(e["lines"])]
        for k in ("speaker", "title", "note", "thought", "look", "vo"):
            if k in e:
                parts.append(k + " = " + luau_str(e[k]))
        if e.get("legacy"):
            parts.append("legacy = true")
        if "glow" in e:
            g = e["glow"]
            gp = "color = %s, radius = %d" % (luau_str(g["color"]), g["radius"])
            if g.get("look"):
                gp += ", look = " + luau_str(g["look"])
            parts.append("glow = { " + gp + " }")
        out.append("\t{ " + ", ".join(parts) + " },")
    out += ["}", "", "local scenes: { Scene } = {"]
    for s in SCENES:
        beats = ", ".join(
            "{ " + (("sp = " + luau_str(b["sp"]) + ", line = " + luau_str(b["line"])) if "sp" in b else ("shot = " + luau_str(b["shot"]))) + " }"
            for b in s["beats"])
        parts = ["id = " + luau_str(s["id"]), "kind = " + luau_str(s["kind"]), "title = " + luau_str(s["title"]),
                 "where = " + luau_str(s["where"]), "trigger = " + luau_str(s["trigger"]), "beats = { " + beats + " }"]
        for k in ("note", "look"):
            if k in s:
                parts.append(k + " = " + luau_str(s[k]))
        out.append("\t{ " + ", ".join(parts) + " },")
    out += ["}", "", "local looks = " + luau_val(LOOKS), "", "local voices = " + luau_val(VOICES), "",
            "local byId: { [string]: Entry } = {}", "for _, e in entries do", "\tbyId[e.id] = e", "end",
            "local sceneById: { [string]: Scene } = {}", "for _, s in scenes do", "\tsceneById[s.id] = s", "end", "",
            "local LoreText = {}", "LoreText.entries = entries", "LoreText.scenes = scenes", "LoreText.looks = looks", "LoreText.voices = voices", "",
            "function LoreText.get(id: string): Entry?", "\treturn byId[id]", "end", "",
            "function LoreText.scene(id: string): Scene?", "\treturn sceneById[id]", "end", "",
            "function LoreText.look(key: string)", "\treturn looks[key]", "end", "",
            "function LoreText.ofKind(kind: string): { Entry }", "\tlocal r = {}", "\tfor _, e in entries do", "\t\tif e.kind == kind then",
            "\t\t\ttable.insert(r, e)", "\t\tend", "\tend", "\treturn r", "end", "", "return LoreText", ""]
    with open(os.path.join(HERE, "LoreText.luau"), "w") as f:
        f.write("\n".join(out))

    sec = {"any": "Any", "l0": "L0 Office Floor", "c0": "Joss's Closet", "desk": "Night Desk (Outpost Zero)", "l1": "L1 Flooded Wing",
           "c1": "Pump House", "falls": "The Falls", "l2": "L2 Wards", "c2": "Ward Station", "dorm": "Dormitory", "l3": "L3 Hollow",
           "c3": "Hollow Camp", "l4": "L4 Garage", "lamp": "Lamp Room", "relay": "The Relay"}
    kinds = ["goal", "rule", "plaque", "poi", "recorder", "radio", "thought", "journal", "entity", "note", "reveal", "card", "item", "tip", "choice", "sign", "system"]
    md = ["# In-game text (v2)", "", "Generated by `build_text.py`; do not edit. Same data as `lore-text.json` and `LoreText.luau`.",
          "Cutscenes, tapes and surveyor dialogue are in `04-cutscenes-and-tapes.md`. Voice casting is in `05-voice-and-radio.md`.", "",
          "Placeholders: `{deaths}` `{floor}` `{n}` `{party}`. A `look` names a backdrop in `looks` (see `02-sections.md`).", ""]
    for k in kinds:
        items = [e for e in E if e["kind"] == k and not e.get("legacy")]
        if not items:
            continue
        md += ["## " + k, "", "| id | where | text | Theo thought | look |", "|---|---|---|---|---|"]
        for e in items:
            spk = (e["speaker"] + ": ") if e.get("speaker") else ""
            txt = "<br>".join(e["lines"])
            nt = (" *" + e["note"] + "*") if e.get("note") else ""
            md.append("| `%s` | %s / %s | %s%s%s | %s | %s |" % (e["id"], sec.get(e["section"], e["section"]), e["where"], spk, txt, nt, e.get("thought", ""), e.get("look", "")))
        md.append("")
    with open(os.path.join(HERE, "03-ingame-text.md"), "w") as f:
        f.write("\n".join(md))

    cs = ["# Cutscenes, videotapes and surveyor dialogue", "",
          "Generated by `build_text.py`. A `~` beat is a picture or sound direction; spoken beats give the speaker. ",
          "All spoken lines are voiced (see `05-voice-and-radio.md`) and subtitled. Tapes play on a CRT or projector in the world; the screen is lit the moment the first dot lands on it.", ""]
    for s in SCENES:
        cs += ["## %s (`%s`, %s)" % (s["title"], s["id"], s["kind"]), "", "- **Where:** " + s["where"], "- **Trigger:** " + s["trigger"]]
        if s.get("look"):
            cs.append("- **Backdrop:** `%s`" % s["look"])
        if s.get("note"):
            cs.append("- **Note:** " + s["note"])
        cs.append("")
        for b in s["beats"]:
            if "shot" in b:
                cs.append("> *[%s]*" % b["shot"])
            else:
                cs.append("> **%s:** %s" % (b["sp"], b["line"]))
        cs.append("")
    with open(os.path.join(HERE, "04-cutscenes-and-tapes.md"), "w") as f:
        f.write("\n".join(cs))
    print("entries:", len(E), "scenes:", len(SCENES))


if __name__ == "__main__":
    main()
