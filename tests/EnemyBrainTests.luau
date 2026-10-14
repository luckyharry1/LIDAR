--!strict
-- Enemy decision logic as pure state machines fed with fake inputs.
local Config = require("../src/shared/Config")
local EnemyBrain = require("../src/shared/pure/EnemyBrain")
local Maze = require("../src/shared/pure/Maze")
local Rng = require("../src/shared/pure/Rng")

local CELL = Config.World.cellSize
local DT = 0.1
local WALK = Config.Player.walkSpeed / CELL -- cells per second

local tests: { [string]: () -> () } = {}

-- A fully open square arena: every interior wall removed.
local function arena(size: number): Maze.Maze
	return Maze.generate(1, size, size, { loopChance = 1, pruneChance = 0, rooms = 0 })
end

local function source(x: number, z: number): EnemyBrain.Source
	return {
		id = 1,
		x = x,
		z = z,
		noise = 0,
		scanning = false,
		crouching = false,
		lookX = 1,
		lookZ = 0,
		active = true,
		decoy = false,
	}
end

local function run(
	enemy: EnemyBrain.Enemy,
	maze: Maze.Maze,
	sources: { EnemyBrain.Source },
	seconds: number,
	each: ((number) -> ())?
): number?
	local rng = Rng.new(5)
	local elapsed = 0
	while elapsed < seconds do
		elapsed += DT
		if each then
			each(elapsed)
		end
		local caught = EnemyBrain.step(enemy, maze, sources, DT, rng, CELL)
		if caught ~= nil then
			return caught
		end
	end
	return nil
end

local function distanceTo(enemy: EnemyBrain.Enemy, s: EnemyBrain.Source): number
	return math.sqrt((enemy.x - s.x) ^ 2 + (enemy.z - s.z) ^ 2)
end

tests["roaming monsters cover the level and only pause briefly"] = function()
	for _, kind in { "wanderer", "listener" } do
		local maze = Maze.generate(11, 6, 6, { loopChance = 0.1, pruneChance = 0.5, rooms = 1 })
		local enemy = EnemyBrain.new(1, kind, { x = 4, y = 4 }, 1, 1)
		local player = source(0.05, 0.05) -- tucked into a corner, crouched and silent
		player.crouching = true
		local visited: { [number]: boolean } = {}
		local count = 0
		local longestPause, pause = 0, 0
		local caught = run(enemy, maze, { player }, 400, function()
			local cell = Maze.cellOf(maze, enemy.x, enemy.z)
			local index = Maze.index(maze, cell.x, cell.y)
			if not visited[index] then
				visited[index] = true
				count += 1
			end
			pause = if enemy.moving then 0 else pause + DT
			longestPause = math.max(longestPause, pause)
		end)
		assert(caught == nil, kind .. " caught a hidden player")
		assert(
			count >= 18,
			`{kind} only visited {count} of 36 cells: it lingers instead of roaming`
		)
		assert(
			longestPause <= enemy.def.lingerMax + 1,
			`{kind} stood still for {longestPause} seconds`
		)
		assert(longestPause >= enemy.def.lingerMin - DT, kind .. " never paused at all")
	end
end

tests["wanderer sees an upright player in its line of sight, but not a crouched one"] = function()
	local maze = arena(12)
	local upright = source(3.4, 1.5)
	local enemy = EnemyBrain.new(1, "wanderer", { x = 2, y = 2 }, 1, 1)
	run(enemy, maze, { upright }, 0.5)
	assert(
		enemy.state == "chase",
		"did not notice a player standing in plain sight: " .. enemy.state
	)

	local crouched = source(3.4, 1.5)
	crouched.crouching = true
	local other = EnemyBrain.new(1, "wanderer", { x = 2, y = 2 }, 1, 1)
	run(other, maze, { crouched }, 0.5)
	assert(other.state == "patrol", "noticed a crouched, silent player: " .. other.state)
end

tests["scattering dots at a wanderer does not give you away"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "wanderer", { x = 2, y = 2 }, 1, 1)
	local player = source(3.4, 1.5)
	player.crouching = true
	player.scanning = true
	run(enemy, maze, { player }, 0.5)
	assert(enemy.state == "patrol", "scanning alone alerted a wanderer")
end

tests["wanderer investigates noise, then gives up and resumes roaming"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "wanderer", { x = 2, y = 2 }, 1, 1)
	local player = source(5.5, 1.5)
	player.crouching = true
	player.noise = 5
	run(enemy, maze, { player }, 1)
	assert(enemy.state == "investigate", "expected investigate, got " .. enemy.state)
	player.noise = 0
	player.x, player.z = 9.95, 8.95
	run(enemy, maze, { player }, 30)
	assert(enemy.state == "patrol", "expected roaming after the search, got " .. enemy.state)
