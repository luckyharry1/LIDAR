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
		base.sweepRechargeMul == 1 and base.shutterLevel == 0 and base.phosphorLevel == 0,
		"base effects are not neutral"
	)
	assert(
		not base.wideLens and base.radarLevel == 0 and not base.decoy and base.wayfinder == 0,
		"base extras are on"
	)
	profile.upgrades = {
		battery = 2,
		cooling = 1,
		persistence = 3,
		lens = 1,
		radar = 2,
		marker = 2,
		wayfinder = 2,
		soles = 1,
	}
	profile.toggles.radar = true
	local effects = Progression.effects(profile)
	assert(effects.sweepRechargeMul < 1, "Capacitor should shorten the recharge")
	assert(
		effects.shutterLevel == 1 and effects.phosphorLevel == 3,
		"shutter or phosphor level wrong"
	)
	assert(effects.wideLens and effects.radarLevel == 2, "lens or radar wrong")
	assert(
		effects.pingLifetime > Config.Coop.pingLifetime and effects.decoy,
		"marker effects wrong"
	)
	assert(effects.wayfinder == 2 and effects.solesLevel == 1, "wayfinder or soles wrong")
	assert(Progression.setToggle(profile, "radar", false), "could not switch the radar off")
	assert(Progression.effects(profile).radarLevel == 0, "radar stayed on")
	assert(
		not Progression.setToggle(profile, "battery", true),
		"toggled an upgrade that has no toggle"
	)
end

tests["buying a switchable upgrade turns it on"] = function()
	local profile = SaveData.default()
	profile.static = 1000
	assert(Progression.buyUpgrade(profile, "radar"), "could not buy the radar")
	assert(Progression.effects(profile).radarLevel == 1, "a newly bought radar should be on")
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

tests["noise: scattering dots is silent, crouching is silent, running and the sweep are loud"] = function()
	local walkSpeed, sprintSpeed, crouchSpeed =
		Config.Player.walkSpeed, Config.Player.sprintSpeed, Config.Player.crouchSpeed
	local still = Noise.radius(0, false, false, false, 0, 0)
	local walk = Noise.radius(walkSpeed, false, false, false, 0, 0)
	local sprint = Noise.radius(sprintSpeed, false, false, false, 0, 0)
	local crouch = Noise.radius(crouchSpeed, false, true, false, 0, 0)
	local sweep = Noise.radius(0, true, false, false, 0, 0)
	assert(still == 0, "standing still should make no noise")
	assert(crouch == 0, "crouch-walking should make no noise")
	assert(walk > 0 and sprint > walk, "sprinting should be louder than walking")
	assert(sweep > sprint, "the sweep should be the loudest thing a player does")
	assert(Noise.radius(sprintSpeed, false, false, false, 3, 0) < sprint, "soft soles do nothing")
	assert(Noise.radius(0, true, false, false, 0, 3) < sweep, "the quiet shutter does nothing")
	assert(Noise.radius(walkSpeed, false, false, true, 0, 0) > walk, "wading should be louder")
	assert(
		Noise.radius(crouchSpeed, false, true, true, 0, 0) > 0,
		"even crouched, wading should be heard"
	)
end

return tests
