--!strict
local Config = require("../src/shared/Config")
local Noise = require("../src/shared/pure/Noise")
local Progression = require("../src/shared/pure/Progression")
local SaveData = require("../src/shared/pure/SaveData")
local Upgrades = require("../src/shared/data/Upgrades")

local tests: { [string]: () -> () } = {}

tests["upgrade costs rise with level and stop at the maximum"] = function()
	for _, def in Upgrades.list do
		local profile = SaveData.default()
		local previous = 0
		for level = 0, def.maxLevel - 1 do
			profile.upgrades[def.id] = level
			local cost = Progression.cost(profile, def.id)
			assert(cost ~= nil and cost >= previous and cost > 0, "bad cost for " .. def.id)
			previous = cost :: number
		end
		profile.upgrades[def.id] = def.maxLevel
		assert(Progression.cost(profile, def.id) == nil, def.id .. " has a cost past its maximum")
	end
	assert(Progression.cost(SaveData.default(), "nonsense") == nil, "unknown upgrade has a cost")
end

tests["buying spends Static exactly once and never overdraws"] = function()
	local profile = SaveData.default()
	local ok = Progression.buyUpgrade(profile, "battery")
	assert(
		not ok and profile.static == 0 and profile.upgrades.battery == nil,
		"bought with no Static"
	)
	profile.static = 40
	ok = Progression.buyUpgrade(profile, "battery")
	assert(
		ok and profile.static == 0 and profile.upgrades.battery == 1,
		"purchase failed or mischarged"
	)
	profile.static = 100000
	for _ = 1, 20 do
		Progression.buyUpgrade(profile, "battery")
	end
	assert(profile.upgrades.battery == Upgrades.byId.battery.maxLevel, "level exceeded the maximum")
	assert(profile.static >= 0, "Static went negative")
end

tests["effects follow upgrade levels"] = function()
	local profile = SaveData.default()
	local base = Progression.effects(profile)
	assert(
		base.heatRateMul == 1 and base.coolMul == 1 and base.lifetimeMul == 1,
		"base effects are not neutral"
	)
	assert(
		not base.wideLens and base.coneMul == 1 and not base.decoy and base.wayfinder == 0,
		"base extras are on"
	)
	profile.upgrades = {
		battery = 2,
		cooling = 1,
		persistence = 3,
		lens = 1,
		marker = 2,
		wayfinder = 2,
		soles = 1,
	}
	profile.toggles.lens = true
	local effects = Progression.effects(profile)
	assert(
		effects.heatRateMul < 1 and effects.coolMul > 1 and effects.lifetimeMul > 1,
		"core effects wrong"
	)
	assert(effects.wideLens and effects.coneMul > 1, "lens should widen the cone")
	assert(
		effects.pingLifetime > Config.Coop.pingLifetime and effects.decoy,
		"marker effects wrong"
	)
	assert(effects.wayfinder == 2 and effects.solesLevel == 1, "wayfinder or soles wrong")
	assert(Progression.setToggle(profile, "lens", false), "could not switch the lens off")
	assert(not Progression.effects(profile).wideLens, "lens stayed on")
	assert(
		not Progression.setToggle(profile, "battery", true),
		"toggled an upgrade that has no toggle"
	)
end

tests["cosmetics are bought once, then equip for free"] = function()
	local profile = SaveData.default()
	local ok = Progression.equipCosmetic(profile, "dots", "dots_amber")
	assert(not ok, "equipped an unaffordable cosmetic")
	profile.static = 200
	ok = Progression.equipCosmetic(profile, "dots", "dots_amber")
	assert(
		ok and profile.static == 120 and profile.cosmetics.dots == "dots_amber",
		"first equip wrong"
	)
	Progression.equipCosmetic(profile, "dots", "")
	assert(profile.cosmetics.dots == "", "default not restored")
	Progression.equipCosmetic(profile, "dots", "dots_amber")
	assert(profile.static == 120, "charged twice for an owned cosmetic")
	assert(
		not Progression.equipCosmetic(profile, "gun", "dots_amber"),
		"equipped into the wrong slot"
	)
end

tests["level rewards add bonuses and pay extra for a clean clear"] = function()
	local clean =
		Progression.levelReward(100, { cells = 2, rescues = 1, plate = false, caught = false })
	local caught =
		Progression.levelReward(100, { cells = 2, rescues = 1, plate = false, caught = true })
	assert(
		clean.cells == 2 * Config.Economy.cellBonus and clean.rescues == Config.Economy.rescueBonus,
		"bonus maths wrong"
	)
	assert(clean.total > caught.total, "a clean clear should pay more")
	assert(caught.total >= 100, "being caught must never reduce the base reward")
	assert(
		clean.total == clean.base + clean.cells + clean.rescues + clean.plate + clean.clean,
		"total does not add up"
	)
end

tests["the streak pays once a day and never resets"] = function()
	local profile = SaveData.default()
	local first = Progression.applyStreak(profile, 20000)
	assert(first == Config.Economy.streakBonuses[1], "first visit bonus wrong")
	assert(Progression.applyStreak(profile, 20000) == 0, "paid twice in one day")
	local afterGap = Progression.applyStreak(profile, 20030)
	assert(afterGap == Config.Economy.streakBonuses[2], "a missed month punished the streak")
	assert(profile.streak.count == 2, "streak count wrong")
	for day = 20031, 20040 do
		assert(Progression.applyStreak(profile, day) > 0, "bonus ladder ran out")
	end
end

tests["noise: running and scanning are loud, upgrades and stillness are quiet"] = function()
	local still = Noise.radius(0, false, false, false, 0)
	local walk = Noise.radius(Config.Player.walkSpeed, false, false, false, 0)
	local sprint = Noise.radius(Config.Player.sprintSpeed, false, false, false, 0)
	local scan = Noise.radius(0, true, false, false, 0)
	local focus = Noise.radius(0, true, true, false, 0)
	assert(still == 0, "standing still and silent should make no noise")
	assert(walk > 0 and sprint > walk, "sprinting should be louder than walking")
	assert(
		focus > scan and scan > walk,
		"focus should be louder than a sweep, a sweep louder than walking"
	)
	assert(
		Noise.radius(Config.Player.sprintSpeed, false, false, false, 3) < sprint,
		"soft soles do nothing"
	)
	assert(
		Noise.radius(Config.Player.walkSpeed, false, false, true, 0) > walk,
		"wading should be louder"
	)
end

return tests
