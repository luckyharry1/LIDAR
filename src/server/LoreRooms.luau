--!strict
-- Builds the lit lore rooms: bright, human-scale, safe. Each theme is a layout table of props
-- and note positions, so a new room is mostly data. Coordinates are room-local, measured from
-- the centre of the floor; the entrance is on the south wall (+z) and the exit on the north.
--
-- Yaw convention for wall props (they extend out of their back): north wall 180, south 0,
-- west -90, east 90.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Config = require(ReplicatedStorage.Shared.Config)
local Lore = require(ReplicatedStorage.Shared.data.Lore)
local Props = require(script.Parent.Props)

export type NotePrompt = { id: string, prompt: ProximityPrompt }
export type LoreRoom = {
	model: Model,
	room: Lore.Room,
	spawnCFrame: CFrame,
	exitPrompt: ProximityPrompt,
	benchPrompt: ProximityPrompt,
	notes: { NotePrompt },
}

type Placement = { kit: string, x: number, z: number, yaw: number }
type NoteSpot = { x: number, y: number, z: number, yaw: number, flat: boolean }
type Layout = {
	props: { Placement },
	notes: { NoteSpot }, -- in the same order as the room's note list
	raisedEntrance: boolean?, -- true: players arrive on a landing and walk down stairs
	flicker: boolean?,
	stone: boolean?, -- true: slate walls and floor instead of plaster and boards
	extras: ((origin: Vector3, parent: Instance) -> ())?, -- anything the kits cannot express
}

local HALF_X = 20
local HALF_Z = 15
local ROOM_HEIGHT = 12
local WALL = 1
local DOOR_WIDTH = 5
local DOOR_HEIGHT = 8.4
local SPAWN_HEIGHT = 3
local LANDING_HEIGHT = 5
local LANDING_DEPTH = 5
local STEP_DEPTH = 1.6
local PANEL_OFFSETS = { -11, 0, 11 }
local FLICKER_MIN, FLICKER_MAX = 0.05, 0.6

-- The waterfall in the Cistern comes down the west wall into a railed pool.
local FALL_X = -16.2 -- room-local position of the sheet of water
local FALL_TOP = 9.8
local FALL_WIDTH = 5
local POOL_EAST = -11 -- the pool runs from the west wall to here
local POOL_HALF_Z = 7
local POOL_SURFACE = 0.6
local RIM_HEIGHT = 0.9
local RAIL_HEIGHT = 3.2
local ROCK = Color3.fromRGB(70, 82, 84)
local WATER = Color3.fromRGB(110, 200, 255)
local MOSS = Color3.fromRGB(64, 132, 70)
local MIST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local function mist(parent: BasePart, falling: boolean)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = MIST_TEXTURE
	emitter.Color = ColorSequence.new(Color3.fromRGB(210, 240, 255))
	emitter.LightEmission = 0.5
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-30, 30)
	if falling then
		emitter.EmissionDirection = Enum.NormalId.Bottom
		emitter.Rate = 70
		emitter.Lifetime = NumberRange.new(0.8, 1.1)
		emitter.Speed = NumberRange.new(3, 5)
		emitter.Acceleration = Vector3.new(0, -22, 0)
		emitter.SpreadAngle = Vector2.new(5, 5)
		emitter.Size = NumberSequence.new(0.9, 1.7)
		emitter.Transparency = NumberSequence.new(0.45, 1)
	else
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Rate = 26
		emitter.Lifetime = NumberRange.new(1.6, 2.6)
		emitter.Speed = NumberRange.new(1, 2.2)
		emitter.SpreadAngle = Vector2.new(50, 50)
		emitter.Size = NumberSequence.new(1.4, 4.2)
		emitter.Transparency = NumberSequence.new(0.7, 1)
	end
	emitter.Parent = parent
end

