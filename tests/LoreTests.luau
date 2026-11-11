--!strict
-- The story wiring: every room, tape, page and card the game shows must resolve to real text
-- from LoreText, and fit the places the builders put it.
local Config = require("../src/shared/Config")
local fs = require("@lune/fs")
local Difficulty = require("../src/shared/pure/Difficulty")
local Lore = require("../src/shared/data/Lore")
local LoreText = require("../src/shared/data/LoreText")
local Places = require("../src/shared/data/Places")
local Tiers = require("../src/shared/data/Tiers")

local HAVEN_NOTES = 1 -- a small haven has one page to read
local ROOM_NOTES = { 3, 4 } -- a big lit room has three, or four with a secret (the Falls)
local PLACEHOLDERS = { deaths = true, party = true, floor = true, n = true }

local tests: { [string]: () -> () } = {}

local function placeholdersIn(text: string): { string }
	local found = {}
	for key in string.gmatch(text, "{(%w+)}") do
		table.insert(found, key)
	end
	return found
end

tests["every room has the notes its size calls for, and they exist"] = function()
	for id, room in Lore.rooms do
		assert(room.id == id, "room id mismatch: " .. id)
		if room.size == "haven" then
			assert(#room.notes == HAVEN_NOTES, `haven {id} has {#room.notes} notes`)
		else
			assert(
				#room.notes >= ROOM_NOTES[1] and #room.notes <= ROOM_NOTES[2],
				`{id} has {#room.notes} notes`
			)
		end
		for _, noteId in room.notes do
			local note = Lore.notes[noteId]
			assert(note ~= nil, `{id} names a missing note {noteId}`)
			assert(note.title ~= "" and note.body ~= "", `{noteId} is empty`)
		end
		assert(room.title ~= "" and room.subtitle ~= "", `{id} has no card`)
	end
end

tests["every lit room a tier leads to exists"] = function()
	for index, tier in Tiers do
		local room = tier.loreRoomAfter
		if room ~= nil then
			assert(Lore.rooms[room] ~= nil, `tier {index} leads to a missing room {room}`)
		end
	end
	assert(Lore.rooms.landing ~= nil, "the Relay landing is missing")
end

tests["a haven follows every odd tier and a big lit room every even one"] = function()
	for index, tier in Tiers do
		local room = Lore.rooms[tier.loreRoomAfter or ""]
		assert(room ~= nil, `tier {index} has no lit break`)
		assert(room.size == (if index % 2 == 1 then "haven" else "room"), `tier {index} break size`)
	end
end

tests["the finale ends on the last note of the Lamp Room"] = function()
	local notes = Lore.rooms.stairwell.notes
	assert(notes[#notes] == "lamp_rule12", "the ending is triggered by the last note")
end

tests["one tape for every recorder in the authored tiers"] = function()
	local recorders = 0
	for _, tier in Tiers do
		recorders += tier.echoes
	end
	assert(#Lore.echoes == recorders, `{#Lore.echoes} tapes for {recorders} recorders`)
	for index, echo in Lore.echoes do
		assert(echo.speaker ~= "", `tape {index} has no speaker`)
		assert(echo.line ~= "" and not string.find(echo.line, "\n"), `tape {index} is not one line`)
	end
end

tests["manual pages are the eleven printed rules"] = function()
	assert(#Lore.plates == 11, "expected eleven manual pages")
	for index, page in Lore.plates do
		assert(
			string.sub(page, 1, #tostring(index) + 1) == index .. ".",
			`page {index} is out of order`
		)
	end
	local margins = 0
	for _, page in Lore.plates do
		if string.find(page, "In the margin: ", 1, true) ~= nil then
			margins += 1
		end
	end
	assert(margins > 0, "margins are not marked")
end

tests["every authored tier has a floor and endless tiers are the Relay"] = function()
	for tier = 1, #Tiers do
		assert(Lore.sectionFor(tier) ~= nil, `tier {tier} has no floor`)
	end
	assert(Lore.sectionFor(#Tiers + 1) == nil, "endless tiers should not have a floor")
	assert(
		string.find(Difficulty.forTier(#Tiers + 2).name, "Relay", 1, true) ~= nil,
		"endless tiers should be Relay floors"
	)
end

tests["only known placeholders appear, and fill replaces them"] = function()
	local texts: { string } = {}
	for _, note in Lore.notes do
		table.insert(texts, note.body)
	end
	for _, echo in Lore.echoes do
		table.insert(texts, echo.line)
	end
	for tier = 1, #Tiers + 1 do
		table.insert(texts, Lore.radioFor(tier))
	end
	table.insert(texts, Lore.relayCard.title)
	for _, text in texts do
		for _, key in placeholdersIn(text) do
			assert(PLACEHOLDERS[key], "unknown placeholder {" .. key .. "}")
		end
	end
	assert(
		Lore.fill("Floor {floor}. {who}", { floor = "B3" }) == "Floor B3. {who}",
		"fill is wrong"
	)
end

tests["Ines counts the falls, or says there were none"] = function()
	local many = Lore.endingBody(4)
	assert(string.find(many, "4 times.", 1, true) ~= nil, "the count is missing")
	local none = Lore.endingBody(0)
	assert(string.find(none, "You never fell.", 1, true) ~= nil, "the no-falls line is missing")
	assert(#placeholdersIn(many) == 0 and #placeholdersIn(none) == 0, "unfilled placeholder")
	assert(Lore.ending.choices.up ~= "" and Lore.ending.choices.stay ~= "", "the choice is missing")
	assert(Lore.ending.ask ~= "" and not string.find(Lore.ending.ask, "\n"), "no question")
	for _, id in { Lore.ending.scenes.opening, Lore.ending.scenes.up, Lore.ending.scenes.stay } do
		assert(LoreText.scene(id) ~= nil, `the finale needs the scene {id}`)
	end
end

tests["the finale keeps the lines that fit the player, the same way as its text"] = function()
	local scene = LoreText.scene("npc.ines")
	assert(scene ~= nil)
	for _, deaths in { 0, 1, 7 } do
		local keep = Lore.endingKeep(deaths)
		local heard = {}
		for _, beat in scene.beats do
			if beat.line ~= nil and keep(beat) then
				table.insert(heard, beat.line)
			end
		end
		local joined = table.concat(heard, "\n")
		assert(
			(string.find(joined, "{deaths}", 1, true) ~= nil) == (deaths > 0),
			`{deaths} falls: the count line is wrong`
		)
		assert(
			(string.find(joined, "You never fell", 1, true) ~= nil) == (deaths == 0),
			`{deaths} falls: the no-falls line is wrong`
		)
		assert(
			(string.find(joined, "You pulled me back", 1, true) ~= nil) == (deaths > 0),
			`{deaths} falls: Theo's reply is wrong`
		)
		assert(#heard == (if deaths > 0 then 6 else 5), `{deaths} falls: {#heard} lines`)
	end
end

tests["Ines and both endings are filmed on the lamp set, in the order the story needs"] = function()
	local expected = {
		["npc.ines"] = { "lamp", "board", "ladder" },
		["end.up"] = { "climb", "morning", "scan42" },
		["end.stay"] = { "take", "keep" },
	}
	for id, cues in expected do
		local scene = LoreText.scene(id)
		assert(scene ~= nil and scene.stage == "lamp", `{id} is not staged on the lamp set`)
		local found = {}
		for _, beat in scene.beats do
			if beat.stage ~= nil then
				table.insert(found, beat.stage)
			end
		end
		assert(
			table.concat(found, ",") == table.concat(cues, ","),
			`{id}: cues {table.concat(found, ",")}`
		)
	end
end

tests["the endings print captions, not stage directions or a mode that does not exist"] = function()
	for _, id in { "end.up", "end.stay" } do
		local scene = LoreText.scene(id)
		assert(scene ~= nil)
		local captions = 0
		for _, beat in scene.beats do
			for _, text in { beat.cap, beat.line, beat.shot } do
				assert(not string.find(text, "Night Shift", 1, true), `{id} promises Night Shift`)
				assert(not string.find(text, "Card:", 1, true), `{id} prints a card direction`)
			end
			if beat.cap ~= nil then
				captions += 1
			end
		end
		assert(captions >= 2, `{id} has no end captions`)
	end
end

tests["every monster has a manual page"] = function()
	for _, kind in { "wanderer", "listener", "mimic", "stalker" } do
		local entity = Lore.entities[kind]
		assert(entity ~= nil and entity.name ~= "" and entity.page ~= "", `{kind} has no page`)
	end
end

tests["every camp scene is spoken by a surveyor who stands in that camp"] = function()
	for id, room in Lore.rooms do
		if room.scene ~= nil then
			assert(room.surveyor ~= nil, `{id} has a scene but no surveyor to stand there`)
		end
		if room.surveyor ~= nil then
			local who = Lore.surveyors[room.surveyor]
			assert(who ~= nil, `{id} names missing surveyor {room.surveyor}`)
			assert(who.scene == room.scene, `{id}: {who.name} speaks another scene`)
			assert(#who.coat == 3 and #who.lamp == 3, `{who.name} needs a coat and lamp colour`)
		end
	end
end

tests["the surveyors found in the maze are named, in a camp, and have something to say"] = function()
	local campOf: { [string]: boolean } = {}
	for _, room in Lore.rooms do
		if room.surveyor ~= nil then
			campOf[room.surveyor] = true
		end
	end
	for tier, key in Config.Surveyor.rescueOfTier do
		local who = Lore.surveyors[key]
		assert(who ~= nil, `tier {tier} finds missing surveyor {key}`)
		assert(campOf[key], `{who.name} is found in tier {tier} but has no camp`)
		assert(
			who.rescued ~= nil and #who.rescued > 0,
			`{who.name} has nothing to say when helped up`
		)
		assert(tier <= #Tiers, `tier {tier} is not an authored tier`)
	end
end

tests["every camp's surveyor, goal and radio call exists"] = function()
	for id, room in Lore.rooms do
		if room.scene ~= nil then
			assert(LoreText.scene(room.scene) ~= nil, `{id} names a missing scene {room.scene}`)
		end
	end
	for tier = 1, #Tiers do
		assert(Lore.goalFor(tier) ~= "", `tier {tier} has no goal`)
		assert(Lore.radioFor(tier) ~= "", `tier {tier} has no radio call`)
	end
	assert(Lore.roomGoal("cistern") ~= "" and Lore.roomGoal("stairwell") ~= "", "room goals")
	assert(Lore.roomGoal("office") == "", "an unlisted room has no goal")
end

tests["every scene opens with something to show and every beat is one thing"] = function()
	assert(LoreText.scene("cs.open") ~= nil and LoreText.scene("tape.orientation") ~= nil)
	for _, scene in LoreText.scenes do
		assert(#scene.beats > 0, `{scene.id} has no beats`)
		for index, beat in scene.beats do
			local parts = (if beat.cap then 1 else 0)
				+ (if beat.shot then 1 else 0)
				+ (if beat.stage then 1 else 0)
				+ (if beat.sp or beat.line then 1 else 0)
			assert(parts == 1, `{scene.id} beat {index} is not exactly one kind`)
			if beat.sp ~= nil then
				assert(beat.line ~= nil and beat.line ~= "", `{scene.id} beat {index} says nothing`)
			end
		end
	end
end

tests["Theo has a thought for every first the tutorial reacts to"] = function()
	for _, key in
		{
			"wake",
			"firstdot",
			"water",
			"pit",
			"plate",
			"falls",
			"surveyor",
			"keys",
			"hush",
			"echo",
			"still",
			"respawn.first",
			"respawn.ines",
		}
	do
		assert(Lore.thought(key) ~= "", `no thought for {key}`)
	end
end

tests["hidden objects carry a thought and a prop"] = function()
	for tier, places in Places.tiers do
		for _, id in places.reveals do
			local reveal = Places.reveal(id)
			assert(
				reveal.thought ~= nil and reveal.thought ~= "",
				`tier {tier}: {id} has no thought`
			)
		end
	end
end

tests["the opening, every tape and the finale are staged with cues the stage knows"] = function()
	local known = { office = true, lean = true, dark = true, wake = true }
	local lampCues = {
		lamp = true,
		board = true,
		ladder = true,
		climb = true,
		morning = true,
		scan42 = true,
		take = true,
		keep = true,
	}
	local tapeCues = {
		reach = true,
		static = true,
		door = true,
		fade = true,
		gone = true,
		dim = true,
		echo = true,
		shape = true,
	}
	local opening = LoreText.scene("cs.open")
	assert(opening ~= nil and opening.stage == "office", "the opening is not staged")
	for _, beat in opening.beats do
		if beat.stage ~= nil then
			assert(known[beat.stage], `unknown staging cue {beat.stage}`)
		end
	end
	local lampScenes = 0
	for _, scene in LoreText.scenes do
		if scene.stage == "lamp" then
			lampScenes += 1
			for _, beat in scene.beats do
				if beat.stage ~= nil then
					assert(lampCues[beat.stage], `{scene.id}: unknown lamp cue {beat.stage}`)
				end
			end
		end
		if scene.kind == "tape" then
			assert(scene.stage == "tape", `{scene.id} is not staged`)
			for _, beat in scene.beats do
				if beat.stage ~= nil then
					assert(tapeCues[beat.stage], `{scene.id}: unknown tape cue {beat.stage}`)
				end
			end
		end
	end
	assert(lampScenes == 3, `{lampScenes} lamp scenes, expected npc.ines, end.up and end.stay`)
	for _, id in { "npc.ines", "end.up", "end.stay" } do
		local scene = LoreText.scene(id)
		assert(scene ~= nil and scene.stage == "lamp", `{id} is not staged on the lamp set`)
	end
end

-- The tapes, in the order a player meets them: the intake's, then one per rest room.
local TAPE_ROOMS = {
	{ room = "copyroom", tape = "tape.halden", kit = "vcrtv" },
	{ room = "office", tape = "tape.hollis", kit = "monitor" },
	{ room = "drybooth", tape = "tape.tobi", kit = "cassette" },
	{ room = "pottingshed", tape = "tape.ravi", kit = "avcart" },
	{ room = "breakroom", tape = "tape.quill", kit = "projector" },
	{ room = "archivenook", tape = "tape.pike", kit = "camcorder" },
}
local TAPE_ORDER = {
	"tape.orientation",
	"tape.halden",
	"tape.hollis",
	"tape.tobi",
	"tape.ravi",
	"tape.quill",
	"tape.pike",
}

tests["every room that has a tape names a real tape, and no tape is in two places"] = function()
	local placed: { [string]: string } = {}
	for id, room in Lore.rooms do
		if room.tape ~= nil then
			local scene = LoreText.scene(room.tape)
			assert(
				scene ~= nil and scene.kind == "tape",
				`{id} names {room.tape}, which is no tape`
			)
			assert(placed[room.tape] == nil, `{room.tape} is in {placed[room.tape]} and {id}`)
			placed[room.tape] = id
			assert(room.dark, `{id}: a tape screen is revealed by the room's lamp`)
		end
	end
	for _, entry in TAPE_ROOMS do
		assert(placed[entry.tape] == entry.room, `{entry.tape} should be in {entry.room}`)
	end
	assert(placed["tape.orientation"] == nil, "the orientation tape is the intake room's")
end

tests["every tape is placed: six rest rooms and the intake room"] = function()
	local props = fs.readFile("src/server/Props.luau")
	local layouts = fs.readFile("src/server/LoreRooms.luau")
	for _, entry in TAPE_ROOMS do
		assert(
			string.find(props, "\n\t" .. entry.kit .. " = {", 1, true) ~= nil,
			`no prop kit {entry.kit}`
		)
		assert(string.find(props, 'name = "TapeScreen"', 1, true) ~= nil)
		assert(
			string.find(layouts, 'kit = "' .. entry.kit .. '"', 1, true) ~= nil,
			`{entry.kit} is in no room layout`
		)
		local room = Lore.rooms[entry.room]
		assert(room ~= nil and room.tape == entry.tape, `{entry.room} does not hold {entry.tape}`)
	end
	local intake = fs.readFile("src/server/TutorialRoom.luau")
	assert(
		string.find(intake, '"tape.orientation"', 1, true) ~= nil,
		"no screen in the intake room"
	)
	assert(string.find(intake, "Config.Tags.tape", 1, true) ~= nil, "the intake TV is not tagged")
	assert(Config.Tags.tape == "Lidar_Tape", "the tape tag changed")
end

tests["tapes are numbered 1 to 7 in the order they are met, in one style"] = function()
	assert(#TAPE_ORDER == 7)
	local seen = 0
	for _, scene in LoreText.scenes do
		if scene.kind == "tape" then
			seen += 1
		end
	end
	assert(seen == #TAPE_ORDER, `{seen} tape scenes, {#TAPE_ORDER} expected`)
	for index, id in TAPE_ORDER do
		local scene = LoreText.scene(id)
		assert(scene ~= nil, `missing {id}`)
		assert(
			string.sub(scene.title, 1, #`Tape {index} of 7:`) == `Tape {index} of 7:`,
			`{id} is titled "{scene.title}", expected "Tape {index} of 7: ..."`
		)
	end
	for _, entry in LoreText.entries do
		for _, line in entry.lines do
			assert(not string.find(string.upper(line), "OF 9", 1, true), `{entry.id} says "of 9"`)
		end
	end
end

-- Vasco, 10 Nov: "the dialogue is way too much and repetitive". These budgets keep it cut.
local SPOKEN_MAX = 90 -- characters in one spoken or thought line
local SPOKEN_BUDGET = { ["cs.open"] = 3, ["tape.orientation"] = 5, ["npc.ines"] = 7 }

tests["every scene stays inside its spoken-line budget, and every line stays short"] = function()
	for _, scene in LoreText.scenes do
		local spoken = 0
		for _, beat in scene.beats do
			if beat.sp ~= nil and beat.line ~= nil then
				spoken += 1
				if scene.kind ~= "cutscene" then
					assert(#beat.line <= SPOKEN_MAX, `{scene.id}: line is {#beat.line} characters`)
				end
			end
		end
		local budget = SPOKEN_BUDGET[scene.id]
			or (if scene.kind == "tape" then 4 elseif scene.kind == "dialogue" then 5 else nil)
		if budget ~= nil then
			assert(spoken <= budget, `{scene.id} speaks {spoken} lines, the budget is {budget}`)
		end
	end
end

tests["no sentence is spoken twice across scenes, thoughts and Base's calls"] = function()
	local seen: { [string]: string } = {}
	local function once(owner: string, line: string)
		local key = string.lower(line)
		if #key > 12 then
			assert(seen[key] == nil, `"{line}" is said by {seen[key]} and {owner}`)
			seen[key] = owner
		end
	end
	for _, scene in LoreText.scenes do
		for _, beat in scene.beats do
			if beat.sp ~= nil and beat.line ~= nil then
				once(scene.id, beat.line)
			end
		end
	end
	for _, kind in { "thought", "radio" } do
		for _, entry in LoreText.ofKind(kind) do
			if not entry.legacy then -- the v1 ids are kept for old callers and say the same things
				for _, line in entry.lines do
					once(entry.id, line)
				end
			end
		end
	end
end

tests["Base's level calls are company, not orders: the HUD goal says what to do"] = function()
	for tier = 1, #Tiers do
		local call = Lore.radioFor(tier)
		assert(string.find(call, "Find ", 1, true) == nil, `tier {tier}: Base repeats the goal`)
		assert(#call <= 110, `tier {tier}: Base talks too long`)
	end
end

return tests
