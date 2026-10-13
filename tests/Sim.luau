--!strict
-- Headless simulation of one level: a scripted bot explores a generated maze using only what
-- it has "scanned", while the real enemy state machines hunt it. Used by tests to show every
-- tier can be cleared and that nothing deadlocks. It models the rules, not the feel.
--
-- The bot plays the way the game teaches: it goes quiet near a Wanderer and routes around it,
-- hides at the wall when a Listener is close, stares a Stalker down, and runs from a chase.

local Config = require("../src/shared/Config")
local EnemyBrain = require("../src/shared/pure/EnemyBrain")
local LevelPlan = require("../src/shared/pure/LevelPlan")
local Maze = require("../src/shared/pure/Maze")
local Noise = require("../src/shared/pure/Noise")
local Rng = require("../src/shared/pure/Rng")

export type Result = {
	cleared: boolean,
	stuck: boolean, -- the bot ran out of things to do: a logic deadlock
	seconds: number,
	deaths: number,
	collected: number,
	modeSeconds: { [string]: number }, -- how long the bot spent in each behaviour
}

local DT = 0.1
local SCAN_CELLS = 5 -- how far down a straight corridor a scan teaches the bot
local SENSE_CELLS = 6 -- how far the bot notices an enemy it has a clear line to
local HEAR_CELLS = 1.5 -- how close a moving enemy must be to be heard through walls
local QUIET_CELLS = 4 -- stop scanning when a Listener is this close
local LISTENER_HIDE_CELLS = 1.3 -- stand still at the wall when a Listener is this close
local LISTENER_CLEAR_CELLS = 1.6 -- and stay hidden until it is this far away again
local LISTENER_FREEZE_CELLS = 0.95 -- closer than this even a step to the wall is heard
local PATROL_HIDE_CELLS = 1.3 -- also hide from a Wanderer that has not noticed the bot
local HIDE_PATH_CELLS = 2 -- but only when it is also this few steps away on foot
local MEMORY_SECONDS = 30 -- how long the bot remembers where it met a Listener or Wanderer
local MEMORY_CELLS = 5 -- and how near that spot it keeps the scanner off
local HUNTER_FREEZE_CELLS = 1 -- with a hunting Wanderer this close, do not even step to the wall
local LANE_OFFSET = 0.36 -- how far off the centre line the bot walks to slip past something
local LANE_CELLS = 1.5 -- it does that when the thing is this close
local STARE_SAFE_CELLS = 1.3 -- with a Listener or hunting Wanderer nearer than this, run instead of pinning a Stalker
local FLEE_CELLS = 2 -- run when something fast is coming and is this close
local EVADE_CELLS = 3 -- walk away quietly when a Wanderer on your trail is this close
local FLEE_SECONDS = 2.5
local PATIENCE_SECONDS = 15 -- how long the bot waits for a blocked route before risking it
local RISK_SECONDS = 10
local HIDE_OFFSET = 0.38 -- distance from the cell centre while hiding, in cells
local MIMIC_SPOT_CHANCE = 0.7 -- how often the bot notices a Mimic's tell
local REPLAN_SECONDS = 0.5
local DEAD_END_PENALTY = 3 -- cells of distance a dead end is "worth less" as a place to retreat to
local SEED_SALT = 17

local Sim = {}

