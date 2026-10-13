--!strict
-- Turns a LevelPlan into parts: floor, ceiling, merged wall runs, the exit door, landmarks,
-- flooded cells, objective pickups and anomaly rooms. Nothing here decides gameplay; it only
-- builds what the plan describes and hands back the pieces the Director needs to wire up.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Config = require(ReplicatedStorage.Shared.Config)
local Figures = require(script.Parent.Figures)
local LevelPlan = require(ReplicatedStorage.Shared.pure.LevelPlan)
local Maze = require(ReplicatedStorage.Shared.pure.Maze)
local Props = require(script.Parent.Props)
local Rng = require(ReplicatedStorage.Shared.pure.Rng)

export type Pickup = { objective: LevelPlan.Objective, model: Model, prompt: ProximityPrompt }
export type Level = {
	model: Model,
	origin: Vector3,
	plan: LevelPlan.LevelPlan,
	startCFrame: CFrame,
	exitDoor: BasePart,
	exitPrompt: ProximityPrompt,
	pickups: { Pickup },
	beaconPosition: Vector3,
}

local CELL = Config.World.cellSize
local HEIGHT = Config.World.wallHeight
local THICK = Config.World.wallThickness
local HALF = CELL / 2
local INNER = HALF - THICK / 2 -- distance from a cell centre to the inside face of its walls

local WALL_COLOR = Color3.fromRGB(86, 88, 80)
local FLOOR_COLOR = Color3.fromRGB(58, 56, 52)
local CEILING_COLOR = Color3.fromRGB(70, 70, 68)
local WATER_COLOR = Color3.fromRGB(30, 60, 70)
local DOOR_COLOR = Color3.fromRGB(120, 96, 60)
local GOLD = Color3.fromRGB(210, 170, 70)

local SPAWN_HEIGHT = 3
local DOOR_SIZE = Vector3.new(5, 8.4, 0.5)
local PILLAR_SIZE = 2.2
local WATER_DEPTH = 0.35
local GRATE_BARS = 7
local GRATE_SPACING = 1.3
local SEED_SALT = 5381

local SIDES = {
	N = Vector3.new(0, 0, -1),
	S = Vector3.new(0, 0, 1),
	E = Vector3.new(1, 0, 0),
	W = Vector3.new(-1, 0, 0),
}

local World = {}

-- World position of a cell centre at floor level.
function World.cellCenter(origin: Vector3, cell: Maze.Cell): Vector3
	return origin + Vector3.new((cell.x - 0.5) * CELL, 0, (cell.y - 0.5) * CELL)
end

-- A CFrame on the inside face of a cell's wall, looking into the cell: the base for wall props.
local function wallBase(center: Vector3, side: string): CFrame
	local direction = SIDES[side]
	local point = center + direction * INNER
	return CFrame.lookAt(point, point - direction)
end

local function closedSides(maze: Maze.Maze, cell: Maze.Cell): { string }
	local list = {}
	for _, name in Maze.DIR_NAMES do
		if not Maze.isOpen(maze, cell.x, cell.y, name) then
			table.insert(list, name)
		end
	end
	return list
end

