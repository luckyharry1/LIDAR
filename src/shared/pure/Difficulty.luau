--!strict
-- Resolves a tier number to its difficulty row. Tiers past the authored table are derived
-- from the last row, so endless mode keeps ramping without new data.

local Tiers = require("../data/Tiers")

export type Tier = Tiers.Tier

local ENDLESS_MAX_SIZE = 10
local ENDLESS_ENEMY_CAP = 3
local ENDLESS_ENEMY_INTERVAL = 2 -- one more enemy every this many tiers, rotating through the kinds
local ENDLESS_ENEMY_ORDER = { "wanderer", "listener", "mimic", "stalker" }
local ENDLESS_SPEED_STEP = 0.02
local ENDLESS_SPEED_CAP = 1.3
local ENDLESS_HEAT_STEP = 0.03
local ENDLESS_HEAT_CAP = 1.5
local ENDLESS_REWARD_STEP = 20
local ENDLESS_LORE_INTERVAL = 3

local Difficulty = {}

Difficulty.authoredCount = #Tiers

function Difficulty.isEndless(tier: number): boolean
	return tier > #Tiers
end

function Difficulty.forTier(tier: number): Tier
	assert(tier >= 1, "tier must be at least 1")
	if tier <= #Tiers then
		return Tiers[tier]
	end
	local last = Tiers[#Tiers]
	local extra = tier - #Tiers
	local enemies = table.clone(last.enemies)
	for added = 1, math.floor(extra / ENDLESS_ENEMY_INTERVAL) do
		local kind = ENDLESS_ENEMY_ORDER[(added - 1) % #ENDLESS_ENEMY_ORDER + 1]
		enemies[kind] = math.min((enemies[kind] or 0) + 1, ENDLESS_ENEMY_CAP)
	end
	return {
		name = "Unmapped " .. extra,
		width = math.min(last.width + math.floor(extra / 2), ENDLESS_MAX_SIZE),
		height = math.min(last.height + math.ceil(extra / 2), ENDLESS_MAX_SIZE),
		loopChance = last.loopChance,
		pruneChance = last.pruneChance,
		rooms = last.rooms + math.floor(extra / 2),
		enemies = enemies,
		enemySpeedScale = math.min(
			last.enemySpeedScale + ENDLESS_SPEED_STEP * extra,
			ENDLESS_SPEED_CAP
		),
		enemySenseScale = last.enemySenseScale,
		objectives = last.objectives,
		exitLocked = true,
		flooded = last.flooded,
		heatScale = math.min(last.heatScale + ENDLESS_HEAT_STEP * extra, ENDLESS_HEAT_CAP),
		reward = last.reward + ENDLESS_REWARD_STEP * extra,
		loreRoomAfter = if extra % ENDLESS_LORE_INTERVAL == 0 then "landing" else nil,
	}
end

return Difficulty
