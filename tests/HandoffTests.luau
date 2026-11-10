--!strict
local Handoff = require("../src/shared/pure/Handoff")

local tests: { [string]: () -> () } = {}

tests["a handoff survives the trip"] = function()
	local data = Handoff.encode("new", 3)
	local back = Handoff.decode(data, 4)
	assert(back ~= nil and back.mode == "new" and back.size == 3, "round trip changed the data")
end

tests["an unknown mode becomes continue"] = function()
	assert(Handoff.encode("cheat", 1).mode == "continue", "unknown mode kept")
end

tests["decode rejects anything that is not a handoff"] = function()
	assert(Handoff.decode(nil, 4) == nil, "nil accepted")
	assert(Handoff.decode("new", 4) == nil, "string accepted")
	assert(Handoff.decode({ mode = "x", size = 1 }, 4) == nil, "bad mode accepted")
	assert(Handoff.decode({ mode = "new", size = 0 }, 4) == nil, "empty party accepted")
	assert(Handoff.decode({ mode = "new", size = 0 / 0 }, 4) == nil, "NaN size accepted")
	assert(Handoff.decode({ mode = "new" }, 4) == nil, "missing size accepted")
end

tests["decode caps the party size"] = function()
	local back = Handoff.decode({ mode = "daily", size = 99 }, 4)
	assert(back ~= nil and back.size == 4, "size not capped")
end

tests["crew puts the leader first and never exceeds the limit"] = function()
	local crew = Handoff.crew("a", { "b", "a", "c", "d", "e" }, 4)
	assert(#crew == 4 and crew[1] == "a", "leader not first or too many")
	assert(crew[2] == "b" and crew[3] == "c" and crew[4] == "d", "order changed")
	assert(#Handoff.crew("a", {}, 4) == 1, "solo crew wrong")
end

return tests
