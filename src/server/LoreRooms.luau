--!strict
-- Builds the lit lore rooms: bright, human-scale, safe. Each theme is a layout table of props
-- and note positions, so a new room is mostly data. Coordinates are room-local, measured from
-- the centre of the floor; the entrance is on the south wall (+z) and the exit on the north.
--
-- Yaw convention for wall props (they extend out of their back): north wall 180, south 0,
-- west -90, east 90.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Config = require(ReplicatedStorage.Shared.Config)
local Lore = require(ReplicatedStorage.Shared.data.Lore)
local Props = require(script.Parent.Props)

export type NotePrompt = { id: string, prompt: ProximityPrompt }
-- A dark room has one object that stands out: its lamp, or the waterfall. Scanned enough, it
-- lights the room and says the room's card. `reveal` does the lighting.
export type Beacon = {
	id: number,
	position: Vector3,
	title: string,
	subtitle: string,
	revealed: boolean,
	reveal: () -> (),
}
export type LoreRoom = {
	model: Model,
	room: Lore.Room,
	spawnCFrame: CFrame,
	exitPrompt: ProximityPrompt,
	benchPrompt: ProximityPrompt,
	notes: { NotePrompt },
	beacon: Beacon?, -- nil in a room that is lit from the start
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
	halfX: number?, -- half the room's width and depth, and its height; the big rooms use
	halfZ: number?, -- the defaults below, the small havens are smaller
	height: number?,
}

