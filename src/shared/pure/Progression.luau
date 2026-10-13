--!strict
-- Progression maths: upgrade costs and purchases, what upgrades do, level rewards, streaks.
-- Operates on SaveData profiles; the server is the only caller that persists the result.

local Config = require("../Config")
local SaveData = require("./SaveData")
local Upgrades = require("../data/Upgrades")

export type Effects = {
	sweepRechargeMul: number, -- multiplies the sweep's recharge time
	shutterLevel: number, -- Quiet Shutter levels (each makes the sweep quieter)
	phosphorLevel: number, -- each level raises the dot budget
	wideLens: boolean,
	radarLevel: number, -- 0 when not owned or switched off
	pingLifetime: number,
	decoy: boolean,
	wayfinder: number,
	solesLevel: number,
}

export type LevelResult = {
	cells: number,
	rescues: number,
	plate: boolean,
	caught: boolean,
}

export type Reward = {
	total: number,
	base: number,
	cells: number,
	rescues: number,
	plate: number,
	clean: number,
}

local CAPACITOR_FACTOR = 0.85 -- sweep recharge time multiplier per Capacitor level
local MARKER_SECONDS = 8 -- extra ping lifetime per Echo Beacon level

local Progression = {}

-- Cost of the next level of an upgrade, or nil when it is unknown or maxed.
function Progression.cost(profile: SaveData.Profile, id: string): number?
	local def = Upgrades.byId[id]
	if def == nil then
		return nil
	end
	local level = profile.upgrades[id] or 0
	if level >= def.maxLevel then
		return nil
	end
	return math.floor(def.baseCost * def.costGrowth ^ level + 0.5)
end

function Progression.buyUpgrade(profile: SaveData.Profile, id: string): (boolean, string)
	local cost = Progression.cost(profile, id)
	if cost == nil then
		return false, "Already at maximum."
	end
	if profile.static < cost then
		return false, "Not enough Static."
	end
	profile.static -= cost
	profile.upgrades[id] = (profile.upgrades[id] or 0) + 1
	local def = Upgrades.byId[id]
	if def.toggle and profile.toggles[id] == nil then
		profile.toggles[id] = true
	end
	return true, def.name .. " upgraded."
end

-- Buys a cosmetic if needed, then equips it. An empty id restores the default for the slot.
function Progression.equipCosmetic(
	profile: SaveData.Profile,
	slot: string,
	id: string
): (boolean, string)
	if slot ~= "dots" and slot ~= "gun" then
		return false, "Unknown slot."
	end
	local cosmetics = profile.cosmetics :: { [string]: any }
	if id == "" then
		cosmetics[slot] = ""
		return true, "Default restored."
	end
	local def = Upgrades.cosmeticById[id]
	if def == nil or def.slot ~= slot then
		return false, "Unknown item."
	end
	if not profile.cosmetics.owned[id] then
		if profile.static < def.cost then
			return false, "Not enough Static."
		end
		profile.static -= def.cost
		profile.cosmetics.owned[id] = true
	end
	cosmetics[slot] = id
	return true, def.name .. " equipped."
end

function Progression.setToggle(profile: SaveData.Profile, id: string, on: boolean): boolean
	local def = Upgrades.byId[id]
	if def == nil or not def.toggle or (profile.upgrades[id] or 0) < 1 then
		return false
	end
	profile.toggles[id] = on
	return true
end

function Progression.effects(profile: SaveData.Profile): Effects
	local function level(id: string): number
		return profile.upgrades[id] or 0
	end
	return {
		sweepRechargeMul = CAPACITOR_FACTOR ^ level("battery"),
		shutterLevel = level("cooling"),
		phosphorLevel = level("persistence"),
		wideLens = level("lens") > 0,
		radarLevel = if profile.toggles.radar == true then level("radar") else 0,
		pingLifetime = Config.Coop.pingLifetime + MARKER_SECONDS * level("marker"),
		decoy = level("marker") > 0,
		wayfinder = level("wayfinder"),
		solesLevel = level("soles"),
	}
end

function Progression.levelReward(baseReward: number, result: LevelResult): Reward
	local economy = Config.Economy
	local cells = result.cells * economy.cellBonus
	local rescues = result.rescues * economy.rescueBonus
	local plate = if result.plate then economy.rareLoreBonus else 0
	local subtotal = baseReward + cells + rescues + plate
	local clean = if result.caught
		then 0
		else math.floor(baseReward * (economy.cleanClearMultiplier - 1) + 0.5)
	return {
		total = subtotal + clean,
		base = baseReward,
		cells = cells,
		rescues = rescues,
		plate = plate,
		clean = clean,
	}
end

-- Records a visit on `day`. The streak never resets: a missed day simply does not add to it.
-- Returns the Static bonus for this visit (zero if today was already counted).
function Progression.applyStreak(profile: SaveData.Profile, day: number): number
	if day <= profile.streak.day then
		return 0
	end
	profile.streak.day = day
	profile.streak.count += 1
	local bonuses = Config.Economy.streakBonuses
	return bonuses[(profile.streak.count - 1) % #bonuses + 1]
end

return Progression
