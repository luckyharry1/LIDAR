--!strict
-- How loud a player is, as a radius in maze cells, from what they are doing.

local Config = require("../Config")

local Noise = {}

function Noise.radius(
	speed: number,
	scanning: boolean,
	focusing: boolean,
	flooded: boolean,
	solesLevel: number
): number
	local settings = Config.Noise
	local move = 0
	if speed >= settings.sprintSpeedThreshold then
		move = settings.sprint
	elseif speed >= settings.walkSpeedThreshold then
		move = settings.walk
	end
	move *= settings.softSolesFactor ^ solesLevel
	if flooded then
		move *= settings.floodedFactor
	end
	local scan = 0
	if scanning then
		scan = if focusing then settings.focus else settings.scan
	end
	return math.max(move, scan)
end

return Noise
