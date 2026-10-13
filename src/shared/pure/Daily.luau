--!strict
-- Calendar-derived seeds: everyone gets the same daily maze and the same weekly anomaly.

local LevelPlan = require("./LevelPlan")

local SECONDS_PER_DAY = 86400
local SEED_MULTIPLIER = 2654435761
local SEED_MODULUS = 2147483647
local EPOCH_WEEKDAY_OFFSET = 3 -- day 0 (1 Jan 1970) was a Thursday; this makes weeks start on Monday

local Daily = {}

function Daily.dayNumber(unixSeconds: number): number
	return math.floor(unixSeconds / SECONDS_PER_DAY)
end

function Daily.seed(day: number): number
	return (day * SEED_MULTIPLIER) % SEED_MODULUS + 1
end

function Daily.weekNumber(day: number): number
	return math.floor((day + EPOCH_WEEKDAY_OFFSET) / 7)
end

function Daily.weeklyAnomaly(week: number): string
	local kinds = LevelPlan.anomalyKinds
	return kinds[week % #kinds + 1]
end

-- Leaderboard key for a day, e.g. "20261013".
function Daily.key(day: number): string
	-- Civil-from-days conversion (proleptic Gregorian), pure arithmetic.
	local z = day + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor(
		(doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365
	)
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	local y = yoe + era * 400 + (if m <= 2 then 1 else 0)
	return string.format("%04d%02d%02d", y, m, d)
end

return Daily
