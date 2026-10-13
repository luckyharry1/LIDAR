--!strict
local DotRules = require("../src/shared/pure/DotRules")

local names = { terrain = "T", friend = "F", enemy = "E" }
local tests: { [string]: () -> () } = {}

tests["untagged is terrain"] = function()
	assert(DotRules.classify({}, names, false) == "terrain", "expected terrain")
end

tests["enemy beats friend unless disguised"] = function()
	assert(DotRules.classify({ "E", "F" }, names, false) == "enemy", "expected enemy")
	assert(DotRules.classify({ "E", "F" }, names, true) == "friend", "expected disguised friend")
end

tests["heat clamps"] = function()
	assert(DotRules.stepHeat(0.9, true, 10, 0.35, 0.2) == 1, "heat should cap at 1")
	assert(DotRules.stepHeat(0.1, false, 10, 0.35, 0.2) == 0, "heat should floor at 0")
end

return tests
