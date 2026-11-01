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
local Lore = require(ReplicatedStorage.Shared.data.Lore)
local LoreText = require(ReplicatedStorage.Shared.data.LoreText)
local Maze = require(ReplicatedStorage.Shared.pure.Maze)
local Places = require(ReplicatedStorage.Shared.data.Places)
local Props = require(script.Parent.Props)
local Rng = require(ReplicatedStorage.Shared.pure.Rng)

export type Pickup = { objective: LevelPlan.Objective, model: Model, prompt: ProximityPrompt }
-- A hidden thing that a scanner can find: a recorder, a story object, a poster, or a lamp-bag
-- (already lit, so scanning it only brings out what is written on it). Ids run in that order.
export type EchoKind = "recorder" | "reveal" | "sign" | "nook"
export type Echo = {
	id: number,
	kind: EchoKind,
	cell: Maze.Cell,
	model: Model,
	position: Vector3,
	revealed: boolean,
	lines: { string }, -- what it says when revealed (a recorder's tape is the Director's to pick)
	glow: Places.Glow?, -- the light it gives off once revealed; nil for a recorder's own lamp
	thought: string?, -- Theo's reaction, said after the words (hidden objects)
	anchor: BasePart?, -- where that light hangs
	dead: boolean, -- a burnt-out lamp-bag: hidden until scanned, then only a dim glow
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
local PROP_SIDE_REACH = INNER - 3.2 -- how far along a wall a prop may sit from its middle
local LAMP_BRIGHTNESS = 2.4
local ECHO_BRIGHTNESS = 2.2
local GLOW_BRIGHTNESS = 2
local PLACE_RANGE_BOOST = 1.5 -- a found object's light reaches the open cells beside it
local GLOW_RANGE_PER_RADIUS = 1.7 -- a story object's glow radius is where it is clearly lit
local LAMP_RADIUS = 6 -- the radius a Config.World.lampRange lantern stands for
local SIGN_LIGHT = { color = { 255, 232, 196 }, radius = 5 }
local SIGN_SLOTS = { 0, -4.3, 4.3 } -- where along a wall a second and third sign go
local MARKER_OFFSET = CFrame.new(0, 4, -2.2) -- a hidden object's light hangs this far into the room
local LAMP_COLOR = Color3.fromRGB(255, 226, 170)
local PATCH_PIXELS_PER_STUD = 6
local WATER_COLOR = Color3.fromRGB(34, 118, 168) -- a lit pool: the cyan dots of water, as paint
local WATER_GLINT = Color3.fromRGB(150, 220, 255)
local WATER_RIPPLES = 7
local WATER_REFLECTANCE = 0.25
local PATCH_STEPS = 6 -- steps of fade across and down a lit surface
-- What a lit corner of each Level looks like, so no two Levels share a wall or a floor: office
-- carpet and wallpaper, wet green tile, clinic lino, cave rock, garage concrete.
type PatchLook = {
	floor: Color3,
	wall: Color3,
	floorMaterial: Enum.Material,
	wallMaterial: Enum.Material,
	floorPattern: string,
	wallPattern: string,
}
-- Real Roblox materials, so each Level's lit stretch has its own grain under the light: the
-- fibres of office carpet and wallpaper, pool tile, clinic lino, cave rock, poured concrete.
local PATCH_LOOKS: { PatchLook } = {
	{
		floor = Color3.fromRGB(122, 104, 70),
		wall = Color3.fromRGB(196, 170, 84),
		floorMaterial = Enum.Material.Fabric,
		wallMaterial = Enum.Material.Fabric,
		floorPattern = "squares",
		wallPattern = "stripes",
	},
	{
		floor = Color3.fromRGB(70, 118, 126),
		wall = Color3.fromRGB(176, 214, 220),
		floorMaterial = Enum.Material.Slate,
		wallMaterial = Enum.Material.Marble,
		floorPattern = "tiles",
		wallPattern = "tiles",
	},
	{
		floor = Color3.fromRGB(138, 160, 148),
		wall = Color3.fromRGB(184, 214, 196),
		floorMaterial = Enum.Material.Plastic,
		wallMaterial = Enum.Material.SmoothPlastic,
		floorPattern = "tiles",
		wallPattern = "stripes",
	},
	{
		floor = Color3.fromRGB(96, 76, 62),
		wall = Color3.fromRGB(112, 92, 134),
		floorMaterial = Enum.Material.Ground,
		wallMaterial = Enum.Material.Rock,
		floorPattern = "boards",
		wallPattern = "boards",
	},
	{
		floor = Color3.fromRGB(86, 86, 92),
		wall = Color3.fromRGB(156, 156, 162),
		floorMaterial = Enum.Material.Asphalt,
		wallMaterial = Enum.Material.Concrete,
		floorPattern = "squares",
		wallPattern = "tiles",
	},
}
local LOOK_OF_TIER = { 1, 1, 2, 2, 3, 3, 4, 5 } -- the authored tiers, two to a Level but the last two

local function patchLook(tier: number): PatchLook
	local index = LOOK_OF_TIER[tier] or (tier - 1) % #PATCH_LOOKS + 1
	return PATCH_LOOKS[index]
end
-- Solid in the middle. An edge fades to nothing only when the patch ends there; an edge shared
-- with the next lit cell, or meeting a lit wall, stays solid so neighbouring pieces join up
-- without a gap. `low` is the left (or top) edge of the surface and `high` the right (or bottom).
local function edgeFade(lowFades: boolean, highFades: boolean): NumberSequence
	local points = {}
	if lowFades then
		table.insert(points, NumberSequenceKeypoint.new(0, 1))
		table.insert(points, NumberSequenceKeypoint.new(0.35, 0.15))
	else
		table.insert(points, NumberSequenceKeypoint.new(0, 0.15))
	end
	if highFades then
		table.insert(points, NumberSequenceKeypoint.new(0.65, 0.15))
		table.insert(points, NumberSequenceKeypoint.new(1, 1))
	else
		table.insert(points, NumberSequenceKeypoint.new(1, 0.15))
	end
	return NumberSequence.new(points)
end
local PATCH_WALL_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.6, 0.3),
	NumberSequenceKeypoint.new(1, 0.1),
})

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

