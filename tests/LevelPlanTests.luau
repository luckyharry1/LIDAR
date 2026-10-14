--!strict
local Difficulty = require("../src/shared/pure/Difficulty")
local Enemies = require("../src/shared/data/Enemies")
local LevelPlan = require("../src/shared/pure/LevelPlan")
local Maze = require("../src/shared/pure/Maze")
local Places = require("../src/shared/data/Places")

local OPTIONS = { forcedAnomaly = nil, allowPlate = true }
local SEEDS_PER_TIER = 150
local LAST_TIER_TESTED = 14

local tests: { [string]: () -> () } = {}

tests["plans are deterministic"] = function()
	for tier = 1, LAST_TIER_TESTED do
		local a = LevelPlan.build(tier, 991, OPTIONS)
		local b = LevelPlan.build(tier, 991, OPTIONS)
		assert(
			#a.objectives == #b.objectives and #a.enemies == #b.enemies,
			"counts differ at tier " .. tier
		)
		for i, objective in a.objectives do
			local other = b.objectives[i]
			assert(
				objective.kind == other.kind
					and objective.cell.x == other.cell.x
					and objective.cell.y == other.cell.y,
				"objective differs"
			)
		end
		for i, enemy in a.enemies do
			local other = b.enemies[i]
			assert(
				enemy.kind == other.kind
					and enemy.cell.x == other.cell.x
					and enemy.cell.y == other.cell.y,
				"enemy differs"
			)
		end
	end
end

