--!strict
-- Versioned save schema. Loading always goes through `load`, which migrates old versions and
-- then rebuilds the profile field by field, so corrupt or hostile data can never reach the game.

local Config = require("../Config")
local Upgrades = require("../data/Upgrades")

export type Profile = {
	version: number,
	static: number,
	upgrades: { [string]: number },
	toggles: { [string]: boolean },
	cosmetics: { owned: { [string]: boolean }, dots: string, gun: string },
	settings: {
		palette: string,
		sharedScans: boolean,
		scanMode: string,
		volume: number,
		dotQuality: string, -- "auto" picks by device; otherwise a key of Config.Lidar.dotBudget
	},
	tutorialDone: boolean,
	checkpointTier: number,
	bestTier: number,
	lore: { [string]: boolean },
	plates: { [string]: boolean },
	echoes: number, -- recorder lines heard so far; the next recorder plays the next line
	met: { [string]: boolean },
	stats: { levels: number, deaths: number, rescues: number, runs: number, distance: number },
	streak: { day: number, count: number },
	daily: { day: number, bestMs: number },
	invitePrompted: boolean,
	endingSeen: boolean,
}

local MAX_STATIC = 10000000
local MAX_TIER = 10000
local MAX_COUNT = 1000000000
local PALETTES = { default = true, alt = true }
local SCAN_MODES = { auto = true, hold = true, toggle = true }
local DOT_QUALITIES = { auto = true, low = true, medium = true, high = true }

local SaveData = {}

function SaveData.default(): Profile
	return {
		version = Config.SaveVersion,
		static = 0,
		upgrades = {},
		toggles = {},
		cosmetics = { owned = {}, dots = "", gun = "" },
		settings = {
			palette = "default",
			sharedScans = true,
			scanMode = "auto",
			volume = 1,
			dotQuality = "auto",
		},
		tutorialDone = false,
		checkpointTier = 1,
		bestTier = 0,
		lore = {},
		plates = {},
		echoes = 0,
		met = {},
		stats = { levels = 0, deaths = 0, rescues = 0, runs = 0, distance = 0 },
		streak = { day = 0, count = 0 },
		daily = { day = 0, bestMs = 0 },
		invitePrompted = false,
		endingSeen = false,
	}
end

-- Version 1 stored the currency as `currency` and had no settings, lore or streak.
local MIGRATIONS: { [number]: (data: { [string]: any }) -> () } = {
	[1] = function(data)
		data.static = data.currency
		data.currency = nil
		data.version = 2
	end,
}

local function number(value: any, fallback: number, min: number, max: number): number
	if type(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(math.floor(value), min, max)
end

local function boolean(value: any, fallback: boolean): boolean
	if type(value) ~= "boolean" then
		return fallback
	end
	return value
end

local function flags(value: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(value) == "table" then
		for key, flag in value do
			if type(key) == "string" and flag == true then
				out[key] = true
			end
		end
	end
	return out
end

local function tableOf(value: any): { [string]: any }
	return if type(value) == "table" then value else {}
end

-- Accepts anything a DataStore might return and produces a valid, current-version profile.
function SaveData.load(raw: any): Profile
	local profile = SaveData.default()
	if type(raw) ~= "table" then
		return profile
	end
	local data = table.clone(raw)
	local version = number(data.version, 1, 1, Config.SaveVersion)
	data.version = version
	while data.version < Config.SaveVersion do
		MIGRATIONS[data.version](data)
	end

	profile.static = number(data.static, 0, 0, MAX_STATIC)
	for id, level in tableOf(data.upgrades) do
		local def = if type(id) == "string" then Upgrades.byId[id] else nil
		if def ~= nil then
			profile.upgrades[id] = number(level, 0, 0, def.maxLevel)
		end
	end
	for id, on in tableOf(data.toggles) do
		if type(id) == "string" and type(on) == "boolean" then
			profile.toggles[id] = on
		end
	end
	local cosmetics = tableOf(data.cosmetics)
	for id in flags(cosmetics.owned) do
		if Upgrades.cosmeticById[id] ~= nil then
			profile.cosmetics.owned[id] = true
		end
	end
	for _, slot in { "dots", "gun" } do
		local id = cosmetics[slot]
		local def = if type(id) == "string" then Upgrades.cosmeticById[id] else nil
		if def ~= nil and def.slot == slot and profile.cosmetics.owned[id] then
			(profile.cosmetics :: { [string]: any })[slot] = id
		end
	end
	local settings = tableOf(data.settings)
	profile.settings.palette = if PALETTES[settings.palette] then settings.palette else "default"
	profile.settings.sharedScans = boolean(settings.sharedScans, true)
	profile.settings.scanMode = if SCAN_MODES[settings.scanMode] then settings.scanMode else "auto"
	if type(settings.volume) == "number" and settings.volume == settings.volume then
		profile.settings.volume = math.clamp(settings.volume, 0, 1)
	end
	profile.settings.dotQuality = if DOT_QUALITIES[settings.dotQuality]
		then settings.dotQuality
		else "auto"
	profile.tutorialDone = boolean(data.tutorialDone, false)
	profile.checkpointTier = number(data.checkpointTier, 1, 1, MAX_TIER)
	profile.bestTier = number(data.bestTier, 0, 0, MAX_TIER)
	profile.lore = flags(data.lore)
	profile.plates = flags(data.plates)
	profile.echoes = number(data.echoes, 0, 0, MAX_COUNT)
	profile.met = flags(data.met)
	local stats = tableOf(data.stats)
	for key in profile.stats do
		(profile.stats :: { [string]: number })[key] = number(stats[key], 0, 0, MAX_COUNT)
	end
	local streak = tableOf(data.streak)
	profile.streak.day = number(streak.day, 0, 0, MAX_COUNT)
	profile.streak.count = number(streak.count, 0, 0, MAX_COUNT)
	local daily = tableOf(data.daily)
	profile.daily.day = number(daily.day, 0, 0, MAX_COUNT)
	profile.daily.bestMs = number(daily.bestMs, 0, 0, MAX_COUNT)
	profile.invitePrompted = boolean(data.invitePrompted, false)
	profile.endingSeen = boolean(data.endingSeen, false)
	return profile
end

return SaveData