-- The transparency a NumberSequence gives at `at` (0 to 1) along its length.
local function sampleSequence(sequence: NumberSequence, at: number): number
	local points = sequence.Keypoints
	for index = 2, #points do
		local before, after = points[index - 1], points[index]
		if at <= after.Time then
			local span = after.Time - before.Time
			if span <= 0 then
				return after.Value
			end
			return before.Value + (after.Value - before.Value) * (at - before.Time) / span
		end
	end
	return points[#points].Value
end

-- The visible stuff of a lit patch: real parts of a real material laid over the invisible
-- surface `part`, thinned out toward the edges in steps so the patch has no hard border. The
-- fades are read off the same `across` and `down` sequences the painted version used (across
-- runs along the face to the right, down from its top), neighbouring steps of the same
-- transparency are joined into one part, and a patch whose edges all run on is a single part.
-- The parts take the invisible one's place in concealment: each remembers what it looked like.
local function fadeSurface(
	part: BasePart,
	color: Color3,
	material: Enum.Material,
	across: NumberSequence,
	down: NumberSequence,
	salt: number
)
	local width, height = part.Size.X, part.Size.Y
	local rows: { { number } } = {}
	local rowKeys: { string } = {}
	for row = 1, PATCH_STEPS do
		local vertical = 1 - sampleSequence(down, (row - 0.5) / PATCH_STEPS)
		local cells: { number } = {}
		for column = 1, PATCH_STEPS do
			local horizontal = 1 - sampleSequence(across, (column - 0.5) / PATCH_STEPS)
			-- Tenths, so steps of nearly the same strength join up.
			cells[column] = math.floor((1 - horizontal * vertical) * 10 + 0.5) / 10
		end
		rows[row] = cells
		rowKeys[row] = table.concat(cells, ",")
	end
	local water = material == Enum.Material.Glass
	local row = 1
	while row <= PATCH_STEPS do
		local last = row
		while last < PATCH_STEPS and rowKeys[last + 1] == rowKeys[row] do
			last += 1
		end
		local column = 1
		while column <= PATCH_STEPS do
			local to = column
			while to < PATCH_STEPS and rows[row][to + 1] == rows[row][column] do
				to += 1
			end
			local transparency = rows[row][column]
			if transparency < 0.95 then
				-- The face's x runs toward the part's -X and its y down toward -Y.
				local u0, u1 = (column - 1) / PATCH_STEPS, to / PATCH_STEPS
				local v0, v1 = (row - 1) / PATCH_STEPS, last / PATCH_STEPS
				local tile = Build.part({
					name = if water then "WaterSurface" else "Surface",
					size = Vector3.new((u1 - u0) * width, (v1 - v0) * height, PATCH_THICKNESS),
					cframe = part.CFrame * CFrame.new(
						-((u0 + u1) / 2 - 0.5) * width,
						(0.5 - (v0 + v1) / 2) * height,
						0
					),
					color = color,
					material = material,
					transparency = if water then 0.2 + transparency * 0.8 else transparency,
					collide = false,
					query = false,
					tag = if water then Config.Tags.shimmer else nil,
					parent = part.Parent :: Instance,
				})
				if water then
					tile.Reflectance = WATER_REFLECTANCE
				end
			end
			column = to + 1
		end
		row = last + 1
	end
	if not water then
		return
	end

	-- Open water also has rings spreading out and a few glints, so a lit pool reads as water
	-- and not as a patch of dry floor.
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PATCH_PIXELS_PER_STUD
	gui.Parent = part
	local group = Instance.new("CanvasGroup")
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.Parent = gui
	local acrossGradient = Instance.new("UIGradient")
	acrossGradient.Transparency = across
	acrossGradient.Parent = group
	local ripples = Random.new(salt)
	for _ = 1, WATER_RIPPLES do
		local size = 0.18 + ripples:NextNumber() * 0.3
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position =
			UDim2.fromScale(0.15 + ripples:NextNumber() * 0.7, 0.15 + ripples:NextNumber() * 0.7)
		ring.Size = UDim2.fromScale(size, size)
		ring.BackgroundTransparency = 1
		ring.BorderSizePixel = 0
		ring.Parent = group
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = ring
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = WATER_GLINT
		stroke.Transparency = 0.2 + ripples:NextNumber() * 0.3
		stroke.Parent = ring
	end
	for _ = 1, 4 do
		local glint = Instance.new("Frame")
		glint.AnchorPoint = Vector2.new(0.5, 0.5)
		glint.Position = UDim2.fromScale(ripples:NextNumber(), ripples:NextNumber())
		glint.Size = UDim2.fromScale(0.2, 0.02)
		glint.Rotation = ripples:NextNumber() * 30 - 15
		glint.BackgroundColor3 = WATER_GLINT
		glint.BackgroundTransparency = 0.25
		glint.BorderSizePixel = 0
		glint.Parent = group
	end
end

-- Which way the surface of a wall runs, seen from inside the cell: for the wall on each side,
-- the sides of the cell its left and its right end touch.
local WALL_ENDS = {
	N = { "W", "E" },
	S = { "E", "W" },
	E = { "N", "S" },
	W = { "S", "N" },
}

-- Visible floor and walls for a light to fall on. A small light (a lamp-bag) gets the cell's
-- floor and the wall nearest `toward`; with `area` (a found story object) the patch is the
-- cell and the open cells beside it, every closed wall of them included, so it reads as a
-- stretch of the place. Water beside any light gets its pool surface. Where two pieces of the
-- patch meet they run on into each other; only the outer edges fade out.
local function buildPatch(
	maze: Maze.Maze,
	origin: Vector3,
	cell: Maze.Cell,
	parent: Instance,
	toward: Vector3?,
	tier: number,
	area: boolean,
	flooded: { [number]: boolean }
)
	local look = patchLook(tier)
	local center = World.cellCenter(origin, cell)
	local span = CELL - THICK
	local patch = Build.model("Patch", parent)
	local function keyOf(at: Maze.Cell): number
		return Maze.index(maze, at.x, at.y)
	end

	-- The cells that get a floor.
	local region: { [number]: Maze.Cell } = { [keyOf(cell)] = cell }
	for _, neighbor in Maze.neighbors(maze, cell.x, cell.y) do
		-- Water next to any light shows as water, whatever kind of light it is.
		if area or flooded[keyOf(neighbor)] then
			region[keyOf(neighbor)] = neighbor
		end
	end

	-- The walls that get painted: [cell key][side].
	local lit: { [number]: { [string]: boolean } } = {}
	local function light(at: Maze.Cell, side: string)
		local key = keyOf(at)
		lit[key] = lit[key] or {}
		lit[key][side] = true
	end
	if area then
		for _, at in region do
			for _, side in closedSides(maze, at) do
				light(at, side)
			end
		end
	else
		local target = toward or center
		local best: string? = nil
		local bestDistance = math.huge
		for _, side in closedSides(maze, cell) do
			local distance = (wallBase(center, side).Position - target).Magnitude
			if distance < bestDistance then
				best, bestDistance = side, distance
			end
		end
		if best ~= nil then
			light(cell, best)
		end
	end
	local function isLit(at: Maze.Cell, side: string): boolean
		local walls = lit[keyOf(at)]
		return walls ~= nil and walls[side] == true
	end

	-- Floors. An edge stays solid where the next cell is part of the patch or a painted wall
	-- stands on it, and fades where the patch ends.
	local function floorFades(at: Maze.Cell, side: string): boolean
		if Maze.isOpen(maze, at.x, at.y, side) then
			local d = Maze.DIRS[side]
			return region[keyOf({ x = at.x + d.dx, y = at.y + d.dy })] == nil
		end
		return not isLit(at, side)
	end
	for key, at in region do
		-- A flooded cell keeps its water: the patch there is the pool's surface, not dry floor.
		local wet = flooded[key] == true
		local position = World.cellCenter(origin, at)
			+ Vector3.new(0, if wet then WATER_DEPTH else 0, 0)
		-- Turned so its front face is up with east to the right and north at the top, which
		-- is the way the fades below are written.
		local floor = Build.part({
			name = if wet then "Water" else "Floor",
			size = Vector3.new(span, span, PATCH_THICKNESS),
			cframe = CFrame.fromMatrix(position, Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1)),
			transparency = 1,
			collide = false,
			parent = patch,
		})
		fadeSurface(
			floor,
			if wet then WATER_COLOR else look.floor,
			if wet then Enum.Material.Glass else look.floorMaterial,
			edgeFade(floorFades(at, "W"), floorFades(at, "E")),
			edgeFade(floorFades(at, "N"), floorFades(at, "S")),
			key
		)
	end

	-- Walls. Each end runs on into the next painted wall round a corner, or along a corridor
	-- into the next lit cell, and fades where the painted part stops. The top always fades.
	local function wallEndFades(at: Maze.Cell, side: string, end_: string): boolean
		if not Maze.isOpen(maze, at.x, at.y, end_) then
			return not isLit(at, end_) -- a corner
		end
		local d = Maze.DIRS[end_]
		local beyond = { x = at.x + d.dx, y = at.y + d.dy }
		return not (
			region[keyOf(beyond)] ~= nil
			and not Maze.isOpen(maze, beyond.x, beyond.y, side)
			and isLit(beyond, side)
		)
	end
	for key, sides in lit do
		local at = Maze.cellAt(maze, key)
		for side in sides do
			local ends = WALL_ENDS[side]
			local wall = Build.part({
				name = "Wall",
				size = Vector3.new(span, HEIGHT, PATCH_THICKNESS),
				cframe = wallBase(World.cellCenter(origin, at), side)
					* CFrame.new(0, HEIGHT / 2, 0),
				transparency = 1,
				collide = false,
				parent = patch,
			})
			fadeSurface(
				wall,
				look.wall,
				look.wallMaterial,
				edgeFade(wallEndFades(at, side, ends[1]), wallEndFades(at, side, ends[2])),
				PATCH_WALL_FADE,
				key * 4 + (table.find(Maze.DIR_NAMES, side) :: number)
			)
		end
	end