local function buildShell(plan: LevelPlan.LevelPlan, origin: Vector3, parent: Instance)
	local maze = plan.maze
	local width, depth = maze.width * CELL, maze.height * CELL
	local middle = origin + Vector3.new(width / 2, 0, depth / 2)
	Build.part({
		name = "Floor",
		size = Vector3.new(width + THICK, 1, depth + THICK),
		cframe = CFrame.new(middle + Vector3.new(0, -0.5, 0)),
		color = FLOOR_COLOR,
		parent = parent,
	})
	Build.part({
		name = "Ceiling",
		size = Vector3.new(width + THICK, 1, depth + THICK),
		cframe = CFrame.new(middle + Vector3.new(0, HEIGHT + 0.5, 0)),
		color = CEILING_COLOR,
		parent = parent,
	})

	local walls = Build.model("Walls", parent)
	local function wall(size: Vector3, position: Vector3)
		Build.part({
			name = "Wall",
			size = size,
			cframe = CFrame.new(origin + position),
			color = WALL_COLOR,
			parent = walls,
		})
	end

	-- Horizontal wall lines (running east-west). Line `row` lies south of maze row `row`.
	for row = 0, maze.height do
		local runStart: number? = nil
		for x = 1, maze.width + 1 do
			local closed = x <= maze.width
				and (row == 0 or row == maze.height or not Maze.isOpen(maze, x, row, "S"))
			if closed and runStart == nil then
				runStart = x
			elseif not closed and runStart ~= nil then
				local length = (x - runStart) * CELL
				wall(
					Vector3.new(length + THICK, HEIGHT, THICK),
					Vector3.new((runStart - 1) * CELL + length / 2, HEIGHT / 2, row * CELL)
				)
				runStart = nil
			end
		end
	end
	-- Vertical wall lines (running north-south). Line `column` lies east of maze column `column`.
	for column = 0, maze.width do
		local runStart: number? = nil
		for y = 1, maze.height + 1 do
			local closed = y <= maze.height
				and (column == 0 or column == maze.width or not Maze.isOpen(maze, column, y, "E"))
			if closed and runStart == nil then
				runStart = y
			elseif not closed and runStart ~= nil then
				local length = (y - runStart) * CELL
				wall(
					Vector3.new(THICK, HEIGHT, length + THICK),
					Vector3.new(column * CELL, HEIGHT / 2, (runStart - 1) * CELL + length / 2)
				)
				runStart = nil
			end
		end
	end

	-- Open rooms get a pillar at each interior corner, so they read as pillar halls.
	for _, room in maze.rooms do
		for vx = room.x, room.x + room.w - 2 do
			for vy = room.y, room.y + room.h - 2 do
				Build.part({
					name = "Pillar",
					size = Vector3.new(PILLAR_SIZE, HEIGHT, PILLAR_SIZE),
					cframe = CFrame.new(origin + Vector3.new(vx * CELL, HEIGHT / 2, vy * CELL)),
					color = WALL_COLOR,
					parent = walls,
				})
			end
		end
	end
end

local function buildGrating(center: Vector3, parent: Instance)
	local model = Build.model("Grating", parent)
	local span = (GRATE_BARS - 1) * GRATE_SPACING
	for i = 0, GRATE_BARS - 1 do
		Build.part({
			name = "Bar",
			size = Vector3.new(0.25, 0.14, span + 1),
			cframe = CFrame.new(center + Vector3.new(i * GRATE_SPACING - span / 2, 0.07, 0)),
			color = Color3.fromRGB(40, 42, 44),
			material = Enum.Material.Metal,
			collide = false,
			parent = model,
		})
	end
	for _, z in { -span / 2 - 0.4, span / 2 + 0.4 } do
		Build.part({
			name = "Frame",
			size = Vector3.new(span + 1, 0.2, 0.4),
			cframe = CFrame.new(center + Vector3.new(0, 0.1, z)),
			color = Color3.fromRGB(40, 42, 44),
			material = Enum.Material.Metal,
			collide = false,
			parent = model,
		})
	end
end

local function buildArch(center: Vector3, alongX: boolean, parent: Instance)
	local model = Build.model("Arch", parent)
	local across = if alongX then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
	local reach = INNER - 1
	for _, sign in { -1, 1 } do
		Build.part({
			name = "Post",
			size = Vector3.new(1.6, HEIGHT - 2, 1.6),
			cframe = CFrame.new(
				center + across * (sign * reach) + Vector3.new(0, (HEIGHT - 2) / 2, 0)
			),
			color = WALL_COLOR,
			parent = model,
		})
	end
	Build.part({
		name = "Lintel",
		size = if alongX
			then Vector3.new(1.6, 2, CELL - THICK)
			else Vector3.new(CELL - THICK, 2, 1.6),
		cframe = CFrame.new(center + Vector3.new(0, HEIGHT - 1, 0)),
		color = WALL_COLOR,
		parent = model,
	})
end

