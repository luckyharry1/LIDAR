--!strict
-- A faint pull towards things worth scanning that nobody has scanned yet: battery cells and
-- the story's hidden objects (recorders, reveal objects, posters). Each one gives off a few
-- slow motes of pale light, too dim and too rare to read as a marker, only when the player is
-- near and nothing stands in between. Once the local gun has touched it the motes stop; from
-- then on the found-item pulse (Immersion) takes over, so the two never look alike.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Dots = require(script.Parent.Dots)
local Lidar = require(script.Parent.Lidar)
local State = require(script.Parent.State)

type Lure = { model: Model, part: Part, emitter: ParticleEmitter }

-- Tuned down after Vasco's first look (22 Oct): the cells were too easy to spot. A mote now
-- appears every few seconds, only close by, and is barely brighter than nothing.
local RANGE = 18 -- studs; farther than this nothing shows
local REFRESH_SECONDS = 0.5
local RATE = 0.3 -- motes per second at the closest; fewer farther away
local MOTE_COLOR = Color3.fromRGB(255, 240, 214) -- a warm white, not the gold of a found item
local STORY_KINDS = { recorder = true, reveal = true, sign = true }
local ANCESTOR_STEPS = 6 -- how far up from a hit part to look for the lured model

local player = Players.LocalPlayer
local folder = Instance.new("Folder")
folder.Name = "LidarLures"
local lures: { [Model]: Lure } = {}
local touched: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude

local Lure = {}

local function newLure(model: Model): Lure
	local part = Instance.new("Part")
	part.Name = "Lure"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1.4, 1.4, 1.4)
	part.CFrame = CFrame.new(model:GetPivot().Position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(MOTE_COLOR)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Brightness = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.4, 0.035),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 0.9),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(2, 3)
	emitter.Speed = NumberRange.new(0.1, 0.3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 0.12, 0) -- drifts up, like dust in a draught
	emitter.RotSpeed = NumberRange.new(-20, 20)
	emitter.Rate = 0
	emitter.Parent = part
	part.Parent = folder
	return { model = model, part = part, emitter = emitter }
end

local function drop(model: Model)
	local lure = lures[model]
	if lure ~= nil then
		lure.part:Destroy()
		lures[model] = nil
	end
end

-- Everything that should pull the eye right now.
local function candidates(): { Model }
	local list: { Model } = {}
	for _, instance in CollectionService:GetTagged(Config.Tags.echo) do
		local kind = instance:GetAttribute("EchoKind")
		if instance:IsA("Model") and type(kind) == "string" and STORY_KINDS[kind] then
			table.insert(list, instance)
		end
	end
	for _, instance in CollectionService:GetTagged(Config.Tags.objective) do
		if instance:IsA("Model") and instance:GetAttribute("Charges") ~= nil then
			table.insert(list, instance)
		end
	end
	return list
end

local function inSight(from: Vector3, model: Model, to: Vector3): boolean
	local filter: { Instance } = { Dots.folder(), folder }
	if player.Character then
		table.insert(filter, player.Character)
	end
	sightParams.FilterDescendantsInstances = filter
	local result = workspace:Raycast(from, to - from, sightParams)
	return result == nil or result.Instance:IsDescendantOf(model)
end

local function refresh()
	local camera = workspace.CurrentCamera
	local active = camera ~= nil and State.inLevel() and not State.menuOpen
	local wanted: { [Model]: boolean } = {}
	if active then
		local eye = (camera :: Camera).CFrame.Position
		for _, model in candidates() do
			if not touched[model] and model:IsDescendantOf(workspace) then
				local at = model:GetPivot().Position
				local distance = (at - eye).Magnitude
				if distance <= RANGE and inSight(eye, model, at) then
					wanted[model] = true
					local lure = lures[model] or newLure(model)
					lures[model] = lure
					lure.emitter.Rate = RATE * (1 - distance / RANGE) ^ 0.5
				end
			end
		end
	end
	for model, lure in lures do
		if not wanted[model] then
			-- Out of range or out of sight: stop emitting and let the last motes fade out.
			lure.emitter.Rate = 0
			if touched[model] or not model:IsDescendantOf(workspace) then
				drop(model)
			end
		end
	end
end

-- Which lurable model a part belongs to, cached per part (`none` holds parts with no owner).
local owners: { [Instance]: Model } = setmetatable({}, { __mode = "k" }) :: any
local none: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function ownerOf(instance: Instance): Model?
	if none[instance] then
		return nil
	end
	local cached = owners[instance]
	if cached ~= nil then
		return cached
	end
	local node: Instance? = instance
	for _ = 1, ANCESTOR_STEPS do
		if node == nil or node == workspace then
			break
		end
		if
			node:IsA("Model")
			and (node:GetAttribute("Charges") ~= nil or node:GetAttribute("EchoKind") ~= nil)
		then
			owners[instance] = node
			return node
		end
		node = node.Parent
	end
	none[instance] = true
	return nil
end

-- Rays that land on a lurable thing end its lure for good, even from far away.
local function onSeen(instance: BasePart)
	local model = ownerOf(instance)
	if model ~= nil and not touched[model] then
		touched[model] = true
		local lure = lures[model]
		if lure ~= nil then
			lure.emitter.Rate = 0
		end
	end
end

function Lure.start()
	folder.Parent = workspace
	Lidar.ignore(folder)
	Lidar.onSeen(onSeen)
	State.onLevel(function()
		for model in lures do
			drop(model)
		end
		table.clear(touched)
	end)
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return Lure
