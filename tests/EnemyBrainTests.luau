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
		focusing = false,
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

tests["wanderer patrols near its post and ignores a silent distant player"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "wanderer", { x = 6, y = 6 }, 1, 1)
	local player = source(0.5, 0.5)
	local moved = false
	local caught = run(enemy, maze, { player }, 60, function()
		moved = moved or enemy.moving
		assert(
			enemy.state == "patrol",
			"wanderer left patrol with nothing to sense: " .. enemy.state
		)
		assert(
			math.abs(enemy.x - 5.5) <= Config.Enemy.patrolRadius + 1,
			"wanderer strayed from its post"
		)
	end)
	assert(caught == nil, "caught a player it could not sense")
	assert(moved, "wanderer never moved")
end

tests["wanderer investigates noise, then gives up and resumes patrol"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "wanderer", { x = 2, y = 2 }, 1, 1)
	local player = source(5.5, 1.5)
	player.noise = 5
	run(enemy, maze, { player }, 1)
	assert(enemy.state == "investigate", "expected investigate, got " .. enemy.state)
	player.noise = 0
	player.x, player.z = 9.5, 5.5
	run(enemy, maze, { player }, 40)
	assert(enemy.state == "patrol", "expected patrol after the search, got " .. enemy.state)
end

tests["wanderer sees a scanning player down a clear line but not a quiet one"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "wanderer", { x = 2, y = 2 }, 1, 1)
	local player = source(4.4, 1.5)
	run(enemy, maze, { player }, 0.5)
	assert(enemy.state == "patrol", "noticed a silent, non-scanning player")
	player.scanning = true
	run(enemy, maze, { player }, 0.5)
	assert(enemy.state ~= "patrol", "did not notice a scanning player in plain sight")
end

tests["wanderer catches a player who stands still nearby"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "wanderer", { x = 2, y = 2 }, 1, 1)
	local player = source(3.2, 1.5)
	player.noise = 2
	local caught = run(enemy, maze, { player }, 30)
	assert(caught == 1, "wanderer never caught a stationary noisy player")
end

tests["wanderer loses a player who simply walks away"] = function()
	local maze = arena(18)
	local enemy = EnemyBrain.new(1, "wanderer", { x = 2, y = 2 }, 1, 1)
	local player = source(3.4, 1.5)
	player.noise = Config.Noise.walk
	player.scanning = true
	run(enemy, maze, { player }, 0.6)
	assert(enemy.state == "chase", "expected a chase to start, got " .. enemy.state)
	player.scanning = false
	local caught = run(enemy, maze, { player }, 40, function()
		player.x = math.min(player.x + WALK * DT, 17.5)
	end)
	assert(caught == nil, "a walking player was caught by a slower wanderer")
	assert(enemy.state ~= "chase", "wanderer never gave up the chase")
end

tests["wanderer loses a player who goes quiet and steps aside"] = function()
	local maze = arena(18)
	local enemy = EnemyBrain.new(1, "wanderer", { x = 4, y = 4 }, 1, 1)
	local player = source(5.3, 3.5)
	player.noise = 2
	run(enemy, maze, { player }, 0.6)
	assert(enemy.state == "chase", "expected a chase to start, got " .. enemy.state)
	-- Go silent and move a short way off the spot the wanderer last sensed.
	player.noise = 0
	player.x, player.z = 5.75, 3.95
	local reachedLastSpot = false
	local caught = run(enemy, maze, { player }, 30, function()
		reachedLastSpot = reachedLastSpot
			or (math.abs(enemy.x - 5.3) < 0.05 and math.abs(enemy.z - 3.5) < 0.05)
	end)
	assert(reachedLastSpot, "wanderer did not walk to the last place it sensed the player")
	assert(caught == nil, "wanderer caught a silent player who had stepped aside")
	assert(enemy.state == "patrol", "wanderer did not give up, state " .. enemy.state)
end

