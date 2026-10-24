--!strict
-- The story wiring: every room, tape, page and card the game shows must resolve to real text
-- from LoreText, and fit the places the builders put it.
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
	assert(Lore.ending.cards.up ~= nil and Lore.ending.cards.stay ~= nil, "an end card is missing")
end

tests["every monster has a manual page"] = function()
	for _, kind in { "wanderer", "listener", "mimic", "stalker" } do
		local entity = Lore.entities[kind]
		assert(entity ~= nil and entity.name ~= "" and entity.page ~= "", `{kind} has no page`)
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

tests["the opening and every tape are staged with cues the stage knows"] = function()
	local known = { office = true, lean = true, dark = true, wake = true }
	local opening = LoreText.scene("cs.open")
	assert(opening ~= nil and opening.stage == "office", "the opening is not staged")
	for _, beat in opening.beats do
		if beat.stage ~= nil then
			assert(known[beat.stage], `unknown staging cue {beat.stage}`)
		end
	end
	for _, scene in LoreText.scenes do
		if scene.kind == "tape" then
			assert(scene.stage == "tape", `{scene.id} is not staged`)
		end
	end
end

return tests
