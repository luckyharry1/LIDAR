--!strict
-- The stairwell between a level and the next place: a narrow flight of stairs the party walks
-- down together. Unlike the maze it is drawn: dark concrete picked out by a string of dim
-- emergency lamps down the flight, so it stays in view behind the "go down?" pop-up and the walk
-- is a continuous place rather than a cut. A brighter lamp on the end wall marks the bottom.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Config = require(ReplicatedStorage.Shared.Config)

export type Passage = {
	model: Model,
	startCFrame: CFrame,
	endPosition: Vector3, -- the middle of the bottom landing; arriving here ends the walk
}

local CONCRETE = Color3.fromRGB(88, 86, 82)
local LAMP_EVERY = 4 -- steps between emergency lamps
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
	slab(
		"EndWall",
		Vector3.new(WIDTH + WALL * 2, wallHeight, WALL),
		at(0, wallCentreY, -length - LANDING - WALL / 2)
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

	-- Emergency lamps down the right wall, each a small warm bulb with a short-reach light.
	local function lamp(name: string, position: Vector3, brightness: number, range: number)
		local bulb = Build.part({
			name = name,
			size = Vector3.new(0.5, 0.5, 0.5),
			cframe = CFrame.new(origin + position),
			color = Color3.fromRGB(255, 190, 110),
			material = Enum.Material.Neon,
			collide = false,
			parent = model,
		})
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 170, 90)
		light.Brightness = brightness
		light.Range = range
		light.Parent = bulb
		return bulb
	end
	lamp("TopLamp", Vector3.new(WIDTH / 2 - 0.4, 5.5, LANDING - 2), 0.7, 12)
	for step = LAMP_EVERY, STEPS, LAMP_EVERY do
		lamp(
			"StairLamp",
			Vector3.new(WIDTH / 2 - 0.4, -step * RISE + 4.5, -(step - 0.5) * RUN),
			0.7,
			12
		)
	end

	-- The lamp at the bottom: a dim warm bulb on the end wall.
	local lampY = -drop + 4
	local lampZ = -length - LANDING + 1
	local bulb = lamp("Lamp", Vector3.new(0, lampY, lampZ), 1.4, 18)
	CollectionService:AddTag(bulb, Config.Tags.objective)

	local spawn = origin + Vector3.new(0, 3, LANDING - 2)
	return {
		model = model,
		startCFrame = CFrame.lookAt(spawn, spawn + Vector3.new(0, 0, -1)),
		endPosition = origin + Vector3.new(0, -drop + 3, -length - LANDING / 2),
	}
end

return Passage
