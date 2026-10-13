--!strict
-- Turns (tier, seed) into a complete, deterministic level description: maze, landmarks,
-- flooded cells, objectives, enemy spawns, lanterns, hidden recorders, pits, alarm plates and
-- an optional anomaly. Server and clients both build the same plan from the same two numbers.

local Config = require("../Config")
local Difficulty = require("./Difficulty")
local Enemies = require("../data/Enemies")
local Maze = require("./Maze")
local Rng = require("./Rng")

export type Cell = Maze.Cell
export type Objective = { id: number, kind: string, cell: Cell }
export type EnemySpawn = { id: number, kind: string, cell: Cell }
export type Anomaly = { kind: string, room: Maze.Room }
export type LevelPlan = {
	tier: number,
	seed: number,
	def: Difficulty.Tier,
	maze: Maze.Maze,
	features: { [number]: string }, -- landmark or prop kind by cell index
	flooded: { [number]: boolean },
	objectives: { Objective },
	enemies: { EnemySpawn },
	exitLocked: boolean,
	lamps: { Cell }, -- lanterns: small pools of real light
	echoes: { Cell }, -- hidden recorders that reveal themselves when scanned enough
	pits: { Cell }, -- holes in the floor, with a ledge all the way round
	plates: { Cell }, -- alarm plates
	anomaly: Anomaly?,
	beaconCell: Cell, -- halfway along the main path; a checkpoint for pass owners
}

export type BuildOptions = {
	forcedAnomaly: string?, -- the weekly featured anomaly, guaranteed when the level has a room
	allowPlate: boolean, -- false once this run has already produced its rare lore plate
}

local SEED_TIER_MIX = 104729
local FEATURE_CHANCE = 0.2
local OPTIONAL_KINDS = { "cell", "rescue", "cell" }
local OBJECTIVE_RULE = {
	minDistance = 2,
	preferDeadEnd = true,
	spacing = 0,
	clearOfStart = false,
	bypassable = false,
}
-- The first lantern sits close to the start: a fixed point to navigate back to.
local FIRST_LAMP_RULE = {
	minDistance = 1,
	preferDeadEnd = false,
	spacing = 0,
	clearOfStart = false,
	bypassable = false,
}
local SCATTER_RULE = {
	minDistance = 3,
	preferDeadEnd = false,
	spacing = 0,
	clearOfStart = false,
	bypassable = false,
}

local LevelPlan = {}

LevelPlan.featureKinds =
	{ "grating", "pipes", "crates", "arch", "cabinet", "vent", "stairs", "hum" }
LevelPlan.anomalyKinds = { "mirror", "upside_down", "bloom" }

local function sameCell(a: Cell, b: Cell): boolean
	return a.x == b.x and a.y == b.y
end

