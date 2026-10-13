--!strict
-- Pure LIDAR dot rules: what colour class a hit gets, how long it lives, how it fades,
-- how big it is drawn, and how the heat meter moves.

local Config = require("../Config")

export type DotClass = "terrain" | "friend" | "enemy" | "objective"

local DotRules = {}

-- `tags` is the set of CollectionService tags on the hit part and its ancestors.
-- Returns the class and whether the dot should land late (the Mimic's tell).
function DotRules.classify(tags: { [string]: boolean }): (DotClass, boolean)
	local names = Config.Tags
	if tags[names.enemy] then
		if tags[names.disguised] then
			return "friend", true
		end
		return "enemy", false
	end
	if tags[names.friend] then
		return "friend", false
	end
	if tags[names.objective] then
		return "objective", false
	end
	return "terrain", false
end

function DotRules.lifetime(class: DotClass, lifetimeMul: number): number
	local lidar = Config.Lidar
	if class == "enemy" then
		return lidar.enemyLifetime -- never extended: enemies must stay elusive
	elseif class == "friend" then
		return lidar.friendLifetime * lifetimeMul
	end
	return lidar.terrainLifetime * lifetimeMul
end

-- Transparency for a dot at a fraction of its lifetime (0 = new, 1 = gone).
function DotRules.fade(ageFraction: number): number
	return math.clamp(ageFraction, 0, 1) ^ Config.Lidar.fadeExponent
end

-- Drawn size in studs: grows gently with distance so far dots stay readable.
function DotRules.size(class: DotClass, distance: number): number
	local lidar = Config.Lidar
	local size = math.min(lidar.dotSize + distance * lidar.dotSizeDistanceScale, lidar.dotSizeMax)
	if class ~= "terrain" then
		size *= lidar.specialDotScale
	end
	return size
end

-- Heat moves toward 1 while focusing and back toward 0 otherwise.
function DotRules.stepHeat(
	heat: number,
	focusing: boolean,
	dt: number,
	heatRate: number,
	coolRate: number
): number
	if focusing then
		return math.min(1, heat + heatRate * dt)
	end
	return math.max(0, heat - coolRate * dt)
end

return DotRules