local function buildWaterfall(origin: Vector3, parent: Instance)
	local model = Build.model("Waterfall", parent)
	local function block(
		name: string,
		size: Vector3,
		position: Vector3,
		yaw: number,
		color: Color3,
		material: Enum.Material,
		collide: boolean
	): Part
		return Build.part({
			name = name,
			size = size,
			cframe = CFrame.new(origin + position) * CFrame.Angles(0, math.rad(yaw), 0),
			color = color,
			material = material,
			collide = collide,
			parent = model,
		})
	end
	local slate = Enum.Material.Slate
	local neon = Enum.Material.Neon
	local wallX = -HALF_X
	-- The rock face, a lip for the water to leave from, and boulders either side of it.
	block(
		"Rock",
		Vector3.new(2.6, ROOM_HEIGHT, 16),
		Vector3.new(wallX + 1.3, ROOM_HEIGHT / 2, 0),
		0,
		ROCK,
		slate,
		true
	)
	block(
		"Lip",
		Vector3.new(4.2, 1.6, FALL_WIDTH + 2),
		Vector3.new(wallX + 2.1, FALL_TOP + 0.6, 0),
		0,
		ROCK,
		slate,
		true
	)
	block(
		"Boulder",
		Vector3.new(3.6, 5, 4),
		Vector3.new(wallX + 2.4, 2.5, -6.4),
		12,
		ROCK,
		slate,
		true
	)
	block(
		"Boulder",
		Vector3.new(3.2, 7, 3.6),
		Vector3.new(wallX + 2.2, 3.5, 6.6),
		-9,
		ROCK,
		slate,
		true
	)
	block(
		"Boulder",
		Vector3.new(2.2, 2, 2.6),
		Vector3.new(wallX + 4.4, 1, 5.2),
		30,
		ROCK,
		slate,
		true
	)

	-- The fall itself: a bright sheet with two paler streaks, and mist where it lands.
	local fallHeight = FALL_TOP - POOL_SURFACE
	local fallMiddle = POOL_SURFACE + fallHeight / 2
	local sheet = block(
		"Fall",
		Vector3.new(0.5, fallHeight, FALL_WIDTH),
		Vector3.new(FALL_X, fallMiddle, 0),
		0,
		WATER,
		neon,
		false
	)
	sheet.Transparency = 0.45
	for _, z in { -1.3, 1.1 } do
		local streak = block(
			"Streak",
			Vector3.new(0.6, fallHeight, 0.7),
			Vector3.new(FALL_X, fallMiddle, z),
			0,
			Color3.fromRGB(225, 245, 255),
			neon,
			false
		)
		streak.Transparency = 0.6
	end
	local head = block(
		"FallHead",
		Vector3.new(0.4, 0.4, FALL_WIDTH),
		Vector3.new(FALL_X, FALL_TOP, 0),
		0,
		WATER,
		neon,
		false
	)
	head.Transparency = 1
	mist(head, true)
	local foot = block(
		"FallFoot",
		Vector3.new(1.4, 0.2, FALL_WIDTH + 1),
		Vector3.new(FALL_X + 0.6, POOL_SURFACE + 0.2, 0),
		0,
		WATER,
		neon,
		false
	)
	foot.Transparency = 1
	mist(foot, false)
	Build.loop(sheet, Config.Audio.waterfall, 0.6, 1, 70)

	-- The pool, lit from below, inside a low stone rim with a rail on the room side.
	local poolWidth = POOL_EAST - wallX
	local poolMiddle = wallX + poolWidth / 2
	local pool = block(
		"Pool",
		Vector3.new(poolWidth, POOL_SURFACE, POOL_HALF_Z * 2),
		Vector3.new(poolMiddle, POOL_SURFACE / 2, 0),
		0,
		Color3.fromRGB(40, 150, 200),
		Enum.Material.SmoothPlastic,
		false
	)
	pool.Transparency = 0.25
	Build.pointLight(pool, Color3.fromRGB(90, 220, 255), 1.6, 24)
	block(
		"Rim",
		Vector3.new(1, RIM_HEIGHT, POOL_HALF_Z * 2 + 2),
		Vector3.new(POOL_EAST + 0.5, RIM_HEIGHT / 2, 0),
		0,
		ROCK,
		slate,
		true
	)
	for _, sign in { -1, 1 } do
		block(
			"Rim",
			Vector3.new(poolWidth, RIM_HEIGHT, 1),
			Vector3.new(poolMiddle, RIM_HEIGHT / 2, sign * (POOL_HALF_Z + 0.5)),
			0,
			ROCK,
			slate,
			true
		)
	end
	local railColor = Color3.fromRGB(70, 74, 80)
	for z = -6, 6, 4 do
		block(
			"Post",
			Vector3.new(0.25, RAIL_HEIGHT, 0.25),
			Vector3.new(POOL_EAST + 0.5, RAIL_HEIGHT / 2, z),
			0,
			railColor,
			Enum.Material.Metal,
			true
		)
	end
	block(
		"Rail",
		Vector3.new(0.25, 0.25, POOL_HALF_Z * 2 - 1),
		Vector3.new(POOL_EAST + 0.5, RAIL_HEIGHT, 0),
		0,
		railColor,
		Enum.Material.Metal,
		true
	)

	-- Moss where the spray reaches.
	local grass = Enum.Material.Grass
	block(
		"Moss",
		Vector3.new(5, 0.1, 4),
		Vector3.new(POOL_EAST + 3.6, 0.05, -4.5),
		14,
		MOSS,
		grass,
		false
	)
	block(
		"Moss",
		Vector3.new(3.4, 0.1, 5),
		Vector3.new(POOL_EAST + 2.8, 0.05, 4.8),
		-20,
		MOSS,
		grass,
		false
	)
	block(
		"Moss",
		Vector3.new(4.2, 0.12, 1),
		Vector3.new(wallX + 2.3, FALL_TOP + 1.46, 0.4),
		0,
		MOSS,
		grass,
		false
	)