function Sim.run(tier: number, seed: number, maxSeconds: number, trace: ((string) -> ())?): Result
	local plan = LevelPlan.build(tier, seed, { forcedAnomaly = nil, allowPlate = false })
	local maze = plan.maze
	local cellSize = Config.World.cellSize
	local rng = Rng.new(seed + SEED_SALT)
	local walk = Config.Player.walkSpeed
	local sprint = Config.Player.sprintSpeed

	local function indexOf(cell: Maze.Cell): number
		return Maze.index(maze, cell.x, cell.y)
	end

	local enemies: { EnemyBrain.Enemy } = {}
	local spotsMimic: { [number]: boolean } = {}
	local mimicPosts: { [number]: Maze.Cell } = {}
	local heardX, heardZ, heardAt = 0, 0, -math.huge -- where a Listener or Wanderer was last noticed
	for _, spawn in plan.enemies do
		table.insert(
			enemies,
			EnemyBrain.new(
				spawn.id,
				spawn.kind,
				spawn.cell,
				plan.def.enemySpeedScale,
				plan.def.enemySenseScale
			)
		)
		spotsMimic[spawn.id] = rng:next() < MIMIC_SPOT_CHANCE
	end

	local known: { [number]: boolean } = {}
	local remaining: { [number]: LevelPlan.Objective } = {}
	for _, objective in plan.objectives do
		remaining[objective.id] = objective
	end
	local exitIndex = indexOf(maze.exit)
	local hasKey = not plan.exitLocked
	local collected = 0
	local deaths = 0

	local bot: EnemyBrain.Source = {
		id = 1,
		x = maze.start.x - 0.5,
		z = maze.start.y - 0.5,
		noise = 0,
		scanning = true,
		focusing = false,
		lookX = 0,
		lookZ = 1,
		active = true,
		decoy = false,
	}
	local sources = { bot }
	local path: { Maze.Cell } = {}
	local replan = 0
	local grace = 0
	local respawn = 0
	local fleeTimer = 0
	local stall = 0 -- seconds spent with the wanted route blocked
	local risk = 0 -- seconds left of ignoring the safety margin
	local lastMode = "explore"
	local modeSeconds: { [string]: number } = {}

	local function learn()
		local here = Maze.cellOf(maze, bot.x, bot.z)
		known[indexOf(here)] = true
		if not bot.scanning then
			return
		end
		for _, name in Maze.DIR_NAMES do
			local d = Maze.DIRS[name]
			local cx, cy = here.x, here.y
			for _ = 1, SCAN_CELLS do
				if not Maze.isOpen(maze, cx, cy, name) then
					break
				end
				cx, cy = cx + d.dx, cy + d.dy
				known[Maze.index(maze, cx, cy)] = true
			end
		end
	end

	-- Breadth-first search over known, unblocked cells from the bot's cell. `visit` is called
	-- for each reached cell and may return a goal cell (the reached cell or a neighbour of it).
	local function search(
		blocked: { [number]: boolean },
		visit: (cell: Maze.Cell, index: number) -> Maze.Cell?
	): { Maze.Cell }?
		local start = Maze.cellOf(maze, bot.x, bot.z)
		local startIndex = indexOf(start)
		local parent: { [number]: number } = { [startIndex] = 0 }
		local queue = { startIndex }
		local head = 1
		while head <= #queue do
			local index = queue[head]
			head += 1
			local cell = Maze.cellAt(maze, index)
			local goal = visit(cell, index)
			if goal ~= nil then
				local route = {}
				local back = index
				while back ~= startIndex do
					table.insert(route, 1, Maze.cellAt(maze, back))
					back = parent[back]
				end
				if indexOf(goal) ~= index then
					table.insert(route, goal)
				end
				return route
			end
			for _, neighbor in Maze.neighbors(maze, cell.x, cell.y) do
				local ni = indexOf(neighbor)
				if parent[ni] == nil and known[ni] and not blocked[ni] then
					parent[ni] = index
					table.insert(queue, ni)
				end
			end
		end
		return nil
	end

	-- The route the bot wants: the key if it needs one, else the exit, else the nearest
	-- frontier. Optional pickups are only collected when the bot happens to walk over them.
	local function wantedRoute(blocked: { [number]: boolean }): { Maze.Cell }?
		local wanted: { [number]: boolean } = {}
		local wantAny = false
		for _, objective in remaining do
			local index = indexOf(objective.cell)
			if known[index] and not blocked[index] and objective.kind == "key" then
				wanted[index] = true
				wantAny = true
			end
		end
		if wantAny then
			local route = search(blocked, function(cell, index)
				return if wanted[index] then cell else nil
			end)
			if route ~= nil then
				return route
			end
		end
		if hasKey and known[exitIndex] and not blocked[exitIndex] then
			local route = search(blocked, function(cell, index)
				return if index == exitIndex then cell else nil
			end)
			if route ~= nil then
				return route
			end
		end
		return search(blocked, function(cell, _index)
			for _, neighbor in Maze.neighbors(maze, cell.x, cell.y) do
				local ni = indexOf(neighbor)
				if not known[ni] and not blocked[ni] then
					return neighbor
				end
			end
			return nil
		end)
	end

	-- The reachable known cell that is farthest, by real path distance, from every danger.
	local function retreatRoute(
		blocked: { [number]: boolean },
		dangers: { EnemyBrain.Enemy }
	): { Maze.Cell }?
		local maps = {}
		for _, enemy in dangers do
			table.insert(maps, Maze.distances(maze, Maze.cellOf(maze, enemy.x, enemy.z)))
		end
		local bestIndex, bestScore = nil, -1
		search(blocked, function(cell, index)
			local score = math.huge
			for _, map in maps do
				score = math.min(score, map[index])
			end
			if #Maze.neighbors(maze, cell.x, cell.y) <= 1 then
				score -= DEAD_END_PENALTY -- a dead end is a trap, not a refuge
			end
			if score > bestScore then
				bestIndex, bestScore = index, score
			end
			return nil
		end)
		if bestIndex == nil then
			return nil
		end
		local target = bestIndex
		return search(blocked, function(cell, index)
			return if index == target then cell else nil
		end)
	end

	local function resetAfterCatch()
		deaths += 1
		respawn = Config.World.respawnSeconds
		bot.active = false
		bot.x, bot.z = maze.start.x - 0.5, maze.start.y - 0.5
		path = {}
		fleeTimer = 0
		for _, enemy in enemies do
			EnemyBrain.reset(enemy)
		end
	end

	local elapsed = 0
	while elapsed < maxSeconds do
		elapsed += DT

		if respawn > 0 then
			respawn -= DT
			if respawn <= 0 then
				grace = Config.World.respawnGraceSeconds
			end
		else
			if grace > 0 then
				grace -= DT
			end
			bot.active = grace <= 0
			learn()

			-- Perception: what the bot can see down a clear line or hear close by.
			local hereCell = Maze.cellOf(maze, bot.x, bot.z)
			local blocked: { [number]: boolean } = {} -- cells to route around, with a margin
			local occupied: { [number]: boolean } = {} -- cells the bot will not enter even when taking a risk
			local unsafe: { [number]: boolean } = {} -- cells never to run through when retreating
			local avoidX, avoidZ, avoidDistance = 0, 0, math.huge -- nearest thing to give a wide berth
			local dangers: { EnemyBrain.Enemy } = {} -- enemies worth routing around
			local nearChaser = math.huge -- fast things coming for the bot: run
			local nearHunter = math.huge -- a Wanderer on the bot's trail: walk away quietly
			local nearPatrol = math.huge -- a Wanderer that has not noticed the bot
			local nearListener = math.huge
			local stalkerInSight: EnemyBrain.Enemy? = nil
			local stalkerDistance = math.huge
			local hereDist: { [number]: number }? = nil -- path steps from the bot, built on demand
			for _, enemy in enemies do
				local dx, dz = enemy.x - bot.x, enemy.z - bot.z
				local d = math.sqrt(dx * dx + dz * dz)
				local clear = Maze.lineOfSight(maze, bot.x, bot.z, enemy.x, enemy.z)
				if (clear and d <= SENSE_CELLS) or (enemy.moving and d <= HEAR_CELLS) then
					local cell = Maze.cellOf(maze, enemy.x, enemy.z)
					local dangerous = false
					if
						d < avoidDistance
						and not (enemy.kind == "stalker" and enemy.state ~= "hunt")
					then
						avoidX, avoidZ, avoidDistance = enemy.x, enemy.z, d
					end
					-- Something close in a straight line but a long walk away (behind a wall) is
					-- not worth hiding from, so nearness to hide from needs a short path too.
					hereDist = hereDist or Maze.distances(maze, hereCell)
					local reachable = (hereDist :: { [number]: number })[indexOf(cell)]
						<= HIDE_PATH_CELLS
					if enemy.kind == "listener" then
						heardX, heardZ, heardAt = enemy.x, enemy.z, elapsed
						if reachable or enemy.state == "hunt" then
							nearListener = math.min(nearListener, d)
						end
						-- Walking is audible to a Listener a cell away, so its surroundings are
						-- off limits even when the bot is taking risks.
						for _, around in
							{ cell, table.unpack(Maze.neighbors(maze, cell.x, cell.y)) }
						do
							blocked[indexOf(around)] = true
							occupied[indexOf(around)] = true
						end
					elseif enemy.kind == "stalker" then
						-- A hunting Stalker is faced and scanned whether or not it is in view yet,
						-- so it is pinned the moment it rounds the corner.
						if enemy.state == "hunt" and d < stalkerDistance then
							stalkerInSight = enemy
							stalkerDistance = d
						end
					elseif enemy.kind == "mimic" then
						if not enemy.disguised and enemy.state ~= "return" then
							spotsMimic[enemy.id] = true
							dangerous = true
							nearChaser = math.min(nearChaser, d)
						elseif spotsMimic[enemy.id] then
							mimicPosts[enemy.id] = enemy.home -- it never moves while disguised
						end
					elseif enemy.state == "chase" or enemy.state == "investigate" then
						heardX, heardZ, heardAt = enemy.x, enemy.z, elapsed
						dangerous = true
						nearHunter = math.min(nearHunter, d)
					else
						heardX, heardZ, heardAt = enemy.x, enemy.z, elapsed
						-- A patrolling Wanderer cannot sense a silent walker: just keep out of
						-- its cell and press into the wall when it comes close.
						if reachable then
							nearPatrol = math.min(nearPatrol, d)
						end
						blocked[indexOf(cell)] = true
						occupied[indexOf(cell)] = true
					end
					if dangerous then
						table.insert(dangers, enemy)
						unsafe[indexOf(cell)] = true
						blocked[indexOf(cell)] = true
						for _, neighbor in Maze.neighbors(maze, cell.x, cell.y) do
							blocked[indexOf(neighbor)] = true
						end
					end
				end
			end
			-- Mimics the bot has seen through stay on its map whether or not they are in view.
			for _, post in mimicPosts do
				occupied[indexOf(post)] = true
				blocked[indexOf(post)] = true
				for _, neighbor in Maze.neighbors(maze, post.x, post.y) do
					blocked[indexOf(neighbor)] = true
				end
			end
			for index in occupied do
				unsafe[index] = true
			end
			blocked[indexOf(hereCell)] = nil
			occupied[indexOf(hereCell)] = nil
			unsafe[indexOf(hereCell)] = nil

			-- Decide what to do this step.
			local speed = walk
			local mode = "explore"
			-- Pinning a Stalker means standing still with the beam on. With a Listener or a
			-- hunting Wanderer almost on top of the bot that is fatal, so then it runs instead.
			local canStare = stalkerInSight ~= nil
				and nearListener > STARE_SAFE_CELLS
				and nearHunter > STARE_SAFE_CELLS
			if stalkerInSight ~= nil and not canStare then
				table.insert(dangers, stalkerInSight)
				nearChaser = math.min(nearChaser, stalkerDistance)
				local cell = Maze.cellOf(maze, stalkerInSight.x, stalkerInSight.z)
				if indexOf(cell) ~= indexOf(hereCell) then
					unsafe[indexOf(cell)] = true
				end
			end
			if nearChaser <= FLEE_CELLS then
				fleeTimer = FLEE_SECONDS
			end
			if canStare then
				mode = "stare"
				fleeTimer = 0
			elseif fleeTimer > 0 then
				mode = "flee"
				fleeTimer -= DT
			elseif nearHunter <= EVADE_CELLS then
				mode = "evade"
			elseif
				nearListener
					<= (if lastMode == "hide" then LISTENER_CLEAR_CELLS else LISTENER_HIDE_CELLS)
				or nearPatrol <= PATROL_HIDE_CELLS
			then
				mode = "hide"
			elseif #dangers > 0 or nearListener <= QUIET_CELLS or nearPatrol <= QUIET_CELLS then
				mode = "sneak"
			elseif elapsed - heardAt <= MEMORY_SECONDS then
				-- Something that follows scans was here a moment ago: keep the scanner off nearby.
				local dx, dz = heardX - bot.x, heardZ - bot.z
				if dx * dx + dz * dz <= MEMORY_CELLS ^ 2 then
					mode = "sneak"
				end
			end
			lastMode = mode
			bot.scanning = mode == "stare" or mode == "explore"
			bot.focusing = mode == "stare" -- the focused beam pins it fastest
			if risk > 0 then
				risk -= DT
			end

			replan -= DT
			if mode == "stare" or mode == "hide" then
				path = {}
			elseif #path == 0 or replan <= 0 then
				replan = REPLAN_SECONDS
				local route: { Maze.Cell }? = nil
				if mode == "flee" or mode == "evade" then
					route = retreatRoute(unsafe, dangers)
				else
					route = wantedRoute(if risk > 0 then occupied else blocked)
					if route == nil then
						if #dangers == 0 and next(blocked) == nil then
							return {
								cleared = false,
								stuck = true,
								seconds = elapsed,
								deaths = deaths,
								collected = collected,
								modeSeconds = modeSeconds,
							}
						end
						-- Blocked: wait where we are. Silent and still is safe unless bumped into.
						stall += REPLAN_SECONDS
						if stall >= PATIENCE_SECONDS then
							stall = 0
							risk = RISK_SECONDS
						end
					else
						stall = 0
					end
				end
				path = route or {}
			end
			-- Never walk into the back of something: stop short and wait for it to move on.
			if (mode == "sneak" or mode == "explore") and #path > 0 then
				local nextIndex = indexOf(path[1])
				if (if risk > 0 then occupied else blocked)[nextIndex] then
					path = {}
				end
			end
			-- Cornered while being followed: press into the wall and hope it loses the trail.
			if mode == "evade" and #path == 0 then
				mode = "hide"
			end
			modeSeconds[mode] = (modeSeconds[mode] or 0) + DT

			-- Move.
			local moved = 0
			if mode == "flee" then
				speed = sprint
			end
			if
				mode == "hide"
				and nearListener > LISTENER_FREEZE_CELLS
				and nearHunter > HUNTER_FREEZE_CELLS
			then
				local tx, tz = hereCell.x - 0.5 - HIDE_OFFSET, hereCell.y - 0.5 - HIDE_OFFSET
				local dx, dz = tx - bot.x, tz - bot.z
				local d = math.sqrt(dx * dx + dz * dz)
				local budget = walk / cellSize * DT
				if d > budget then
					bot.x += dx / d * budget
					bot.z += dz / d * budget
					moved = walk
				else
					bot.x, bot.z = tx, tz
				end
			elseif mode ~= "hide" and #path > 0 then
				local budget = speed / cellSize * DT
				local cell = path[1]
				local tx, tz = cell.x - 0.5, cell.y - 0.5
				if avoidDistance <= LANE_CELLS then
					-- Hug the wall on the side away from the enemy while passing it.
					local ax, az = tx - (hereCell.x - 0.5), tz - (hereCell.y - 0.5)
					local length = math.sqrt(ax * ax + az * az)
					if length > 0 then
						local px, pz = -az / length, ax / length
						if px * (bot.x - avoidX) + pz * (bot.z - avoidZ) < 0 then
							px, pz = -px, -pz
						end
						tx += px * LANE_OFFSET
						tz += pz * LANE_OFFSET
					end
				end
				local dx, dz = tx - bot.x, tz - bot.z
				local d = math.sqrt(dx * dx + dz * dz)
				if d > 0 then
					bot.lookX, bot.lookZ = dx / d, dz / d
				end
				if d <= budget then
					bot.x, bot.z = tx, tz
					table.remove(path, 1)
				else
					bot.x += dx / d * budget
					bot.z += dz / d * budget
				end
				moved = speed
			end
			if stalkerInSight ~= nil and bot.scanning then
				bot.lookX, bot.lookZ = stalkerInSight.x - bot.x, stalkerInSight.z - bot.z
			end
			local here = Maze.cellOf(maze, bot.x, bot.z)
			local hereIndex = indexOf(here)
			bot.noise =
				Noise.radius(moved, bot.scanning, bot.focusing, plan.flooded[hereIndex] == true, 0)

			-- Pick up whatever is in this cell; leave through the exit when allowed.
			for id, objective in remaining do
				if indexOf(objective.cell) == hereIndex then
					remaining[id] = nil
					collected += 1
					if objective.kind == "key" then
						hasKey = true
					end
				end
			end
			if hasKey and hereIndex == exitIndex then
				return {
					cleared = true,
					stuck = false,
					seconds = elapsed,
					deaths = deaths,
					collected = collected,
					modeSeconds = modeSeconds,
				}
			end
		end

		for _, enemy in enemies do
			if EnemyBrain.step(enemy, maze, sources, DT, rng, cellSize) ~= nil then
				spotsMimic[enemy.id] = true -- once bitten, the bot recognises this one
				if trace then
					trace(
						string.format(
							"t=%.1f caught by %s (%s) at %.2f,%.2f mode=%s scanning=%s",
							elapsed,
							enemy.kind,
							enemy.state,
							bot.x,
							bot.z,
							lastMode,
							tostring(bot.scanning)
						)
					)
				end
				resetAfterCatch()
				break
			end
		end
	end

	return {
		cleared = false,
		stuck = false,
		seconds = elapsed,
		deaths = deaths,
		collected = collected,
		modeSeconds = modeSeconds,
	}
end

return Sim