end

-- A bare place to hang a light for something that is hidden: invisible even once revealed.
local function addMarker(model: Model, at: CFrame): BasePart
	local marker = Build.part({
		name = "Marker",
		size = Vector3.new(0.2, 0.2, 0.2),
		cframe = at,
		transparency = 1,
		collide = false,
		query = false,
		parent = model,
	})
	marker:SetAttribute("Marker", true)
	return marker
end

-- Marks a model so a scanner can find it: after enough dots land on it the client asks the
-- server to reveal it. `gold` draws it with the fine dots items get.
local function markScannable(model: Model, id: number, gold: boolean)
	model:SetAttribute("EchoId", id)
	CollectionService:AddTag(model, Config.Tags.echo)
	if gold then
		CollectionService:AddTag(model, Config.Tags.objective)
	end
end

local function newEcho(
	id: number,
	kind: EchoKind,
	cell: Maze.Cell,
	model: Model,
	lines: { string },
	glow: Places.Glow?
): Echo
	model:SetAttribute("EchoKind", kind) -- clients lure the eye to unscanned story things
	return {
		id = id,
		kind = kind,
		cell = cell,
		model = model,
		position = model:GetPivot().Position,
		revealed = false,
		lines = lines,
		glow = glow,
		thought = nil,
		anchor = nil,
		dead = false,
	}
