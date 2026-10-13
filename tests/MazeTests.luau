--!strict
local Maze = require("../src/shared/pure/Maze")

local OPTIONS = { loopChance = 0.06, pruneChance = 0.5, rooms = 2 }
local SEED_COUNT = 10000
local TIME_BUDGET_SECONDS = 60

local tests: { [string]: () -> () } = {}

tests["same seed gives the same maze"] = function()
	local a = Maze.generate(42, 12, 12, OPTIONS)
	local b = Maze.generate(42, 12, 12, OPTIONS)
	assert(a.exit.x == b.exit.x and a.exit.y == b.exit.y, "exit differs")
	assert(a.pathLength == b.pathLength, "path length differs")
	for i = 1, 144 do
		for _, dir in Maze.DIR_NAMES do
			assert(a.open[i][dir] == b.open[i][dir], "passage differs at cell " .. i)
		end
	end
end

tests["different seeds give different mazes"] = function()
	local a = Maze.generate(1, 10, 10, OPTIONS)
	local b = Maze.generate(2, 10, 10, OPTIONS)
	local differences = 0
	for i = 1, 100 do
		for _, dir in Maze.DIR_NAMES do
			if a.open[i][dir] ~= b.open[i][dir] then
				differences += 1
			end
		end
	end
	assert(differences > 0, "two seeds produced an identical maze")
end

tests["10,000 seeds are solvable, in size and in time budget"] = function()
	local start = os.clock()
	for seed = 1, SEED_COUNT do
		local size = 5 + seed % 14
		local maze = Maze.generateVerified(seed, size, size, OPTIONS)
		assert(Maze.isSolvable(maze), "unsolvable seed " .. seed)
		assert(maze.width == size and maze.height == size, "wrong size for seed " .. seed)
		assert(maze.pathLength >= 2, "exit too close for seed " .. seed)
		assert(#maze.rooms == OPTIONS.rooms, "wrong room count for seed " .. seed)
	end
	local elapsed = os.clock() - start
	assert(elapsed < TIME_BUDGET_SECONDS, "maze generation too slow: " .. elapsed)
end

tests["passages are symmetric"] = function()
	local maze = Maze.generate(7, 9, 9, OPTIONS)
	for y = 1, 9 do
		for x = 1, 9 do
			for _, name in Maze.DIR_NAMES do
				if Maze.isOpen(maze, x, y, name) then
					local d = Maze.DIRS[name]
					assert(Maze.inBounds(maze, x + d.dx, y + d.dy), "passage leaves the maze")
					assert(Maze.isOpen(maze, x + d.dx, y + d.dy, d.opposite), "one-way passage")
				end
			end
		end
	end
end

tests["path follows open passages and has the BFS length"] = function()
	for seed = 1, 200 do
		local maze = Maze.generate(seed, 8, 8, OPTIONS)
		local path = Maze.path(maze, maze.start, maze.exit)
		assert(#path == maze.pathLength, "path length mismatch for seed " .. seed)
		local cx, cy = maze.start.x, maze.start.y
		for _, cell in path do
			local stepped = false
			for _, name in Maze.DIR_NAMES do
				local d = Maze.DIRS[name]
				if cx + d.dx == cell.x and cy + d.dy == cell.y then
					assert(Maze.isOpen(maze, cx, cy, name), "path walks through a wall")
					stepped = true
				end
			end
			assert(stepped, "path jumps between non-adjacent cells")
			cx, cy = cell.x, cell.y
		end
	end
end

tests["line of sight is blocked by walls and clear through passages"] = function()
	local maze = Maze.generate(3, 6, 6, { loopChance = 0, pruneChance = 0, rooms = 0 })
	for y = 1, 6 do
		for x = 1, 5 do
			local visible = Maze.lineOfSight(maze, x - 0.5, y - 0.5, x + 0.5, y - 0.5)
			assert(
				visible == Maze.isOpen(maze, x, y, "E"),
				"sight disagrees with the wall east of " .. x .. "," .. y
			)
		end
	end
	assert(Maze.lineOfSight(maze, 0.2, 0.2, 0.8, 0.8), "no sight inside one cell")
	assert(not Maze.lineOfSight(maze, 0.5, 0.5, 40, 40), "sight to a point outside the maze")
end

tests["cellOf clamps into the maze"] = function()
	local maze = Maze.generate(1, 4, 4, OPTIONS)
	local cell = Maze.cellOf(maze, -3, 99)
	assert(cell.x == 1 and cell.y == 4, "cellOf did not clamp")
	local inside = Maze.cellOf(maze, 2.5, 0.5)
	assert(inside.x == 3 and inside.y == 1, "cellOf picked the wrong cell")
end

return tests