end

tests["wanderer catches a player who stands still nearby"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "wanderer", { x = 2, y = 2 }, 1, 1)
	local player = source(3.2, 1.5)
	local caught = run(enemy, maze, { player }, 30)
	assert(caught == 1, "wanderer never caught a player standing in front of it")
end

tests["wanderer loses a player who simply walks away"] = function()
	local maze = arena(18)
	local enemy = EnemyBrain.new(1, "wanderer", { x = 2, y = 2 }, 1, 1)
	local player = source(3.4, 1.5)
	run(enemy, maze, { player }, 0.6)
	assert(enemy.state == "chase", "expected a chase to start, got " .. enemy.state)
	local caught = run(enemy, maze, { player }, 24, function()
		player.x = math.min(player.x + WALK * DT, 17.95)
		player.z = math.min(player.z + WALK * DT * 0.02, 1.95)
		player.crouching = player.x >= 17.9 -- hide once there is nowhere left to walk
	end)
	assert(caught == nil, "a walking player was caught by a slower wanderer")
	assert(enemy.state ~= "chase", "wanderer never gave up the chase")
end

tests["wanderer loses a player who crouches and steps aside"] = function()
	local maze = arena(18)
	local enemy = EnemyBrain.new(1, "wanderer", { x = 4, y = 4 }, 1, 1)
	local player = source(5.3, 3.5)
	run(enemy, maze, { player }, 0.6)
	assert(enemy.state == "chase", "expected a chase to start, got " .. enemy.state)
	-- Crouch and move a short way off the spot the wanderer last saw.
	player.crouching = true
	player.x, player.z = 5.95, 3.95
	local reachedLastSpot = false
	local caught = run(enemy, maze, { player }, 12, function()
		reachedLastSpot = reachedLastSpot
			or (math.abs(enemy.x - 5.3) < 0.05 and math.abs(enemy.z - 3.5) < 0.05)
	end)
	assert(reachedLastSpot, "wanderer did not walk to the last place it saw the player")
	assert(caught == nil, "wanderer caught a crouched player who had stepped aside")
	assert(enemy.state ~= "chase", "wanderer kept chasing a player it could not sense")
end

tests["listener hunts a loud player and ignores a silent one beside it"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "listener", { x = 2, y = 2 }, 1, 1)
	local player = source(4.5, 4.5)
	player.scanning = true -- the listener is blind: standing and scanning is not a sound
	run(enemy, maze, { player }, 4, function()
		assert(enemy.state ~= "hunt", "blind listener reacted to something it could not hear")
	end)
	player.noise = Config.Noise.sprint
	run(enemy, maze, { player }, 0.5)
	assert(enemy.state == "hunt", "listener did not hunt sprint noise")
end

tests["listener goes to the noise, listens, then moves on"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "listener", { x = 2, y = 2 }, 1, 1)
	local player = source(6.5, 1.5)
	player.noise = 5
	run(enemy, maze, { player }, 0.5)
	player.noise = 0
	player.crouching = true
	player.x, player.z = 6.95, 1.95 -- stepped into the corner and went quiet
	local sawListen = false
	local caught = run(enemy, maze, { player }, 14, function()
		sawListen = sawListen or enemy.state == "listen"
	end)
	assert(sawListen, "listener never stopped to listen")
	assert(enemy.state == "drift", "listener did not go back to roaming, got " .. enemy.state)
	assert(caught == nil, "listener caught a player who went quiet and stepped aside")
end

tests["listener catches a player who keeps making noise"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "listener", { x = 2, y = 2 }, 1, 1)
	local player = source(6.5, 1.9)
	player.noise = Config.Noise.sweep
	local caught = run(enemy, maze, { player }, 30)
	assert(caught == 1, "listener failed to catch a constantly noisy player")
end

tests["a decoy lures a listener but can never be caught"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "listener", { x = 2, y = 2 }, 1, 1)
	local player = source(1.95, 5.95)
	player.crouching = true
	local decoy = source(5.5, 1.5)
	decoy.id = 2
	decoy.active = false
	decoy.decoy = true
	decoy.noise = Config.Noise.ping
	local reached = false
	local caught = run(enemy, maze, { player, decoy }, 8, function()
		reached = reached or (math.abs(enemy.x - 5.5) < 0.6 and math.abs(enemy.z - 1.5) < 0.6)
	end)
	assert(caught == nil, "a decoy was caught")
	assert(reached, "listener did not go to the decoy")
end