function LevelPlan.build(tier: number, seed: number, options: BuildOptions): LevelPlan
	local def = Difficulty.forTier(tier)
	local maze = Maze.generateVerified(seed, def.width, def.height, {
		loopChance = def.loopChance,
		pruneChance = def.pruneChance,
		rooms = def.rooms,
	})
	local rng = Rng.new(seed * 31 + tier * SEED_TIER_MIX)
	local startDist = Maze.distances(maze, maze.start)

	local taken: { [number]: boolean } = {
		[Maze.index(maze, maze.start.x, maze.start.y)] = true,
		[Maze.index(maze, maze.exit.x, maze.exit.y)] = true,
	}

	-- Candidate cells, far-from-start first within each group, shuffled for variety.
	local deadEnds = {}
	for _, cell in maze.deadEnds do
		if not sameCell(cell, maze.exit) then
			table.insert(deadEnds, cell)
		end
	end
	rng:shuffle(deadEnds)
	local allCells = {}
	for i = 1, maze.width * maze.height do
		table.insert(allCells, Maze.cellAt(maze, i))
	end
	rng:shuffle(allCells)

	-- Picks a free cell at least `minDistance` steps from the start and `spacing` steps from
	-- every cell in `apart`. When nothing fits, spacing is relaxed first, then distance, so
	-- enemies crowd each other before they crowd the start.
	local apart: { { [number]: number } } = {}
	local cellCount = maze.width * maze.height

	-- True when every other cell stays reachable with this one walled off. Something that
	-- must not be walked into (a Mimic) only ever sits in such a cell, so it never plugs
	-- the one route through the level.
	local function isBypassable(index: number): boolean
		local seen = { [index] = true, [1] = true }
		local queue = { 1 } -- the start is always cell (1, 1)
		local head = 1
		while head <= #queue do
			local cell = Maze.cellAt(maze, queue[head])
			head += 1
			for _, neighbor in Maze.neighbors(maze, cell.x, cell.y) do
				local ni = Maze.index(maze, neighbor.x, neighbor.y)
				if not seen[ni] then
					seen[ni] = true
					table.insert(queue, ni)
				end
			end
		end
		return #queue == cellCount - 1
	end

	type Rule = {
		minDistance: number, -- path steps from the start
		preferDeadEnd: boolean,
		spacing: number, -- path steps from everything in `apart`
		clearOfStart: boolean, -- also keep a straight-line distance from the start
		bypassable: boolean, -- must not plug the only route
	}

	-- Picks a free cell that satisfies the rule. When nothing fits, spacing is relaxed first
	-- and distance from the start second, so enemies crowd each other before the start.
	local function take(rule: Rule): Cell
		local pools = if rule.preferDeadEnd then { deadEnds, allCells } else { allCells }
		for distance = rule.minDistance, 0, -1 do
			for gap = rule.spacing, 0, -1 do
				for _, pool in pools do
					for _, cell in pool do
						local index = Maze.index(maze, cell.x, cell.y)
						local fits = not taken[index] and startDist[index] >= distance
						if fits and rule.clearOfStart and distance > 0 then
							-- Path distance alone lets things start just across an open room.
							local dx, dy = cell.x - maze.start.x, cell.y - maze.start.y
							fits = dx * dx + dy * dy >= Config.Enemy.spawnClearCells ^ 2
						end
						if fits then
							for _, distances in apart do
								if distances[index] < gap then
									fits = false
									break
								end
							end
						end
						if fits and rule.bypassable then
							fits = isBypassable(index)
						end
						if fits then
							taken[index] = true
							return cell
						end
					end
				end
			end
		end
		error("level has no free cell")
	end

	-- Objectives.
	local objectives: { Objective } = {}
	local count = rng:int(def.objectives.min, def.objectives.max)
	local kinds = {}
	if def.exitLocked then
		table.insert(kinds, "key")
	end
	local optional = table.clone(OPTIONAL_KINDS)
	if tier > 1 then
		rng:shuffle(optional)
	end
	for _, kind in optional do
		if #kinds < count then
			table.insert(kinds, kind)
		end
	end
	if
		options.allowPlate
		and tier >= Config.Anomaly.minTier
		and rng:next() < Config.Anomaly.rareLoreChance
	then
		table.insert(kinds, "plate")
	end
	for i, kind in kinds do
		table.insert(objectives, { id = i, kind = kind, cell = take(OBJECTIVE_RULE) })
	end

	-- Enemies. Iterate kinds in a fixed order so the plan is deterministic.
	local enemies: { EnemySpawn } = {}
	local kindNames = {}
	for kind in def.enemies do
		table.insert(kindNames, kind)
	end
	table.sort(kindNames)
	for _, kind in kindNames do
		for _ = 1, def.enemies[kind] do
			local minDistance = math.min(Enemies[kind].minSpawnCells, maze.pathLength - 1)
			local cell = take({
				minDistance = minDistance,
				preferDeadEnd = kind == "mimic",
				spacing = Config.Enemy.spawnSpacingCells,
				clearOfStart = true,
				bypassable = kind == "mimic",
			})
			table.insert(apart, Maze.distances(maze, cell))
			table.insert(enemies, { id = #enemies + 1, kind = kind, cell = cell })
		end
	end

	-- Lanterns, recorders, pits and alarm plates. Each takes its own cell.
	local lamps: { Cell } = {}
	for i = 1, def.lamps do
		table.insert(lamps, take(if i == 1 then FIRST_LAMP_RULE else SCATTER_RULE))
	end
	local echoes: { Cell } = {}
	for _ = 1, def.echoes do
		table.insert(echoes, take(SCATTER_RULE))
	end
	local pits: { Cell } = {}
	for _ = 1, def.pits do
		table.insert(pits, take(SCATTER_RULE))
	end
	local plates: { Cell } = {}
	for _ = 1, def.plates do
		table.insert(plates, take(SCATTER_RULE))
	end

	-- Flooded cells and landmarks.
	local flooded: { [number]: boolean } = {}
	local features: { [number]: string } = {}
	for i = 1, maze.width * maze.height do
		if not taken[i] then
			if rng:next() < def.flooded then
				flooded[i] = true
			elseif rng:next() < FEATURE_CHANCE then
				features[i] = LevelPlan.featureKinds[rng:int(1, #LevelPlan.featureKinds)]
			end
		end
	end

	-- Anomaly: needs a room to live in.
	local anomaly: Anomaly? = nil
	if #maze.rooms > 0 and tier >= Config.Anomaly.minTier then
		local kind = options.forcedAnomaly
		if kind == nil and rng:next() < Config.Anomaly.chancePerLevel then
			kind = LevelPlan.anomalyKinds[rng:int(1, #LevelPlan.anomalyKinds)]
		end
		if kind ~= nil then
			anomaly = { kind = kind, room = maze.rooms[rng:int(1, #maze.rooms)] }
		end
	end

	-- Beacon: the cell halfway along the shortest route to the exit.
	local route = Maze.path(maze, maze.start, maze.exit)
	local beaconCell = route[math.max(1, math.floor(#route / 2))] or maze.start

	return {
		tier = tier,
		seed = seed,
		def = def,
		maze = maze,
		features = features,
		flooded = flooded,
		objectives = objectives,
		enemies = enemies,
		exitLocked = def.exitLocked,
		lamps = lamps,
		echoes = echoes,
		pits = pits,
		plates = plates,
		anomaly = anomaly,
		beaconCell = beaconCell,
	}
end

return LevelPlan
