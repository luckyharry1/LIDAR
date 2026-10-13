--!strict
-- The story wiring: every room, tape, page and card the game shows must resolve to real text
-- from LoreText, and fit the places the builders put it.
local Difficulty = require("../src/shared/pure/Difficulty")
local Lore = require("../src/shared/data/Lore")
local Tiers = require("../src/shared/data/Tiers")

local NOTE_SPOTS = 3 -- every lore room layout in src/server/LoreRooms has three note spots
local PLACEHOLDERS = { deaths = true, party = true, floor = true, n = true }

local tests: { [string]: () -> () } = {}

local function placeholdersIn(text: string): { string }
	local found = {}
	for key in string.gmatch(text, "{(%w+)}") do
		table.insert(found, key)
	end
	return found
end

tests["every room has three notes that exist"] = function()
	for id, room in Lore.rooms do
		assert(room.id == id, "room id mismatch: " .. id)
		assert(#room.notes == NOTE_SPOTS, `{id} has {#room.notes} notes, layouts have {NOTE_SPOTS}`)
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
	assert(string.find(Lore.plates[2], "In the margin: ", 1, true) ~= nil, "margins are not marked")
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
	table.insert(texts, Lore.radio.floor)
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

return tests
