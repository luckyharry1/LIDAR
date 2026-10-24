--!strict
-- The stairwell between a level and the next place: a narrow flight of stairs the party walks
-- down together. Unlike the maze it is drawn: dark concrete picked out by a string of dim
-- emergency lamps down the flight, so it stays in view behind the "go down?" pop-up and the walk
-- is a continuous place rather than a cut. A brighter lamp on the end wall marks the bottom.

-- The stairwell between a level and the next place: a narrow flight of stairs the party walks
-- down together. Unlike the maze it is drawn: dark concrete with light blocks set into both walls
-- that come on one by one as someone walks down, so the flight lights up ahead of them. The bottom
-- is an open doorway into unlit darkness; walking into it ends the stairwell.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Config = require(ReplicatedStorage.Shared.Config)

export type Passage = {
	model: Model,
	startCFrame: CFrame,
	endPosition: Vector3, -- inside the dark past the doorway; arriving here ends the walk
	update: (positions: { Vector3 }) -> (), -- lights the blocks near anyone on the stairs
}

type Block = { position: Vector3, bulb: BasePart, light: PointLight, on: boolean }

local CONCRETE = Color3.fromRGB(88, 86, 82)
local BLOCK_EVERY = 3 -- steps between light blocks on each wall
local BLOCK_AHEAD = 11 -- studs ahead of a walker that a block comes on
local BLOCK_FADE_SECONDS = 0.7
local DARK_RUN = 16 -- studs of unlit corridor past the doorway
local DOOR_WIDTH = 5
local DOOR_HEIGHT = 7.5
local STEPS = 28
local RUN = 2.6 -- studs of floor per step
local RISE = 0.9 -- studs each step drops
local WIDTH = 7
local LANDING = 8
local HEIGHT = 8 -- clear height above the steps
local WALL = 1

local Passage = {}

