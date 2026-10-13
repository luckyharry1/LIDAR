--!strict
-- Small helpers for building geometry out of primitive parts.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type PartSpec = {
	name: string?,
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?,
	shape: Enum.PartType?,
	collide: boolean?, -- default true
	query: boolean?, -- default true: LIDAR rays hit it
	transparency: number?,
	tag: string?,
	parent: Instance,
}

local DEFAULT_COLOR = Color3.fromRGB(72, 74, 70)

local Build = {}

function Build.rgb(triple: { number }): Color3
	return Color3.fromRGB(triple[1], triple[2], triple[3])
end

function Build.part(spec: PartSpec): Part
	local part = Instance.new("Part")
	part.Name = spec.name or "Part"
	part.Anchored = true
	part.Size = spec.size
	part.CFrame = spec.cframe
	part.Color = spec.color or DEFAULT_COLOR
	part.Material = spec.material or Enum.Material.Concrete
	part.Shape = spec.shape or Enum.PartType.Block
	part.CanCollide = spec.collide ~= false
	part.CanQuery = spec.query ~= false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = spec.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if spec.tag then
		CollectionService:AddTag(part, spec.tag)
	end
	part.Parent = spec.parent
	return part
end

function Build.model(name: string, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

function Build.prompt(part: BasePart, action: string, object: string, hold: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = Config.World.promptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = part
	return prompt
end

function Build.pointLight(
	parent: Instance,
	color: Color3,
	brightness: number,
	range: number
): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
	return light
end

-- Makes everything under `root` invisible and unlit. The maze is never seen, only scanned:
-- its parts still stop rays and feet, but draw nothing, so dots show through the walls.
function Build.hide(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
		elseif descendant:IsA("Light") then
			descendant.Enabled = false
		end
	end
end

-- A looping positional sound. Tagged so each client can route it through its volume setting.
function Build.loop(
	parent: BasePart,
	id: string,
	volume: number,
	speed: number,
	maxDistance: number
): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 6
	sound.RollOffMaxDistance = maxDistance
	CollectionService:AddTag(sound, Config.Tags.sound)
	sound.Parent = parent
	sound:Play()
	return sound
end

-- Welds every part in a model to its root and unanchors them, so moving the anchored root
-- moves the whole thing with a single replicated CFrame.
function Build.weldTo(root: BasePart, model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = descendant
			weld.Parent = descendant
			descendant.Anchored = false
			descendant.Massless = true
		end
	end
	model.PrimaryPart = root
end

return Build