tests["mimic stays disguised until a player is close, then chases and returns"] = function()
	local maze = arena(18)
	local enemy = EnemyBrain.new(1, "mimic", { x = 16, y = 6 }, 1, 1)
	local player = source(12.5, 5.5)
	run(enemy, maze, { player }, 10)
	assert(enemy.disguised and enemy.state == "disguised", "mimic revealed itself at a distance")
	assert(not enemy.moving, "a disguised mimic should not move")

	player.x = 15.5 - 0.8
	run(enemy, maze, { player }, 0.4)
	assert(enemy.state == "reveal" and not enemy.disguised, "mimic did not reveal when approached")
	local before = enemy.x
	run(enemy, maze, { player }, Config.Enemy.mimicRevealDelay - 0.5)
	assert(
		enemy.x == before,
		"mimic moved during its reveal delay: the player gets no time to react"
	)

	-- The player sprints away; the chase is timed, so the mimic goes home.
	local sprint = Config.Player.sprintSpeed / CELL
	local caught = run(enemy, maze, { player }, 30, function()
		player.x = math.max(player.x - sprint * DT, 6.5)
	end)
	assert(caught == nil, "a sprinting player was caught by the mimic")
	assert(enemy.disguised, "mimic did not return to its disguise")
	assert(
		math.abs(enemy.x - 15.5) < 0.01 and math.abs(enemy.z - 5.5) < 0.01,
		"mimic did not return home"
	)
end

tests["mimic catches a player who walks instead of running"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "mimic", { x = 6, y = 6 }, 1, 1)
	local player = source(5.5 - 0.8, 5.5)
	local caught = run(enemy, maze, { player }, 20, function()
		player.x = math.max(player.x - WALK * DT, 0.5)
	end)
	assert(caught == 1, "walking away from a revealed mimic should not be enough")
end

tests["a mimic sits where it is told and returns there"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "mimic", { x = 6, y = 6 }, 1, 1)
	EnemyBrain.setRest(enemy, 5.5, 5.86)
	assert(enemy.x == 5.5 and enemy.z == 5.86, "rest position not applied")
	local player = source(5.5, 5.2)
	run(enemy, maze, { player }, 2)
	assert(not enemy.disguised, "mimic did not reveal")
	player.active = false
	run(enemy, maze, { player }, 20)
	assert(
		math.abs(enemy.x - 5.5) < 0.01 and math.abs(enemy.z - 5.86) < 0.01,
		"mimic did not return to its seat"
	)
end

tests["stalker is pinned while scanned and advances when not"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "stalker", { x = 5, y = 2 }, 1, 1)
	local player = source(1.5, 1.5)
	player.scanning = true
	player.lookX, player.lookZ = 1, 0 -- pointing straight at it
	run(enemy, maze, { player }, 1)
	assert(enemy.state == "hunt", "stalker did not wake")
	local before = enemy.x
	local caught = run(enemy, maze, { player }, 1)
	assert(enemy.frozen and enemy.x == before, "stalker moved while being scanned")
	assert(caught == nil, "a pinned stalker caught someone")

	player.lookX, player.lookZ = -1, 0 -- look away
	run(enemy, maze, { player }, 1)
	assert(not enemy.frozen and enemy.x < before, "stalker did not advance when unobserved")

	player.scanning = false
	caught = run(enemy, maze, { player }, 20)
	assert(caught == 1, "an unobserved stalker should reach a standing player")
end

tests["a stalker pinned long enough withdraws and stays away for a while"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "stalker", { x = 5, y = 2 }, 1, 1)
	local player = source(1.5, 1.5)
	run(enemy, maze, { player }, 1.5) -- let it wake and close in a little
	assert(enemy.state == "hunt" and enemy.x < 4.5, "stalker did not approach")
	player.scanning = true
	player.lookX, player.lookZ = 1, 0
	local caught = run(enemy, maze, { player }, Config.Enemy.stalkerStareSeconds + 0.5)
	assert(caught == nil, "caught while being stared down")
	assert(enemy.state == "withdraw", "stalker did not withdraw, state " .. enemy.state)
	player.scanning = false
	caught = run(enemy, maze, { player }, Config.Enemy.stalkerCooldown - 2)
	assert(caught == nil, "a withdrawn stalker caught someone")
	assert(enemy.state == "dormant" and enemy.x == 4.5, "stalker did not return to its post")
	caught = run(enemy, maze, { player }, 30)
	assert(caught == 1, "stalker never came back after its cooldown")
end

tests["stalker stays dormant when nobody is near"] = function()
	local maze = arena(16)
	local enemy = EnemyBrain.new(1, "stalker", { x = 14, y = 14 }, 1, 1)
	local player = source(0.5, 0.5)
	run(enemy, maze, { player }, 10)
	assert(enemy.state == "dormant" and enemy.x == 13.5, "a distant stalker woke up")
end

