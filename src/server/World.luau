--!strict
-- Turns a LevelPlan into parts. The maze is never drawn: its walls, floor, props and pickups
-- stop rays and feet but are invisible, so the only picture of a level is the dots a scanner
-- leaves on it, and those show through the walls. The exceptions are the few things that
-- make their own light: lanterns, and hidden recorders once they have been revealed. Each of
-- those gets a visible patch of floor and wall around it for its light to fall on.
-- Nothing here decides gameplay; it builds what the plan describes and hands back the pieces
-- the Director needs to wire up.

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
export type Echo = {
	id: number,
	cell: Maze.Cell,
	model: Model,
	position: Vector3,
	revealed: boolean,
}
export type Plate = { position: Vector3, rearmAt: number }
export type Level = {
	model: Model,
	lit: Model, -- the visible parts: lanterns, revealed recorders and their patches
	origin: Vector3,
	plan: LevelPlan.LevelPlan,
	startCFrame: CFrame,
	exitDoor: BasePart,
	exitPrompt: ProximityPrompt,
	pickups: { Pickup },
	echoes: { Echo },
	plates: { Plate },
	beaconPosition: Vector3,
}

local CELL = Config.World.cellSize
local HEIGHT = Config.World.wallHeight
local THICK = Config.World.wallThickness
local HALF = CELL / 2
local INNER = HALF - THICK / 2 -- distance from a cell centre to the inside face of its walls

local SPAWN_HEIGHT = 3
local DOOR_SIZE = Vector3.new(5, 8.4, 0.5)
local PILLAR_SIZE = 2.2
local WATER_DEPTH = 0.35
local GRATE_BARS = 7
local GRATE_SPACING = 1.3
local SEED_SALT = 5381
local PIT_RIM = 0.5 -- width of the marked edge round a pit
local PLATE_HEIGHT = 0.14
local PATCH_THICKNESS = 0.04 -- visible patches sit this proud of the invisible surface
local SKIRTING_HEIGHT = 0.6
local PROP_SIDE_REACH = INNER - 3.2 -- how far along a wall a prop may sit from its middle
local LAMP_BRIGHTNESS = 2.4
local ECHO_BRIGHTNESS = 2.2
local LAMP_COLOR = Color3.fromRGB(255, 226, 170)
local PATCH_FLOOR = Color3.fromRGB(126, 118, 104)
local PATCH_WALL = Color3.fromRGB(150, 152, 144)
local PATCH_TRIM = Color3.fromRGB(60, 58, 54)

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

