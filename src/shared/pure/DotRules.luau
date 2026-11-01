--!strict
-- Pure LIDAR dot rules: what kind of dot a hit makes, whether it is permanent, how big it is
-- drawn, how densely dots may be packed, and how the sweep recharges.

local Config = require("../Config")

-- The world (wall, floor, ceiling, water) and items are permanent. People and monsters fade.
export type DotKind =
	"wall"
	| "floor"
	| "ceiling"
	| "water"
	| "friend"
	| "enemy"
	| "objective"
	| "hazard"

local FLOOR_NORMAL = 0.7 -- surfaces facing up more than this are floor; facing down, ceiling

local DotRules = {}

-- `tags` is the set of CollectionService tags on the hit part and its ancestors; `normalY` is
-- the vertical part of the surface normal. Returns the kind and whether the dot should land
-- late (the Mimic's tell).
function DotRules.classify(tags: { [string]: boolean }, normalY: number): (DotKind, boolean)
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
	if tags[names.hazard] then
		return "hazard", false
	end
	if tags[names.water] then
		return "water", false
	end
	if normalY > FLOOR_NORMAL then
		return "floor", false
	elseif normalY < -FLOOR_NORMAL then
		return "ceiling", false
	end
	return "wall", false
end

-- A floor's own surfaces: the story's look for its walls and floor, lifted to a brightness a dot
-- can carry (the Hollow's rock is nearly black on paper), and a ceiling in the wall's hue.
-- Returns the wall, floor and ceiling dot colours as RGB triples.
DotRules.themePeakWall = 225
DotRules.themePeakFloor = 175
DotRules.themePeakCeiling = 120

local function lifted(triple: { number }, peak: number): { number }
	local top = math.max(triple[1], triple[2], triple[3], 1)
	local scale = peak / top
	return {
		math.min(255, math.floor(triple[1] * scale)),
		math.min(255, math.floor(triple[2] * scale)),
		math.min(255, math.floor(triple[3] * scale)),
	}
end

function DotRules.themeColors(
	wallColor: { number },
	floorColor: { number }
): ({ number }, { number }, { number })
	local ceiling = lifted(wallColor, DotRules.themePeakCeiling)
	ceiling = { ceiling[1] * 0.85, ceiling[2] * 0.95, math.min(255, ceiling[3] * 1.15) }
	return lifted(wallColor, DotRules.themePeakWall),
		lifted(floorColor, DotRules.themePeakFloor),
		ceiling
end

function DotRules.isPermanent(kind: DotKind): boolean
	return kind ~= "friend" and kind ~= "enemy"
end

-- Seconds a fading dot lasts.
function DotRules.lifetime(kind: DotKind): number
	return if kind == "enemy" then Config.Lidar.enemyLifetime else Config.Lidar.friendLifetime
end

-- Transparency for a fading dot at a fraction of its lifetime (0 = new, 1 = gone).
function DotRules.fade(ageFraction: number): number
	return math.clamp(ageFraction, 0, 1) ^ Config.Lidar.fadeExponent
end

-- Drawn size in studs: grows gently with distance so far dots stay readable.
function DotRules.size(kind: DotKind, distance: number): number
	local lidar = Config.Lidar
	local size = math.min(lidar.dotSize + distance * lidar.dotSizeDistanceScale, lidar.dotSizeMax)
	if kind == "objective" or kind == "hazard" then
		size *= lidar.itemDotScale
	elseif kind == "friend" or kind == "enemy" then
		size *= lidar.markDotScale
	elseif kind == "water" then
		size *= 1.6 -- flooded floor reads as water at a glance, not as dim floor
	end
	return size
end

-- Which packing grid a hit uses: 1 (near, fine), 2 (mid), 3 (far, coarse) or 4 (items and
-- hazards, finest of all, whatever the distance).
function DotRules.gridLevel(kind: DotKind, distance: number): number
	local lidar = Config.Lidar
	if kind == "objective" or kind == "hazard" then
		return 4
	elseif distance <= lidar.gridNearRange then
		return 1
	elseif distance <= lidar.gridMidRange then
		return 2
	end
	return 3
end

DotRules.gridSizes =
	{ Config.Lidar.gridNear, Config.Lidar.gridMid, Config.Lidar.gridFar, Config.Lidar.gridItem }

-- How many permanent dots the world may hold for a quality setting and Afterglow level.
function DotRules.budget(quality: string, afterglowLevel: number): number
	local lidar = Config.Lidar
	local base = lidar.dotBudget[quality] or lidar.dotBudget.medium
	return math.floor(base * (lidar.budgetBase + lidar.budgetPerAfterglowLevel * afterglowLevel))
end

-- The sweep's charge moves from 0 (just fired) to 1 (ready).
function DotRules.stepCharge(charge: number, dt: number, rechargeSeconds: number): number
	return math.min(1, charge + dt / rechargeSeconds)
end

return DotRules
