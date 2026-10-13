--!strict
-- Runs the enemies of the current level. All decisions come from the pure EnemyBrain state
-- machines stepped at a fixed rate; this module only feeds them player positions, moves the
-- models to match, and reports catches. Enemies never use physics or PathfindingService:
-- they walk the maze graph, which is cheap and cannot get stuck on geometry.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local EnemyBrain = require(ReplicatedStorage.Shared.pure.EnemyBrain)
local Figures = require(script.Parent.Figures)
local Maze = require(ReplicatedStorage.Shared.pure.Maze)
local Rng = require(ReplicatedStorage.Shared.pure.Rng)
local World = require(script.Parent.World)

type Runtime = {
	brain: EnemyBrain.Enemy,
	model: Model,
	restCFrame: CFrame?, -- where a disguised Mimic sits, against a wall like a real surveyor
	revealed: boolean,
}

type Session = {
	level: World.Level,
	rng: Rng.Rng,
	getSources: () -> { EnemyBrain.Source },
	onCaught: (enemy: EnemyBrain.Enemy, sourceId: number) -> (),
	runtimes: { Runtime },
}

local CELL = Config.World.cellSize
local STEP = 1 / Config.Enemy.tickHz
local MAX_STEPS_PER_FRAME = 3
local MIMIC_REVEALED_SCALE = 1.35
local REST_FROM_WALL = 1.9
local SEED_SALT = 911

local BUILDERS: { [string]: (parent: Instance, tag: string?) -> Model } = {
	wanderer = Figures.wanderer,
	listener = Figures.listener,
	mimic = Figures.sitting,
	stalker = Figures.stalker,
}

local Enemies = {}

local session: Session? = nil
local accumulator = 0

local function place(runtime: Runtime, origin: Vector3)
	local brain = runtime.brain
	local root = runtime.model.PrimaryPart :: BasePart
	local disguisedAtRest = brain.kind == "mimic"
		and (brain.state == "disguised" or brain.state == "cooldown")
	if disguisedAtRest and runtime.restCFrame then
		root.CFrame = runtime.restCFrame
	else
		local position = origin + Vector3.new(brain.x * CELL, 0, brain.z * CELL)
		root.CFrame = CFrame.lookAt(position, position + Vector3.new(brain.faceX, 0, brain.faceZ))
	end

	local model = runtime.model
	if model:GetAttribute("Moving") ~= brain.moving then
		model:SetAttribute("Moving", brain.moving)
	end
	if model:GetAttribute("Frozen") ~= brain.frozen then
		model:SetAttribute("Frozen", brain.frozen)
	end
	if brain.kind == "mimic" then
		local revealed = not brain.disguised
		if revealed ~= runtime.revealed then
			runtime.revealed = revealed
			if revealed then
				CollectionService:RemoveTag(model, Config.Tags.disguised)
				model:ScaleTo(MIMIC_REVEALED_SCALE)
			else
				CollectionService:AddTag(model, Config.Tags.disguised)
				model:ScaleTo(1)
			end
		end
	end
end

-- Spawns the level's enemies and starts stepping them.
function Enemies.spawn(
	level: World.Level,
	getSources: () -> { EnemyBrain.Source },
	onCaught: (enemy: EnemyBrain.Enemy, sourceId: number) -> ()
)
	Enemies.clear()
	local plan = level.plan
	local folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = level.model
	local runtimes: { Runtime } = {}
	for _, spawn in plan.enemies do
		local brain = EnemyBrain.new(
			spawn.id,
			spawn.kind,
			spawn.cell,
			plan.def.enemySpeedScale,
			plan.def.enemySenseScale
		)
		local model = BUILDERS[spawn.kind](folder, Config.Tags.enemy)
		model.Name = spawn.kind .. spawn.id
		model:SetAttribute("Kind", spawn.kind)
		local runtime: Runtime = { brain = brain, model = model, restCFrame = nil, revealed = true }
		if spawn.kind == "mimic" then
			-- Sit with its back to a wall of its cell, exactly as a rescuable surveyor does.
			local center = World.cellCenter(level.origin, spawn.cell)
			for _, name in Maze.DIR_NAMES do
				if not Maze.isOpen(plan.maze, spawn.cell.x, spawn.cell.y, name) then
					local d = Maze.DIRS[name]
					local outward = Vector3.new(d.dx, 0, d.dy)
					local seat = center + outward * (CELL / 2 - REST_FROM_WALL)
					runtime.restCFrame = CFrame.lookAt(seat, seat - outward)
					break
				end
			end
		end
		place(runtime, level.origin)
		table.insert(runtimes, runtime)
	end
	session = {
		level = level,
		rng = Rng.new(plan.seed + SEED_SALT),
		getSources = getSources,
		onCaught = onCaught,
		runtimes = runtimes,
	}
	accumulator = 0
end

function Enemies.clear()
	session = nil
end

-- Sends every enemy back to its post: used when a solo player (or the whole party) respawns.
function Enemies.resetAll()
	local current = session
	if current == nil then
		return
	end
	for _, runtime in current.runtimes do
		EnemyBrain.reset(runtime.brain)
		place(runtime, current.level.origin)
	end
end

function Enemies.stun(enemy: EnemyBrain.Enemy)
	EnemyBrain.stun(enemy)
end

local function step()
	local current = session
	if current == nil then
		return
	end
	local sources = current.getSources()
	if #sources == 0 then
		return
	end
	local maze = current.level.plan.maze
	for _, runtime in current.runtimes do
		local caught = EnemyBrain.step(runtime.brain, maze, sources, STEP, current.rng, CELL)
		place(runtime, current.level.origin)
		if caught ~= nil then
			current.onCaught(runtime.brain, caught)
			if session ~= current then
				return -- the catch ended or reset the level
			end
		end
	end
end

function Enemies.start()
	RunService.Heartbeat:Connect(function(dt: number)
		if session == nil then
			return
		end
		accumulator = math.min(accumulator + dt, STEP * MAX_STEPS_PER_FRAME)
		while accumulator >= STEP do
			accumulator -= STEP
			step()
		end
	end)
end

return Enemies
