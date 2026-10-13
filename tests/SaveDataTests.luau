--!strict
local Config = require("../src/shared/Config")
local SaveData = require("../src/shared/pure/SaveData")

local tests: { [string]: () -> () } = {}

tests["missing data gives a default profile"] = function()
	for _, raw in { nil :: any, 5, "text", true } do
		local profile = SaveData.load(raw)
		assert(
			profile.version == Config.SaveVersion
				and profile.static == 0
				and profile.checkpointTier == 1,
			"bad default"
		)
		assert(not profile.tutorialDone, "tutorial should start incomplete")
	end
end

tests["version 1 saves migrate: currency becomes Static"] = function()
	local profile = SaveData.load({
		version = 1,
		currency = 250,
		upgrades = { battery = 2 },
		tutorialDone = true,
	})
	assert(profile.version == Config.SaveVersion, "version not bumped")
	assert(profile.static == 250, "currency was not carried over")
	assert(profile.upgrades.battery == 2 and profile.tutorialDone, "old fields lost")
	assert(
		profile.settings.palette == "default" and profile.streak.count == 0,
		"new fields not defaulted"
	)
end

tests["a save with no version is treated as version 1"] = function()
	local profile = SaveData.load({ currency = 12 })
	assert(profile.static == 12, "unversioned save not migrated")
end

tests["current saves round-trip unchanged"] = function()
	local profile = SaveData.default()
	profile.static = 321
	profile.upgrades.cooling = 2
	profile.toggles.lens = false
	profile.cosmetics.owned.dots_mint = true
	profile.cosmetics.dots = "dots_mint"
	profile.settings.palette = "alt"
	profile.settings.volume = 0.4
	profile.checkpointTier = 6
	profile.lore.office_welcome = true
	profile.stats.deaths = 9
	profile.streak = { day = 20000, count = 4 }
	profile.endingSeen = true
	local again = SaveData.load(profile)
	assert(
		again.static == 321 and again.upgrades.cooling == 2 and again.toggles.lens == false,
		"core fields changed"
	)
	assert(
		again.cosmetics.dots == "dots_mint" and again.settings.palette == "alt",
		"cosmetics or settings changed"
	)
	assert(
		again.settings.volume == 0.4 and again.checkpointTier == 6 and again.lore.office_welcome,
		"fields changed"
	)
	assert(
		again.stats.deaths == 9 and again.streak.count == 4 and again.endingSeen,
		"stats changed"
	)
end

tests["hostile or corrupt values are clamped or dropped"] = function()
	local profile = SaveData.load({
		version = Config.SaveVersion,
		static = -500,
		upgrades = { battery = 9999, hacked = 5, cooling = "many" },
		cosmetics = { owned = { fake = true }, dots = "fake", gun = 7 },
		settings = { palette = "rainbow", scanMode = {}, volume = 40 },
		checkpointTier = 0 / 0,
		bestTier = -3,
		lore = { office_welcome = "yes", [5] = true },
		stats = { levels = 1e30, deaths = "x" },
		streak = "nope",
	})
	assert(profile.static == 0, "negative Static accepted")
	assert(profile.upgrades.battery == 4, "upgrade level not clamped to its maximum")
	assert(
		profile.upgrades.hacked == nil and profile.upgrades.cooling == 0,
		"bad upgrade entries kept"
	)
	assert(
		next(profile.cosmetics.owned) == nil
			and profile.cosmetics.dots == ""
			and profile.cosmetics.gun == "",
		"bad cosmetics kept"
	)
	assert(
		profile.settings.palette == "default" and profile.settings.scanMode == "auto",
		"bad settings kept"
	)
	assert(profile.settings.volume == 1, "volume not clamped")
	assert(profile.checkpointTier == 1 and profile.bestTier == 0, "bad tiers kept")
	assert(next(profile.lore) == nil, "bad lore flags kept")
	assert(profile.stats.levels == 1000000000 and profile.stats.deaths == 0, "stats not sanitised")
	assert(profile.streak.count == 0, "bad streak kept")
end

tests["a save from a newer version loads without error"] = function()
	local profile = SaveData.load({ version = Config.SaveVersion + 5, static = 10 })
	assert(profile.static == 10 and profile.version == Config.SaveVersion, "future save rejected")
end

tests["loading does not mutate the stored table"] = function()
	local raw = { version = 1, currency = 5 }
	SaveData.load(raw)
	assert(raw.currency == 5 and raw.version == 1, "load changed its input")
end

return tests
