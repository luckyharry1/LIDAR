--!strict
-- How far something really is from the player: the walk through the maze, not the straight
-- line. A monster on the other side of a wall is a whole corridor away, so it should not make
-- the screen red or the heart race. Off the maze grid (havens, the stairwell) it falls back to
-- the straight line.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Maze = require(ReplicatedStorage.Shared.pure.Maze)
local State = require(script.Parent.State)

local CELL = Config.World.cellSize

local Reach = {}

local cachedPlan: any = nil
local cachedFrom = 0
local cachedSteps: { [number]: number } = {}

local function cellIndex(maze: Maze.Maze, position: Vector3): number?
	local relative = (position - State.server.origin) / CELL
	if
		relative.X < 0
		or relative.Z < 0
		or relative.X >= maze.width
		or relative.Z >= maze.height
	then
		return nil
	end
	local cell = Maze.cellOf(maze, relative.X, relative.Z)
	return Maze.index(maze, cell.x, cell.y)
end

-- Distance in studs from `from` (the player) to `to` (a monster), walking the maze's open sides.
function Reach.distance(from: Vector3, to: Vector3): number
	local straight = (to - from).Magnitude
	local plan = State.plan
	if plan == nil or not State.inLevel() then
		return straight
	end
	local maze = plan.maze
	local fromIndex = cellIndex(maze, from)
	local toIndex = cellIndex(maze, to)
	if fromIndex == nil or toIndex == nil then
		return straight
	end
	if cachedPlan ~= plan or cachedFrom ~= fromIndex then
		cachedPlan = plan
		cachedFrom = fromIndex
		cachedSteps = Maze.distances(maze, Maze.cellAt(maze, fromIndex))
	end
	local steps = cachedSteps[toIndex]
	if steps == nil then
		return math.huge -- sealed off: no way to reach it
	end
	if steps <= 1 then
		return straight -- same or next cell: the straight line is the walk
	end
	return math.max(straight, (steps - 1) * CELL)
end

return Reach
