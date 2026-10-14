--!strict
-- The scanner in the player's hands. In the dark only its pinprick status light shows (and
-- the gun's silhouette against the dots); in a lit room it is lowered out of the way. The
-- light is pale when the sweep is ready and red while it recharges, so the charge can be read
-- without looking away, and the gun tips from top to bottom as a sweep runs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Atmosphere = require(script.Parent.Atmosphere)
local Avatar = require(script.Parent.Avatar)
local Config = require(ReplicatedStorage.Shared.Config)
local Lidar = require(script.Parent.Lidar)
local State = require(script.Parent.State)
local Upgrades = require(ReplicatedStorage.Shared.data.Upgrades)

type Piece = { part: Part, offset: CFrame }
type Spec = {
	size: { number },
	at: { number },
	color: { number }?, -- nil: takes the housing colour (and any equipped skin)
	shape: Enum.PartType?,
	turn: number?, -- yaw in degrees (cylinders lie along x, so 90 points them forward)
	pitch: number?,
}

local lidar = Config.Lidar

-- Where the gun sits relative to the camera, and how big it is drawn.
local REST = CFrame.new(0.5, -0.46, -1.15)
local SCALE = 0.5
local DEFAULT_HOUSING = { 96, 100, 108 }
local DARK = { 34, 36, 40 }
local READY_LIGHT = Color3.fromRGB(200, 220, 255)
local CHARGING_LIGHT = Color3.fromRGB(255, 60, 40)
local LIGHT_SIZE = 0.014 -- a pinprick: it must never compete with the dots
local LIGHT_OFFSET = CFrame.new(0, 0.115, 0.2)
local SWAY = 0.018
local KICK = 0.006 -- how far the gun jitters while scanning
local SWEEP_TILT = 0.2 -- share of the sweep's own angles the gun follows as it runs
local SWEEP_PULL = 0.025 -- the gun draws back a touch while sweeping
local FIRST_PERSON_DISTANCE = 1.2 -- beyond this the camera is in third person: hide the gun
local LOWERED_ABOVE = 0.2 -- how lit it must be before the scanner is put away

-- Sizes and positions are in gun-local studs before SCALE; z is negative toward the muzzle.
local SPECS: { Spec } = {
	{ size = { 0.34, 0.4, 1.2 }, at = { 0, 0, 0 } }, -- body
	{ size = { 0.24, 0.5, 0.28 }, at = { 0, -0.4, 0.34 }, pitch = -12 }, -- grip
	{ size = { 0.3, 0.12, 0.7 }, at = { 0, 0.26, 0.05 } }, -- top rail
	{
		size = { 0.5, 0.26, 0.26 },
		at = { 0, 0.02, -0.82 },
		color = DARK,
		shape = Enum.PartType.Cylinder,
		turn = 90,
	}, -- barrel
	{
		size = { 0.07, 0.48, 0.48 },
		at = { 0, 0.02, -1.1 },
		color = DARK,
		shape = Enum.PartType.Cylinder,
		turn = 90,
	}, -- emitter dish
	{ size = { 0.36, 0.08, 0.3 }, at = { 0, -0.24, -0.3 }, color = DARK }, -- trigger guard
}

local Viewmodel = {}

local player = Players.LocalPlayer
local model = Instance.new("Model")
model.Name = "Scanner"
local pieces: { Piece } = {}
local housing: { Part } = {}
local light: Part
local swayTime = 0
local sweepStarted = 0
local wasSweeping = false

local function newPart(
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.Color = color
	part.Material = material
	part.Shape = shape or Enum.PartType.Block
	part.Parent = model
	return part
end

local function rgb(triple: { number }): Color3
	return Color3.fromRGB(triple[1], triple[2], triple[3])
end

local function build()
	for _, spec in SPECS do
		local size = Vector3.new(spec.size[1], spec.size[2], spec.size[3]) * SCALE
		local part =
			newPart(size, rgb(spec.color or DEFAULT_HOUSING), Enum.Material.Metal, spec.shape)
		local offset = CFrame.new(spec.at[1] * SCALE, spec.at[2] * SCALE, spec.at[3] * SCALE)
			* CFrame.Angles(math.rad(spec.pitch or 0), math.rad(spec.turn or 0), 0)
		table.insert(pieces, { part = part, offset = offset })
		if spec.color == nil then
			table.insert(housing, part)
		end
	end
	light = newPart(Vector3.one * LIGHT_SIZE, READY_LIGHT, Enum.Material.Neon, Enum.PartType.Ball)
	table.insert(pieces, { part = light, offset = LIGHT_OFFSET })
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	local stage = State.server.stage
	local character = player.Character
	local head = if character then character:FindFirstChild("Head") else nil
	local firstPerson = camera ~= nil
		and head ~= nil
		and head:IsA("BasePart")
		and (camera.CFrame.Position - head.Position).Magnitude < FIRST_PERSON_DISTANCE
	-- In a lit room the scanner is lowered: there is nothing to scan and it would only be in the way.
	local visible = firstPerson
		and Atmosphere.lit < LOWERED_ABOVE
		and (stage == "tutorial" or stage == "level")
	if not visible or camera == nil then
		if model.Parent ~= nil then
			model.Parent = nil
		end
		return
	end
	if model.Parent ~= camera then
		model.Parent = camera
	end

	swayTime += dt * (if Avatar.moving then 6 else 1.2)
	local bob = if Avatar.moving then 1 else 0.3
	local sway =
		CFrame.new(math.sin(swayTime * 0.5) * SWAY, math.abs(math.cos(swayTime)) * SWAY * bob, 0)
	local kick = CFrame.new()
	if Lidar.firing or Lidar.sweeping then
		kick = CFrame.new((math.random() - 0.5) * KICK, (math.random() - 0.5) * KICK, 0)
	end
	-- Follow the sweep line down the view: start tipped up, finish tipped down.
	local now = os.clock()
	if Lidar.sweeping and not wasSweeping then
		sweepStarted = now
	end
	wasSweeping = Lidar.sweeping
	local tilt = CFrame.new()
	if Lidar.sweeping then
		local progress = math.clamp((now - sweepStarted) / lidar.sweepSeconds, 0, 1)
		local pitch = lidar.sweepUpDeg - progress * (lidar.sweepUpDeg + lidar.sweepDownDeg)
		tilt = CFrame.new(0, 0, SWEEP_PULL) * CFrame.Angles(math.rad(pitch * SWEEP_TILT), 0, 0)
	end
	local base = camera.CFrame * REST * sway * kick * tilt
	for _, entry in pieces do
		entry.part.CFrame = base * entry.offset
	end
	light.Color = CHARGING_LIGHT:Lerp(READY_LIGHT, Lidar.charge)
	light.Transparency = if Lidar.firing or Lidar.sweeping then 0.35 else 0.7
end

local function applySkin()
	local skin = Upgrades.cosmeticById[State.profile.cosmetics.gun]
	local color = rgb(if skin then skin.color else DEFAULT_HOUSING)
	for _, part in housing do
		part.Color = color
	end
end

function Viewmodel.start()
	build()
	Lidar.ignore(model)
	State.onProfile(applySkin)
	RunService:BindToRenderStep("LidarViewmodel", Enum.RenderPriority.Camera.Value + 2, update)
end

return Viewmodel