end

local LAYOUTS: { [string]: Layout } = {
	office = {
		props = {
			{ kit = "desk", x = -12, z = -15, yaw = 180 },
			{ kit = "chair", x = -12, z = -9.4, yaw = 0 },
			{ kit = "desk", x = -20, z = 3, yaw = -90 },
			{ kit = "chair", x = -14.4, z = 3, yaw = 90 },
			{ kit = "shelf", x = 20, z = -9, yaw = 90 },
			{ kit = "cabinet", x = 20, z = -3.5, yaw = 90 },
			{ kit = "cabinet", x = 20, z = -0.6, yaw = 90 },
			{ kit = "bench", x = 20, z = 8, yaw = 90 },
			{ kit = "board", x = 9, z = -15, yaw = 180 },
			{ kit = "lamp", x = -17.5, z = -15, yaw = 180 },
			{ kit = "plant", x = 16.5, z = -15, yaw = 180 },
			{ kit = "plant", x = -17.5, z = 15, yaw = 0 },
			{ kit = "rug", x = 0, z = 3, yaw = 0 },
		},
		notes = {
			{ x = -16.6, y = 4.2, z = -14.2, yaw = 180, flat = false },
			{ x = -11.2, y = 3.12, z = -13.4, yaw = 20, flat = true },
			{ x = -18.4, y = 3.12, z = 3.6, yaw = 80, flat = true },
		},
	},
	breakroom = {
		props = {
			{ kit = "table", x = 0, z = 1.7, yaw = 0 },
			{ kit = "chair", x = 0, z = 5.6, yaw = 0 },
			{ kit = "chair", x = 0, z = -5.6, yaw = 180 },
			{ kit = "chair", x = -5.4, z = 0, yaw = -90 },
			{ kit = "chair", x = 5.4, z = 0, yaw = 90 },
			{ kit = "vending", x = -12, z = -15, yaw = 180 },
			{ kit = "kettle", x = 10, z = -15, yaw = 180 },
			{ kit = "board", x = -20, z = 0, yaw = -90 },
			{ kit = "bench", x = 20, z = 5, yaw = 90 },
			{ kit = "shelf", x = 20, z = -9, yaw = 90 },
			{ kit = "plant", x = 17, z = 15, yaw = 0 },
			{ kit = "lamp", x = -17, z = 15, yaw = 0 },
			{ kit = "rug", x = 0, z = 3, yaw = 0 },
		},
		notes = {
			{ x = -19.7, y = 4.4, z = 2.2, yaw = -90, flat = false },
			{ x = 0.8, y = 3.02, z = 0.4, yaw = 30, flat = true },
			{ x = 11.6, y = 4.2, z = -14.7, yaw = 180, flat = false },
		},
	},
	cistern = {
		stone = true,
		extras = buildWaterfall,
		props = {
			{ kit = "bench", x = 20, z = 6, yaw = 90 },
			{ kit = "table", x = 9, z = 15, yaw = 0 },
			{ kit = "chair", x = 9, z = 10.2, yaw = 180 },
			{ kit = "plant", x = 16.5, z = 15, yaw = 0 },
			{ kit = "seedlings", x = 12, z = -15, yaw = 180 },
			{ kit = "fern", x = -14, z = 15, yaw = 0 },
			{ kit = "fern", x = -9, z = -15, yaw = 180 },
			{ kit = "fern", x = 20, z = -4, yaw = 90 },
			{ kit = "flowers", x = -8, z = 15, yaw = 0 },
			{ kit = "flowers", x = -15, z = -15, yaw = 180 },
			{ kit = "flowers", x = 20, z = -10, yaw = 90 },
			{ kit = "flowers", x = 5.5, z = -15, yaw = 180 },
		},
		notes = {
			{ x = -10.3, y = 2.2, z = 3, yaw = -90, flat = false },
			{ x = -5.4, y = 4.4, z = -14.7, yaw = 180, flat = false },
			{ x = 9.6, y = 3.02, z = 13.2, yaw = -20, flat = true },
		},
	},
	stairwell = {
		raisedEntrance = true,
		flicker = true,
		props = {
			{ kit = "desk", x = -10, z = -15, yaw = 180 },
			{ kit = "chair", x = -10, z = -9.4, yaw = 0 },
			{ kit = "cradle", x = -5.6, z = -15, yaw = 180 },
			{ kit = "lamp", x = -15.5, z = -15, yaw = 180 },
			{ kit = "board", x = -20, z = -5, yaw = -90 },
			{ kit = "shelf", x = 20, z = -9, yaw = 90 },
			{ kit = "bench", x = 20, z = 1, yaw = 90 },
			{ kit = "cabinet", x = 12, z = -15, yaw = 180 },
			{ kit = "plant", x = 16.5, z = -15, yaw = 180 },
			{ kit = "rug", x = -8, z = -4, yaw = 0 },
		},
		notes = {
			{ x = -19.7, y = 4.4, z = -3.2, yaw = -90, flat = false },
			{ x = -11.4, y = 3.12, z = -13.6, yaw = 0, flat = true },
			{ x = -8.6, y = 3.12, z = -13.2, yaw = 25, flat = true },
		},
	},
	landing = {
		props = {
			{ kit = "table", x = -8, z = -15, yaw = 180 },
			{ kit = "chair", x = -8, z = -10, yaw = 0 },
			{ kit = "lamp", x = -14, z = -15, yaw = 180 },
			{ kit = "bench", x = 20, z = 2, yaw = 90 },
			{ kit = "plant", x = 16, z = -15, yaw = 180 },
			{ kit = "rug", x = 0, z = 3, yaw = 0 },
		},
		notes = {
			{ x = -9, y = 3.02, z = -13.4, yaw = 10, flat = true },
			{ x = -7, y = 3.02, z = -12.6, yaw = -30, flat = true },
			{ x = -8.2, y = 3.02, z = -14.2, yaw = 60, flat = true },
		},
	},
}