local HALF_X = 20 -- a big lit room is 40 by 30 studs and 12 high; a haven sets its own size
local HALF_Z = 15
local ROOM_HEIGHT = 12
local BEACON_ID = 60 -- the echo id of a dark room's beacon, clear of any level's own ids
local LAMP_REACH = 22 -- how far from its lamp a dark room shows itself once the lamp is revealed
local FALLS_REACH = 48 -- the waterfall lights the whole cavern
local HAVEN_PANELS = { -4.5, 4.5 } -- light panels in a haven (a big room uses PANEL_OFFSETS)
-- Ceiling tubes. A lit room (the Lamp Room, the Relay landing) has them on but soft. In a dark
-- haven they stay dead when its lamp is found: dim plastic and a faint glow, so the lamp is the
-- light and the corners stay dark. Neon panels there bloomed into a white-out.
local PANEL_BRIGHTNESS, PANEL_RANGE = 0.9, 30
local DEAD_TUBE_BRIGHTNESS, DEAD_TUBE_RANGE = 0.25, 16
local DEAD_TUBE_COLOR = Color3.fromRGB(96, 92, 84)
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
local FORD_HALF = 2.5 -- the gap in the pool's rim is twice this wide
local ALCOVE_HEIGHT = 7 -- the niche behind the fall is 4 wide, 2 deep and this high
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
	-- The rock face has a niche in it, behind the water: a secret alcove (see below).
	for _, sign in { -1, 1 } do
		block(
			"Rock",
			Vector3.new(2.6, ROOM_HEIGHT, 6),
			Vector3.new(wallX + 1.3, ROOM_HEIGHT / 2, sign * 5),
			0,
			ROCK,
			slate,
			true
		)
	end
	block(
		"RockBack",
		Vector3.new(0.6, ROOM_HEIGHT, 4),
		Vector3.new(wallX + 0.3, ROOM_HEIGHT / 2, 0),
		0,
		ROCK,
		slate,
		true
	)
	block(
		"RockTop",
		Vector3.new(2, ROOM_HEIGHT - ALCOVE_HEIGHT, 4),
		Vector3.new(wallX + 1.6, ALCOVE_HEIGHT + (ROOM_HEIGHT - ALCOVE_HEIGHT) / 2, 0),
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
	-- The rim and rail on the room side have a gap in the middle, a ford straight across the
	-- pool to the sheet of water and the alcove behind it.
	local sideLength = POOL_HALF_Z + 1 - FORD_HALF
	for _, sign in { -1, 1 } do
		block(
			"Rim",
			Vector3.new(1, RIM_HEIGHT, sideLength),
			Vector3.new(POOL_EAST + 0.5, RIM_HEIGHT / 2, sign * (FORD_HALF + sideLength / 2)),
			0,
			ROCK,
			slate,
			true
		)
	end
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
	local railLength = POOL_HALF_Z - 0.5 - FORD_HALF
	for _, sign in { -1, 1 } do
		block(
			"Rail",
			Vector3.new(0.25, 0.25, railLength),
			Vector3.new(POOL_EAST + 0.5, RAIL_HEIGHT, sign * (FORD_HALF + railLength / 2)),
			0,
			railColor,
			Enum.Material.Metal,
			true
		)
	end

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

	-- The alcove: a chalk drawing of the whole building on the back wall, stairs at the
	-- bottom, the falls near the top, and a circle at the very bottom where the Lamp goes.
	local chalk = Color3.fromRGB(236, 238, 232)
	local backX = wallX + 0.64
	block(
		"Slate",
		Vector3.new(0.08, 5.2, 3.6),
		Vector3.new(backX, 3.3, 0),
		0,
		Color3.fromRGB(40, 48, 50),
		slate,
		false
	)
	for floor = 0, 5 do
		block(
			"ChalkFloor",
			Vector3.new(0.04, 0.07, 2.4),
			Vector3.new(backX + 0.06, 1.3 + floor * 0.65, -0.2),
			0,
			chalk,
			Enum.Material.SmoothPlastic,
			false
		)
	end
	for _, z in { -1.4, 1 } do
		block(
			"ChalkWall",
			Vector3.new(0.04, 3.3, 0.07),
			Vector3.new(backX + 0.06, 2.95, z - 0.2),
			0,
			chalk,
			Enum.Material.SmoothPlastic,
			false
		)
	end
	block(
		"ChalkLamp",
		Vector3.new(0.05, 0.6, 0.6),
		Vector3.new(backX + 0.07, 0.9, -0.2),
		0,
		Color3.fromRGB(255, 232, 170),
		neon,
		false
	).Shape =
		Enum.PartType.Cylinder
	block(
		"ChalkFalls",
		Vector3.new(0.05, 0.4, 0.4),
		Vector3.new(backX + 0.07, 4.9, 0.4),
		0,
		WATER,
		neon,
		false
	).Shape =
		Enum.PartType.Cylinder
	local glow = block(
		"AlcoveLight",
		Vector3.new(0.3, 0.3, 0.3),
		Vector3.new(wallX + 1.6, 4.6, 0),
		0,
		chalk,
		Enum.Material.SmoothPlastic,
		false
	)
	glow.Transparency = 1
	Build.pointLight(glow, Color3.fromRGB(255, 236, 200), 1.1, 12)
end

local LAYOUTS: { [string]: Layout } = {
	-- The havens: one small lit room after each odd tier. A lamp, a bench, and one page.
	copyroom = {
		halfX = 11,
		halfZ = 8.5,
		height = 10,
		props = {
			{ kit = "copier", x = -6.5, z = -8.5, yaw = 180 },
			{ kit = "desk", x = -11, z = 2.5, yaw = -90 },
			{ kit = "chair", x = -6.6, z = 2.5, yaw = 90 },
			{ kit = "board", x = -11, z = -4.5, yaw = -90 },
			{ kit = "shelf", x = 11, z = -5, yaw = 90 },
			{ kit = "bench", x = 11, z = 1, yaw = 90 },
			{ kit = "lamp", x = 6.5, z = -8.5, yaw = 180 },
			{ kit = "plant", x = 8.5, z = 8.5, yaw = 0 },
			{ kit = "rug", x = 0, z = 0, yaw = 0 },
		},
		notes = {
			{ x = -6.5, y = 2.56, z = -5, yaw = 10, flat = true },
		},
	},
	drybooth = {
		halfX = 10,
		halfZ = 8,
		height = 10,
		props = {
			{ kit = "gauge", x = -5.5, z = -8, yaw = 180 },
			{ kit = "board", x = -10, z = -1.5, yaw = -90 },
			{ kit = "desk", x = -10, z = 4, yaw = -90 },
			{ kit = "chair", x = -5.4, z = 4, yaw = 90 },
			{ kit = "kettle", x = 6, z = -8, yaw = 180 },
			{ kit = "shelf", x = 10, z = -3, yaw = 90 },
			{ kit = "bench", x = 10, z = 3.5, yaw = 90 },
			{ kit = "lamp", x = -9, z = -8, yaw = 180 },
			{ kit = "plant", x = 8, z = 8, yaw = 0 },
			{ kit = "rug", x = 0, z = 0, yaw = 0 },
		},
		notes = {
			{ x = -9.7, y = 4.4, z = -1.5, yaw = -90, flat = false },
		},
	},
	pottingshed = {
		halfX = 11,
		halfZ = 8.5,
		height = 10,
		props = {
			{ kit = "pottingbench", x = -3.5, z = -8.5, yaw = 180 },
			{ kit = "plant", x = 6, z = -8.5, yaw = 180 },
			{ kit = "fern", x = -11, z = -3, yaw = -90 },
			{ kit = "fern", x = 9, z = 8.5, yaw = 0 },
			{ kit = "flowers", x = 11, z = -5, yaw = 90 },
			{ kit = "flowers", x = -11, z = 4, yaw = -90 },
			{ kit = "lamp", x = 4, z = -8.5, yaw = 180 },
			{ kit = "bench", x = 11, z = 1, yaw = 90 },
			{ kit = "chair", x = 6.5, z = 0, yaw = -90 },
			{ kit = "rug", x = 0, z = 0, yaw = 0 },
		},
		notes = {
			{ x = -5.2, y = 3.2, z = -7, yaw = -15, flat = true },
		},
	},
	archivenook = {
		halfX = 10,
		halfZ = 8.5,
		height = 10,
		props = {
			{ kit = "shelf", x = -10, z = -5.5, yaw = -90 },
			{ kit = "shelf", x = -10, z = -1, yaw = -90 },
			{ kit = "cardindex", x = -10, z = 4.5, yaw = -90 },
			{ kit = "shelf", x = 10, z = -5.5, yaw = 90 },
			{ kit = "shelf", x = 10, z = -1, yaw = 90 },
			{ kit = "bench", x = 10, z = 5, yaw = 90 },
			{ kit = "desk", x = 5.5, z = -8.5, yaw = 180 },
			{ kit = "chair", x = 5.5, z = -2.9, yaw = 0 },
			{ kit = "lamp", x = 9, z = -8.5, yaw = 180 },
		},
		notes = {
			{ x = -9, y = 4.68, z = 4.5, yaw = 80, flat = true },
		},
	},
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
			-- The fourth: a chalk drawing in the alcove behind the waterfall.
			{ x = -19.3, y = 2.3, z = 1.5, yaw = -90, flat = false },
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

LoreRooms.BEACON_ID = BEACON_ID

-- Shortest distance from a point to a part's box.
local function distanceTo(part: BasePart, position: Vector3): number
	local localPoint = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	return (localPoint - clamped).Magnitude
end

-- Puts a room in the dark like the maze: its parts stop feet and rays but draw nothing, and
-- its lights, mist and printed text are off. `target` (the lamp, or the waterfall) is marked
-- so a scanner can find it; revealing it brings back everything within `reach` of `position`.
local function darken(
	model: Model,
	target: Instance,
	position: Vector3,
	reach: number,
	room: Lore.Room
): Beacon
	local parts: { { part: BasePart, transparency: number } } = {}
	local switches: { Instance } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant:GetAttribute("Marker") ~= true then
				table.insert(parts, { part = descendant, transparency = descendant.Transparency })
				descendant.Transparency = 1
			end
		elseif
			descendant:IsA("Light")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("SurfaceGui")
		then
			if (descendant :: any).Enabled then
				local light: any = descendant
				table.insert(switches, descendant)
				light.Enabled = false
			end
		end
	end
	model:SetAttribute("Dark", true)
	target:SetAttribute("EchoId", BEACON_ID)
	CollectionService:AddTag(target, Config.Tags.echo)
	CollectionService:AddTag(target, Config.Tags.objective)
	local beacon: Beacon
	beacon = {
		id = BEACON_ID,
		position = position,
		title = room.title,
		subtitle = room.subtitle,
		revealed = false,
		reveal = function()
			beacon.revealed = true
			model:SetAttribute("Dark", false)
			CollectionService:RemoveTag(target, Config.Tags.echo)
			for _, record in parts do
				if distanceTo(record.part, position) <= reach then
					record.part.Transparency = record.transparency
					if record.part:GetAttribute("Tube") == true then
						record.part.Material = Enum.Material.SmoothPlastic
						record.part.Color = DEAD_TUBE_COLOR
					end
				end
			end
			for _, switch in switches do
				local holder = switch.Parent
				if
					holder ~= nil
					and holder:IsA("BasePart")
					and distanceTo(holder, position) <= reach
				then
					if holder:GetAttribute("Tube") == true and switch:IsA("PointLight") then
						switch.Brightness = DEAD_TUBE_BRIGHTNESS
						switch.Range = DEAD_TUBE_RANGE
					end
					(switch :: any).Enabled = true
				end
			end
			-- Tells clients the haven is found, so they calm the bloom inside it.
			local zone = model:FindFirstChild("LitZone")
			if zone then
				zone:SetAttribute("Revealed", true)
			end
		end,
	}
	return beacon
end

local function at(origin: Vector3, x: number, y: number, z: number, yaw: number): CFrame
	return CFrame.new(origin + Vector3.new(x, y, z)) * CFrame.Angles(0, math.rad(yaw), 0)
end

local function buildShell(room: Lore.Room, layout: Layout, origin: Vector3, parent: Instance)
	local hx, hz, rh = layout.halfX or HALF_X, layout.halfZ or HALF_Z, layout.height or ROOM_HEIGHT
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
	local spanX, spanZ = hx * 2 + WALL * 2, hz * 2 + WALL * 2
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
		Vector3.new(0, rh + 0.5, 0),
		wallColor,
		Enum.Material.SmoothPlastic
	)
	local plaster = if layout.stone then Enum.Material.Slate else Enum.Material.SmoothPlastic
	slab(
		"WallN",
		Vector3.new(spanX, rh, WALL),
		Vector3.new(0, rh / 2, -hz - WALL / 2),
		wallColor,
		plaster
	)
	slab(
		"WallS",
		Vector3.new(spanX, rh, WALL),
		Vector3.new(0, rh / 2, hz + WALL / 2),
		wallColor,
		plaster
	)
	slab(
		"WallW",
		Vector3.new(WALL, rh, spanZ),
		Vector3.new(-hx - WALL / 2, rh / 2, 0),
		wallColor,
		plaster
	)
	slab(
		"WallE",
		Vector3.new(WALL, rh, spanZ),
		Vector3.new(hx + WALL / 2, rh / 2, 0),
		wallColor,
		plaster
	)
	-- A dado rail and skirting so the walls do not read as flat colour.
	local trim = wallColor:Lerp(Color3.new(0, 0, 0), 0.35)
	for _, y in { 0.4, 4 } do
		local height = if y < 1 then 0.8 else 0.3
		slab("TrimN", Vector3.new(hx * 2, height, 0.2), Vector3.new(0, y, -hz + 0.1), trim, plaster)
		slab("TrimS", Vector3.new(hx * 2, height, 0.2), Vector3.new(0, y, hz - 0.1), trim, plaster)
		slab("TrimW", Vector3.new(0.2, height, hz * 2), Vector3.new(-hx + 0.1, y, 0), trim, plaster)
		slab("TrimE", Vector3.new(0.2, height, hz * 2), Vector3.new(hx - 0.1, y, 0), trim, plaster)
	end
end

-- What each theme has on its floor and walls besides plaster: wet patches, rust, roots, paper.
type Grime = { wet: boolean, rust: boolean, roots: boolean, paper: boolean, scratches: boolean }
local GRIME: { [string]: Grime } = {
	copyroom = { wet = false, rust = false, roots = false, paper = true, scratches = true },
	office = { wet = false, rust = false, roots = false, paper = true, scratches = true },
	breakroom = { wet = true, rust = false, roots = false, paper = true, scratches = true },
	drybooth = { wet = true, rust = true, roots = false, paper = false, scratches = false },
	cistern = { wet = true, rust = true, roots = true, paper = false, scratches = false },
	pottingshed = { wet = false, rust = true, roots = true, paper = false, scratches = true },
	archivenook = { wet = false, rust = false, roots = false, paper = true, scratches = true },
	stairwell = { wet = false, rust = true, roots = false, paper = false, scratches = true },
	landing = { wet = false, rust = true, roots = false, paper = false, scratches = true },
}
local DETAIL_GRIME = { wet = false, rust = false, roots = false, paper = false, scratches = true }

-- Floor tiles, stains, puddles, cracks and a trail of footprints, and on the walls streaks,
-- claw marks, handprints, pipes and cables. All of it is thin and shares the room's lighting,
-- so in a dark room it only shows near the object that was scanned. It is the same set every
-- time a room is built, so a player who returns finds the same marks.
local function buildDetail(
	roomId: string,
	room: Lore.Room,
	layout: Layout,
	origin: Vector3,
	parent: Instance
)
	local hx, hz, rh = layout.halfX or HALF_X, layout.halfZ or HALF_Z, layout.height or ROOM_HEIGHT
	local grime = GRIME[room.theme] or DETAIL_GRIME
	local seed = 0
	for index = 1, #roomId do
		seed = (seed * 31 + string.byte(roomId, index)) % 1000003
	end
	local random = Random.new(seed)
	local floorColor = Build.rgb(room.floor)
	local wallColor = Build.rgb(room.wall)
	local dark = Color3.new(0, 0, 0)
	local detail = Build.model("Detail", parent)
	local function mark(
		name: string,
		size: Vector3,
		cframe: CFrame,
		color: Color3,
		material: Enum.Material,
		shape: Enum.PartType?
	)
		Build.part({
			name = name,
			size = size,
			cframe = cframe,
			color = color,
			material = material,
			shape = shape,
			collide = false,
			parent = detail,
		})
	end
	local function floorAt(x: number, z: number, yaw: number): CFrame
		return CFrame.new(origin + Vector3.new(x, 0.04, z)) * CFrame.Angles(0, math.rad(yaw), 0)
	end

	-- Floor: a loose grid of tiles or boards, a shade lighter or darker than the rest.
	local cell = 4
	for gx = -hx + cell / 2, hx - cell / 2, cell do
		for gz = -hz + cell / 2, hz - cell / 2, cell do
			local tone = random:NextNumber(0.15, 0.4)
			if random:NextNumber() < 0.45 then
				mark(
					"Tile",
					Vector3.new(cell - 0.3, 0.06, cell - 0.3),
					floorAt(gx, gz, 0),
					floorColor:Lerp(
						if random:NextNumber() < 0.5 then dark else Color3.new(1, 1, 1),
						tone * 0.5
					),
					layout.stone and Enum.Material.Cobblestone or Enum.Material.Wood
				)
			end
		end
	end
	-- Stains, puddles and rust blooms.
	local blots = math.floor(hx * hz / 30)
	for _ = 1, blots do
		local x, z = random:NextNumber(-hx + 1, hx - 1), random:NextNumber(-hz + 1, hz - 1)
		local radius = random:NextNumber(0.8, 2.6)
		local wet = grime.wet and random:NextNumber() < 0.55
		mark(
			if wet then "Puddle" else "Stain",
			Vector3.new(0.07, radius * 2, radius * 2.4),
			floorAt(x, z, random:NextNumber(0, 180)) * CFrame.Angles(0, 0, math.rad(90)),
			if wet
				then Color3.fromRGB(46, 78, 92)
				elseif grime.rust and random:NextNumber() < 0.5 then Color3.fromRGB(
					120,
					62,
					36
				)
				else floorColor:Lerp(dark, 0.6),
			if wet then Enum.Material.Glass else Enum.Material.Slate,
			Enum.PartType.Cylinder
		)
	end
	-- Cracks, and rubble where a floor has given up.
	for _ = 1, 7 do
		local x, z = random:NextNumber(-hx + 2, hx - 2), random:NextNumber(-hz + 2, hz - 2)
		mark(
			"Crack",
			Vector3.new(random:NextNumber(3, 7), 0.06, 0.12),
			floorAt(x, z, random:NextNumber(0, 180)),
			floorColor:Lerp(dark, 0.8),
			Enum.Material.Slate
		)
		for _ = 1, 3 do
			mark(
				"Rubble",
				Vector3.new(
					random:NextNumber(0.2, 0.6),
					random:NextNumber(0.2, 0.5),
					random:NextNumber(0.2, 0.6)
				),
				floorAt(
					x + random:NextNumber(-1.5, 1.5),
					z + random:NextNumber(-1.5, 1.5),
					random:NextNumber(0, 180)
				),
				floorColor:Lerp(dark, 0.3),
				Enum.Material.Slate
			)
		end
	end
	-- Paper on the floor, or roots coming through it.
	if grime.paper then
		for _ = 1, 14 do
			mark(
				"Paper",
				Vector3.new(0.9, 0.03, 1.2),
				floorAt(
					random:NextNumber(-hx + 1, hx - 1),
					random:NextNumber(-hz + 1, hz - 1),
					random:NextNumber(0, 180)
				),
				Color3.fromRGB(214, 206, 180):Lerp(dark, random:NextNumber(0, 0.4)),
				Enum.Material.SmoothPlastic
			)
		end
	end
	if grime.roots then
		for _ = 1, 8 do
			local x, z = random:NextNumber(-hx + 1, hx - 1), random:NextNumber(-hz + 1, hz - 1)
			mark(
				"Root",
				Vector3.new(random:NextNumber(3, 6), 0.35, 0.35),
				floorAt(x, z, random:NextNumber(0, 180)) * CFrame.new(0, 0.1, 0),
				Color3.fromRGB(70, 52, 36),
				Enum.Material.Wood
			)
		end
	end
	-- A trail of footprints from the entrance toward the door out: someone came this way, and
	-- the prints stop short of the wall.
	for step = 0, 9 do
		local side = if step % 2 == 0 then -0.5 else 0.5
		mark(
			"Footprint",
			Vector3.new(0.5, 0.05, 1),
			floorAt(side + random:NextNumber(-0.15, 0.15), hz - 3 - step * (hz * 1.5 / 10), 0),
			Color3.fromRGB(34, 28, 26),
			Enum.Material.Slate
		)
	end

	-- Walls: each of the four, seen from inside. `along` runs left to right, `up` is height.
	local walls = {
		{ face = Vector3.new(0, 0, -hz), span = hx, yaw = 0 },
		{ face = Vector3.new(0, 0, hz), span = hx, yaw = 180 },
		{ face = Vector3.new(-hx, 0, 0), span = hz, yaw = 90 },
		{ face = Vector3.new(hx, 0, 0), span = hz, yaw = 270 },
	}
	for _, wall in walls do
		local function onWall(along: number, up: number, lean: number): CFrame
			return CFrame.new(origin + wall.face + Vector3.new(0, up, 0))
				* CFrame.Angles(0, math.rad(wall.yaw), 0)
				* CFrame.new(along, 0, 0.06)
				* CFrame.Angles(0, 0, math.rad(lean))
		end
		-- Damp or soot running down from the ceiling.
		for _ = 1, 5 do
			local length = random:NextNumber(rh * 0.3, rh * 0.8)
			mark(
				"Streak",
				Vector3.new(random:NextNumber(0.2, 0.8), length, 0.05),
				onWall(random:NextNumber(-wall.span + 1, wall.span - 1), rh - length / 2, 0),
				wallColor:Lerp(dark, random:NextNumber(0.45, 0.75)),
				Enum.Material.Slate
			)
		end
		-- A big dark patch of something that soaked in.
		mark(
			"Soak",
			Vector3.new(random:NextNumber(2.5, 5), random:NextNumber(2, 4), 0.05),
			onWall(
				random:NextNumber(-wall.span + 3, wall.span - 3),
				random:NextNumber(2, rh - 3),
				0
			),
			if grime.rust then Color3.fromRGB(88, 44, 30) else wallColor:Lerp(dark, 0.7),
			Enum.Material.Slate
		)
		-- Claw marks: four long scratches that never quite line up.
		if grime.scratches then
			local along, up =
				random:NextNumber(-wall.span + 3, wall.span - 3), random:NextNumber(3, rh - 4)
			for line = 0, 3 do
				mark(
					"Scratch",
					Vector3.new(0.08, random:NextNumber(2.2, 3.4), 0.04),
					onWall(along + line * 0.45, up + random:NextNumber(-0.3, 0.3), -12),
					wallColor:Lerp(dark, 0.9),
					Enum.Material.Slate
				)
			end
		end
		-- Handprints at shoulder height, smeared downward.
		for _ = 1, 2 do
			local along = random:NextNumber(-wall.span + 2, wall.span - 2)
			local up = random:NextNumber(3, 5)
			mark(
				"Palm",
				Vector3.new(0.45, 0.5, 0.04),
				onWall(along, up, 0),
				Color3.fromRGB(70, 18, 16),
				Enum.Material.Slate
			)
			for finger = -1, 1 do
				mark(
					"Finger",
					Vector3.new(0.1, 0.4, 0.04),
					onWall(along + finger * 0.14, up + 0.4, finger * 8),
					Color3.fromRGB(70, 18, 16),
					Enum.Material.Slate
				)
			end
			mark(
				"Smear",
				Vector3.new(0.18, random:NextNumber(1, 2), 0.04),
				onWall(along, up - 1, 0),
				Color3.fromRGB(58, 14, 12),
				Enum.Material.Slate
			)
		end
		-- Peeling: a curled sheet of wall hanging off.
		mark(
			"Peel",
			Vector3.new(random:NextNumber(1.5, 3), random:NextNumber(1, 2), 0.12),
			onWall(
				random:NextNumber(-wall.span + 2, wall.span - 2),
				random:NextNumber(4, rh - 2),
				random:NextNumber(-6, 6)
			),
			wallColor:Lerp(Color3.new(1, 1, 1), 0.12),
			Enum.Material.Fabric
		)
	end
	-- A pipe along the ceiling, and cables sagging from it.
	local pipeColor = if grime.rust then Color3.fromRGB(104, 66, 44) else Color3.fromRGB(80, 84, 88)
	mark(
		"Pipe",
		Vector3.new(0.5, 0.5, hz * 2 - 1),
		CFrame.new(origin + Vector3.new(hx - 1.5, rh - 0.6, 0)),
		pipeColor,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	for index = 1, 4 do
		mark(
			"Cable",
			Vector3.new(0.12, random:NextNumber(1.2, 3), 0.12),
			CFrame.new(
				origin
					+ Vector3.new(hx - 1.5 - index * 0.2, rh - 0.6 - 1, -hz + index * (hz * 2 / 5))
			),
			Color3.fromRGB(24, 24, 26),
			Enum.Material.SmoothPlastic
		)
	end
end

local function buildLights(room: Lore.Room, layout: Layout, origin: Vector3, parent: Instance)
	local color = Build.rgb(room.light)
	local rh = layout.height or ROOM_HEIGHT
	local panels = if layout.halfX ~= nil then HAVEN_PANELS else PANEL_OFFSETS
	for _, x in panels do
		local panel = Build.part({
			name = "LightPanel",
			size = Vector3.new(5, 0.2, 2.2),
			cframe = CFrame.new(origin + Vector3.new(x, rh - 0.1, 0)),
			color = color,
			material = Enum.Material.Neon,
			collide = false,
			parent = parent,
		})
		panel:SetAttribute("Tube", true)
		local light = Build.pointLight(panel, color, PANEL_BRIGHTNESS, PANEL_RANGE)
		if layout.flicker and x == panels[1] then
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

	local hx, hz, rh = layout.halfX or HALF_X, layout.halfZ or HALF_Z, layout.height or ROOM_HEIGHT
	local model = Build.model("LoreRoom_" .. roomId, workspace)
	buildShell(room, layout, origin, model)
	buildLights(room, layout, origin, model)
	buildDetail(roomId, room, layout, origin, model)
	if layout.extras then
		layout.extras(origin, model)
	end

	local entranceHeight = if layout.raisedEntrance then LANDING_HEIGHT else 0
	if layout.raisedEntrance then
		buildStairs(origin, model)
	end
	buildDoor(origin, hz, 0, "EntranceDoor", model, entranceHeight)
	local exitDoor = buildDoor(origin, -hz, 180, "ExitDoor", model, 0)
	-- The way on is an open doorway: the panel is a flat black gap you walk through.
	exitDoor.Color = Color3.new(0, 0, 0)
	exitDoor.Material = Enum.Material.SmoothPlastic
	exitDoor.CanCollide = false
	for _, child in model:GetChildren() do
		if
			child.Name == "Handle"
			and child:IsA("BasePart")
			and (child.Position - exitDoor.Position).Magnitude < DOOR_WIDTH
		then
			child:Destroy()
		end
	end
	local exitPrompt = Build.prompt(exitDoor, "Continue", "Into the dark", 0.6)

	local benchPrompt: ProximityPrompt? = nil
	local lampProp: Model? = nil
	for _, placement in layout.props do
		local prop = Props.place(
			placement.kit,
			at(origin, placement.x, 0, placement.z, placement.yaw),
			model
		)
		if placement.kit == "lamp" and lampProp == nil then
			lampProp = prop
		end
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

	-- A dark room has no light until its one standout object is scanned: the room's lamp, or
	-- in the Falls the waterfall itself (the sound of it is the way in).
	local beacon: Beacon? = nil
	if room.dark then
		local fall = model:FindFirstChild("Waterfall")
		local sheet = if fall then fall:FindFirstChild("Fall") else nil
		if lampProp ~= nil then
			beacon = darken(model, lampProp, lampProp:GetPivot().Position, LAMP_REACH, room)
		elseif fall ~= nil and sheet ~= nil and sheet:IsA("BasePart") then
			beacon = darken(model, fall, sheet.Position, FALLS_REACH, room)
		end
	end

	-- The zone marks where the player is. In a lit room it also tells each client to bring the
	-- lights up while they stand inside it; a dark room only brings the title card.
	local zone = Build.part({
		name = "LitZone",
		size = Vector3.new(hx * 2 + WALL * 2, rh + 2, hz * 2 + WALL * 2),
		cframe = CFrame.new(origin + Vector3.new(0, rh / 2, 0)),
		transparency = 1,
		collide = false,
		query = false,
		tag = Config.Tags.litZone,
		parent = model,
	})
	zone:SetAttribute("Light", Build.rgb(room.light))
	zone:SetAttribute("Dark", beacon ~= nil)
	zone:SetAttribute("Title", room.title)
	zone:SetAttribute("Subtitle", room.subtitle)

	local spawnPoint = origin + Vector3.new(0, entranceHeight + SPAWN_HEIGHT, hz - 3)
	return {
		model = model,
		room = room,
		spawnCFrame = CFrame.lookAt(spawnPoint, spawnPoint + Vector3.new(0, 0, -1)),
		exitPrompt = exitPrompt,
		benchPrompt = benchPrompt :: ProximityPrompt,
		notes = notes,
		beacon = beacon,
	}
end

return LoreRooms
