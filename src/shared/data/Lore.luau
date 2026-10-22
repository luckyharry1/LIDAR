--!strict
-- All written story, as the game uses it. The words themselves come from the story thread's
-- LoreText (docs/story): this module only decides where each piece goes. Rooms reference
-- notes by id; adding a note, a room or a recorder line is a data change.
--
-- The story (the Backrooms, docs/story/01-story-bible.md) is told plainly by Theo Marsh, who
-- learns as the player does, and by the surveyors he finds: bulletins, tapes, camps and a
-- radio. Placeholders in braces ({deaths}, {party}, {floor}, {n}) are filled where the text
-- is shown, with Lore.fill.

local LoreText = require("./LoreText")

type Beat = LoreText.Beat

export type Note = { title: string, body: string }
export type Room = {
	id: string,
	title: string, -- shown as a title card on entry
	subtitle: string,
	size: string, -- "haven": a small lit room after a level; "room": a big one
	dark: boolean, -- true: built in the dark like the maze; one object (its lamp, or the waterfall) lights it once scanned
	theme: string, -- which layout the builder uses
	wall: { number }, -- RGB
	floor: { number },
	light: { number },
	notes: { string },
	scene: string?, -- a surveyor who talks to you here, first visit (LoreText scene id)
}
export type Echo = { speaker: string, line: string }
export type Card = { title: string, subtitle: string }
export type Section = { first: number, last: number, floor: string, card: Card, radio: string }
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

-- A found object as a note: what it says, then what Theo makes of it.
local function found(id: string): string
	local entry = LoreText.get(id)
	assert(entry ~= nil, "missing story text " .. id)
	local body = text(id)
	if entry.thought ~= nil then
		body ..= "\n\nTheo: " .. entry.thought
	end
	return body
end

Lore.notes = {
	-- The camps, one small haven each: a surveyor to meet (rooms[...].scene) and one thing to read.
	haven_copy = { title = "Joss's workbench", body = found("poi.c0.bench") },
	haven_booth = { title = "Hana's chart", body = found("poi.c1.chart") },
	haven_shed = { title = "Ravi's radio", body = found("poi.c2.radio") },
	haven_nook = { title = "The mugs", body = found("poi.c3.mugs") },
	-- The Night Desk, after tier 2: the first exhale. The Survey's radio works here.
	desk_signin = { title = "Sign-in sheet", body = found("poi.desk.signin") },
	desk_self = { title = "Survey handset", body = found("poi.desk.radio") },
	desk_mugs = { title = "Corkboard", body = found("poi.desk.board") },
	-- The Falls, after tier 4: the place the dark cannot rewrite.
	falls_ines = { title = "Tape, on a ledge", body = tape("rec.falls.1") },
	falls_lena = { title = "Tape, under the camp stove", body = tape("rec.falls.2") },
	falls_guestbook = { title = "Guest book", body = found("poi.falls.guestbook") },
	falls_behind = { title = "Mural, behind the water", body = found("poi.falls.behind") },
	-- The Dormitory, after tier 6: the quiet one. Who is still out there.
	bunk_board = { title = "Whiteboard", body = text("note.dorm.board") },
	bunk_pim = { title = "Letters, pinned to a bunk", body = text("note.dorm.letters") },
	bunk_theory = { title = "Model of the Halden", body = found("rev.dorm.model") },
	-- The Lamp Room, after tier 8: the finale. Reading the last page brings Ines's choice.
	lamp_postcard = { title = "The Lamp", body = found("poi.lamp.lamp") },
	lamp_pim = { title = "The board", body = found("poi.lamp.board") },
	lamp_rule12 = { title = "Manual, page 12. Handwritten", body = text("rule.12") },
	-- Relay floors, between endless tiers: someone lit this before you.
	relay_1 = { title = "Poster", body = text("sign.relay.1") },
	relay_2 = { title = "Poster", body = text("sign.relay.2") },
	relay_3 = { title = "Note by the kettle", body = text("sign.relay.3") },
} :: { [string]: Note }