tests["every tier places valid, non-overlapping contents"] = function()
	for tier = 1, LAST_TIER_TESTED do
		local def = Difficulty.forTier(tier)
		for seed = 1, SEEDS_PER_TIER do
			local plan = LevelPlan.build(tier, seed, OPTIONS)
			local maze = plan.maze
			local startDist = Maze.distances(maze, maze.start)
			local used: { [number]: boolean } = {
				[Maze.index(maze, maze.start.x, maze.start.y)] = true,
				[Maze.index(maze, maze.exit.x, maze.exit.y)] = true,
			}
			local hasKey = false
			local sideObjectives = 0
			for _, objective in plan.objectives do
				local index = Maze.index(maze, objective.cell.x, objective.cell.y)
				assert(not used[index], `objective overlaps at tier {tier} seed {seed}`)
				assert(startDist[index] ~= nil, "objective is unreachable")
				used[index] = true
				hasKey = hasKey or objective.kind == "key"
				if objective.kind ~= "plate" then
					sideObjectives += 1
				end
			end
			assert(
				sideObjectives >= 1 and sideObjectives <= 3,
				`tier {tier} has {sideObjectives} side objectives`
			)
			assert(hasKey == plan.exitLocked, "key and locked exit disagree")
			local expected = 0
			for _, count in def.enemies do
				expected += count
			end
			assert(#plan.enemies == expected, "wrong enemy count")
			for _, enemy in plan.enemies do
				local index = Maze.index(maze, enemy.cell.x, enemy.cell.y)
				assert(not used[index], `enemy overlaps at tier {tier} seed {seed}`)
				used[index] = true
				local minimum = math.min(Enemies[enemy.kind].minSpawnCells, maze.pathLength - 1)
				assert(
					startDist[index] >= math.min(minimum, 3),
					`enemy spawns on top of the start at tier {tier} seed {seed}`
				)
			end
			for index in plan.flooded do
				assert(not used[index], "flooded cell under an objective, enemy, start or exit")
			end
			local revealCells = {}
			for _, reveal in plan.reveals do
				table.insert(revealCells, reveal.cell)
			end
			local extras = {
				{ name = "lamp", cells = plan.lamps, count = def.lamps },
				{
					name = "reveal",
					cells = revealCells,
					count = #Places.forTier(tier).reveals,
				},
				{ name = "echo", cells = plan.echoes, count = def.echoes },
				{ name = "pit", cells = plan.pits, count = def.pits },
				{ name = "plate", cells = plan.plates, count = def.plates },
			}
			for _, extra in extras do
				assert(#extra.cells == extra.count, `wrong {extra.name} count at tier {tier}`)
				for _, cell in extra.cells do
					local index = Maze.index(maze, cell.x, cell.y)
					assert(
						not used[index],
						`{extra.name} overlaps something at tier {tier} seed {seed}`
					)
					assert(not plan.flooded[index], extra.name .. " placed in a flooded cell")
					used[index] = true
				end
			end
			for _, cell in plan.pits do
				assert(
					startDist[Maze.index(maze, cell.x, cell.y)] >= 2,
					"a pit next to the level start"
				)
			end
			assert(#plan.nooks == #plan.lamps, "every lamp-bag needs a variant")
			for index, variant in plan.nooks do
				assert(
					variant >= 1 and variant <= Places.nookCount,
					"lamp-bag variant out of range"
				)
				if index == 1 or tier <= 2 then
					assert(variant ~= Places.deadNook, "an early lamp-bag is burnt out")
				end
			end
			for _, sign in plan.signs do
				assert(
					sign.cell.x >= 1
						and sign.cell.x <= maze.width
						and sign.cell.y >= 1
						and sign.cell.y <= maze.height,
					"a sign outside the maze"
				)
			end
			assert(Maze.isSolvable(maze), "unsolvable level")
		end
	end
end

tests["lamp-bags are spread along the way through"] = function()
	for tier = 2, LAST_TIER_TESTED do
		local far, total = 0, 0
		for seed = 1, SEEDS_PER_TIER do
			local plan = LevelPlan.build(tier, seed, OPTIONS)
			local startDist = Maze.distances(plan.maze, plan.maze.start)
			local farthest = 0
			for _, cell in plan.lamps do
				farthest = math.max(farthest, startDist[Maze.index(plan.maze, cell.x, cell.y)])
			end
			far += farthest / plan.maze.pathLength
			total += 1
		end
		assert(far / total >= 0.5, `tier {tier} lamp-bags stay near the start`)
	end
end

tests["every sign and hidden object in the places data exists in the story"] = function()
	for tier, places in Places.tiers do
		for _, id in places.reveals do
			assert(#Places.reveal(id).lines > 0, `tier {tier}: {id} has no lines`)
		end
		for _, sign in places.signs do
			assert(#Places.signLines(sign.id) > 0, `tier {tier}: {sign.id} has no text`)
		end
	end
	for variant = 1, Places.nookCount do
		assert(#Places.nookLines(variant) > 0, "a lamp-bag says nothing")
	end
end

tests["tier one is small and forgiving"] = function()
	local def = Difficulty.forTier(1)
	assert(def.width <= 6 and def.height <= 6, "tier one maze is too big")
	assert(def.enemies.wanderer == 1, "tier one should have exactly one Wanderer")
	local total = 0
	for _, count in def.enemies do
		total += count
	end
	assert(total == 1, "tier one should have one enemy")
	assert(not def.exitLocked, "tier one exit must not be locked")
end

tests["difficulty ramps and endless tiers keep growing"] = function()
	assert(Difficulty.authoredCount >= 8, "need at least eight authored tiers")
	local previousCells = 0
	for tier = 1, Difficulty.authoredCount do
		local def = Difficulty.forTier(tier)
		local cells = def.width * def.height
		assert(cells > previousCells, "maze does not grow at tier " .. tier)
		previousCells = cells
	end
	local last = Difficulty.forTier(Difficulty.authoredCount)
	local endless = Difficulty.forTier(Difficulty.authoredCount + 6)
	assert(Difficulty.isEndless(Difficulty.authoredCount + 1), "endless flag wrong")
	assert(
		endless.height > last.height and endless.reward > last.reward,
		"endless tiers do not ramp"
	)
	assert(Difficulty.forTier(500).width <= 10, "endless maze size is unbounded")
end

tests["a lore room follows every two to three tiers"] = function()
	local gap = 0
	for tier = 1, Difficulty.authoredCount + 9 do
		gap += 1
		if Difficulty.forTier(tier).loreRoomAfter ~= nil then
			assert(gap >= 1 and gap <= 3, "lore room gap of " .. gap .. " before tier " .. tier)
			gap = 0
		end
	end
	assert(gap <= 3, "no lore room near the end of the tested range")
end

tests["a forced anomaly appears whenever the level has a room"] = function()
	local seen = 0
	for seed = 1, 60 do
		local plan = LevelPlan.build(4, seed, { forcedAnomaly = "bloom", allowPlate = false })
		if #plan.maze.rooms > 0 then
			assert(plan.anomaly ~= nil and plan.anomaly.kind == "bloom", "forced anomaly missing")
			seen += 1
		end
		for _, objective in plan.objectives do
			assert(objective.kind ~= "plate", "plate placed although disallowed")
		end
	end
	assert(seen > 0, "no rooms generated in sixty seeds")
end

return tests