end

-- Lamp-bags: a satchel with a bare bulb burning, lighting the patch of floor and wall round
-- it. Scanning one brings out what is written on its tag. Some are burnt out: those are
-- invisible until scanned, and then only glow dimly.
local function buildLamps(
	plan: LevelPlan.LevelPlan,
	origin: Vector3,
	parent: Instance,
	rng: Rng.Rng,
	firstId: number
): { Echo }
	local echoes: { Echo } = {}
	for index, cell in plan.lamps do
		local variant = plan.nooks[index]
		local center = World.cellCenter(origin, cell)
		local base = againstWall(plan.maze, center, cell, rng)
		local dead = variant == Places.deadNook
		local lantern = Props.place("lantern", base, parent)
		if variant == 1 then
			Props.place("nookmug", base, lantern)
		elseif variant == 2 then
			Props.place("nookstool", base, lantern)
		elseif dead then
			Props.place("nooktag", base, lantern)
		end
		local glow = Places.nookGlow(variant)
		local bulb = lantern:FindFirstChild("Bulb") :: BasePart
		if dead then
			bulb.Material = Enum.Material.SmoothPlastic
			bulb.Color = Color3.fromRGB(60, 56, 50)
		else
			local range = Config.World.lampRange * glow.radius / LAMP_RADIUS
			Build.pointLight(bulb, LAMP_COLOR, LAMP_BRIGHTNESS, range)
			buildPatch(
				plan.maze,
				origin,
				cell,
				parent,
				base.Position,
				plan.tier,
				false,
				plan.flooded
			)
		end
		local echo =
			newEcho(firstId + index - 1, "nook", cell, lantern, Places.nookLines(variant), glow)
		echo.dead = dead
		echo.anchor = bulb
		markScannable(lantern, echo.id, false)
		lantern:SetAttribute("Light", true) -- wakes to a glance (Config.Lidar.lightRevealHits)
		if dead then
			Build.hide(lantern)
		end
		table.insert(echoes, echo)
	end
	return echoes