local LoreRooms = {}

local function at(origin: Vector3, x: number, y: number, z: number, yaw: number): CFrame
	return CFrame.new(origin + Vector3.new(x, y, z)) * CFrame.Angles(0, math.rad(yaw), 0)
end

local function buildShell(room: Lore.Room, layout: Layout, origin: Vector3, parent: Instance)
	local wallColor = Build.rgb(room.wall)
	local function slab(
		name: string,
		size: Vector3,
		position: Vector3,
		color: Color3,
		material: Enum.Material
	)
		Build.part({
			name = name,
			size = size,
			cframe = CFrame.new(origin + position),
			color = color,
			material = material,
			parent = parent,
		})
	end
	local spanX, spanZ = HALF_X * 2 + WALL * 2, HALF_Z * 2 + WALL * 2
	slab(
		"Floor",
		Vector3.new(spanX, 1, spanZ),
		Vector3.new(0, -0.5, 0),
		Build.rgb(room.floor),
		if layout.stone then Enum.Material.Slate else Enum.Material.WoodPlanks
	)
	slab(
		"Ceiling",
		Vector3.new(spanX, 1, spanZ),
		Vector3.new(0, ROOM_HEIGHT + 0.5, 0),
		wallColor,
		Enum.Material.SmoothPlastic
	)
	local plaster = if layout.stone then Enum.Material.Slate else Enum.Material.SmoothPlastic
	slab(
		"WallN",
		Vector3.new(spanX, ROOM_HEIGHT, WALL),
		Vector3.new(0, ROOM_HEIGHT / 2, -HALF_Z - WALL / 2),
		wallColor,
		plaster
	)
	slab(
		"WallS",
		Vector3.new(spanX, ROOM_HEIGHT, WALL),
		Vector3.new(0, ROOM_HEIGHT / 2, HALF_Z + WALL / 2),
		wallColor,
		plaster
	)
	slab(
		"WallW",
		Vector3.new(WALL, ROOM_HEIGHT, spanZ),
		Vector3.new(-HALF_X - WALL / 2, ROOM_HEIGHT / 2, 0),
		wallColor,
		plaster
	)
	slab(
		"WallE",
		Vector3.new(WALL, ROOM_HEIGHT, spanZ),
		Vector3.new(HALF_X + WALL / 2, ROOM_HEIGHT / 2, 0),
		wallColor,
		plaster
	)
	-- A dado rail and skirting so the walls do not read as flat colour.
	local trim = wallColor:Lerp(Color3.new(0, 0, 0), 0.35)
	for _, y in { 0.4, 4 } do
		local height = if y < 1 then 0.8 else 0.3
		slab(
			"TrimN",
			Vector3.new(HALF_X * 2, height, 0.2),
			Vector3.new(0, y, -HALF_Z + 0.1),
			trim,
			plaster
		)
		slab(
			"TrimS",
			Vector3.new(HALF_X * 2, height, 0.2),
			Vector3.new(0, y, HALF_Z - 0.1),
			trim,
			plaster
		)
		slab(
			"TrimW",
			Vector3.new(0.2, height, HALF_Z * 2),
			Vector3.new(-HALF_X + 0.1, y, 0),
			trim,
			plaster
		)
		slab(
			"TrimE",
			Vector3.new(0.2, height, HALF_Z * 2),
			Vector3.new(HALF_X - 0.1, y, 0),
			trim,
			plaster
		)
	end