function Passage.build(origin: Vector3): Passage
	local model = Build.model("Passage", workspace)
	local drop = STEPS * RISE
	local length = STEPS * RUN
	local function slab(name: string, size: Vector3, cframe: CFrame)
		Build.part({
			name = name,
			size = size,
			cframe = cframe,
			color = CONCRETE,
			material = Enum.Material.Concrete,
			parent = model,
		})
	end
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(origin + Vector3.new(x, y, z))
	end

	-- Top landing, the steps, bottom landing.
	slab("TopLanding", Vector3.new(WIDTH, 1, LANDING), at(0, -0.5, LANDING / 2))
	for step = 1, STEPS do
		slab("Step", Vector3.new(WIDTH, 1, RUN), at(0, -step * RISE - 0.5, -(step - 0.5) * RUN))
	end
	slab("BottomLanding", Vector3.new(WIDTH, 1, LANDING), at(0, -drop - 0.5, -length - LANDING / 2))

	-- Side walls and end walls, one tall slab each.
	local top = HEIGHT + 1
	local wallHeight = top + drop + 2
	local wallCentreY = (top - drop - 2) / 2
	local wallLength = length + LANDING * 2
	local wallCentreZ = (LANDING - length - LANDING) / 2
	for _, side in { -1, 1 } do
		slab(
			"SideWall",
			Vector3.new(WALL, wallHeight, wallLength),
			at(side * (WIDTH / 2 + WALL / 2), wallCentreY, wallCentreZ)
		)
	end
	slab(
		"StartWall",
		Vector3.new(WIDTH + WALL * 2, wallHeight, WALL),
		at(0, wallCentreY, LANDING + WALL / 2)
	)
	-- Ceiling: flat over the landings, sloped to follow the steps.
	slab("TopCeiling", Vector3.new(WIDTH, 1, LANDING), at(0, HEIGHT + 0.5, LANDING / 2))
	slab(
		"BottomCeiling",
		Vector3.new(WIDTH, 1, LANDING),
		at(0, HEIGHT - drop + 0.5, -length - LANDING / 2)
	)
	local from = origin + Vector3.new(0, HEIGHT + 0.5, 0)
	local to = origin + Vector3.new(0, HEIGHT - drop + 0.5, -length)
	slab(
		"SlopedCeiling",
		Vector3.new(WIDTH, 1, (to - from).Magnitude),
		CFrame.lookAt((from + to) / 2, to)
	)

	-- Light blocks set into both walls: flat slabs flush with the wall that start as dark
	-- concrete and warm up when a walker comes within BLOCK_AHEAD studs.
	local blocks: { Block } = {}
	local function block(side: number, y: number, z: number)
		local bulb = Build.part({
			name = "LightBlock",
			size = Vector3.new(0.3, 1.1, 2),
			cframe = at(side * (WIDTH / 2 - 0.1), y, z),
			color = CONCRETE,
			material = Enum.Material.Concrete,
			collide = false,
			parent = model,
		})
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 176, 100)
		light.Brightness = 0
		light.Range = 13
		light.Parent = bulb
		table.insert(blocks, { position = bulb.Position, bulb = bulb, light = light, on = false })
	end
	block(1, 4.5, LANDING - 2)
	block(-1, 4.5, LANDING - 2)
	for step = BLOCK_EVERY, STEPS, BLOCK_EVERY do
		local z = -(step - 0.5) * RUN
		local y = -step * RISE + 4.2
		block(if step % 2 == 0 then 1 else -1, y, z)
		block(if step % 2 == 0 then -1 else 1, y, z - RUN * 1.5)
	end

	-- The way on: a doorway in the foot of the stairs, then a corridor with no light at all.
	local doorZ = -length - LANDING
	local doorY = -drop
	local sideWidth = (WIDTH - DOOR_WIDTH) / 2
	for _, side in { -1, 1 } do
		slab(
			"DoorSide",
			Vector3.new(sideWidth, DOOR_HEIGHT + 1, WALL),
			at(
				side * (DOOR_WIDTH / 2 + sideWidth / 2),
				doorY + (DOOR_HEIGHT + 1) / 2,
				doorZ - WALL / 2
			)
		)
	end
	local header = Build.part({
		name = "DoorHeader",
		size = Vector3.new(WIDTH, HEIGHT - DOOR_HEIGHT + 1, WALL),
		cframe = at(0, doorY + DOOR_HEIGHT + (HEIGHT - DOOR_HEIGHT + 1) / 2, doorZ - WALL / 2),
		color = CONCRETE,
		material = Enum.Material.Concrete,
		parent = model,
	})
	CollectionService:AddTag(header, Config.Tags.objective) -- a scan draws it in gold
	local darkLength = DARK_RUN + WALL
	for _, side in { -1, 1 } do
		slab(
			"DarkWall",
			Vector3.new(WALL, wallHeight, darkLength),
			at(side * (WIDTH / 2 + WALL / 2), wallCentreY, doorZ - darkLength / 2)
		)
	end
	slab("DarkFloor", Vector3.new(WIDTH, 1, darkLength), at(0, doorY - 0.5, doorZ - darkLength / 2))
	slab(
		"DarkCeiling",
		Vector3.new(WIDTH, 1, darkLength),
		at(0, doorY + HEIGHT + 0.5, doorZ - darkLength / 2)
	)
	slab(
		"DarkEnd",
		Vector3.new(WIDTH + WALL * 2, wallHeight, WALL),
		at(0, wallCentreY, doorZ - darkLength - WALL / 2)
	)

	local function update(positions: { Vector3 })
		for _, entry in blocks do
			if not entry.on then
				for _, position in positions do
					-- Along the walk: lit once the walker is within reach, whichever side of it.
					if math.abs(position.Z - entry.position.Z) <= BLOCK_AHEAD then
						entry.on = true
						local info = TweenInfo.new(BLOCK_FADE_SECONDS)
						TweenService:Create(entry.light, info, { Brightness = 1.1 }):Play()
						TweenService
							:Create(entry.bulb, info, { Color = Color3.fromRGB(255, 190, 110) })
							:Play()
						entry.bulb.Material = Enum.Material.Neon
						break
					end
				end
			end
		end
	end

	local spawn = origin + Vector3.new(0, 3, LANDING - 2)
	return {
		model = model,
		startCFrame = CFrame.lookAt(spawn, spawn + Vector3.new(0, 0, -1)),
		endPosition = origin + Vector3.new(0, -drop + 3, doorZ - 7),
		update = update,
	}
end

return Passage
