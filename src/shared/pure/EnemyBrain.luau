--!strict
-- Pure enemy state machines on the maze grid. The server feeds real player positions in;
-- the headless simulation feeds a bot. Positions are continuous, in cell units (see Maze).
--
-- Wanderer: patrol -> investigate (heard or saw scanning) -> chase (close) -> search -> patrol.
--           A chase ends when the target gets far enough away, or goes unsensed long enough;
--           the Wanderer then walks to the last place it sensed them.
-- Listener: drift -> hunt (heard noise) -> listen -> drift. Blind; lunges only at close noise.
-- Mimic:    disguised -> reveal -> chase (timed) -> return -> cooldown -> disguised
-- Stalker:  dormant -> hunt -> withdraw (pinned long enough) -> dormant. Frozen while scanned.

local Config = require("../Config")
local Enemies = require("../data/Enemies")
local Maze = require("./Maze")
local Rng = require("./Rng")

export type Source = {
	id: number,
	x: number,
	z: number,
	noise: number, -- audible radius in cells
	scanning: boolean,
	focusing: boolean, -- scanning with the narrow, loud, hot beam
	lookX: number, -- horizontal look direction
	lookZ: number,
	active: boolean, -- false while downed, in respawn grace or outside the level
	decoy: boolean, -- a ping marker: audible, but never chased or caught
}

export type Enemy = {
	id: number,
	kind: string,
	def: Enemies.EnemyDef,
	speedScale: number,
	senseScale: number, -- multiplies hearing and sight range
	home: Maze.Cell,
	restX: number, -- where it stands when idle: the centre of its home cell unless set otherwise
	restZ: number,
	x: number,
	z: number,
	state: string,
	path: { Maze.Cell },
	timer: number,
	thinkTimer: number,
	targetId: number?,
	goalX: number, -- last position the target was sensed at
	goalZ: number,
	disguised: boolean,
	frozen: boolean,
	moving: boolean,
	faceX: number,
	faceZ: number,
}

local IDLE_STATE =
	{ wanderer = "patrol", listener = "drift", mimic = "disguised", stalker = "dormant" }
local LUNGE_CELLS = 1.2 -- a Listener homes on the exact spot only when the noise is this close
local MIMIC_RETURN_SPEED = 0.6
local ARRIVE_EPSILON = 0.001

local EnemyBrain = {}

local function distance(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = ax - bx, az - bz
	return math.sqrt(dx * dx + dz * dz)
end

function EnemyBrain.reset(enemy: Enemy)
	enemy.x = enemy.restX
	enemy.z = enemy.restZ
	enemy.state = IDLE_STATE[enemy.kind]
	enemy.path = {}
	enemy.timer = 0
	enemy.thinkTimer = 0
	enemy.targetId = nil
	enemy.disguised = enemy.kind == "mimic"
	enemy.frozen = false
	enemy.moving = false
end

function EnemyBrain.new(
	id: number,
	kind: string,
	cell: Maze.Cell,
	speedScale: number,
	senseScale: number
): Enemy
	local def = Enemies[kind]
	assert(def ~= nil, "unknown enemy kind " .. kind)
	local enemy: Enemy = {
		id = id,
		kind = kind,
		def = def,
		speedScale = speedScale,
		senseScale = senseScale,
		home = cell,
		restX = cell.x - 0.5,
		restZ = cell.y - 0.5,
		x = 0,
		z = 0,
		state = "",
		path = {},
		timer = 0,
		thinkTimer = 0,
		targetId = nil,
		goalX = 0,
		goalZ = 0,
		disguised = false,
		frozen = false,
		moving = false,
		faceX = 0,
		faceZ = 1,
	}
	EnemyBrain.reset(enemy)
	return enemy
end

-- Moves an enemy's idle spot within its home cell (a Mimic sits against a wall, as a real
-- stranded surveyor does) and puts it there.
function EnemyBrain.setRest(enemy: Enemy, x: number, z: number)
	enemy.restX = x
	enemy.restZ = z
	EnemyBrain.reset(enemy)
end

-- Pause an enemy after it catches someone in co-op so it cannot camp the spot.
function EnemyBrain.stun(enemy: Enemy)
	enemy.state = "stunned"
	enemy.timer = Config.Enemy.stunSeconds
	enemy.path = {}
	enemy.targetId = nil
	enemy.frozen = false
	enemy.moving = false
