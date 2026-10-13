--!strict
local Daily = require("../src/shared/pure/Daily")
local LevelPlan = require("../src/shared/pure/LevelPlan")

local tests: { [string]: () -> () } = {}

tests["day number changes at midnight UTC"] = function()
	assert(Daily.dayNumber(0) == 0, "epoch is not day zero")
	assert(Daily.dayNumber(86399) == 0 and Daily.dayNumber(86400) == 1, "day boundary wrong")
end

tests["daily seeds are stable, distinct and valid"] = function()
	local seen: { [number]: boolean } = {}
	for day = 20000, 20400 do
		local seed = Daily.seed(day)
		assert(seed == Daily.seed(day), "seed is not stable")
		assert(seed >= 1 and seed == math.floor(seed), "seed is not a positive integer")
		assert(not seen[seed], "two days share a seed")
		seen[seed] = true
	end
end

tests["calendar keys match known dates"] = function()
	assert(Daily.key(0) == "19700101", "epoch key wrong: " .. Daily.key(0))
	assert(Daily.key(19782) == "20240229", "leap day key wrong: " .. Daily.key(19782))
	assert(Daily.key(20739) == "20261013", "key wrong: " .. Daily.key(20739))
end

tests["weeks start on Monday and rotate the featured anomaly"] = function()
	-- 5 Jan 1970 (day 4) was a Monday.
	assert(Daily.weekNumber(3) ~= Daily.weekNumber(4), "week did not roll over on Monday")
	assert(Daily.weekNumber(4) == Daily.weekNumber(10), "week changed mid-week")
	local kinds: { [string]: boolean } = {}
	for week = 1, #LevelPlan.anomalyKinds do
		kinds[Daily.weeklyAnomaly(week)] = true
	end
	for _, kind in LevelPlan.anomalyKinds do
		assert(kinds[kind], kind .. " is never the featured anomaly")
	end
end

return tests