-- Room ids and themes are the builder's (src/server/LoreRooms); every layout has three note
-- spots, so every room has three notes.
local copyCard = card("card.c0")
local boothCard = card("card.c1")
local shedCard = card("card.c2")
local nookCard = card("card.c3")
local deskCard = card("card.desk")
local fallsCard = card("card.falls")
local bunkCard = card("card.dorm")
local lampCard = card("card.lamp")
local relayCard = card("card.relay")

Lore.rooms = {
	copyroom = {
		id = "copyroom",
		dark = true,
		size = "haven",
		title = copyCard.title,
		subtitle = copyCard.subtitle,
		theme = "copyroom",
		wall = { 200, 190, 170 },
		floor = { 112, 96, 80 },
		light = { 255, 226, 186 },
		notes = { "haven_copy" },
		scene = "npc.joss",
	},
	drybooth = {
		id = "drybooth",
		dark = true,
		size = "haven",
		title = boothCard.title,
		subtitle = boothCard.subtitle,
		theme = "drybooth",
		wall = { 150, 168, 160 },
		floor = { 84, 92, 88 },
		light = { 255, 232, 190 },
		notes = { "haven_booth" },
		scene = "npc.hana",
	},
	pottingshed = {
		id = "pottingshed",
		dark = true,
		size = "haven",
		title = shedCard.title,
		subtitle = shedCard.subtitle,
		theme = "pottingshed",
		wall = { 150, 170, 140 },
		floor = { 110, 90, 66 },
		light = { 255, 236, 190 },
		notes = { "haven_shed" },
		scene = "npc.ravi",
	},
	archivenook = {
		id = "archivenook",
		dark = true,
		size = "haven",
		title = nookCard.title,
		subtitle = nookCard.subtitle,
		theme = "archivenook",
		wall = { 170, 164, 150 },
		floor = { 92, 88, 82 },
		light = { 255, 214, 160 },
		notes = { "haven_nook" },
		scene = "npc.pim",
	},
	office = {
		id = "office",
		dark = true,
		size = "room",
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
		dark = true,
		size = "room",
		title = fallsCard.title,
		subtitle = fallsCard.subtitle,
		theme = "cistern",
		wall = { 96, 118, 124 },
		floor = { 84, 96, 92 },
		light = { 235, 248, 250 },
		notes = { "falls_guestbook", "falls_ines", "falls_lena", "falls_behind" },
		scene = "npc.lena",
	},
	breakroom = {
		id = "breakroom",
		dark = true,
		size = "room",
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
		dark = false,
		size = "room",
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
		dark = false,
		size = "room",
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
		"rec.l0.1",
		"rec.l0.2",
		"rec.l0.3",
		"rec.l1.1",
		"rec.l1.2",
		"rec.l1.3",
		"rec.l2.1",
		"rec.l2.2",
		"rec.l2.3",
		"rec.l3.1",
		"rec.l3.2",
		"rec.l3.3",
	}
do
	table.insert(Lore.echoes, { speaker = speakerOf(id), line = spoken(id) })
end
Lore.echoSpeaker = "Tape" -- for any tape that does not name its speaker

-- Pages torn from the survey manual, found in the maze (one per run at most): its numbered
-- rules with the crew's margin notes. Page 12 is in the Lamp Room.
Lore.plateTitle = "Manual page"
Lore.plates = {} :: { string }
for index = 1, 11 do
	table.insert(Lore.plates, text(string.format("rule.%02d", index)))
end

-- The Levels. Each is one or two tiers; its card is shown on the way in.
Lore.sections = {
	{ first = 1, last = 2, floor = "L0", card = card("card.l0"), radio = "radio.l0" },
	{ first = 3, last = 4, floor = "L1", card = card("card.l1"), radio = "radio.l1" },
	{ first = 5, last = 6, floor = "L2", card = card("card.l2"), radio = "radio.l2" },
	{ first = 7, last = 7, floor = "L3", card = card("card.l3"), radio = "radio.l3" },
	{ first = 8, last = 8, floor = "L4", card = card("card.l4"), radio = "radio.l4" },
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

-- Base on the radio. Real Base asks what you see and gives plain next steps, and never says
-- "come to me". The Echo's fake Base only gives orders, and only near the Echo: that is the
-- tell, and the manual (rule 7) says so.
local function spokenAll(ids: { string }): { string }
	local out = {}
	for _, id in ids do
		table.insert(out, spoken(id))
	end
	return out
end

Lore.radio = {
	speaker = "Base",
	fakeSpeaker = "Base", -- the Echo wears the name, too
	desk = spoken("radio.first"), -- the first time at the Night Desk
	cleared = spoken("radio.clear"),
	dark = spokenAll({ "radio.idle.1", "radio.idle.2", "radio.idle.3" }),
	back = spokenAll({ "radio.back.1", "radio.back.2", "radio.back.3" }),
	fake = spokenAll({ "radio.fake.1", "radio.fake.2", "radio.fake.3", "radio.fake.4" }),
}

-- The call on arriving at a tier: its Level's, or an idle one on the endless Relay floors.
function Lore.radioFor(tier: number): string
	local section = Lore.sectionFor(tier)
	if section ~= nil then
		return spoken(section.radio)
	end
	return Lore.radio.dark[(tier % #Lore.radio.dark) + 1]
end

-- Theo's spoken thoughts (LoreText kind "thought"), by the id after "thought.".
function Lore.thought(id: string): string
	return spoken("thought." .. id)
end

-- What the player is trying to do, shown on the HUD: one goal per tier, and one for the two
-- rooms that have their own.
local GOALS = {
	[1] = "goal.l0",
	[2] = "goal.l0b",
	[3] = "goal.l1",
	[4] = "goal.l1b",
	[5] = "goal.l2",
	[6] = "goal.l2",
	[7] = "goal.l3",
	[8] = "goal.l4",
} :: { [number]: string }
local ROOM_GOALS = { cistern = "goal.falls", stairwell = "goal.lamp" } :: { [string]: string }

function Lore.goalFor(tier: number): string
	local id = GOALS[tier]
	return if id then spoken(id) else ""
end

function Lore.roomGoal(roomId: string): string
	local id = ROOM_GOALS[roomId]
	return if id then spoken(id) else ""
end

-- A scene as plain paragraphs: spoken lines carry their speaker, directions are narration.
local function sceneParagraphs(id: string, keep: ((Beat) -> boolean)?): { string }
	local scene = LoreText.scene(id)
	assert(scene ~= nil, "missing scene " .. id)
	local out = {}
	for _, beat in scene.beats do
		if keep == nil or keep(beat) then
			if beat.sp ~= nil and beat.line ~= nil then
				table.insert(out, beat.sp .. ": " .. beat.line)
			elseif beat.shot ~= nil then
				table.insert(out, beat.shot)
			end
		end
	end
	return out
end

-- The finale. Ines speaks, then offers the choice; each choice has its own end card.
Lore.ending = {
	title = "Ines Calder",
	body = "", -- set below: the general case; Lore.endingBody fills in the real count
	choices = { up = text("choice.up"), stay = text("choice.stay") },
	cards = {
		up = { title = "Up", body = table.concat(sceneParagraphs("end.up"), "\n\n") },
		stay = { title = "The lamp", body = table.concat(sceneParagraphs("end.stay"), "\n\n") },
	} :: { [string]: Note },
}

-- Ines's words for a player who was taken `deaths` times on the way down. The scene counts the
-- falls once; a player who never fell hears that instead.
function Lore.endingBody(deaths: number): string
	local count = math.max(0, math.floor(deaths))
	local paragraphs = sceneParagraphs("npc.ines", function(beat: Beat): boolean
		local line = beat.line or ""
		if beat.shot ~= nil then
			return false -- the pictures belong to the cutscene, not the panel
		elseif string.find(line, "{deaths}", 1, true) then
			return count > 0
		elseif string.sub(line, 1, 14) == "You never fell" then
			return count == 0
		elseif string.sub(line, 1, 19) == "Ines. You pulled me" then
			return count > 0
		end
		return true
	end)
	return Lore.fill(table.concat(paragraphs, "\n\n"), { deaths = count })
end
Lore.ending.body = Lore.endingBody(1)

return Lore
