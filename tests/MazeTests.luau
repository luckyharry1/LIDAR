--!strict
local Maze = require("../src/shared/pure/Maze")

local OPTIONS = { loopChance = 0.06, pruneChance = 0.5 }

local tests: { [string]: () -> () } = {}

tests["maze is deterministic per seed"] = function()
	local a = Maze.generate(42, 12, 12, OPTIONS)
	local b = Maze.generate(42, 12, 12, OPTIONS)
	assert(a.exit.x == b.exit.x and a.exit.y == b.exit.y and a.pathLength == b.pathLength)
	for i = 1, 144 do
		for dir, v in a.open[i] do
			assert(b.open[i][dir] == v)
		end
	end
end

tests["10000 seeds are solvable and in budget"] = function()
	local start = os.clock()
	for seed = 1, 10000 do
		local size = 5 + seed % 10
		local maze = Maze.generateVerified(seed, size, size, OPTIONS)
		assert(Maze.isSolvable(maze), "unsolvable seed " .. seed)
		assert(maze.width == size and maze.height == size)
		assert(maze.pathLength >= size - 1)
	end
	assert(os.clock() - start < 60, "maze generation too slow")
end

return tests
