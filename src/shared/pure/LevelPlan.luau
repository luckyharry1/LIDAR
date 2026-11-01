--!strict
-- Turns (tier, seed) into a complete, deterministic level description: maze, landmarks,
-- flooded cells, objectives, enemy spawns, lanterns, hidden recorders, pits, alarm plates and
-- an optional anomaly. Server and clients both build the same plan from the same two numbers.

local Config = require("../Config")
local Difficulty = require("./Difficulty")
local Enemies = require("../data/Enemies")
local Maze = require("./Maze")
local Places = require("../data/Places")
local Rng = require("./Rng")

export type Cell = Maze.Cell
-- `charges` is set on battery cells only: the sweep charges the cell gives (1 or 2).
export type Objective = { id: number, kind: string, cell: Cell, charges: number? }
export type EnemySpawn = { id: number, kind: string, cell: Cell }
export type Anomaly = { kind: string, room: Maze.Room }
export type Reveal = { id: string, cell: Cell } -- a hidden object (Places.reveal) in its own cell
export type Sign = { id: string, cell: Cell } -- a notice on a wall; may share a cell
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
	lamps: { Cell }, -- lamp-bags: small pools of real light, spread along the way through
	nooks: { number }, -- which of the four lamp-bag variants each lamp is (Places.nookLines)
	echoes: { Cell }, -- hidden recorders that reveal themselves when scanned enough
	reveals: { Reveal }, -- other hidden objects, each with its own lines of story
	signs: { Sign }, -- posters and stencils
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
local LAST_FORGIVING_TIER = 2 -- up to here every lamp-bag burns
local FEATURE_CHANCE = 0.2
local OPTIONAL_KINDS: { string } = { "rescue" } -- battery cells are placed on their own (def.batteries)
local FIRST_RESCUE_TIER = 2
local OBJECTIVE_RULE = {
	minDistance = 2,
	preferDeadEnd = true,
	spacing = 0,
	clearOfStart = false,
	bypassable = false,
}
-- The first battery cell is found early, so the sweep can be learned on every floor. The
-- rest prefer dead ends: a reward for looking round the corner instead of running past.
local FIRST_CELL_RULE = {
	minDistance = 1,
	preferDeadEnd = true,
	spacing = 0,
	clearOfStart = false,
	bypassable = false,
}
-- The first lamp-bag sits a little way along the route, close to the start: a fixed point to
-- navigate back to. Later ones keep at least this many path steps from every other lamp-bag.
local FIRST_LAMP_STEP = 0.12
local LAMP_SPACING_CELLS = 5
local LAMP_MIN_SPACING_CELLS = 3 -- never closer than this unless the maze leaves no room
local LAMP_ROUTE_STEPS = 5 -- a short way through holds one lamp-bag per this many cells, at most
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
	-- The beacon: the cell halfway along the shortest route to the exit. Players who own the
	-- Surveyor's Kit respawn there, so it needs the same room round it the start has.
	local route = Maze.path(maze, maze.start, maze.exit)
	local beaconCell = route[math.max(1, math.floor(#route / 2))] or maze.start
	local beaconDist = Maze.distances(maze, beaconCell)

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

	-- Picks a free cell that satisfies the rule. When nothing fits, spacing is relaxed first,
	-- then the room left round the checkpoint beacon, and distance from the start last, so
	-- enemies crowd each other, then the beacon, before the start.
	local function take(rule: Rule): Cell
		local pools = if rule.preferDeadEnd then { deadEnds, allCells } else { allCells }
		for distance = rule.minDistance, 0, -1 do
			for gap = rule.spacing, 0, -1 do
				-- Enemy posts also keep clear of the beacon: a player who respawns there must
				-- not wake up next to one.
				local beaconTop = if rule.clearOfStart then Config.Enemy.checkpointClearCells else 0
				for beaconGap = beaconTop, 0, -1 do
					for _, pool in pools do
						for _, cell in pool do
							local index = Maze.index(maze, cell.x, cell.y)
							local fits = not taken[index] and startDist[index] >= distance
							if fits and rule.clearOfStart and distance > 0 then
								-- Path distance alone lets things start just across an open room.
								local clear = Config.Enemy.spawnClearCells ^ 2
								local dx, dy = cell.x - maze.start.x, cell.y - maze.start.y
								fits = dx * dx + dy * dy >= clear
								if fits and beaconGap > 0 then
									dx, dy = cell.x - beaconCell.x, cell.y - beaconCell.y
									fits = dx * dx + dy * dy >= clear
										and beaconDist[index] >= beaconGap
								end
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
		end
		error("level has no free cell")
	end

	-- Objectives.
	local objectives: { Objective } = {}
	local count = rng:int(def.objectives.min, def.objectives.max)
	if Config.Surveyor.rescueOfTier[tier] ~= nil then
		count = math.max(count, 2) -- the key and the surveyor this floor is known for
	end
	local kinds = {}
	if def.exitLocked then
		table.insert(kinds, "key")
	end
	local optional: { string } = if tier >= FIRST_RESCUE_TIER
		then table.clone(OPTIONAL_KINDS)
		else {}
	rng:shuffle(optional)
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
	-- Battery cells: the only thing that charges the sweep in a level.
	for i = 1, def.batteries do
		local charges = if rng:next() < Config.Battery.doubleChance then 2 else 1
		table.insert(objectives, {
			id = #objectives + 1,
			kind = "cell",
			cell = take(if i == 1 then FIRST_CELL_RULE else OBJECTIVE_RULE),
			charges = charges,
		})
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

	-- Lamp-bags, recorders, pits and alarm plates. Each takes its own cell.
	-- The first lamp-bag sits close to the start. The rest are spread along the shortest way
	-- through at even steps, so a player walking it meets one about every minute: a place to
	-- see the walls, take stock and hear a line of story. Two bags are never close together:
	-- a cell too near a lamp already placed is passed over (the gap is relaxed only when the
	-- route cannot offer anything wider). A bag the route cannot offer at all goes anywhere.
	local lampDistances: { { [number]: number } } = {}
	local function clearOfLamps(index: number, gap: number): boolean
		for _, distances in lampDistances do
			if distances[index] < gap then
				return false
			end
		end
		return true
	end
	local function takeNearStep(step: number): Cell
		local target = math.clamp(math.floor(#route * step + 0.5), 1, #route)
		local function tryStep(position: number, gap: number): Cell?
			local cell = route[position]
			if cell == nil then
				return nil
			end
			local index = Maze.index(maze, cell.x, cell.y)
			if taken[index] or startDist[index] < 1 or not clearOfLamps(index, gap) then
				return nil
			end
			taken[index] = true
			return cell
		end
		for gap = LAMP_SPACING_CELLS, 0, -1 do
			-- The step itself first, then outward from it, before and after, one cell at a time.
			local found = tryStep(target, gap)
			for offset = 1, #route do
				found = found or tryStep(target + offset, gap) or tryStep(target - offset, gap)
			end
			if found ~= nil then
				return found
			end
			if gap == LAMP_MIN_SPACING_CELLS then
				-- Nothing on the route is far enough from the others: any cell that is.
				for _, cell in allCells do
					local index = Maze.index(maze, cell.x, cell.y)
					if not taken[index] and startDist[index] >= 1 and clearOfLamps(index, gap) then
						taken[index] = true
						return cell
					end
				end
			end
		end
		return take(SCATTER_RULE)
	end
	local lamps: { Cell } = {}
	local nooks: { number } = {}
	local deadNookAllowed = tier >= LAST_FORGIVING_TIER + 1
	-- A short route cannot hold the tier's full count without bunching them up: fewer, then, but
	-- never fewer than two where the tier has them (the second goes off the route if it must).
	local lampCount =
		math.clamp(math.floor(#route / LAMP_ROUTE_STEPS), math.min(2, def.lamps), def.lamps)
	local deadCount = 0
	for i = 1, lampCount do
		if i == 1 then
			table.insert(lamps, takeNearStep(FIRST_LAMP_STEP))
		else
			table.insert(lamps, takeNearStep((i - 1) / (lampCount - 1) * 0.8 + 0.1))
		end
		local placed = lamps[#lamps]
		table.insert(lampDistances, Maze.distances(maze, placed))
		-- The first bag always burns; a burnt-out one is a small secret, never on the first floor.
		-- At least two bags always burn, so no level is left with a single light.
		local mayBurnOut = i > 1 and deadNookAllowed and lampCount - (deadCount + 1) >= 2
		local top = if mayBurnOut then Places.nookCount else Places.nookCount - 1
		local variant = rng:int(1, top)
		if variant == Places.deadNook then
			deadCount += 1
		end
		table.insert(nooks, variant)
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

	-- Hidden objects and signs from the story (src/shared/data/Places).
	local places = Places.forTier(tier)
	local reveals: { Reveal } = {}
	for _, id in places.reveals do
		table.insert(reveals, { id = id, cell = take(SCATTER_RULE) })
	end
	local signs: { Sign } = {}
	for _, sign in places.signs do
		local cell: Cell? = nil
		if sign.at == "start" then
			cell = maze.start
		elseif sign.at == "exit" then
			cell = maze.exit
		elseif sign.at == "pit" then
			cell = pits[#signs % math.max(1, #pits) + 1]
		elseif sign.at == "plate" then
			cell = plates[#signs % math.max(1, #plates) + 1]
		else
			cell = take(SCATTER_RULE)
		end
		-- A sign for a trap the level does not have is left out.
		if cell ~= nil then
			table.insert(signs, { id = sign.id, cell = cell })
		end
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
		nooks = nooks,
		echoes = echoes,
		reveals = reveals,
		signs = signs,
		pits = pits,
		plates = plates,
		anomaly = anomaly,
		beaconCell = beaconCell,
	}
end

return LevelPlan
