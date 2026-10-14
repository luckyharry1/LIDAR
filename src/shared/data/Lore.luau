--!strict
-- All written story, as the game uses it. The words themselves come from the story thread's
-- LoreText (docs/story): this module only decides where each piece goes. Rooms reference
-- notes by id; adding a note, a room or a recorder line is a data change.
--
-- The story ("The Understory", docs/story/01-story-bible.md) is told indirectly: notices,
-- tapes, a sign-in sheet, a manual with margin notes. Nobody explains; the player assembles
-- it. Placeholders in braces ({deaths}, {party}, {floor}, {n}) are filled where the text is
-- shown, with Lore.fill.

local LoreText = require("./LoreText")

export type Note = { title: string, body: string }
export type Room = {
	id: string,
	title: string, -- shown as a title card on entry
	subtitle: string,
	theme: string, -- which layout the builder uses
	wall: { number }, -- RGB
	floor: { number },
	light: { number },
	notes: { string },
}
export type Echo = { speaker: string, line: string }
export type Card = { title: string, subtitle: string }
export type Section = { first: number, last: number, floor: string, card: Card }
export type Entity = { name: string, page: string }

local Lore = {}

-- The lines of a story entry. Margin notes (handwritten in the manual) are marked as such.
local function linesOf(id: string): { string }
	local entry = LoreText.get(id)
	assert(entry ~= nil, "missing story text " .. id)
	local out = {}
	for _, line in entry.lines do
		if string.sub(line, 1, 8) == "margin: " then
			table.insert(out, "In the margin: " .. string.sub(line, 9))
		else
			table.insert(out, line)
		end
	end
	return out
end

local function text(id: string): string
	return table.concat(linesOf(id), "\n")
end

local function speakerOf(id: string): string
	local entry = LoreText.get(id)
	return if entry and entry.speaker then entry.speaker else ""
end

-- A tape: who is speaking, then what they say.
local function tape(id: string): string
	local speaker = speakerOf(id)
	return if speaker ~= "" then speaker .. ":\n" .. text(id) else text(id)
end

-- Spoken lines run on as one line of speech.
local function spoken(id: string): string
	return table.concat(linesOf(id), " ")
end

local function card(id: string): Card
	local lines = linesOf(id)
	local count = #lines
	return { title = lines[count - 1], subtitle = lines[count] }
end

-- Replaces {name} placeholders with the given values; unknown ones are left as they are.
function Lore.fill(template: string, values: { [string]: string | number }): string
	return (
		string.gsub(template, "{(%w+)}", function(key: string): string
			local value = values[key]
			return if value ~= nil then tostring(value) else "{" .. key .. "}"
		end)
	)
end

Lore.notes = {
	-- The Night Desk, after tier 2: the first exhale. Crew 7 has done this before.
	desk_signin = { title = "Sign-in sheet", body = text("note.desk.signin") },
	desk_self = { title = "Torn note, under the lamp", body = text("note.desk.self") },
	desk_mugs = { title = "Mug rack", body = text("rev.desk.mugs") },
	-- The Falls, after tier 4: the place the dark cannot rewrite.
	falls_ines = { title = "Tape, on a ledge", body = tape("rec.falls.1") },
	falls_lena = { title = "Tape, under the camp stove", body = tape("rec.falls.2") },
	falls_guestbook = { title = "Guest book", body = text("note.falls.guestbook") },
	-- The Bunk Room, after tier 6: the quiet, sad one. What the red things were.
	bunk_board = { title = "Corkboard", body = text("note.bunk.board") },
	bunk_pim = { title = "Folded note, under a bunk", body = text("note.bunk.pim") },
	bunk_theory = { title = "Tape, on the stove shelf", body = tape("rec.bunk.1") },
	-- The Lamp Room, after tier 8: the finale. Reading the last page brings Ines's choice.
	lamp_postcard = { title = "Postcard, pinned up", body = text("rev.lamp.postcard") },
	lamp_pim = { title = "Recorder, by the ladder", body = tape("npc.pim.recording") },
	lamp_rule12 = { title = "Manual, page 12. Handwritten", body = text("rule.12") },
	-- Relay floors, between endless tiers: someone lit this before you.
	relay_1 = { title = "Poster", body = text("sign.relay.1") },
	relay_2 = { title = "Poster", body = text("sign.relay.2") },
	relay_3 = { title = "Note by the kettle", body = text("sign.relay.3") },
} :: { [string]: Note }

-- Room ids and themes are the builder's (src/server/LoreRooms); every layout has three note
-- spots, so every room has three notes.
local deskCard = card("card.desk")
local fallsCard = card("card.falls")
local bunkCard = card("card.bunk")
local lampCard = card("card.lamp")
local relayCard = card("card.relay")