end

-- Straight-line pursuit; only valid with a clear line to the target. Drops the stored path so
-- a stale route is never resumed from a different cell.
local function moveToward(enemy: Enemy, tx: number, tz: number, speed: number, dt: number): boolean
	enemy.path = {}
	local d = distance(enemy.x, enemy.z, tx, tz)
	local budget = speed * dt
	if d <= ARRIVE_EPSILON then
		enemy.moving = false
		return true
	end
	enemy.faceX, enemy.faceZ = (tx - enemy.x) / d, (tz - enemy.z) / d
	enemy.moving = budget > 0
	if d <= budget then
		enemy.x, enemy.z = tx, tz
		return true
	end
	enemy.x += enemy.faceX * budget
	enemy.z += enemy.faceZ * budget
	return false
end

-- Walks the stored path of cell centres. Returns true once the path is finished.
local function followPath(enemy: Enemy, speed: number, dt: number): boolean
	local budget = speed * dt
	enemy.moving = false
	while budget > 0 and #enemy.path > 0 do
		local cell = enemy.path[1]
		local tx, tz = cell.x - 0.5, cell.y - 0.5
		local d = distance(enemy.x, enemy.z, tx, tz)
		if d > ARRIVE_EPSILON then
			enemy.faceX, enemy.faceZ = (tx - enemy.x) / d, (tz - enemy.z) / d
			enemy.moving = true
		end
		if d <= budget then
			enemy.x, enemy.z = tx, tz
			budget -= d
			table.remove(enemy.path, 1)
		else
			enemy.x += enemy.faceX * budget
			enemy.z += enemy.faceZ * budget
			budget = 0
		end
	end
	return #enemy.path == 0
end

local function setGoal(enemy: Enemy, maze: Maze.Maze, cell: Maze.Cell)
	local here = Maze.cellOf(maze, enemy.x, enemy.z)
	local path = Maze.path(maze, here, cell)
	if #path == 0 then
		path = { cell }
	end
	enemy.path = path
end

local function findSource(sources: { Source }, id: number?): Source?
	if id == nil then
		return nil
	end
	for _, source in sources do
		if source.id == id then
			return source
		end
	end
	return nil
end

local function hears(enemy: Enemy, source: Source): boolean
	if enemy.def.hearing <= 0 or source.noise <= 0 or not (source.active or source.decoy) then
		return false
	end
	return distance(enemy.x, enemy.z, source.x, source.z)
		<= source.noise * enemy.def.hearing * enemy.senseScale
end

local function sees(enemy: Enemy, maze: Maze.Maze, source: Source): boolean
	if enemy.def.sightCells <= 0 or not source.active or not source.scanning then
		return false
	end
	if distance(enemy.x, enemy.z, source.x, source.z) > enemy.def.sightCells * enemy.senseScale then
		return false
	end
	return Maze.lineOfSight(maze, enemy.x, enemy.z, source.x, source.z)
end

-- Nearest source this enemy can currently hear or see.
local function senseNearest(enemy: Enemy, maze: Maze.Maze, sources: { Source }): Source?
	local best: Source? = nil
	local bestDistance = math.huge
	for _, source in sources do
		local d = distance(enemy.x, enemy.z, source.x, source.z)
		if d < bestDistance and (hears(enemy, source) or sees(enemy, maze, source)) then
			best, bestDistance = source, d
		end
	end
	return best
end

local function pathCells(maze: Maze.Maze, dist: { [number]: number }, source: Source): number
	local cell = Maze.cellOf(maze, source.x, source.z)
	return dist[Maze.index(maze, cell.x, cell.y)] or math.huge
end

