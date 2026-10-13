local process = require("@lune/process")
local LevelPlan = require("../src/shared/pure/LevelPlan")
local Maze = require("../src/shared/pure/Maze")
local tier = tonumber(process.args[1]) or 1
local seed = tonumber(process.args[2]) or 1
local plan = LevelPlan.build(tier, seed, { forcedAnomaly = nil, allowPlate = false })
local maze = plan.maze
local dist = Maze.distances(maze, maze.start)
print(
	"size",
	maze.width,
	maze.height,
	"exit",
	maze.exit.x,
	maze.exit.y,
	"pathLength",
	maze.pathLength,
	"deadEnds",
	#maze.deadEnds
)
for _, e in plan.enemies do
	print(
		"enemy",
		e.kind,
		e.cell.x,
		e.cell.y,
		"startDist",
		dist[Maze.index(maze, e.cell.x, e.cell.y)]
	)
end
for _, o in plan.objectives do
	print(
		"objective",
		o.kind,
		o.cell.x,
		o.cell.y,
		"startDist",
		dist[Maze.index(maze, o.cell.x, o.cell.y)]
	)
end
-- ASCII map
for y = 1, maze.height do
	local top, mid = "", ""
	for x = 1, maze.width do
		top ..= "+" .. (Maze.isOpen(maze, x, y, "N") and "  " or "--")
		local ch = "  "
		if x == maze.start.x and y == maze.start.y then
			ch = "S "
		end
		if x == maze.exit.x and y == maze.exit.y then
			ch = "X "
		end
		for _, e in plan.enemies do
			if e.cell.x == x and e.cell.y == y then
				ch = string.sub(e.kind, 1, 1) .. " "
			end
		end
		for _, o in plan.objectives do
			if o.cell.x == x and o.cell.y == y then
				ch = string.upper(string.sub(o.kind, 1, 1)) .. "*"
			end
		end
		mid ..= (Maze.isOpen(maze, x, y, "W") and " " or "|") .. ch
	end
	print(top .. "+")
	print(mid .. "|")
end
