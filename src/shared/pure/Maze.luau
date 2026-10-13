--!strict
-- Pure seeded maze generator: backtracker, loop pass, dead-end pruning, solvability check.

local Rng = require("./Rng")

export type Cell = { x: number, y: number }
export type Maze = {
	width: number,
	height: number,
	open: { [number]: { [string]: boolean } }, -- open[cellIndex][dir] = passage exists
	start: Cell,
	exit: Cell,
	deadEnds: { Cell },
	pathLength: number,
	seed: number,
}

export type Options = {
	loopChance: number, -- chance per wall of the loop pass to open
	pruneChance: number, -- chance per dead end to be opened up
}

local DIRS = {
	N = { dx = 0, dy = -1, opposite = "S" },
	S = { dx = 0, dy = 1, opposite = "N" },
	E = { dx = 1, dy = 0, opposite = "W" },
	W = { dx = -1, dy = 0, opposite = "E" },
}
local DIR_NAMES = { "N", "E", "S", "W" }

local Maze = {}

local function index(width: number, x: number, y: number): number
	return (y - 1) * width + x
end

local function inBounds(maze: Maze, x: number, y: number): boolean
	return x >= 1 and y >= 1 and x <= maze.width and y <= maze.height
end

local function link(maze: Maze, x: number, y: number, dir: string)
	local d = DIRS[dir]
	maze.open[index(maze.width, x, y)][dir] = true
	maze.open[index(maze.width, x + d.dx, y + d.dy)][d.opposite] = true
end

local function openCount(maze: Maze, x: number, y: number): number
	local n = 0
	for _ in maze.open[index(maze.width, x, y)] do
		n += 1
	end
	return n
end

-- Breadth-first distances from a cell. Returns distance map keyed by cell index.
function Maze.distances(maze: Maze, from: Cell): { [number]: number }
	local dist = { [index(maze.width, from.x, from.y)] = 0 }
	local queue: { Cell } = { from }
	local head = 1
	while head <= #queue do
		local c = queue[head]
		head += 1
		local base = dist[index(maze.width, c.x, c.y)]
		for dir in maze.open[index(maze.width, c.x, c.y)] do
			local d = DIRS[dir]
			local nx, ny = c.x + d.dx, c.y + d.dy
			local ni = index(maze.width, nx, ny)
			if dist[ni] == nil then
				dist[ni] = base + 1
				table.insert(queue, { x = nx, y = ny })
			end
		end
	end
	return dist
end

-- True when the exit is reachable from the start and every cell is reachable.
function Maze.isSolvable(maze: Maze): boolean
	local dist = Maze.distances(maze, maze.start)
	if dist[index(maze.width, maze.exit.x, maze.exit.y)] == nil then
		return false
	end
	local count = 0
	for _ in dist do
		count += 1
	end
	return count == maze.width * maze.height
end

function Maze.generate(seed: number, width: number, height: number, options: Options): Maze
	assert(width >= 2 and height >= 2, "maze must be at least 2x2")
	local rng = Rng.new(seed)
	local maze: Maze = {
		width = width,
		height = height,
		open = {},
		start = { x = 1, y = 1 },
		exit = { x = width, y = height },
		deadEnds = {},
		pathLength = 0,
		seed = seed,
	}
	for i = 1, width * height do
		maze.open[i] = {}
	end

	-- Iterative recursive backtracker.
	local visited: { [number]: boolean } = { [1] = true }
	local stack: { Cell } = { { x = 1, y = 1 } }
	while #stack > 0 do
		local c = stack[#stack]
		local choices = {}
		for _, name in DIR_NAMES do
			local d = DIRS[name]
			local nx, ny = c.x + d.dx, c.y + d.dy
			if inBounds(maze, nx, ny) and not visited[index(width, nx, ny)] then
				table.insert(choices, name)
			end
		end
		if #choices == 0 then
			table.remove(stack)
		else
			local name = choices[rng:int(1, #choices)]
			local d = DIRS[name]
			link(maze, c.x, c.y, name)
			visited[index(width, c.x + d.dx, c.y + d.dy)] = true
			table.insert(stack, { x = c.x + d.dx, y = c.y + d.dy })
		end
	end

	-- Loop pass: open extra walls so the maze is not a pure tree.
	for y = 1, height do
		for x = 1, width do
			for _, name in { "E", "S" } do
				local d = DIRS[name]
				if
					inBounds(maze, x + d.dx, y + d.dy) and not maze.open[index(width, x, y)][name]
				then
					if rng:next() < options.loopChance then
						link(maze, x, y, name)
					end
				end
			end
		end
	end

	-- Dead-end pruning: open one extra wall at a share of dead ends.
	for y = 1, height do
		for x = 1, width do
			if openCount(maze, x, y) == 1 and rng:next() < options.pruneChance then
				local names = table.clone(DIR_NAMES)
				rng:shuffle(names)
				for _, name in names do
					local d = DIRS[name]
					if
						inBounds(maze, x + d.dx, y + d.dy)
						and not maze.open[index(width, x, y)][name]
					then
						link(maze, x, y, name)
						break
					end
				end
			end
		end
	end

	-- Exit is the cell farthest from the start; dead ends host side objectives.
	local dist = Maze.distances(maze, maze.start)
	local best, bestDist = maze.start, -1
	for y = 1, height do
		for x = 1, width do
			local dd = dist[index(width, x, y)]
			if dd > bestDist then
				best, bestDist = { x = x, y = y }, dd
			end
			if openCount(maze, x, y) == 1 and not (x == 1 and y == 1) then
				table.insert(maze.deadEnds, { x = x, y = y })
			end
		end
	end
	maze.exit = best
	maze.pathLength = bestDist
	return maze
end

-- Generate then verify; reseed deterministically until solvable (kept as a guard).
function Maze.generateVerified(seed: number, width: number, height: number, options: Options): Maze
	for attempt = 0, 9 do
		local maze = Maze.generate(seed + attempt * 7919, width, height, options)
		if Maze.isSolvable(maze) then
			return maze
		end
	end
	error("no solvable maze found for seed " .. seed)
end

return Maze