local function buildVent(center: Vector3, alongX: boolean, parent: Instance)
	local model = Build.model("Vent", parent)
	Build.part({
		name = "Duct",
		size = if alongX
			then Vector3.new(CELL - THICK, 1.8, 3)
			else Vector3.new(3, 1.8, CELL - THICK),
		cframe = CFrame.new(center + Vector3.new(0, HEIGHT - 0.9, 0)),
		color = Color3.fromRGB(96, 100, 104),
		material = Enum.Material.Metal,
		collide = false,
		parent = model,
	})
	Build.part({
		name = "Grille",
		size = Vector3.new(2.4, 1.2, 2.4),
		cframe = CFrame.new(center + Vector3.new(0, HEIGHT - 2.4, 0)),
		color = Color3.fromRGB(60, 62, 66),
		material = Enum.Material.DiamondPlate,
		collide = false,
		parent = model,
	})
end

local function addHum(prop: Model)
	local sound = Instance.new("Sound")
	sound.Name = "Hum"
	sound.SoundId = Config.Audio.air
	sound.Looped = true
	sound.PlaybackSpeed = 0.42
	sound.Volume = 0.35
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 6
	sound.RollOffMaxDistance = 55
	sound.Parent = prop.PrimaryPart
	sound:Play()
end

local function buildFeatures(
	plan: LevelPlan.LevelPlan,
	origin: Vector3,
	parent: Instance,
	rng: Rng.Rng
)
	local maze = plan.maze
	local features = Build.model("Landmarks", parent)
	local indices = {}
	for index in plan.features do
		table.insert(indices, index)
	end
	table.sort(indices)
	for _, index in indices do
		local kind = plan.features[index]
		local cell = Maze.cellAt(maze, index)
		local center = World.cellCenter(origin, cell)
		local closed = closedSides(maze, cell)
		local alongX = Maze.isOpen(maze, cell.x, cell.y, "E")
			or Maze.isOpen(maze, cell.x, cell.y, "W")
		if kind == "grating" or #closed == 0 then
			buildGrating(center, features)
		elseif kind == "arch" then
			buildArch(center, alongX, features)
		elseif kind == "vent" then
			buildVent(center, alongX, features)
		else
			local side = closed[rng:int(1, #closed)]
			local base = wallBase(center, side)
			if kind == "crates" then
				-- Tuck crates into a corner so the middle of the corridor stays clear.
				base *= CFrame.new(if rng:next() < 0.5 then -(INNER - 3.2) else INNER - 3.2, 0, 0)
			end
			local prop = Props.place(kind, base, features)
			if kind == "hum" then
				addHum(prop)
			end
		end
	end
end

local function buildWater(plan: LevelPlan.LevelPlan, origin: Vector3, parent: Instance)
	local water = Build.model("Water", parent)
	for index in plan.flooded do
		local center = World.cellCenter(origin, Maze.cellAt(plan.maze, index))
		local pool = Build.part({
			name = "Pool",
			size = Vector3.new(CELL - THICK, WATER_DEPTH, CELL - THICK),
			cframe = CFrame.new(center + Vector3.new(0, WATER_DEPTH / 2, 0)),
			color = WATER_COLOR,
			material = Enum.Material.Glass,
			collide = false,
			parent = water,
		})
		pool:SetAttribute("Flooded", true)
	end
end

-- The exit: a door set into a closed side of the exit cell (or free-standing if it has none).
local function buildExit(
	plan: LevelPlan.LevelPlan,
	origin: Vector3,
	parent: Instance
): (BasePart, ProximityPrompt)
	local maze = plan.maze
	local center = World.cellCenter(origin, maze.exit)
	local closed = closedSides(maze, maze.exit)
	local base: CFrame
	if #closed > 0 then
		base = wallBase(center, closed[1]) * CFrame.new(0, 0, -DOOR_SIZE.Z / 2)
	else
		base = CFrame.new(center)
	end
	local model = Build.model("Exit", parent)
	local door = Build.part({
		name = "ExitDoor",
		size = DOOR_SIZE,
		cframe = base * CFrame.new(0, DOOR_SIZE.Y / 2, 0),
		color = DOOR_COLOR,
		material = Enum.Material.Wood,
		tag = Config.Tags.objective,
		parent = model,
	})
	for _, x in { -DOOR_SIZE.X / 2 - 0.4, DOOR_SIZE.X / 2 + 0.4 } do
		Build.part({
			name = "Jamb",
			size = Vector3.new(0.8, DOOR_SIZE.Y + 0.8, 0.9),
			cframe = base * CFrame.new(x, (DOOR_SIZE.Y + 0.8) / 2, 0),
			color = WALL_COLOR,
			tag = Config.Tags.objective,
			parent = model,
		})
	end
	Build.part({
		name = "Header",
		size = Vector3.new(DOOR_SIZE.X + 1.6, 0.8, 0.9),
		cframe = base * CFrame.new(0, DOOR_SIZE.Y + 0.4, 0),
		color = WALL_COLOR,
		tag = Config.Tags.objective,
		parent = model,
	})
	Build.part({
		name = "Handle",
		size = Vector3.new(0.3, 0.9, 0.5),
		cframe = base * CFrame.new(DOOR_SIZE.X / 2 - 0.7, 4, -0.4),
		color = GOLD,
		material = Enum.Material.Metal,
		tag = Config.Tags.objective,
		parent = model,
	})
	local prompt = Build.prompt(door, "Open", "Exit", 0.4)
	return door, prompt
end

local function buildPickup(
	objective: LevelPlan.Objective,
	center: Vector3,
	face: CFrame,
	parent: Instance
): Pickup
	local model = Build.model("Pickup_" .. objective.kind, parent)
	local main: BasePart
	local prompt: ProximityPrompt
	if objective.kind == "rescue" then
		local figure = Figures.sitting(model, Config.Tags.friend)
		figure:PivotTo(face * CFrame.new(0, 0, -1.4))
		main = figure.PrimaryPart :: BasePart
		CollectionService:AddTag(figure, Config.Tags.rescue)
		prompt = Build.prompt(main, "Help up", "Surveyor", 1.5)
	else
		local stand = Build.part({
			name = "Stand",
			size = Vector3.new(1.6, 2.6, 1.6),
			cframe = CFrame.new(center + Vector3.new(0, 1.3, 0)),
			color = Color3.fromRGB(60, 60, 64),
			material = Enum.Material.Metal,
			tag = Config.Tags.objective,
			parent = model,
		})
		if objective.kind == "key" then
			main = Build.part({
				name = "Key",
				size = Vector3.new(0.3, 0.5, 1.5),
				cframe = CFrame.new(center + Vector3.new(0, 2.9, 0))
					* CFrame.Angles(0, math.rad(30), 0),
				color = GOLD,
				material = Enum.Material.Metal,
				collide = false,
				tag = Config.Tags.objective,
				parent = model,
			})
			Build.part({
				name = "Bow",
				size = Vector3.new(0.3, 0.9, 0.9),
				cframe = main.CFrame * CFrame.new(0, 0, 1),
				color = GOLD,
				material = Enum.Material.Metal,
				shape = Enum.PartType.Cylinder,
				collide = false,
				tag = Config.Tags.objective,
				parent = model,
			})
			prompt = Build.prompt(stand, "Take", "Key", 0.3)
		elseif objective.kind == "cell" then
			main = Build.part({
				name = "Cell",
				size = Vector3.new(1.8, 0.9, 0.9),
				cframe = CFrame.new(center + Vector3.new(0, 3.5, 0))
					* CFrame.Angles(0, 0, math.rad(90)),
				color = Color3.fromRGB(90, 200, 160),
				material = Enum.Material.Metal,
				shape = Enum.PartType.Cylinder,
				collide = false,
				tag = Config.Tags.objective,
				parent = model,
			})
			prompt = Build.prompt(stand, "Take", "Battery cell", 0.3)
		else -- plate
			main = Build.part({
				name = "Plate",
				size = Vector3.new(1.8, 1.2, 0.15),
				cframe = CFrame.new(center + Vector3.new(0, 3.1, 0))
					* CFrame.Angles(math.rad(-20), 0, 0),
				color = GOLD,
				material = Enum.Material.Metal,
				collide = false,
				tag = Config.Tags.objective,
				parent = model,
			})
			prompt = Build.prompt(stand, "Read", "Survey plate", 0.3)
		end
	end
	return { objective = objective, model = model, prompt = prompt }
end

-- Marks an anomaly room for clients and, for the upside-down room, hangs furniture overhead.
local function buildAnomaly(plan: LevelPlan.LevelPlan, origin: Vector3, parent: Instance)
	local anomaly = plan.anomaly
	if anomaly == nil then
		return
	end
	local room = anomaly.room
	local size = Vector3.new(room.w * CELL - THICK, HEIGHT, room.h * CELL - THICK)
	local center = origin
		+ Vector3.new(
			(room.x - 1 + room.w / 2) * CELL,
			HEIGHT / 2,
			(room.y - 1 + room.h / 2) * CELL
		)
	local zone = Build.part({
		name = "Anomaly",
		size = size,
		cframe = CFrame.new(center),
		transparency = 1,
		collide = false,
		query = false,
		tag = Config.Tags.anomaly,
		parent = parent,
	})
	zone:SetAttribute("Kind", anomaly.kind)
	if anomaly.kind == "upside_down" then
		-- Furniture bolted to the ceiling, the right way up for someone standing on it.
		local flip = CFrame.new(center + Vector3.new(0, HEIGHT / 2, 0))
			* CFrame.Angles(math.pi, 0, 0)
		Props.place("desk", flip * CFrame.new(-3, 0, 2), parent)
		Props.place("chair", flip * CFrame.new(-3, 0, 5.5) * CFrame.Angles(0, math.pi, 0), parent)
		Props.place("shelf", flip * CFrame.new(4, 0, 1), parent)
		Props.place("table", flip * CFrame.new(3, 0, -4), parent)
		Props.place("cabinet", flip * CFrame.new(-5, 0, -3), parent)
	end
end

function World.buildLevel(plan: LevelPlan.LevelPlan, origin: Vector3): Level
	local maze = plan.maze
	local rng = Rng.new(plan.seed + SEED_SALT)
	local model = Build.model("Level", workspace)
	model:SetAttribute("Tier", plan.tier)
	model:SetAttribute("Seed", plan.seed)

	buildShell(plan, origin, model)
	buildFeatures(plan, origin, model, rng)
	buildWater(plan, origin, model)
	buildAnomaly(plan, origin, model)
	local exitDoor, exitPrompt = buildExit(plan, origin, model)

	local pickups: { Pickup } = {}
	for _, objective in plan.objectives do
		local center = World.cellCenter(origin, objective.cell)
		local closed = closedSides(maze, objective.cell)
		local face = if #closed > 0 then wallBase(center, closed[1]) else CFrame.new(center)
		table.insert(pickups, buildPickup(objective, center, face, model))
	end

	-- Face the player down an open passage from the start cell.
	local startCenter = World.cellCenter(origin, maze.start)
	local lookAt = startCenter + Vector3.new(0, 0, 1)
	for _, name in Maze.DIR_NAMES do
		if Maze.isOpen(maze, maze.start.x, maze.start.y, name) then
			lookAt = startCenter + SIDES[name]
			break
		end
	end
	local spawnPoint = startCenter + Vector3.new(0, SPAWN_HEIGHT, 0)

	return {
		model = model,
		origin = origin,
		plan = plan,
		startCFrame = CFrame.lookAt(spawnPoint, lookAt + Vector3.new(0, SPAWN_HEIGHT, 0)),
		exitDoor = exitDoor,
		exitPrompt = exitPrompt,
		pickups = pickups,
		beaconPosition = World.cellCenter(origin, plan.beaconCell)
			+ Vector3.new(0, SPAWN_HEIGHT, 0),
	}
end

return World