tests["listener ignores a silent player and hunts a loud one"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "listener", { x = 2, y = 2 }, 1, 1)
	local player = source(4.5, 4.5)
	player.scanning = true -- scanning is seen, not heard: the listener is blind
	run(enemy, maze, { player }, 5, function()
		assert(enemy.state ~= "hunt", "blind listener reacted to a silent scan")
	end)
	player.noise = Config.Noise.sprint
	run(enemy, maze, { player }, 0.5)
	assert(enemy.state == "hunt", "listener did not hunt sprint noise")
end

tests["listener goes to the noise, listens, then drifts away"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "listener", { x = 2, y = 2 }, 1, 1)
	local player = source(6.5, 1.5)
	player.noise = 5
	run(enemy, maze, { player }, 0.5)
	player.noise = 0
	player.x, player.z = 6.5, 1.9 -- stepped to the side of the corridor and went quiet
	local sawListen = false
	local caught = run(enemy, maze, { player }, 30, function()
		sawListen = sawListen or enemy.state == "listen"
	end)
	assert(sawListen, "listener never stopped to listen")
	assert(enemy.state == "drift", "listener did not return to drifting, got " .. enemy.state)
	assert(caught == nil, "listener caught a player who went quiet and stepped aside")
end

tests["listener catches a player who keeps making noise"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "listener", { x = 2, y = 2 }, 1, 1)
	local player = source(6.5, 1.9)
	player.noise = Config.Noise.focus
	local caught = run(enemy, maze, { player }, 30)
	assert(caught == 1, "listener failed to catch a constantly noisy player")
end

tests["a decoy lures a listener but can never be caught"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "listener", { x = 2, y = 2 }, 1, 1)
	local player = source(1.5, 5.5)
	local decoy = source(5.5, 1.5)
	decoy.id = 2
	decoy.active = false
	decoy.decoy = true
	decoy.noise = Config.Noise.ping
	local caught = run(enemy, maze, { player, decoy }, 8)
	assert(caught == nil, "a decoy was caught")
	assert(
		math.abs(enemy.x - 5.5) < 0.6 and math.abs(enemy.z - 1.5) < 0.6,
		"listener did not go to the decoy"
	)
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

tests["stalker is pinned while scanned and advances when not"] = function()
	local maze = arena(12)
	local enemy = EnemyBrain.new(1, "stalker", { x = 6, y = 2 }, 1, 1)
	local player = source(1.5, 1.5)
	player.scanning = true
	player.lookX, player.lookZ = 1, 0 -- pointing straight at it
	run(enemy, maze, { player }, 1)
	assert(enemy.state == "hunt", "stalker did not wake")
	local before = enemy.x
	local caught = run(enemy, maze, { player }, 1.5)
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
	local enemy = EnemyBrain.new(1, "stalker", { x = 6, y = 2 }, 1, 1)
	local player = source(1.5, 1.5)
	run(enemy, maze, { player }, 2) -- let it wake and close in a little
	assert(enemy.state == "hunt" and enemy.x < 5.5, "stalker did not approach")
	player.scanning = true
	player.lookX, player.lookZ = 1, 0
	local caught = run(enemy, maze, { player }, Config.Enemy.stalkerStareSeconds + 0.5)
	assert(caught == nil, "caught while being stared down")
	assert(enemy.state == "withdraw", "stalker did not withdraw, state " .. enemy.state)
	player.scanning = false
	caught = run(enemy, maze, { player }, Config.Enemy.stalkerCooldown - 2)
	assert(caught == nil, "a withdrawn stalker caught someone")
	assert(enemy.state == "dormant" and enemy.x == 5.5, "stalker did not return to its post")
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
					EnemyBrain.observation(enemy, maze, { player }) == 0,
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
	player.noise = 3
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
			-- The player wanders along random routes, randomly loud and scanning.
			if #route == 0 then
				route = Maze.path(
					maze,
					Maze.cellOf(maze, player.x, player.z),
					{ x = rng:int(1, 9), y = rng:int(1, 9) }
				)
				player.noise = if rng:next() < 0.5 then 0 else rng:next() * 4
				player.scanning = rng:next() < 0.6
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
