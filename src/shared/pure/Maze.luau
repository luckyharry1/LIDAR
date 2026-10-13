--!strict
-- Pure seeded maze generator: backtracker, loop pass, dead-end pruning, open rooms,
-- plus the grid queries the rest of the game needs (distances, paths, line of sight).
--
-- Continuous positions are in cell units: cell (x, y) covers [x-1, x) by [y-1, y), so its
-- centre is (x - 0.5, y - 0.5). North is -y, east is +x.

local Rng = require("./Rng")

export type Cell = { x: number, y: number }
export type Room = { x: number, y: number, w: number, h: number }
export type Maze = {
	width: number,
	height: number,
	open: { [number]: { [string]: boolean } }, -- open[cellIndex][dir] = passage exists
	start: Cell,
	exit: Cell,
	deadEnds: { Cell },
	rooms: { Room },
	pathLength: number,
	seed: number,
}

export type Options = {
	loopChance: number, -- chance per closed wall to be opened by the loop pass
	pruneChance: number, -- chance per dead end to be opened up
	rooms: number, -- number of open multi-cell rooms to carve
}

local DIRS = {
	N = { dx = 0, dy = -1, opposite = "S" },
	S = { dx = 0, dy = 1, opposite = "N" },
	E = { dx = 1, dy = 0, opposite = "W" },
	W = { dx = -1, dy = 0, opposite = "E" },
}
local DIR_NAMES = { "N", "E", "S", "W" }
local RESEED_STEP = 7919
local MAX_ATTEMPTS = 10
local ROOM_MIN, ROOM_MAX = 2, 3

local Maze = {}

Maze.DIRS = DIRS
Maze.DIR_NAMES = DIR_NAMES

function Maze.index(maze: Maze, x: number, y: number): number
	return (y - 1) * maze.width + x
end

function Maze.cellAt(maze: Maze, index: number): Cell
	return { x = (index - 1) % maze.width + 1, y = math.floor((index - 1) / maze.width) + 1 }
end

function Maze.inBounds(maze: Maze, x: number, y: number): boolean
	return x >= 1 and y >= 1 and x <= maze.width and y <= maze.height
end

function Maze.isOpen(maze: Maze, x: number, y: number, dir: string): boolean
	return maze.open[Maze.index(maze, x, y)][dir] == true
end

-- The cell containing a continuous position, clamped into the maze.
function Maze.cellOf(maze: Maze, px: number, pz: number): Cell
	return {
		x = math.clamp(math.floor(px) + 1, 1, maze.width),
		y = math.clamp(math.floor(pz) + 1, 1, maze.height),
	}
end

local function link(maze: Maze, x: number, y: number, dir: string)
	local d = DIRS[dir]
	maze.open[Maze.index(maze, x, y)][dir] = true
	maze.open[Maze.index(maze, x + d.dx, y + d.dy)][d.opposite] = true
end

local function openCount(maze: Maze, x: number, y: number): number
	local n = 0
	for _ in maze.open[Maze.index(maze, x, y)] do
		n += 1
	end
	return n
end

function Maze.neighbors(maze: Maze, x: number, y: number): { Cell }
	local list = {}
	for _, name in DIR_NAMES do
		if maze.open[Maze.index(maze, x, y)][name] then
			local d = DIRS[name]
			table.insert(list, { x = x + d.dx, y = y + d.dy })
		end
	end
	return list
end

-- Breadth-first step counts from a cell, keyed by cell index.
function Maze.distances(maze: Maze, from: Cell): { [number]: number }
	local width = maze.width
	local dist = { [Maze.index(maze, from.x, from.y)] = 0 }
	local queue = { Maze.index(maze, from.x, from.y) }
	local head = 1
	while head <= #queue do
		local ci = queue[head]
		head += 1
		local base = dist[ci]
		local cx, cy = (ci - 1) % width + 1, math.floor((ci - 1) / width) + 1
		for dir in maze.open[ci] do
			local d = DIRS[dir]
			local ni = (cy + d.dy - 1) * width + cx + d.dx
			if dist[ni] == nil then
				dist[ni] = base + 1
				table.insert(queue, ni)
			end
		end
	end
	return dist
end

-- Shortest path as a list of cells after `from`, ending at `to`. Empty when from == to.
function Maze.path(maze: Maze, from: Cell, to: Cell): { Cell }
	local dist = Maze.distances(maze, to)
	local path = {}
	local cx, cy = from.x, from.y
	local here = dist[Maze.index(maze, cx, cy)]
	if here == nil then
		return path
	end
	while here > 0 do
		for _, name in DIR_NAMES do
			if maze.open[Maze.index(maze, cx, cy)][name] then
				local d = DIRS[name]
				local nd = dist[Maze.index(maze, cx + d.dx, cy + d.dy)]
				if nd == here - 1 then
					cx, cy, here = cx + d.dx, cy + d.dy, nd
					table.insert(path, { x = cx, y = cy })
					break
				end
			end
		end
	end
	return path
