--!strict
-- The stairwell between a level and the next place: a narrow flight of stairs the party walks
-- down together. Like the maze it is never drawn; the scanner is the only way to see it. The one
-- thing that shines is a dim lamp on the landing at the bottom, so there is somewhere to go.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Config = require(ReplicatedStorage.Shared.Config)

export type Passage = {
	model: Model,
	startCFrame: CFrame,
	endPosition: Vector3, -- the middle of the bottom landing; arriving here ends the walk
}

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
			material = Enum.Material.Concrete,
			transparency = 1,
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

	-- The lamp at the bottom: a dim warm bulb on the end wall.
	local lampY = -drop + 4
	local lampZ = -length - LANDING + 1
	local bulb = Build.part({
		name = "Lamp",
		size = Vector3.new(1, 1, 1),
		cframe = at(0, lampY, lampZ),
		color = Color3.fromRGB(255, 190, 110),
		material = Enum.Material.Neon,
		collide = false,
		parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Brightness = 0.8
	light.Range = 14
	light.Parent = bulb
	CollectionService:AddTag(bulb, Config.Tags.objective)

	local spawn = origin + Vector3.new(0, 3, LANDING - 2)
	return {
		model = model,
		startCFrame = CFrame.lookAt(spawn, spawn + Vector3.new(0, 0, -1)),
		endPosition = origin + Vector3.new(0, -drop + 3, -length - LANDING / 2),
	}
end

return Passage