end

local function buildLights(room: Lore.Room, layout: Layout, origin: Vector3, parent: Instance)
	local color = Build.rgb(room.light)
	for _, x in PANEL_OFFSETS do
		local panel = Build.part({
			name = "LightPanel",
			size = Vector3.new(5, 0.2, 2.2),
			cframe = CFrame.new(origin + Vector3.new(x, ROOM_HEIGHT - 0.1, 0)),
			color = color,
			material = Enum.Material.Neon,
			collide = false,
			parent = parent,
		})
		local light = Build.pointLight(panel, color, 1.5, 34)
		if layout.flicker and x == PANEL_OFFSETS[1] then
			-- One tired tube that never quite settles.
			task.spawn(function()
				local random = Random.new()
				while panel.Parent ~= nil do
					light.Enabled = not light.Enabled
					panel.Material = if light.Enabled
						then Enum.Material.Neon
						else Enum.Material.SmoothPlastic
					task.wait(
						if light.Enabled
							then random:NextNumber(FLICKER_MAX, FLICKER_MAX * 4)
							else random:NextNumber(FLICKER_MIN, FLICKER_MAX)
					)
				end
			end)
		end
	end
end

local function buildDoor(
	origin: Vector3,
	z: number,
	yaw: number,
	name: string,
	parent: Instance,
	y: number
): BasePart
	local base = at(origin, 0, y, z, yaw)
	local door = Build.part({
		name = name,
		size = Vector3.new(DOOR_WIDTH, DOOR_HEIGHT, 0.5),
		cframe = base * CFrame.new(0, DOOR_HEIGHT / 2, -0.25),
		color = Color3.fromRGB(110, 78, 50),
		material = Enum.Material.Wood,
		parent = parent,
	})
	for _, x in { -DOOR_WIDTH / 2 - 0.3, DOOR_WIDTH / 2 + 0.3 } do
		Build.part({
			name = "Jamb",
			size = Vector3.new(0.6, DOOR_HEIGHT + 0.6, 0.7),
			cframe = base * CFrame.new(x, (DOOR_HEIGHT + 0.6) / 2, -0.3),
			color = Color3.fromRGB(70, 50, 34),
			material = Enum.Material.Wood,
			parent = parent,
		})
	end
	Build.part({
		name = "Header",
		size = Vector3.new(DOOR_WIDTH + 1.2, 0.6, 0.7),
		cframe = base * CFrame.new(0, DOOR_HEIGHT + 0.3, -0.3),
		color = Color3.fromRGB(70, 50, 34),
		material = Enum.Material.Wood,
		parent = parent,
	})
	Build.part({
		name = "Handle",
		size = Vector3.new(0.3, 0.3, 0.6),
		cframe = base * CFrame.new(DOOR_WIDTH / 2 - 0.7, 4, -0.7),
		color = Color3.fromRGB(196, 160, 84),
		material = Enum.Material.Metal,
		parent = parent,
	})
	return door
end

