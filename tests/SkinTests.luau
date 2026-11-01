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
		elseif def.kind == "robux" then
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
	assert(SkinRules.status(tungsten, 0, {}, {}) == "playtime", "unlocked at zero minutes")
	assert(SkinRules.status(tungsten, 15 * 60 - 1, {}, {}) == "playtime", "unlocked a second early")
	assert(SkinRules.status(tungsten, 15 * 60, {}, {}) == "owned", "not unlocked on time")
	assert(
		SkinRules.status(tungsten, 0, { pack = true }, {}) == "playtime",
		"the pack bought playtime"
	)
	assert(SkinRules.status(rose, 1e9, {}, {}) == "robux", "playtime unlocked a robux skin")
	assert(
		SkinRules.status(rose, 0, { rose = true }, {}) == "owned",
		"its own pass did not unlock it"
	)
	assert(
		SkinRules.status(rose, 0, { aurora = true }, {}) == "robux",
		"another skin's pass unlocked it"
	)
	assert(SkinRules.status(rose, 0, { pack = true }, {}) == "owned", "the pack did not unlock it")
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

tests["wallTint is the skin's colour, else nothing"] = function()
	local profile = SaveData.default()
	assert(SkinRules.wallTint(profile) == nil, "plain scanner has a tint")
	profile.skin = "rose"
	local rose = SkinRules.wallTint(profile)
	assert(rose ~= nil and rose[1] == 255 and rose[2] == 80, "wrong skin colour")
end

tests["no skin colour is close to a meaning colour or to the plain dots"] = function()
	local meaning = {
		Config.Palettes.default.friend,
		Config.Palettes.default.enemy,
		Config.Palettes.default.objective,
		Config.Palettes.default.hazard,
		Config.Palettes.default.water, -- water is a safety signal: no skin may look like it
	}
	local function distance(a: { number }, b: { number }): number
		return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
	end
	for _, def in Skins.list do
		for _, color in meaning do
			assert(distance(def.wall, color) > 90, def.id .. " looks like a meaning colour")
		end
		if def.kind == "robux" then
			assert(
				distance(def.wall, Config.Palettes.default.wall) > 120,
				def.id .. " is too close to the standard dots to stand out"
			)
		else
			-- Even the muted skins must visibly differ from the plain dots, or players think
			-- the skin did nothing.
			assert(
				distance(def.wall, Config.Palettes.default.wall) > 50,
				def.id .. " is too close to the standard dots to be noticed"
			)
		end
		-- The dimmer floor and ceiling versions must stay clear of the meaning colours too.
		for _, kind in { "floor", "ceiling" } do
			local dim = SkinRules.surfaceTint(def.wall, kind) :: { number }
			for _, color in meaning do
				assert(
					distance(dim, color) > 60,
					def.id .. " " .. kind .. " looks like a meaning colour"
				)
			end
		end
	end
end

tests["a skin recolours walls, floors and ceilings, and nothing else"] = function()
	local wall = { 200, 100, 50 }
	assert(SkinRules.surfaceTint(wall, "wall")[1] == 200, "wall tint changed")
	local floor = SkinRules.surfaceTint(wall, "floor") :: { number }
	local ceiling = SkinRules.surfaceTint(wall, "ceiling") :: { number }
	assert(floor[1] == 160 and floor[2] == 80 and floor[3] == 40, "floor tint wrong")
	assert(ceiling[1] == 120 and ceiling[2] == 60 and ceiling[3] == 30, "ceiling tint wrong")
	for _, kind in { "friend", "enemy", "objective", "hazard", "water", "nonsense" } do
		assert(SkinRules.surfaceTint(wall, kind) == nil, kind .. " dots must keep their colour")
	end
end

tests["Static skins are bought once, then wear for free"] = function()
	local profile = SaveData.default()
	local ok = SkinRules.equip(profile, "ember", {})
	assert(not ok and profile.skin == "" and profile.static == 0, "wore a skin it could not afford")
	profile.static = 200
	ok = SkinRules.equip(profile, "ember", {})
	assert(
		ok and profile.static == 200 - Skins.byId.ember.cost and profile.skin == "ember",
		"first wear should cost Static"
	)
	SkinRules.equip(profile, "", {})
	local spent = profile.static
	SkinRules.equip(profile, "ember", {})
	assert(profile.static == spent and profile.skin == "ember", "charged twice")
	profile.ownedSkins.ember = nil
	assert(SkinRules.enforce(profile, {}) and profile.skin == "", "kept an unowned Static skin")
end

tests["a skin that changes the gun model says so in its description"] = function()
	for _, def in Skins.list do
		local says = string.find(string.lower(def.blurb), "gun", 1, true) ~= nil
		assert(says or def.model == "classic", def.id .. " changes the gun but does not say so")
	end
end

tests["every skin has a scanner model the gun can build"] = function()
	local known = {}
	for _, model in Skins.models do
		known[model] = true
	end
	local extra = 0
	for _, def in Skins.list do
		assert(known[def.model], def.id .. " has an unknown model " .. def.model)
		if def.model ~= "classic" then
			extra += 1
		end
		if def.kind == "static" then
			assert((def.cost or 0) > 0, def.id .. " is a Static skin with no cost")
		end
	end
	-- Players should be able to earn exactly one non-classic model by playing, as a taste of
	-- the ones that cost Robux.
	local earnedModels = 0
	for _, def in Skins.list do
		if def.kind == "playtime" and def.model ~= "classic" then
			earnedModels += 1
		end
	end
	assert(earnedModels == 1, "exactly one earned skin should have a different model")
	assert(extra >= 4, "too few distinct scanner models")
end

tests["version 2 saves migrate: the old cosmetics are folded into the skins"] = function()
	local profile = SaveData.load({
		version = 2,
		static = 40,
		cosmetics = { owned = { dots_amber = true }, dots = "dots_amber", gun = "" },
	})
	assert(profile.version == Config.SaveVersion and profile.static == 40, "not migrated")
	assert(profile.skin == "" and next(profile.ownedSkins) == nil, "old cosmetics leaked in")
end

return tests
