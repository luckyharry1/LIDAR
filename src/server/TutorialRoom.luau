--!strict
-- The first thing a new player stands in: one small dark room with a baffle wall and a door
-- at the far end. The client's tutorial prompts do the teaching; this only builds the space.
-- Like the maze, it is invisible: it can only be scanned. A television on a cart holds the
-- Survey's orientation tape; the client plays it once enough dots have landed on the screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Config = require(ReplicatedStorage.Shared.Config)

export type Tutorial = {
	model: Model,
	spawnCFrame: CFrame,
	exitPrompt: ProximityPrompt,
	exitDoor: BasePart,
}

local HALF_X = 9
local HALF_Z = 18
local HEIGHT = Config.World.wallHeight
local WALL = Config.World.wallThickness
local SPAWN_HEIGHT = 3
local BAFFLE_Z = -3 -- a wall across the room with a gap at one side
local BAFFLE_GAP = 6
local DOOR_SIZE = Vector3.new(5, 8.4, 0.5)
local COLOR = Color3.fromRGB(86, 88, 80)
local TV_Z = 9 -- along the east wall, in view from the first steps

local TutorialRoom = {}

function TutorialRoom.build(origin: Vector3): Tutorial
	local model = Build.model("Tutorial", workspace)
	local function slab(name: string, size: Vector3, position: Vector3)
		Build.part({
			name = name,
			size = size,
			cframe = CFrame.new(origin + position),
			color = COLOR,
			parent = model,
		})
	end
	local spanX, spanZ = HALF_X * 2 + WALL * 2, HALF_Z * 2 + WALL * 2
	slab("Floor", Vector3.new(spanX, 1, spanZ), Vector3.new(0, -0.5, 0))
	slab("Ceiling", Vector3.new(spanX, 1, spanZ), Vector3.new(0, HEIGHT + 0.5, 0))
	slab("WallN", Vector3.new(spanX, HEIGHT, WALL), Vector3.new(0, HEIGHT / 2, -HALF_Z - WALL / 2))
	slab("WallS", Vector3.new(spanX, HEIGHT, WALL), Vector3.new(0, HEIGHT / 2, HALF_Z + WALL / 2))
	slab("WallW", Vector3.new(WALL, HEIGHT, spanZ), Vector3.new(-HALF_X - WALL / 2, HEIGHT / 2, 0))
	slab("WallE", Vector3.new(WALL, HEIGHT, spanZ), Vector3.new(HALF_X + WALL / 2, HEIGHT / 2, 0))
	local baffleLength = HALF_X * 2 - BAFFLE_GAP
	slab(
		"Baffle",
		Vector3.new(baffleLength, HEIGHT, WALL),
		Vector3.new(-HALF_X + baffleLength / 2, HEIGHT / 2, BAFFLE_Z)
	)
	slab("Pillar", Vector3.new(2.2, HEIGHT, 2.2), Vector3.new(-3, HEIGHT / 2, 8))
	slab("Pillar", Vector3.new(2.2, HEIGHT, 2.2), Vector3.new(4, HEIGHT / 2, -11))

	local cart = Vector3.new(HALF_X - 1.8, 0, TV_Z)
	slab("TVCart", Vector3.new(2.4, 1.6, 3.2), cart + Vector3.new(0, 0.8, 0))
	slab("TVBody", Vector3.new(2, 1.7, 2.6), cart + Vector3.new(0, 2.45, 0))
	slab("TVScreen", Vector3.new(0.1, 1.3, 2), cart + Vector3.new(-1.05, 2.45, 0))

	local doorBase = CFrame.new(origin + Vector3.new(0, 0, -HALF_Z + DOOR_SIZE.Z / 2))
	local door = Build.part({
		name = "ExitDoor",
		size = DOOR_SIZE,
		cframe = doorBase * CFrame.new(0, DOOR_SIZE.Y / 2, 0),
		color = Color3.fromRGB(120, 96, 60),
		material = Enum.Material.Wood,
		tag = Config.Tags.objective,
		parent = model,
	})
	for _, x in { -DOOR_SIZE.X / 2 - 0.4, DOOR_SIZE.X / 2 + 0.4 } do
		Build.part({
			name = "Jamb",
			size = Vector3.new(0.8, DOOR_SIZE.Y + 0.8, 0.9),
			cframe = doorBase * CFrame.new(x, (DOOR_SIZE.Y + 0.8) / 2, 0),
			color = COLOR,
			tag = Config.Tags.objective,
			parent = model,
		})
	end
	Build.part({
		name = "Header",
		size = Vector3.new(DOOR_SIZE.X + 1.6, 0.8, 0.9),
		cframe = doorBase * CFrame.new(0, DOOR_SIZE.Y + 0.4, 0),
		color = COLOR,
		tag = Config.Tags.objective,
		parent = model,
	})

	local exitPrompt = Build.prompt(door, "Open", "Door", 0.4)
	Build.hide(model)

	local spawnPoint = origin + Vector3.new(0, SPAWN_HEIGHT, HALF_Z - 4)
	return {
		model = model,
		spawnCFrame = CFrame.lookAt(spawnPoint, spawnPoint + Vector3.new(0, 0, -1)),
		exitPrompt = exitPrompt,
		exitDoor = door,
	}
end

return TutorialRoom