-- A landing against the south wall with steps down to the floor, for the stairwell room.
local function buildStairs(origin: Vector3, parent: Instance)
	local stone = Color3.fromRGB(120, 116, 110)
	Build.part({
		name = "Landing",
		size = Vector3.new(9, LANDING_HEIGHT, LANDING_DEPTH),
		cframe = CFrame.new(
			origin + Vector3.new(0, LANDING_HEIGHT / 2, HALF_Z - LANDING_DEPTH / 2)
		),
		color = stone,
		parent = parent,
	})
	for step = 1, LANDING_HEIGHT - 1 do
		local height = LANDING_HEIGHT - step
		Build.part({
			name = "Step",
			size = Vector3.new(9, height, STEP_DEPTH),
			cframe = CFrame.new(
				origin
					+ Vector3.new(0, height / 2, HALF_Z - LANDING_DEPTH - (step - 0.5) * STEP_DEPTH)
			),
			color = stone,
			parent = parent,
		})
	end
	for _, x in { -4.4, 4.4 } do
		Build.part({
			name = "Rail",
			size = Vector3.new(0.3, 3, LANDING_DEPTH),
			cframe = CFrame.new(
				origin + Vector3.new(x, LANDING_HEIGHT + 1.5, HALF_Z - LANDING_DEPTH / 2)
			),
			color = Color3.fromRGB(70, 74, 80),
			material = Enum.Material.Metal,
			parent = parent,
		})
	end
end

function LoreRooms.build(roomId: string, origin: Vector3): LoreRoom
	local room = Lore.rooms[roomId]
	assert(room ~= nil, "unknown lore room " .. roomId)
	local layout = LAYOUTS[room.theme]
	assert(layout ~= nil, "no layout for theme " .. room.theme)

	local model = Build.model("LoreRoom_" .. roomId, workspace)
	buildShell(room, layout, origin, model)
	buildLights(room, layout, origin, model)
	if layout.extras then
		layout.extras(origin, model)
	end

	local entranceHeight = if layout.raisedEntrance then LANDING_HEIGHT else 0
	if layout.raisedEntrance then
		buildStairs(origin, model)
	end
	buildDoor(origin, HALF_Z, 0, "EntranceDoor", model, entranceHeight)
	local exitDoor = buildDoor(origin, -HALF_Z, 180, "ExitDoor", model, 0)
	local exitPrompt = Build.prompt(exitDoor, "Continue", "Into the dark", 0.6)

	local benchPrompt: ProximityPrompt? = nil
	for _, placement in layout.props do
		local prop = Props.place(
			placement.kit,
			at(origin, placement.x, 0, placement.z, placement.yaw),
			model
		)
		if placement.kit == "bench" then
			benchPrompt = Build.prompt(prop.PrimaryPart :: BasePart, "Use", "Workbench", 0.2)
		end
	end
	assert(benchPrompt ~= nil, "every lore room needs a bench")

	local notes: { NotePrompt } = {}
	for index, noteId in room.notes do
		local spot = layout.notes[index]
		local note = Lore.notes[noteId]
		local tilt = if spot.flat then CFrame.new() else CFrame.Angles(math.rad(90), 0, 0)
		local paper = Build.part({
			name = "Note",
			size = Vector3.new(1.3, 0.06, 1.7),
			cframe = at(origin, spot.x, spot.y, spot.z, spot.yaw) * tilt,
			color = Color3.fromRGB(240, 234, 214),
			material = Enum.Material.SmoothPlastic,
			collide = false,
			parent = model,
		})
		table.insert(notes, { id = noteId, prompt = Build.prompt(paper, "Read", note.title, 0.2) })
	end

	-- The lit zone tells each client to bring the lights up while they stand inside it.
	local zone = Build.part({
		name = "LitZone",
		size = Vector3.new(HALF_X * 2 + WALL * 2, ROOM_HEIGHT + 2, HALF_Z * 2 + WALL * 2),
		cframe = CFrame.new(origin + Vector3.new(0, ROOM_HEIGHT / 2, 0)),
		transparency = 1,
		collide = false,
		query = false,
		tag = Config.Tags.litZone,
		parent = model,
	})
	zone:SetAttribute("Light", Build.rgb(room.light))
	zone:SetAttribute("Title", room.title)
	zone:SetAttribute("Subtitle", room.subtitle)

	local spawnPoint = origin + Vector3.new(0, entranceHeight + SPAWN_HEIGHT, HALF_Z - 3)
	return {
		model = model,
		room = room,
		spawnCFrame = CFrame.lookAt(spawnPoint, spawnPoint + Vector3.new(0, 0, -1)),
		exitPrompt = exitPrompt,
		benchPrompt = benchPrompt :: ProximityPrompt,
		notes = notes,
	}
end

return LoreRooms
