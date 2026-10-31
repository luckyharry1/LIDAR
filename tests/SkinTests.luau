--!strict
local Config = require("../src/shared/Config")
local SaveData = require("../src/shared/pure/SaveData")
local SkinRules = require("../src/shared/pure/SkinRules")
local Skins = require("../src/shared/data/Skins")

local tests: { [string]: () -> () } = {}

tests["every skin is well formed and its pass key exists in Config"] = function()
	local seen: { [string]: boolean } = {}
	for _, def in Skins.list do
		assert(not seen[def.id] and def.id ~= "", "duplicate or empty skin id " .. def.id)
		seen[def.id] = true
		assert(#def.wall == 3 and #def.gun == 3, def.id .. " needs RGB triples")
		for _, channel in { table.unpack(def.wall), table.unpack(def.gun) } do
			assert(channel >= 0 and channel <= 255, def.id .. " has a colour out of range")
		end
		if def.kind == "playtime" then
			assert((def.minutes or 0) > 0, def.id .. " is a playtime skin with no minutes")
		else
			assert(def.pass ~= nil, def.id .. " is a robux skin with no pass key")
			assert(
				Config.Monetization.skinPassIds[def.pass :: string] ~= nil,
				def.id .. " has no pass id slot in Config.Monetization.skinPassIds"
			)
		end
	end
	assert(Config.Monetization.skinPassIds[Skins.packKey] ~= nil, "the pack has no pass id slot")
end

tests["playtime skins unlock on time alone, robux skins need a pass"] = function()
	local tungsten, rose = Skins.byId.tungsten, Skins.byId.rose
	assert(SkinRules.status(tungsten, 0, {}) == "playtime", "unlocked at zero minutes")
	assert(SkinRules.status(tungsten, 15 * 60 - 1, {}) == "playtime", "unlocked a second early")
	assert(SkinRules.status(tungsten, 15 * 60, {}) == "owned", "not unlocked on time")
	assert(SkinRules.status(tungsten, 0, { pack = true }) == "playtime", "the pack bought playtime")
	assert(SkinRules.status(rose, 1e9, {}) == "robux", "playtime unlocked a robux skin")
	assert(SkinRules.status(rose, 0, { rose = true }) == "owned", "its own pass did not unlock it")
	assert(
		SkinRules.status(rose, 0, { aurora = true }) == "robux",
		"another skin's pass unlocked it"
	)
	assert(SkinRules.status(rose, 0, { pack = true }) == "owned", "the pack did not unlock it")
	assert(SkinRules.secondsLeft(tungsten, 15 * 60 - 90) == 90, "wrong time left")
	assert(SkinRules.secondsLeft(tungsten, 1e9) == 0, "negative time left")
end

tests["equipping needs the skin unlocked; an empty id restores the plain scanner"] = function()
	local profile = SaveData.default()
	local ok = SkinRules.equip(profile, "tungsten", {})
	assert(not ok and profile.skin == "", "wore a skin that was not earned")
	ok = SkinRules.equip(profile, "rose", {})
	assert(not ok and profile.skin == "", "wore a skin that was not bought")
	assert(not SkinRules.equip(profile, "nonsense", {}), "wore an unknown skin")
	profile.stats.playSeconds = 15 * 60
	ok = SkinRules.equip(profile, "tungsten", {})
	assert(ok and profile.skin == "tungsten", "could not wear an earned skin")
	ok = SkinRules.equip(profile, "rose", { rose = true })
	assert(ok and profile.skin == "rose", "could not wear a bought skin")
	ok = SkinRules.equip(profile, "", {})
	assert(ok and profile.skin == "", "could not take the skin off")
end

tests["enforce takes off a skin the player no longer qualifies for"] = function()
	local profile = SaveData.default()
	profile.skin = "aurora"
	assert(SkinRules.enforce(profile, {}) and profile.skin == "", "kept an unowned skin")
	profile.skin = "aurora"
	assert(
		not SkinRules.enforce(profile, { pack = true }) and profile.skin == "aurora",
		"dropped an owned skin"
	)
	profile.skin = ""
	assert(not SkinRules.enforce(profile, {}), "changed a plain scanner")
end

tests["newlyEarned reports each playtime skin once, as the clock crosses it"] = function()
	assert(#SkinRules.newlyEarned(0, 10) == 0, "earned something at ten seconds")
	local earned = SkinRules.newlyEarned(15 * 60 - 1, 15 * 60)
	assert(#earned == 1 and earned[1].id == "tungsten", "missed the first unlock")
	assert(#SkinRules.newlyEarned(15 * 60, 15 * 60 + 5) == 0, "reported an unlock twice")
	assert(#SkinRules.newlyEarned(0, 1e9) == 4, "a long jump should cross every playtime skin")
end

tests["skin and playtime survive a save; a bad skin id is dropped"] = function()
	local profile = SaveData.default()
	profile.skin = "glacier"
	profile.stats.playSeconds = 4000
	local again = SaveData.load(profile)
	assert(again.skin == "glacier" and again.stats.playSeconds == 4000, "skin or playtime lost")
	assert(
		SaveData.load({ version = Config.SaveVersion, skin = "fake" }).skin == "",
		"kept a fake skin"
	)
	assert(
		SaveData.load({ version = Config.SaveVersion, skin = 5 }).skin == "",
		"kept a non-string"
	)
	local hostile = SaveData.load({ version = Config.SaveVersion, stats = { playSeconds = -5 } })
	assert(hostile.stats.playSeconds == 0, "negative playtime accepted")
end

return tests