-- A random cell near the enemy's post. Patrols keep out of the cells around the level start,
-- so nothing idles on top of a player who has just respawned.
local function randomPatrolCell(enemy: Enemy, maze: Maze.Maze, rng: Rng.Rng): Maze.Cell
	local dist = Maze.distances(maze, enemy.home)
	local startDist = Maze.distances(maze, maze.start)
	local options = {}
	for index, steps in dist do
		if
			steps <= Config.Enemy.patrolRadius
			and startDist[index] > Config.Enemy.startSafeCells
		then
			table.insert(options, index)
		end
	end
	if #options == 0 then
		return enemy.home
	end
	table.sort(options)
	return Maze.cellAt(maze, options[rng:int(1, #options)])
end

local function scaled(enemy: Enemy, studsPerSecond: number, cellSize: number): number
	return studsPerSecond * enemy.speedScale / cellSize
end

local function stepWanderer(
	enemy: Enemy,
	maze: Maze.Maze,
	sources: { Source },
	dt: number,
	rng: Rng.Rng,
	cellSize: number,
	think: boolean
)
	local def = enemy.def
	if think then
		local dist = Maze.distances(maze, Maze.cellOf(maze, enemy.x, enemy.z))
		local sensed = senseNearest(enemy, maze, sources)
		if enemy.state == "chase" then
			-- In a chase `timer` counts how long the target has gone unsensed.
			local target = findSource(sources, enemy.targetId)
			if
				target == nil
				or not target.active
				or pathCells(maze, dist, target) > def.loseCells
			then
				enemy.state = "search"
				enemy.timer = def.searchSeconds
				enemy.path = {}
				enemy.targetId = nil
			elseif hears(enemy, target) or sees(enemy, maze, target) then
				enemy.timer = 0
				enemy.goalX, enemy.goalZ = target.x, target.z
				setGoal(enemy, maze, Maze.cellOf(maze, target.x, target.z))
			else
				enemy.timer += Config.Enemy.thinkInterval
				if enemy.timer >= def.searchSeconds then
					enemy.state = "investigate"
					enemy.targetId = nil
					setGoal(enemy, maze, Maze.cellOf(maze, enemy.goalX, enemy.goalZ))
				end
			end
		elseif sensed ~= nil then
			if sensed.active and pathCells(maze, dist, sensed) <= def.chaseCells then
				enemy.state = "chase"
				enemy.targetId = sensed.id
				enemy.timer = 0
				enemy.goalX, enemy.goalZ = sensed.x, sensed.z
			else
				enemy.state = "investigate"
			end
			setGoal(enemy, maze, Maze.cellOf(maze, sensed.x, sensed.z))
		elseif enemy.state == "patrol" and #enemy.path == 0 then
			setGoal(enemy, maze, randomPatrolCell(enemy, maze, rng))
		end
	end

	if enemy.state == "search" then
		enemy.timer -= dt
		enemy.moving = false
		if enemy.timer <= 0 then
			enemy.state = "patrol"
		end
	elseif enemy.state == "chase" then
		-- Head for the last sensed position: straight there when the way is clear.
		if Maze.lineOfSight(maze, enemy.x, enemy.z, enemy.goalX, enemy.goalZ) then
			moveToward(enemy, enemy.goalX, enemy.goalZ, scaled(enemy, def.chaseSpeed, cellSize), dt)
		else
			followPath(enemy, scaled(enemy, def.chaseSpeed, cellSize), dt)
		end
	elseif enemy.state == "investigate" then
		if followPath(enemy, scaled(enemy, def.alertSpeed, cellSize), dt) then
			enemy.state = "search"
			enemy.timer = def.searchSeconds
		end
	else
		followPath(enemy, scaled(enemy, def.patrolSpeed, cellSize), dt)
	end
end

local function stepListener(
	enemy: Enemy,
	maze: Maze.Maze,
	sources: { Source },
	dt: number,
	rng: Rng.Rng,
	cellSize: number,
	think: boolean
)
	local def = enemy.def
	if think then
		local heard = senseNearest(enemy, maze, sources)
		if heard ~= nil then
			enemy.state = "hunt"
			enemy.targetId = heard.id
			setGoal(enemy, maze, Maze.cellOf(maze, heard.x, heard.z))
		else
			enemy.targetId = nil
			if enemy.state == "drift" and #enemy.path == 0 then
				setGoal(enemy, maze, randomPatrolCell(enemy, maze, rng))
			end
		end
	end

	if enemy.state == "listen" then
		enemy.timer -= dt
		enemy.moving = false
		if enemy.timer <= 0 then
			enemy.state = "drift"
		end
	elseif enemy.state == "hunt" then
		local target = findSource(sources, enemy.targetId)
		local speed = scaled(enemy, def.alertSpeed, cellSize)
		if
			target ~= nil
			and target.active
			and distance(enemy.x, enemy.z, target.x, target.z) <= LUNGE_CELLS
			and Maze.lineOfSight(maze, enemy.x, enemy.z, target.x, target.z)
		then
			moveToward(enemy, target.x, target.z, speed, dt)
		elseif followPath(enemy, speed, dt) then
			enemy.state = "listen"
			enemy.timer = def.searchSeconds
		end
	else
		followPath(enemy, scaled(enemy, def.patrolSpeed, cellSize), dt)
	end
end

local function stepMimic(
	enemy: Enemy,
	maze: Maze.Maze,
	sources: { Source },
	dt: number,
	_rng: Rng.Rng,
	cellSize: number,
	think: boolean
)
	local def = enemy.def
	if enemy.state == "disguised" then
		enemy.moving = false
		if think then
			for _, source in sources do
				if
					source.active
					and distance(enemy.x, enemy.z, source.x, source.z) <= def.chaseCells
					and Maze.lineOfSight(maze, enemy.x, enemy.z, source.x, source.z)
				then
					enemy.state = "reveal"
					enemy.timer = Config.Enemy.mimicRevealDelay
					enemy.targetId = source.id
					enemy.disguised = false
					break
				end
			end
		end
	elseif enemy.state == "reveal" then
		enemy.timer -= dt
		if enemy.timer <= 0 then
			enemy.state = "chase"
			enemy.timer = def.searchSeconds
		end
	elseif enemy.state == "chase" then
		enemy.timer -= dt
		local target = findSource(sources, enemy.targetId)
		local lost = target == nil or not target.active or enemy.timer <= 0
		if not lost and think and target ~= nil then
			local dist = Maze.distances(maze, Maze.cellOf(maze, enemy.x, enemy.z))
			lost = pathCells(maze, dist, target) > def.loseCells
			if not lost then
				setGoal(enemy, maze, Maze.cellOf(maze, target.x, target.z))
			end
		end
		if lost or target == nil then
			enemy.state = "return"
			enemy.targetId = nil
			setGoal(enemy, maze, enemy.home)
		elseif Maze.lineOfSight(maze, enemy.x, enemy.z, target.x, target.z) then
			moveToward(enemy, target.x, target.z, scaled(enemy, def.chaseSpeed, cellSize), dt)
		else
			followPath(enemy, scaled(enemy, def.chaseSpeed, cellSize), dt)
		end
	elseif enemy.state == "return" then
		local speed = scaled(enemy, def.chaseSpeed * MIMIC_RETURN_SPEED, cellSize)
		if
			followPath(enemy, speed, dt) and moveToward(enemy, enemy.restX, enemy.restZ, speed, dt)
		then
			enemy.state = "cooldown"
			enemy.timer = Config.Enemy.mimicCooldown
			enemy.disguised = true
		end
	else -- cooldown
		enemy.timer -= dt
		enemy.moving = false
		if enemy.timer <= 0 then
			enemy.state = "disguised"
		end
	end
end

-- How hard the enemy is being pinned: 0 when no active player's scanner points at it with a
-- clear line, 1 for a normal scan, more for a focused one.
function EnemyBrain.observation(enemy: Enemy, maze: Maze.Maze, sources: { Source }): number
	local strength = 0
	for _, source in sources do
		if source.active and source.scanning then
			local dx, dz = enemy.x - source.x, enemy.z - source.z
			local d = math.sqrt(dx * dx + dz * dz)
			local lookLength = math.sqrt(source.lookX * source.lookX + source.lookZ * source.lookZ)
			if d <= enemy.def.sightCells and d > 0 and lookLength > 0 then
				local dot = (dx * source.lookX + dz * source.lookZ) / (d * lookLength)
				if
					dot >= Config.Enemy.stalkerConeDot
					and Maze.lineOfSight(maze, source.x, source.z, enemy.x, enemy.z)
				then
					strength = math.max(
						strength,
						if source.focusing then Config.Enemy.stalkerFocusRate else 1
					)
				end
			end
		end
	end
	return strength
end

local function stepStalker(
	enemy: Enemy,
	maze: Maze.Maze,
	sources: { Source },
	dt: number,
	_rng: Rng.Rng,
	cellSize: number,
	think: boolean
)
	local def = enemy.def
	local settings = Config.Enemy
	if enemy.state == "withdraw" then
		enemy.frozen = false
		local speed = scaled(enemy, def.chaseSpeed * settings.stalkerWithdrawSpeed, cellSize)
		if followPath(enemy, speed, dt) then
			enemy.state = "dormant"
			enemy.timer = settings.stalkerCooldown
		end
		return
	end
	if enemy.state == "dormant" then
		enemy.frozen = false
		enemy.moving = false
		enemy.timer = math.max(0, enemy.timer - dt)
	end

	if think then
		local dist = Maze.distances(maze, Maze.cellOf(maze, enemy.x, enemy.z))
		local nearest: Source? = nil
		local nearestSteps = math.huge
		for _, source in sources do
			if source.active then
				local steps = pathCells(maze, dist, source)
				if steps < nearestSteps then
					nearest, nearestSteps = source, steps
				end
			end
		end
		if enemy.state == "dormant" then
			if enemy.timer <= 0 and nearest ~= nil and nearestSteps <= def.chaseCells then
				enemy.state = "hunt"
				enemy.timer = 0
			end
		elseif nearest == nil or nearestSteps > def.loseCells then
			enemy.state = "dormant"
			enemy.timer = 0
			enemy.targetId = nil
			enemy.path = {}
		end
		if enemy.state == "hunt" and nearest ~= nil then
			enemy.targetId = nearest.id
			setGoal(enemy, maze, Maze.cellOf(maze, nearest.x, nearest.z))
		end
	end
	if enemy.state ~= "hunt" then
		return
	end

	-- In the hunt state `timer` counts how long the Stalker has been pinned.
	local pinned = EnemyBrain.observation(enemy, maze, sources)
	enemy.frozen = pinned > 0
	if enemy.frozen then
		enemy.moving = false
		enemy.timer += dt * pinned
		if enemy.timer >= settings.stalkerStareSeconds then
			enemy.state = "withdraw"
			enemy.frozen = false
			enemy.targetId = nil
			setGoal(enemy, maze, enemy.home)
		end
		return
	end
	enemy.timer = math.max(0, enemy.timer - dt * settings.stalkerStareDecay)
	local target = findSource(sources, enemy.targetId)
	local speed = scaled(enemy, def.chaseSpeed, cellSize)
	if
		target ~= nil
		and target.active
		and Maze.lineOfSight(maze, enemy.x, enemy.z, target.x, target.z)
	then
		moveToward(enemy, target.x, target.z, speed, dt)
	else
		followPath(enemy, speed, dt)
	end
end

local HANDLERS = {
	wanderer = stepWanderer,
	listener = stepListener,
	mimic = stepMimic,
	stalker = stepStalker,
}

local function canCatch(enemy: Enemy): boolean
	if enemy.kind == "mimic" then
		return enemy.state == "chase"
	elseif enemy.kind == "stalker" then
		return enemy.state == "hunt" and not enemy.frozen
	end
	return true
end

-- Advances one enemy by dt seconds. Returns the id of a player it caught this step, if any.
function EnemyBrain.step(
	enemy: Enemy,
	maze: Maze.Maze,
	sources: { Source },
	dt: number,
	rng: Rng.Rng,
	cellSize: number
): number?
	local nearestAny = math.huge
	for _, source in sources do
		if not source.decoy then
			nearestAny = math.min(nearestAny, distance(enemy.x, enemy.z, source.x, source.z))
		end
	end
	if nearestAny > Config.Enemy.sleepCells then
		enemy.moving = false
		return nil
	end

	if enemy.state == "stunned" then
		enemy.timer -= dt
		enemy.moving = false
		if enemy.timer <= 0 then
			if enemy.kind == "mimic" then
				enemy.state = "return"
				setGoal(enemy, maze, enemy.home)
			else
				enemy.state = IDLE_STATE[enemy.kind]
			end
		end
		return nil
	end

	enemy.thinkTimer -= dt
	local think = enemy.thinkTimer <= 0
	if think then
		enemy.thinkTimer = Config.Enemy.thinkInterval
	end
	HANDLERS[enemy.kind](enemy, maze, sources, dt, rng, cellSize, think)

	if canCatch(enemy) then
		local radius = enemy.def.catchRadius / cellSize
		for _, source in sources do
			if
				source.active
				and distance(enemy.x, enemy.z, source.x, source.z) <= radius
				and Maze.lineOfSight(maze, enemy.x, enemy.z, source.x, source.z)
			then
				return source.id
			end
		end
	end
	return nil
end

return EnemyBrain