tests["a scan cannot pin a stalker through a wall"] = function()
	local maze = Maze.generate(3, 6, 6, { loopChance = 0, pruneChance = 0, rooms = 0 })
	-- Find two side-by-side cells with a wall between them.
	for y = 1, 6 do
		for x = 1, 5 do
			if not Maze.isOpen(maze, x, y, "E") then
				local enemy = EnemyBrain.new(1, "stalker", { x = x + 1, y = y }, 1, 1)
				local player = source(x - 0.5, y - 0.5)
				player.scanning = true
				assert(
					not EnemyBrain.isObserved(enemy, maze, { player }),
					"observed through a wall"
				)
				return
			end
		end
	end
	error("test maze had no interior wall")
end

tests["enemies ignore players who are inactive"] = function()
	local maze = arena(8)
	for _, kind in { "wanderer", "listener", "mimic", "stalker" } do
		local enemy = EnemyBrain.new(1, kind, { x = 3, y = 3 }, 1, 1)
		local player = source(2.6, 2.5)
		player.active = false
		player.noise = 5
		player.scanning = true
		local caught = run(enemy, maze, { player }, 10)
		assert(caught == nil, kind .. " caught an inactive player")
	end
end

tests["distant enemies sleep"] = function()
	local maze = arena(18)
	local enemy = EnemyBrain.new(1, "wanderer", { x = 17, y = 17 }, 1, 1)
	local player = source(0.5, 0.5)
	run(enemy, maze, { player }, 20)
	assert(enemy.x == 16.5 and enemy.z == 16.5, "an enemy beyond the sleep distance moved")
end

tests["a stunned enemy cannot catch until it recovers"] = function()
	local maze = arena(8)
	local enemy = EnemyBrain.new(1, "wanderer", { x = 3, y = 3 }, 1, 1)
	local player = source(2.5, 2.5)
	EnemyBrain.stun(enemy)
	local caught = run(enemy, maze, { player }, Config.Enemy.stunSeconds - 0.3)
	assert(caught == nil, "caught while stunned")
	caught = run(enemy, maze, { player }, 5)
	assert(caught == 1, "never recovered from the stun")
end

tests["reset returns an enemy to its post and first state"] = function()
	local maze = arena(8)
	local enemy = EnemyBrain.new(1, "mimic", { x = 4, y = 4 }, 1, 1)
	local player = source(3.2, 3.5)
	run(enemy, maze, { player }, 3)
	EnemyBrain.reset(enemy)
	assert(
		enemy.x == 3.5 and enemy.z == 3.5 and enemy.state == "disguised" and enemy.disguised,
		"reset incomplete"
	)
end

tests["fuzz: enemies never walk through walls, leave the maze or produce bad numbers"] = function()
	local kinds = { "wanderer", "listener", "mimic", "stalker" }
	for seed = 1, 40 do
		local maze = Maze.generate(seed, 9, 9, { loopChance = 0.08, pruneChance = 0.5, rooms = 2 })
		local rng = Rng.new(seed)
		local enemies = {}
		for i, kind in kinds do
			table.insert(
				enemies,
				EnemyBrain.new(i, kind, { x = rng:int(1, 9), y = rng:int(1, 9) }, 1, 1)
			)
		end
		local player = source(0.5, 0.5)
		local route: { Maze.Cell } = {}
		for _ = 1, 1500 do
			-- The player wanders along random routes, randomly loud, crouched and scanning.
			if #route == 0 then
				route = Maze.path(
					maze,
					Maze.cellOf(maze, player.x, player.z),
					{ x = rng:int(1, 9), y = rng:int(1, 9) }
				)
				player.noise = if rng:next() < 0.5 then 0 else rng:next() * 4
				player.scanning = rng:next() < 0.6
				player.crouching = rng:next() < 0.3
				player.lookX, player.lookZ = rng:next() - 0.5, rng:next() - 0.5
			end
			if #route > 0 then
				player.x, player.z = route[1].x - 0.5, route[1].y - 0.5
				table.remove(route, 1)
			end
			for _, enemy in enemies do
				local px, pz = enemy.x, enemy.z
				local caught = EnemyBrain.step(enemy, maze, { player }, DT, rng, CELL)
				assert(enemy.x == enemy.x and enemy.z == enemy.z, "position became NaN")
				assert(
					enemy.x >= 0 and enemy.x <= 9 and enemy.z >= 0 and enemy.z <= 9,
					"enemy left the maze"
				)
				assert(
					Maze.lineOfSight(maze, px, pz, enemy.x, enemy.z),
					`{enemy.kind} moved through a wall (seed {seed}, state {enemy.state})`
				)
				if caught ~= nil then
					assert(
						distanceTo(enemy, player) * CELL <= enemy.def.catchRadius + 0.001,
						"caught from too far away"
					)
					EnemyBrain.reset(enemy)
				end
			end
		end
	end
end

return tests