end

-- Hidden recorders: invisible until a scanner has put enough dots on them.
local function buildRecorders(
	plan: LevelPlan.LevelPlan,
	origin: Vector3,
	parent: Instance,
	rng: Rng.Rng,
	firstId: number
): { Echo }
	local echoes: { Echo } = {}
	for index, cell in plan.echoes do
		local id = firstId + index - 1
		local center = World.cellCenter(origin, cell)
		local model = Props.place("recorder", againstWall(plan.maze, center, cell, rng), parent)
		model.Name = "Echo" .. id
		markScannable(model, id, true)
		Build.hide(model)
		local echo = newEcho(id, "recorder", cell, model, {}, nil)
		local lamp = model:FindFirstChild("Lamp")
		echo.anchor = if lamp and lamp:IsA("BasePart") then lamp else nil
		table.insert(echoes, echo)
	end
	return echoes
end

-- The story's hidden objects: a desk lamp, a coat, a dinghy. Invisible until scanned enough;
-- then they light up their corner and say their lines.
local function buildReveals(
	plan: LevelPlan.LevelPlan,
	origin: Vector3,
	parent: Instance,
	rng: Rng.Rng,
	firstId: number
): { Echo }
	local echoes: { Echo } = {}
	for index, reveal in plan.reveals do
		local id = firstId + index - 1
		local details = Places.reveal(reveal.id)
		local center = World.cellCenter(origin, reveal.cell)
		local base = againstWall(plan.maze, center, reveal.cell, rng)
		local model = Props.place(details.kit, base, parent)
		model.Name = "Reveal_" .. reveal.id
		local echo = newEcho(id, "reveal", reveal.cell, model, details.lines, details.glow)
		echo.anchor = addMarker(model, base * MARKER_OFFSET)
		echo.thought = details.thought
		markScannable(model, id, true)
		Build.hide(model)
		table.insert(echoes, echo)
	end
	return echoes