end

-- True when the straight segment between two continuous positions crosses no wall.
function Maze.lineOfSight(maze: Maze, ax: number, az: number, bx: number, bz: number): boolean
	local cx, cy = math.floor(ax) + 1, math.floor(az) + 1
	local tx, ty = math.floor(bx) + 1, math.floor(bz) + 1
	if not Maze.inBounds(maze, cx, cy) or not Maze.inBounds(maze, tx, ty) then
		return false
	end
	local dx, dz = bx - ax, bz - az
	local stepX = if dx > 0 then 1 else -1
	local stepY = if dz > 0 then 1 else -1
	local tDeltaX = if dx ~= 0 then math.abs(1 / dx) else math.huge
	local tDeltaY = if dz ~= 0 then math.abs(1 / dz) else math.huge
	local tMaxX = if dx > 0
		then (cx - ax) * tDeltaX
		elseif dx < 0 then (ax - (cx - 1)) * tDeltaX
		else math.huge
	local tMaxY = if dz > 0
		then (cy - az) * tDeltaY
		elseif dz < 0 then (az - (cy - 1)) * tDeltaY
		else math.huge
	local guard = maze.width + maze.height + 4
	while (cx ~= tx or cy ~= ty) and guard > 0 do
		guard -= 1
		if tMaxX < tMaxY then
			if not maze.open[Maze.index(maze, cx, cy)][if stepX > 0 then "E" else "W"] then
				return false
			end
			cx += stepX
			tMaxX += tDeltaX
		else
			if not maze.open[Maze.index(maze, cx, cy)][if stepY > 0 then "S" else "N"] then
				return false
			end
			cy += stepY
			tMaxY += tDeltaY
		end
		if not Maze.inBounds(maze, cx, cy) then
			return false
		end
	end
	return cx == tx and cy == ty
end

-- True when the exit is reachable from the start and every cell is reachable.
function Maze.isSolvable(maze: Maze): boolean
	local dist = Maze.distances(maze, maze.start)
	if dist[Maze.index(maze, maze.exit.x, maze.exit.y)] == nil then
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
		rooms = {},
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
			if Maze.inBounds(maze, nx, ny) and not visited[Maze.index(maze, nx, ny)] then
				table.insert(choices, name)
			end
		end
		if #choices == 0 then
			table.remove(stack)
		else
			local name = choices[rng:int(1, #choices)]
			local d = DIRS[name]
			link(maze, c.x, c.y, name)
			visited[Maze.index(maze, c.x + d.dx, c.y + d.dy)] = true
			table.insert(stack, { x = c.x + d.dx, y = c.y + d.dy })
		end
	end

	-- Loop pass: open extra walls so the maze is not a pure tree.
	for y = 1, height do
		for x = 1, width do
			for _, name in { "E", "S" } do
				local d = DIRS[name]
				if
					Maze.inBounds(maze, x + d.dx, y + d.dy) and not Maze.isOpen(maze, x, y, name)
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
						Maze.inBounds(maze, x + d.dx, y + d.dy)
						and not Maze.isOpen(maze, x, y, name)
					then
						link(maze, x, y, name)
						break
					end
				end
			end
		end
	end

	-- Rooms: clear every interior wall of a few small blocks to make open halls.
	for _ = 1, options.rooms do
		-- A room never spans more than half the maze, so small levels keep their corridors.
		local w = math.min(rng:int(ROOM_MIN, ROOM_MAX), math.max(ROOM_MIN, width // 2))
		local h = math.min(rng:int(ROOM_MIN, ROOM_MAX), math.max(ROOM_MIN, height // 2))
		local rx = rng:int(1, width - w + 1)
		local ry = rng:int(1, height - h + 1)
		for y = ry, ry + h - 1 do
			for x = rx, rx + w - 1 do
				if x < rx + w - 1 then
					link(maze, x, y, "E")
				end
				if y < ry + h - 1 then
					link(maze, x, y, "S")
				end
			end
		end
		table.insert(maze.rooms, { x = rx, y = ry, w = w, h = h })
	end

	-- Exit is the cell farthest from the start; dead ends host side objectives.
	local dist = Maze.distances(maze, maze.start)
	local best, bestDist = maze.start, -1
	for y = 1, height do
		for x = 1, width do
			local dd = dist[Maze.index(maze, x, y)]
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
	for attempt = 0, MAX_ATTEMPTS - 1 do
		local maze = Maze.generate(seed + attempt * RESEED_STEP, width, height, options)
		if Maze.isSolvable(maze) then
			return maze
		end
	end
	error("no solvable maze found for seed " .. seed)
end

return Maze