Lore.rooms = {
	office = {
		id = "office",
		title = deskCard.title,
		subtitle = deskCard.subtitle,
		theme = "office",
		wall = { 196, 178, 150 },
		floor = { 120, 86, 60 },
		light = { 255, 214, 170 },
		notes = { "desk_mugs", "desk_signin", "desk_self" },
	},
	cistern = {
		id = "cistern",
		title = fallsCard.title,
		subtitle = fallsCard.subtitle,
		theme = "cistern",
		wall = { 96, 118, 124 },
		floor = { 84, 96, 92 },
		light = { 235, 248, 250 },
		notes = { "falls_guestbook", "falls_ines", "falls_lena" },
	},
	breakroom = {
		id = "breakroom",
		title = bunkCard.title,
		subtitle = bunkCard.subtitle,
		theme = "breakroom",
		wall = { 178, 190, 170 },
		floor = { 150, 140, 120 },
		light = { 255, 224, 190 },
		notes = { "bunk_board", "bunk_pim", "bunk_theory" },
	},
	stairwell = {
		id = "stairwell",
		title = lampCard.title,
		subtitle = lampCard.subtitle,
		theme = "stairwell",
		wall = { 186, 176, 160 },
		floor = { 96, 90, 84 },
		light = { 255, 206, 150 },
		notes = { "lamp_postcard", "lamp_pim", "lamp_rule12" },
	},
	landing = {
		id = "landing",
		title = Lore.fill(relayCard.title, { n = "" }):gsub("%s+$", ""),
		subtitle = relayCard.subtitle,
		theme = "landing",
		wall = { 190, 184, 172 },
		floor = { 104, 96, 88 },
		light = { 255, 218, 176 },
		notes = { "relay_1", "relay_2", "relay_3" },
	},
} :: { [string]: Room }

-- Field recorders hidden in the maze. Scan one enough and it reveals itself, lights its
-- corner of the level and plays its tape. Each player hears them in this order, so the story
-- unfolds the same way however the levels are explored: three tapes per floor, twelve in all,
-- one for every recorder in tiers 1 to 8.
Lore.echoes = {} :: { Echo }
for _, id in
	{
		"rec.annex.1",
		"rec.annex.2",
		"rec.annex.3",
		"rec.flood.1",
		"rec.flood.2",
		"rec.flood.3",
		"rec.over.1",
		"rec.over.2",
		"rec.over.3",
		"rec.found.1",
		"rec.found.2",
		"rec.found.3",
	}
do
	table.insert(Lore.echoes, { speaker = speakerOf(id), line = spoken(id) })
end
Lore.echoSpeaker = "Recorder" -- for any tape that does not name its speaker

-- Pages torn from the survey manual, found in the maze (one per run at most): its numbered
-- rules with the crew's margin notes. Page 12 is in the Lamp Room.
Lore.plateTitle = "Manual page"
Lore.plates = {} :: { string }
for index = 1, 11 do
	table.insert(Lore.plates, text(string.format("rule.%02d", index)))
end

-- The floors. Each floor is two tiers; its card is shown on the way in.
Lore.sections = {
	{ first = 1, last = 2, floor = "B3", card = card("card.annex") },
	{ first = 3, last = 4, floor = "B4", card = card("card.flood") },
	{ first = 5, last = 6, floor = "B5", card = card("card.over") },
	{ first = 7, last = 8, floor = "B6", card = card("card.found") },
} :: { Section }
Lore.relayCard = relayCard -- endless floors: fill {n}
Lore.dailyCard = card("card.relay.daily")

-- The section a tier belongs to, or nil past the authored floors (the Relay).
function Lore.sectionFor(tier: number): Section?
	for _, section in Lore.sections do
		if tier >= section.first and tier <= section.last then
			return section
		end
	end
	return nil
end

-- The monsters, as the manual names them. A page unlocks on first sighting.
Lore.entities = {
	wanderer = { name = "the Pacer", page = text("ent.wanderer") },
	listener = { name = "the Hush", page = text("ent.listener") },
	mimic = { name = "the Echo", page = text("ent.mimic") },
	stalker = { name = "the Still", page = text("ent.stalker") },
} :: { [string]: Entity }

-- Base on the radio. Real Base reports and counts; it never gives directions. The Echo's
-- fake Base does, and only near the Echo: that difference is the tell.
Lore.radio = {
	speaker = speakerOf("radio.base.1"),
	fakeSpeaker = speakerOf("radio.fake.1"),
	desk = spoken("radio.desk.1"), -- the first time at the Night Desk
	lit = spoken("radio.base.1"), -- idle in a lit room
	floor = spoken("radio.base.2"), -- a new floor: fill {floor}
	cleared = spoken("radio.base.5"),
	dark = { spoken("radio.base.3"), spoken("radio.base.4") },
	back = { spoken("radio.back.1"), spoken("radio.back.2"), spoken("radio.back.3") },
	fake = {
		spoken("radio.fake.1"),
		spoken("radio.fake.2"),
		spoken("radio.fake.3"),
		spoken("radio.fake.4"),
	},
}

-- The finale. Ines speaks, then offers the choice; each choice has its own end card.
local function inesLines(deaths: number): string
	local ids = { "npc.ines.1", "npc.ines.2", if deaths > 0 then "npc.ines.3" else "npc.ines.3z" }
	table.insert(ids, "npc.ines.4")
	table.insert(ids, "npc.ines.5")
	table.insert(ids, "npc.ines.6")
	local parts = {}
	for _, id in ids do
		table.insert(parts, text(id))
	end
	return Lore.fill(table.concat(parts, "\n\n"), { deaths = deaths })
end

Lore.ending = {
	title = speakerOf("npc.ines.1"),
	body = inesLines(1), -- the general case; Lore.endingBody fills in the real count
	choices = { up = text("choice.up"), stay = text("choice.stay") },
	cards = {
		up = { title = "Up", body = text("end.up") },
		stay = { title = "The lamp", body = text("end.stay") },
	} :: { [string]: Note },
}

-- Ines's words for a player who was taken `deaths` times on the way down.
function Lore.endingBody(deaths: number): string
	return inesLines(math.max(0, math.floor(deaths)))
end

return Lore