end

-- Posters and stencils. They are paper on a wall: invisible until scanned, then readable by
-- a small light of their own. Several signs in one cell take different walls and positions.
local function buildSigns(
	plan: LevelPlan.LevelPlan,
	origin: Vector3,
	parent: Instance,
	firstId: number
): { Echo }
	local echoes: { Echo } = {}
	local perCell: { [number]: number } = {}
	for _, sign in plan.signs do
		local closed = closedSides(plan.maze, sign.cell)
		if #closed > 0 then
			local index = Maze.index(plan.maze, sign.cell.x, sign.cell.y)
			local count = perCell[index] or 0
			perCell[index] = count + 1
			local side = closed[count % #closed + 1]
			local slot = SIGN_SLOTS[math.floor(count / #closed) % #SIGN_SLOTS + 1]
			local center = World.cellCenter(origin, sign.cell)
			local base = wallBase(center, side) * CFrame.new(slot, 0, 0)
			local lines = Places.signLines(sign.id)
			local model = Props.sign(base, lines, parent)
			model.Name = "Sign_" .. sign.id
			local echo = newEcho(firstId + #echoes, "sign", sign.cell, model, lines, SIGN_LIGHT)
			echo.anchor = addMarker(model, base * MARKER_OFFSET)
			markScannable(model, echo.id, false)
			Build.hide(model)
			table.insert(echoes, echo)
		end
	end
	return echoes
end

-- A hidden thing has been scanned enough: it shows itself and lights its corner of the level.
-- A lit lamp-bag is already showing; scanning it only brings out its tag, and a burnt-out one
-- appears now, with a dim glow.
function World.revealEcho(level: Level, echo: Echo)
	echo.revealed = true
	CollectionService:RemoveTag(echo.model, Config.Tags.echo)
	if echo.kind == "nook" and not echo.dead then
		return
	end
	Build.show(echo.model)
	-- A found story object or tape is the point of its corner of the level: it lights every wall
	-- of its cell and the open floor beside it, so the range is wider than a poster's.
	local showsPlace = echo.kind == "reveal" or echo.kind == "recorder"
	local boost = if showsPlace then PLACE_RANGE_BOOST else 1
	local anchor = echo.anchor
	if anchor ~= nil then
		local glow = echo.glow
		if glow ~= nil then
			Build.pointLight(
				anchor,
				Build.rgb(glow.color),
				GLOW_BRIGHTNESS,
				glow.radius * GLOW_RANGE_PER_RADIUS * boost
			)
		else
			Build.pointLight(
				anchor,
				anchor.Color,
				ECHO_BRIGHTNESS,
				Config.World.echoLightRange * boost
			)
		end
	end
	echo.model.Parent = level.lit
	if echo.kind ~= "sign" then
		buildPatch(
			level.plan.maze,
			level.origin,
			echo.cell,
			level.lit,
			if echo.anchor then echo.anchor.Position else echo.model:GetPivot().Position,
			level.plan.tier,
			showsPlace,
			level.plan.flooded
		)
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
	local prompt = Build.prompt(door, "Open", "Exit", 0.4)
	return door, prompt
end

-- The thing that opens a locked exit, as the story names it for this level: a fuse, a valve
-- wheel, a coil of rope, a crank, a lamp core, or a brass key. `at` is where it hovers.
local function buildGateItem(gate: string, at: Vector3, parent: Instance)
	local function part(
		name: string,
		size: Vector3,
		offset: CFrame,
		color: Color3,
		shape: Enum.PartType?,
		material: Enum.Material?
	)
		return Build.part({
			name = name,
			size = size,
			cframe = CFrame.new(at) * offset,
			color = color,
			material = material,
			shape = shape,
			collide = false,
			parent = parent,
		})
	end
	local upright = CFrame.Angles(0, 0, math.rad(90))
	local cylinder = Enum.PartType.Cylinder
	local brass = Color3.fromRGB(196, 160, 84)
	if gate == "fuse" then
		part(
			"Tube",
			Vector3.new(1.6, 0.6, 0.6),
			upright,
			Color3.fromRGB(200, 214, 220),
			cylinder,
			Enum.Material.Glass
		)
		part(
			"CapTop",
			Vector3.new(0.3, 0.7, 0.7),
			CFrame.new(0, 0.9, 0) * upright,
			brass,
			cylinder,
			Enum.Material.Metal
		)
		part(
			"CapBottom",
			Vector3.new(0.3, 0.7, 0.7),
			CFrame.new(0, -0.9, 0) * upright,
			brass,
			cylinder,
			Enum.Material.Metal
		)
	elseif gate == "valve" then
		local iron = Color3.fromRGB(86, 90, 92)
		part("Wheel", Vector3.new(0.25, 2.4, 2.4), upright, iron, cylinder, Enum.Material.Metal)
		part("SpokeA", Vector3.new(2.6, 0.18, 0.22), CFrame.new(), iron, nil, Enum.Material.Metal)
		part("SpokeB", Vector3.new(0.22, 0.18, 2.6), CFrame.new(), iron, nil, Enum.Material.Metal)
	elseif gate == "rope" then
		local fibre = Color3.fromRGB(168, 142, 96)
		for step = 0, 7 do
			local angle = step / 8 * math.pi * 2
			part(
				"Coil",
				Vector3.new(0.5, 0.5, 0.9),
				CFrame.new(math.cos(angle) * 0.9, 0, math.sin(angle) * 0.9)
					* CFrame.Angles(0, -angle, 0),
				fibre,
				nil,
				Enum.Material.Fabric
			)
		end
		part(
			"End",
			Vector3.new(0.3, 0.3, 1.2),
			CFrame.new(1.2, -0.3, 0.8),
			fibre,
			nil,
			Enum.Material.Fabric
		)
	elseif gate == "crank" then
		local iron = Color3.fromRGB(86, 90, 92)
		part("Shaft", Vector3.new(0.25, 1.6, 0.25), CFrame.new(), iron, nil, Enum.Material.Metal)
		part(
			"Arm",
			Vector3.new(1.2, 0.22, 0.22),
			CFrame.new(0.5, 0.8, 0),
			iron,
			nil,
			Enum.Material.Metal
		)
		part(
			"Knob",
			Vector3.new(0.5, 0.5, 0.5),
			CFrame.new(1.1, 0.8, 0),
			Color3.fromRGB(122, 86, 56),
			Enum.PartType.Ball,
			Enum.Material.Wood
		)
	elseif gate == "core" then
		local glass = part(
			"Glass",
			Vector3.new(1.3, 1.3, 1.3),
			CFrame.new(),
			Color3.fromRGB(214, 232, 255),
			Enum.PartType.Ball,
			Enum.Material.Neon
		)
		glass.Transparency = 0.25
	else
		local key = part(
			"Key",
			Vector3.new(0.3, 0.5, 1.5),
			CFrame.Angles(0, math.rad(30), 0),
			Color3.fromRGB(196, 160, 84),
			nil,
			Enum.Material.Metal
		)
		Build.part({
			name = "Bow",
			size = Vector3.new(0.3, 0.9, 0.9),
			cframe = key.CFrame * CFrame.new(0, 0, 1),
			shape = Enum.PartType.Cylinder,
			collide = false,
			parent = parent,
		})
	end
end

-- The story's name for a level's gate item and the line that goes with it ("Fuse", "Not
-- blown. Just waiting."). Endless floors and any gate without an entry fall back to the key.
function World.gate(plan: LevelPlan.LevelPlan): (string, string, string)
	local gate = plan.def.gate or "key"
	local entry = LoreText.get("item." .. gate)
	if entry == nil then
		gate = "key"
		entry = LoreText.get("item.key")
	end
	local title = if entry and entry.title then entry.title else "Key"
	local line = if entry then entry.lines[1] or "" else ""
	local description = string.gsub(line, "^[^:]*:%s*", "")
	return gate, title, description
end

local function buildPickup(
	objective: LevelPlan.Objective,
	gate: string,
	gateTitle: string,
	center: Vector3,
	face: CFrame,
	parent: Instance,
	tier: number
): Pickup
	local model = Build.model("Pickup_" .. objective.kind, parent)
	local prompt: ProximityPrompt
	if objective.kind == "rescue" then
		-- Before a camp that has a surveyor, the one you find here is them: same face in the dark,
		-- the same name on the prompt, and the same person is waiting in the camp afterwards.
		local who = Lore.surveyors[Config.Surveyor.rescueOfTier[tier] or ""]
		local figure = if who
			then Figures.surveyor(model, who, Config.Tags.friend, true)
			else Figures.sitting(model, Config.Tags.friend)
		figure:PivotTo(face * CFrame.new(0, 0, -1.4))
		CollectionService:AddTag(figure, Config.Tags.rescue)
		prompt = Build.prompt(
			figure.PrimaryPart :: BasePart,
			"Help up",
			if who then who.name else "Surveyor",
			1.5
		)
	else
		CollectionService:AddTag(model, Config.Tags.objective)
		local stand = Build.part({
			name = "Stand",
			size = Vector3.new(1.6, 2.6, 1.6),
			cframe = CFrame.new(center + Vector3.new(0, 1.3, 0)),
			parent = model,
		})
		if objective.kind == "key" then
			buildGateItem(gate, center + Vector3.new(0, 3, 0), model)
			prompt = Build.prompt(stand, "Take", gateTitle, 0.3)
		elseif objective.kind == "cell" then
			-- A double cell is two cylinders side by side, so its dots read differently.
			local charges = objective.charges or 1
			for index = 1, charges do
				local offset = (index - (charges + 1) / 2) * 1.05
				Build.part({
					name = "Cell",
					size = Vector3.new(1.8, 0.9, 0.9),
					cframe = CFrame.new(center + Vector3.new(offset, 3.5, 0))
						* CFrame.Angles(0, 0, math.rad(90)),
					shape = Enum.PartType.Cylinder,
					collide = false,
					parent = model,
				})
			end
			model:SetAttribute("Charges", charges)
			local title = if charges > 1
				then "Battery cells (2 sweeps)"
				else "Battery cell (1 sweep)"
			prompt = Build.prompt(stand, "Take", title, 0.3)
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
	local gate, gateTitle = World.gate(plan)
	for _, objective in plan.objectives do
		local center = World.cellCenter(origin, objective.cell)
		local closed = closedSides(maze, objective.cell)
		local face = if #closed > 0 then wallBase(center, closed[1]) else CFrame.new(center)
		table.insert(
			pickups,
			buildPickup(objective, gate, gateTitle, center, face, dark, plan.tier)
		)
	end
	-- Hidden things get ids in this order: recorders, story objects, posters, then lamp-bags.
	local echoes = buildRecorders(plan, origin, dark, rng, 1)
	for _, echo in buildReveals(plan, origin, dark, rng, #echoes + 1) do
		table.insert(echoes, echo)
	end
	for _, echo in buildSigns(plan, origin, dark, #echoes + 1) do
		table.insert(echoes, echo)
	end
	if plan.tier == 1 then
		-- Level 1 starts where the player lands: the wall behind them has melted.
		local center = World.cellCenter(origin, maze.start)
		local closed = closedSides(maze, maze.start)
		local facing = "N"
		for _, name in Maze.DIR_NAMES do
			if Maze.isOpen(maze, maze.start.x, maze.start.y, name) then
				facing = name
				break
			end
		end
		local behind = ({ N = "S", S = "N", E = "W", W = "E" })[facing]
		local side = if table.find(closed, behind) then behind else closed[1]
		if side ~= nil then
			Props.meltedWall(wallBase(center, side), dark)
		end
	end
	Build.hide(dark)
	for _, echo in buildLamps(plan, origin, lit, rng, #echoes + 1) do
		table.insert(echoes, echo)
	end
	-- Lamps and their lit patches start dark too: each client shows them as its scan finds
	-- them (client/Immersion). Things revealed later are moved into `lit` already showing.
	Build.conceal(lit)

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
