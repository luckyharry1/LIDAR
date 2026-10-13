--!strict
local Config = require("../src/shared/Config")
local DotRules = require("../src/shared/pure/DotRules")

local tags = Config.Tags
local tests: { [string]: () -> () } = {}

tests["untagged hits are terrain"] = function()
	local class, late = DotRules.classify({})
	assert(class == "terrain" and not late, "expected plain terrain")
end

tests["friends are green and enemies red"] = function()
	assert(DotRules.classify({ [tags.friend] = true }) == "friend", "expected friend")
	assert(DotRules.classify({ [tags.enemy] = true }) == "enemy", "expected enemy")
	assert(DotRules.classify({ [tags.objective] = true }) == "objective", "expected objective")
end

tests["enemy outranks friend unless disguised"] = function()
	assert(
		DotRules.classify({ [tags.enemy] = true, [tags.friend] = true }) == "enemy",
		"enemy should win"
	)
	local class, late = DotRules.classify({ [tags.enemy] = true, [tags.disguised] = true })
	assert(class == "friend" and late, "a disguised Mimic should read as a late friend dot")
end

tests["enemy dots fade fastest and ignore lifetime upgrades"] = function()
	assert(
		DotRules.lifetime("enemy", 1) < DotRules.lifetime("friend", 1),
		"enemy should fade before friend"
	)
	assert(
		DotRules.lifetime("friend", 1) < DotRules.lifetime("terrain", 1),
		"friend should fade before terrain"
	)
	assert(
		DotRules.lifetime("enemy", 2) == DotRules.lifetime("enemy", 1),
		"enemy lifetime must not scale"
	)
	assert(
		DotRules.lifetime("terrain", 2) == 2 * DotRules.lifetime("terrain", 1),
		"terrain lifetime should scale"
	)
end

tests["fade runs from visible to gone"] = function()
	assert(DotRules.fade(0) == 0, "new dots should be opaque")
	assert(DotRules.fade(1) == 1, "expired dots should be invisible")
	assert(DotRules.fade(5) == 1 and DotRules.fade(-1) == 0, "fade should clamp")
	assert(DotRules.fade(0.5) < 0.5, "fade should stay bright for most of the lifetime")
end

tests["dot size grows with distance and is capped"] = function()
	assert(DotRules.size("terrain", 80) > DotRules.size("terrain", 5), "far dots should be larger")
	assert(DotRules.size("terrain", 100000) == Config.Lidar.dotSizeMax, "size should cap")
	assert(DotRules.size("enemy", 10) > DotRules.size("terrain", 10), "enemy dots should be larger")
end

tests["heat clamps between zero and one"] = function()
	assert(DotRules.stepHeat(0.9, true, 10, 0.35, 0.2) == 1, "heat should cap at 1")
	assert(DotRules.stepHeat(0.1, false, 10, 0.35, 0.2) == 0, "heat should floor at 0")
	assert(DotRules.stepHeat(0.5, true, 1, 0.2, 0.2) > 0.5, "focus should add heat")
end

return tests
