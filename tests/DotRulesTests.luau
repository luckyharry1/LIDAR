--!strict
local Config = require("../src/shared/Config")
local DotRules = require("../src/shared/pure/DotRules")

local tags = Config.Tags
local tests: { [string]: () -> () } = {}

tests["untagged hits are sorted into wall, floor and ceiling by their normal"] = function()
	assert(DotRules.classify({}, 0) == "wall", "a vertical surface should be wall")
	assert(DotRules.classify({}, 1) == "floor", "an upward surface should be floor")
	assert(DotRules.classify({}, -1) == "ceiling", "a downward surface should be ceiling")
end

tests["tags decide people, monsters, items and water"] = function()
	assert(DotRules.classify({ [tags.friend] = true }, 0) == "friend", "expected friend")
	assert(DotRules.classify({ [tags.enemy] = true }, 0) == "enemy", "expected enemy")
	assert(DotRules.classify({ [tags.objective] = true }, 1) == "objective", "expected objective")
	assert(DotRules.classify({ [tags.water] = true }, 1) == "water", "expected water")
	assert(DotRules.classify({ [tags.hazard] = true }, 1) == "hazard", "expected hazard")
end

tests["enemy outranks friend unless disguised"] = function()
	assert(
		DotRules.classify({ [tags.enemy] = true, [tags.friend] = true }, 0) == "enemy",
		"enemy should win"
	)
	local kind, late = DotRules.classify({ [tags.enemy] = true, [tags.disguised] = true }, 0)
	assert(kind == "friend" and late, "a disguised Mimic should read as a late friend dot")
end

tests["the world is permanent; people and monsters fade, monsters fastest"] = function()
	for _, kind in { "wall", "floor", "ceiling", "water", "objective", "hazard" } do
		assert(DotRules.isPermanent(kind :: any), kind .. " dots should be permanent")
	end
	assert(
		not DotRules.isPermanent("friend") and not DotRules.isPermanent("enemy"),
		"marks should fade"
	)
	assert(
		DotRules.lifetime("enemy") < DotRules.lifetime("friend"),
		"monster marks should fade first"
	)
end

tests["fade runs from visible to gone"] = function()
	assert(DotRules.fade(0) == 0, "new dots should be opaque")
	assert(DotRules.fade(1) == 1, "expired dots should be invisible")
	assert(DotRules.fade(5) == 1 and DotRules.fade(-1) == 0, "fade should clamp")
	assert(DotRules.fade(0.5) < 0.5, "fade should stay bright for most of the lifetime")
end

tests["dots are tiny, grow with distance, and items are finest"] = function()
	assert(DotRules.size("wall", 5) <= 0.1, "near dots should be tiny")
	assert(DotRules.size("wall", 120) > DotRules.size("wall", 5), "far dots should be larger")
	assert(DotRules.size("wall", 100000) == Config.Lidar.dotSizeMax, "size should cap")
	for distance = 10, 90, 10 do
		-- the far dots straight ahead must stay visible: not much under 1.5 px on screen
		local angular = DotRules.size("wall", distance) / distance
		assert(angular >= 0.0018, "far dots should not shrink to nothing")
	end
	assert(DotRules.size("objective", 10) < DotRules.size("wall", 10), "item dots should be finer")
	assert(DotRules.size("enemy", 10) > DotRules.size("wall", 10), "marks should be larger")
end

tests["closer surfaces are packed more finely"] = function()
	assert(
		DotRules.gridLevel("wall", 3) == 1
			and DotRules.gridLevel("floor", 30) == 2
			and DotRules.gridLevel("wall", 120) == 3,
		"grid levels wrong"
	)
	assert(
		DotRules.gridLevel("objective", 120) == 4 and DotRules.gridLevel("hazard", 3) == 4,
		"items and hazards should always use the finest grid"
	)
	local sizes = DotRules.gridSizes
	assert(sizes[1] < sizes[2] and sizes[2] < sizes[3], "grids should get coarser with distance")
	assert(sizes[4] < sizes[1], "the item grid should be the finest")
end

tests["dot budget follows the quality setting and the Phosphor upgrade"] = function()
	assert(
		DotRules.budget("low", 0) < DotRules.budget("medium", 0),
		"medium should hold more than low"
	)
	assert(
		DotRules.budget("medium", 0) < DotRules.budget("high", 0),
		"high should hold more than medium"
	)
	assert(
		DotRules.budget("medium", 3) > DotRules.budget("medium", 0),
		"Phosphor should raise the budget"
	)
	assert(
		DotRules.budget("nonsense", 0) == DotRules.budget("medium", 0),
		"unknown quality should fall back"
	)
end

tests["the sweep recharges to full and no further"] = function()
	assert(DotRules.stepCharge(0, 3.5, 7) == 0.5, "half the recharge time should give half charge")
	assert(DotRules.stepCharge(0.9, 10, 7) == 1, "charge should cap at 1")
end

return tests
