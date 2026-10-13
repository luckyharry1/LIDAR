--!strict
-- How loud a player is, as a radius in maze cells, from what they are doing.
-- Scattering dots is silent. Crouching makes movement silent (except in water). Running and
-- the sweep are loud.

local Config = require("../Config")

local Noise = {}

function Noise.radius(
	speed: number,
	sweeping: boolean,
	crouching: boolean,
	flooded: boolean,
	solesLevel: number,
	shutterLevel: number
): number
	local settings = Config.Noise
	local move = 0
	if speed >= settings.walkSpeedThreshold then
		if crouching then
			move = if flooded then settings.wade else 0
		else
			move = if speed >= settings.sprintSpeedThreshold then settings.sprint else settings.walk
			move *= settings.softSolesFactor ^ solesLevel
			if flooded then
				move *= settings.floodedFactor
			end
		end
	end
	local scan = if sweeping then settings.sweep * settings.quietShutterFactor ^ shutterLevel else 0
	return math.max(move, scan)
end

return Noise
