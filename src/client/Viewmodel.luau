--!strict
-- The scanner in the player's hands. In the dark only its status light shows (and the gun's
-- silhouette against the dots); in a lit room the whole housing is visible. The light runs
-- from pale to red with heat, so the meter can be read without looking away from the dots.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Avatar = require(script.Parent.Avatar)
local Lidar = require(script.Parent.Lidar)
local State = require(script.Parent.State)
local Upgrades = require(ReplicatedStorage.Shared.data.Upgrades)

type Piece = { part: Part, offset: CFrame }

local REST = CFrame.new(0.85, -0.78, -1.5)
local DEFAULT_HOUSING = Color3.fromRGB(46, 48, 54)
local COOL_LIGHT = Color3.fromRGB(200, 220, 255)
local LIGHT_SIZE = 0.014 -- a pinprick: it must never compete with the dots
local HOT_LIGHT = Color3.fromRGB(255, 60, 40)
local SWAY = 0.035
local KICK = 0.012 -- how far the gun jitters while scanning
local FIRST_PERSON_DISTANCE = 1.2 -- beyond this the camera is in third person: hide the gun

local Viewmodel = {}

local player = Players.LocalPlayer
local model = Instance.new("Model")
model.Name = "Scanner"
local pieces: { Piece } = {}
local housing: { Part } = {}
local light: Part
local swayTime = 0

local function piece(
	size: Vector3,
	offset: CFrame,
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
	table.insert(pieces, { part = part, offset = offset })
	return part
end

local function build()
	local metal = Enum.Material.Metal
	table.insert(
		housing,
		piece(Vector3.new(0.34, 0.42, 1.25), CFrame.new(0, 0, 0), DEFAULT_HOUSING, metal)
	)
	table.insert(
		housing,
		piece(
			Vector3.new(0.26, 0.5, 0.3),
			CFrame.new(0, -0.4, 0.35) * CFrame.Angles(math.rad(-12), 0, 0),
			DEFAULT_HOUSING,
			metal
		)
	)
	piece(
		Vector3.new(0.5, 0.3, 0.3),
		CFrame.new(0, 0.02, -0.85) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(26, 26, 30),
		metal,
		Enum.PartType.Cylinder
	)
	piece(
		Vector3.new(0.08, 0.46, 0.46),
		CFrame.new(0, 0.02, -1.12) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(80, 84, 92),
		metal,
		Enum.PartType.Cylinder
	)
	light = piece(
		Vector3.one * LIGHT_SIZE,
		CFrame.new(0, 0.225, 0.42),
		COOL_LIGHT,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
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
	local visible = firstPerson and (stage == "tutorial" or stage == "level" or stage == "lore")
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
	local sway = CFrame.new(
		math.sin(swayTime * 0.5) * SWAY,
		math.abs(math.cos(swayTime)) * SWAY * (if Avatar.moving then 1 else 0.3),
		0
	)
	local kick = if Lidar.firing
		then CFrame.new(
			(math.random() - 0.5) * KICK,
			(math.random() - 0.5) * KICK,
			if Lidar.focusing then 0.04 else 0
		)
		else CFrame.new()
	local base = camera.CFrame * REST * sway * kick
	for _, entry in pieces do
		entry.part.CFrame = base * entry.offset
	end
	light.Color = COOL_LIGHT:Lerp(HOT_LIGHT, Lidar.heat)
	light.Transparency = if Lidar.firing then 0.1 else 0.5
end

local function applySkin()
	local skin = Upgrades.cosmeticById[State.profile.cosmetics.gun]
	local color = if skin
		then Color3.fromRGB(skin.color[1], skin.color[2], skin.color[3])
		else DEFAULT_HOUSING
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