-- Where something that stands against a wall goes in a cell: a random closed side, slid a
-- little along it. A cell with no walls gets it in the middle.
local function againstWall(maze: Maze.Maze, center: Vector3, cell: Maze.Cell, rng: Rng.Rng): CFrame
	local closed = closedSides(maze, cell)
	if #closed == 0 then
		return CFrame.new(center)
	end
	local slide = (rng:next() * 2 - 1) * PROP_SIDE_REACH
	return wallBase(center, closed[rng:int(1, #closed)]) * CFrame.new(slide, 0, 0)
end

-- A hole in the floor: four ledges round it, a shaft, a bottom, and a marked rim.
local function buildPit(center: Vector3, parent: Instance)
	local hole = Config.World.pitSize / 2
	local ledge = HALF - hole
	local depth = Config.World.pitDepth
	local pit = Build.model("Pit", parent)
	for _, sign in { -1, 1 } do
		local reach = sign * (hole + ledge / 2)
		Build.part({
			name = "Ledge",
			size = Vector3.new(CELL, 1, ledge),
			cframe = CFrame.new(center + Vector3.new(0, -0.5, reach)),
			parent = pit,
		})
		Build.part({
			name = "Ledge",
			size = Vector3.new(ledge, 1, hole * 2),
			cframe = CFrame.new(center + Vector3.new(reach, -0.5, 0)),
			parent = pit,
		})
		local shaft = sign * (hole + 0.5)
		local shaftY = -1 - (depth - 1) / 2
		Build.part({
			name = "Shaft",
			size = Vector3.new(hole * 2 + 2, depth - 1, 1),
			cframe = CFrame.new(center + Vector3.new(0, shaftY, shaft)),
			parent = pit,
		})
		Build.part({
			name = "Shaft",
			size = Vector3.new(1, depth - 1, hole * 2),
			cframe = CFrame.new(center + Vector3.new(shaft, shaftY, 0)),
			parent = pit,
		})
		local rim = sign * (hole + PIT_RIM / 2)
		Build.part({
			name = "Rim",
			size = Vector3.new(hole * 2 + PIT_RIM * 2, PATCH_THICKNESS, PIT_RIM),
			cframe = CFrame.new(center + Vector3.new(0, PATCH_THICKNESS / 2, rim)),
			collide = false,
			tag = Config.Tags.hazard,
			parent = pit,
		})
		Build.part({
			name = "Rim",
			size = Vector3.new(PIT_RIM, PATCH_THICKNESS, hole * 2),
			cframe = CFrame.new(center + Vector3.new(rim, PATCH_THICKNESS / 2, 0)),
			collide = false,
			tag = Config.Tags.hazard,
			parent = pit,
		})
	end
	Build.part({
		name = "Bottom",
		size = Vector3.new(hole * 2 + 2, 1, hole * 2 + 2),
		cframe = CFrame.new(center + Vector3.new(0, -depth - 0.5, 0)),
		parent = pit,
	})
end

local function buildShell(plan: LevelPlan.LevelPlan, origin: Vector3, parent: Instance)
	local maze = plan.maze
	local width, depth = maze.width * CELL, maze.height * CELL
	local middle = origin + Vector3.new(width / 2, 0, depth / 2)

	-- Floor: one slab per run of solid cells in a row, so pit cells are left open.
	local pitAt: { [number]: boolean } = {}
	for _, cell in plan.pits do
		pitAt[Maze.index(maze, cell.x, cell.y)] = true
		buildPit(World.cellCenter(origin, cell), parent)
	end
	local floor = Build.model("Floor", parent)
	for y = 1, maze.height do
		local runStart: number? = nil
		for x = 1, maze.width + 1 do
			local solid = x <= maze.width and not pitAt[Maze.index(maze, x, y)]
			if solid and runStart == nil then
				runStart = x
			elseif not solid and runStart ~= nil then
				local length = (x - runStart) * CELL
				Build.part({
					name = "Slab",
					size = Vector3.new(length, 1, CELL),
					cframe = CFrame.new(
						origin
							+ Vector3.new(
								(runStart - 1) * CELL + length / 2,
								-0.5,
								(y - 0.5) * CELL
							)
					),
					parent = floor,
				})
				runStart = nil
			end
		end
	end
	Build.part({
		name = "Ceiling",
		size = Vector3.new(width + THICK, 1, depth + THICK),
		cframe = CFrame.new(middle + Vector3.new(0, HEIGHT + 0.5, 0)),
		parent = parent,
	})

	local walls = Build.model("Walls", parent)
	local function wall(size: Vector3, position: Vector3)
		Build.part({
			name = "Wall",
			size = size,
			cframe = CFrame.new(origin + position),
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
			collide = false,
			parent = model,
		})
	end
	for _, z in { -span / 2 - 0.4, span / 2 + 0.4 } do
		Build.part({
			name = "Frame",
			size = Vector3.new(span + 1, 0.2, 0.4),
			cframe = CFrame.new(center + Vector3.new(0, 0.1, z)),
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
			parent = model,
		})
	end
	Build.part({
		name = "Lintel",
		size = if alongX
			then Vector3.new(1.6, 2, CELL - THICK)
			else Vector3.new(CELL - THICK, 2, 1.6),
		cframe = CFrame.new(center + Vector3.new(0, HEIGHT - 1, 0)),
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
		collide = false,
		parent = model,
	})
	Build.part({
		name = "Grille",
		size = Vector3.new(2.4, 1.2, 2.4),
		cframe = CFrame.new(center + Vector3.new(0, HEIGHT - 2.4, 0)),
		collide = false,
		parent = model,
	})
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
				base *= CFrame.new(
					if rng:next() < 0.5 then -PROP_SIDE_REACH else PROP_SIDE_REACH,
					0,
					0
				)
			end
			local prop = Props.place(kind, base, features)
			if kind == "hum" then
				Build.loop(prop.PrimaryPart :: BasePart, Config.Audio.air, 0.35, 0.42, 55)
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
			collide = false,
			tag = Config.Tags.water,
			parent = water,
		})
		pool:SetAttribute("Flooded", true)
	end
end

-- Alarm plates: a low slab in the middle of a cell. Stepping on one is very loud.
local function buildPlates(plan: LevelPlan.LevelPlan, origin: Vector3, parent: Instance): { Plate }
	local plates: { Plate } = {}
	local side = Config.World.plateRadius * 2
	for _, cell in plan.plates do
		local center = World.cellCenter(origin, cell)
		Build.part({
			name = "AlarmPlate",
			size = Vector3.new(side, PLATE_HEIGHT, side),
			cframe = CFrame.new(center + Vector3.new(0, PLATE_HEIGHT / 2, 0)),
			collide = false,
			tag = Config.Tags.hazard,
			parent = parent,
		})
		table.insert(plates, { position = center, rearmAt = 0 })
	end
	return plates
end

-- Visible floor and wall for one cell, for a light to fall on.
local function buildPatch(maze: Maze.Maze, origin: Vector3, cell: Maze.Cell, parent: Instance)
	local center = World.cellCenter(origin, cell)
	local span = CELL - THICK
	local patch = Build.model("Patch", parent)
	Build.part({
		name = "Floor",
		size = Vector3.new(span, PATCH_THICKNESS, span),
		cframe = CFrame.new(center),
		color = PATCH_FLOOR,
		collide = false,
		parent = patch,
	})
	for _, side in closedSides(maze, cell) do
		local base = wallBase(center, side)
		Build.part({
			name = "Wall",
			size = Vector3.new(span, HEIGHT, PATCH_THICKNESS),
			cframe = base * CFrame.new(0, HEIGHT / 2, 0),
			color = PATCH_WALL,
			collide = false,
			parent = patch,
		})
		Build.part({
			name = "Skirting",
			size = Vector3.new(span, SKIRTING_HEIGHT, PATCH_THICKNESS * 3),
			cframe = base * CFrame.new(0, SKIRTING_HEIGHT / 2, -PATCH_THICKNESS),
			color = PATCH_TRIM,
			collide = false,
			parent = patch,
		})
	end
end

local function buildLamps(
	plan: LevelPlan.LevelPlan,
	origin: Vector3,
	parent: Instance,
	rng: Rng.Rng
)
	for _, cell in plan.lamps do
		local center = World.cellCenter(origin, cell)
		local lantern = Props.place("lantern", againstWall(plan.maze, center, cell, rng), parent)
		local bulb = lantern:FindFirstChild("Bulb") :: BasePart
		Build.pointLight(bulb, LAMP_COLOR, LAMP_BRIGHTNESS, Config.World.lampRange)
		buildPatch(plan.maze, origin, cell, parent)
	end
end

-- Hidden recorders: invisible until a scanner has put enough dots on them.
local function buildEchoes(
	plan: LevelPlan.LevelPlan,
	origin: Vector3,
	parent: Instance,
	rng: Rng.Rng
): { Echo }
	local echoes: { Echo } = {}
	for id, cell in plan.echoes do
		local center = World.cellCenter(origin, cell)
		local model = Props.place("recorder", againstWall(plan.maze, center, cell, rng), parent)
		model.Name = "Echo" .. id
		model:SetAttribute("EchoId", id)
		CollectionService:AddTag(model, Config.Tags.echo)
		CollectionService:AddTag(model, Config.Tags.objective)
		Build.hide(model)
		table.insert(echoes, {
			id = id,
			cell = cell,
			model = model,
			position = model:GetPivot().Position,
			revealed = false,
		})
	end
	return echoes
end

-- A recorder has been scanned enough: it shows itself and lights its corner of the level.
function World.revealEcho(level: Level, echo: Echo)
	echo.revealed = true
	CollectionService:RemoveTag(echo.model, Config.Tags.echo)
	for _, descendant in echo.model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 0
		end
	end
	local lamp = echo.model:FindFirstChild("Lamp")
	if lamp and lamp:IsA("BasePart") then
		Build.pointLight(lamp, lamp.Color, ECHO_BRIGHTNESS, Config.World.echoLightRange)
	end
	echo.model.Parent = level.lit
	buildPatch(level.plan.maze, level.origin, echo.cell, level.lit)
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
	CollectionService:AddTag(model, Config.Tags.objective)
	local door = Build.part({
		name = "ExitDoor",
		size = DOOR_SIZE,
		cframe = base * CFrame.new(0, DOOR_SIZE.Y / 2, 0),
		parent = model,
	})
	for _, x in { -DOOR_SIZE.X / 2 - 0.4, DOOR_SIZE.X / 2 + 0.4 } do
		Build.part({
			name = "Jamb",
			size = Vector3.new(0.8, DOOR_SIZE.Y + 0.8, 0.9),
			cframe = base * CFrame.new(x, (DOOR_SIZE.Y + 0.8) / 2, 0),
			parent = model,
		})
	end
	Build.part({
		name = "Header",
		size = Vector3.new(DOOR_SIZE.X + 1.6, 0.8, 0.9),
		cframe = base * CFrame.new(0, DOOR_SIZE.Y + 0.4, 0),
		parent = model,
	})
	Build.part({
		name = "Handle",
		size = Vector3.new(0.3, 0.9, 0.5),
		cframe = base * CFrame.new(DOOR_SIZE.X / 2 - 0.7, 4, -0.4),
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
	local prompt: ProximityPrompt
	if objective.kind == "rescue" then
		local figure = Figures.sitting(model, Config.Tags.friend)
		figure:PivotTo(face * CFrame.new(0, 0, -1.4))
		CollectionService:AddTag(figure, Config.Tags.rescue)
		prompt = Build.prompt(figure.PrimaryPart :: BasePart, "Help up", "Surveyor", 1.5)
	else
		CollectionService:AddTag(model, Config.Tags.objective)
		local stand = Build.part({
			name = "Stand",
			size = Vector3.new(1.6, 2.6, 1.6),
			cframe = CFrame.new(center + Vector3.new(0, 1.3, 0)),
			parent = model,
		})
		if objective.kind == "key" then
			local key = Build.part({
				name = "Key",
				size = Vector3.new(0.3, 0.5, 1.5),
				cframe = CFrame.new(center + Vector3.new(0, 2.9, 0))
					* CFrame.Angles(0, math.rad(30), 0),
				collide = false,
				parent = model,
			})
			Build.part({
				name = "Bow",
				size = Vector3.new(0.3, 0.9, 0.9),
				cframe = key.CFrame * CFrame.new(0, 0, 1),
				shape = Enum.PartType.Cylinder,
				collide = false,
				parent = model,
			})
			prompt = Build.prompt(stand, "Take", "Key", 0.3)
		elseif objective.kind == "cell" then
			Build.part({
				name = "Cell",
				size = Vector3.new(1.8, 0.9, 0.9),
				cframe = CFrame.new(center + Vector3.new(0, 3.5, 0))
					* CFrame.Angles(0, 0, math.rad(90)),
				shape = Enum.PartType.Cylinder,
				collide = false,
				parent = model,
			})
			prompt = Build.prompt(stand, "Take", "Battery cell", 0.3)
		else -- plate
			Build.part({
				name = "Plate",
				size = Vector3.new(1.8, 1.2, 0.15),
				cframe = CFrame.new(center + Vector3.new(0, 3.1, 0))
					* CFrame.Angles(math.rad(-20), 0, 0),
				collide = false,
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
	local dark = Build.model("Dark", model)
	local lit = Build.model("Lit", model)

	buildShell(plan, origin, dark)
	buildFeatures(plan, origin, dark, rng)
	buildWater(plan, origin, dark)
	buildAnomaly(plan, origin, dark)
	local plates = buildPlates(plan, origin, dark)
	local exitDoor, exitPrompt = buildExit(plan, origin, dark)

	local pickups: { Pickup } = {}
	for _, objective in plan.objectives do
		local center = World.cellCenter(origin, objective.cell)
		local closed = closedSides(maze, objective.cell)
		local face = if #closed > 0 then wallBase(center, closed[1]) else CFrame.new(center)
		table.insert(pickups, buildPickup(objective, center, face, dark))
	end
	local echoes = buildEchoes(plan, origin, dark, rng)
	Build.hide(dark)
	buildLamps(plan, origin, lit, rng)

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
		lit = lit,
		origin = origin,
		plan = plan,
		startCFrame = CFrame.lookAt(spawnPoint, lookAt + Vector3.new(0, SPAWN_HEIGHT, 0)),
		exitDoor = exitDoor,
		exitPrompt = exitPrompt,
		pickups = pickups,
		echoes = echoes,
		plates = plates,
		beaconPosition = World.cellCenter(origin, plan.beaconCell)
			+ Vector3.new(0, SPAWN_HEIGHT, 0),
	}
end

return World
