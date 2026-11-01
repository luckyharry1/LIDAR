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
local Skins = require(ReplicatedStorage.Shared.data.Skins)
local State = require(script.Parent.State)

type Piece = { part: Part, offset: CFrame }
type ModelDef = { specs: { Spec }, light: CFrame }
type Spec = {
	size: { number },
	at: { number },
	color: { number }?, -- nil: takes the housing colour (and any equipped skin)
	shape: Enum.PartType?,
	turn: number?, -- yaw in degrees (cylinders lie along x, so 90 points them forward)
	pitch: number?,
	glow: boolean?, -- dim neon in the skin's dot colour
}

local lidar = Config.Lidar

-- Where the gun sits relative to the camera, and how big it is drawn.
local REST = CFrame.new(0.5, -0.46, -1.15)
local SCALE = 0.5
local DEFAULT_HOUSING = { 96, 100, 108 }
local DARK = { 34, 36, 40 }
local READY_LIGHT = Color3.fromRGB(200, 220, 255)
local CHARGING_LIGHT = Color3.fromRGB(255, 60, 40)
local GLOW_TRANSPARENCY = 0.35 -- the model's glowing part: dim, so it never competes with the dots
local RIM_TRANSPARENCY = 0.55 -- the faint outline that makes the gun's shape show in the dark
local PLAIN_DOTS = { 196, 200, 210 }
local LIGHT_SIZE = 0.014 -- a pinprick: it must never compete with the dots
local SWAY = 0.018
local KICK = 0.006 -- how far the gun jitters while scanning
local SWEEP_TILT = 0.2 -- share of the sweep's own angles the gun follows as it runs
local SWEEP_PULL = 0.025 -- the gun draws back a touch while sweeping
-- Beyond this the camera is in third person: hide the gun. Crouching lowers the view by
-- crouchCameraDrop, which must not count as leaving first person (the gun stays up while crouched).
local FIRST_PERSON_DISTANCE = 1.2 + Config.Player.crouchCameraDrop
local LOWERED_ABOVE = 0.2 -- how lit it must be before the scanner is put away

-- Sizes and positions are in gun-local studs before SCALE; z is negative toward the muzzle.
-- Every scanner model is a list of these pieces. A piece with no colour takes the skin's gun
-- colour; `glow` pieces are dim neon in the skin's dot colour, so each model still reads as its
-- own shape in the dark, where little else of the gun shows.
local GRIP: Spec = { size = { 0.24, 0.5, 0.28 }, at = { 0, -0.4, 0.34 }, pitch = -12 }

local MODELS: { [string]: ModelDef } = {
	-- The original: a boxy gun with a barrel and an emitter dish.
	classic = {
		light = CFrame.new(0, 0.115, 0.2),
		specs = {
			{ size = { 0.34, 0.4, 1.2 }, at = { 0, 0, 0 } }, -- body
			GRIP,
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
		},
	},
	-- A hand lantern: a round body, a cage, a carry handle and a glowing lens.
	lantern = {
		light = CFrame.new(0, 0.24, 0.3),
		specs = {
			{
				size = { 0.9, 0.42, 0.42 },
				at = { 0, 0, -0.1 },
				shape = Enum.PartType.Cylinder,
				turn = 90,
			},
			{
				size = { 0.1, 0.52, 0.52 },
				at = { 0, 0, -0.58 },
				color = DARK,
				shape = Enum.PartType.Cylinder,
				turn = 90,
			},
			{
				size = { 0.05, 0.36, 0.36 },
				at = { 0, 0, -0.66 },
				glow = true,
				shape = Enum.PartType.Cylinder,
				turn = 90,
			},
			{ size = { 0.06, 0.2, 0.6 }, at = { 0, 0.38, -0.1 }, color = DARK }, -- carry handle
			{ size = { 0.05, 0.05, 0.9 }, at = { 0.27, 0, -0.1 }, color = DARK }, -- cage bars
			{ size = { 0.05, 0.05, 0.9 }, at = { -0.27, 0, -0.1 }, color = DARK },
			{ size = { 0.22, 0.4, 0.26 }, at = { 0, -0.42, 0.25 }, pitch = -12 }, -- grip
		},
	},
	-- A radar dish on a slim body, with a glowing feed in front of the dish.
	dish = {
		light = CFrame.new(0, 0.2, 0.2),
		specs = {
			{ size = { 0.28, 0.3, 1.0 }, at = { 0, 0, 0 } },
			GRIP,
			{ size = { 0.1, 0.1, 0.4 }, at = { 0, 0.05, -0.6 }, color = DARK }, -- neck
			{
				size = { 0.06, 0.9, 0.9 },
				at = { 0, 0.05, -0.95 },
				shape = Enum.PartType.Cylinder,
				turn = 90,
			},
			{
				size = { 0.14, 0.14, 0.14 },
				at = { 0, 0.05, -0.72 },
				glow = true,
				shape = Enum.PartType.Ball,
			},
		},
	},
	-- A long slim barrel with fins and a glowing crystal at the muzzle.
	prism = {
		light = CFrame.new(0, 0.16, 0.35),
		specs = {
			{ size = { 0.24, 0.28, 1.4 }, at = { 0, 0, -0.1 } },
			{ size = { 0.22, 0.5, 0.26 }, at = { 0, -0.38, 0.4 }, pitch = -12 },
			{ size = { 0.04, 0.3, 0.7 }, at = { 0, 0.26, -0.3 } }, -- top fin
			{ size = { 0.62, 0.04, 0.5 }, at = { 0, 0, -0.5 } }, -- wings
			{
				size = { 0.22, 0.22, 0.22 },
				at = { 0, 0.02, -0.95 },
				glow = true,
				turn = 45,
				pitch = 45,
			}, -- crystal
		},
	},
	-- Flower petals round the muzzle with a glowing heart.
	blossom = {
		light = CFrame.new(0, 0.2, 0.2),
		specs = {
			{ size = { 0.26, 0.3, 1.0 }, at = { 0, 0, 0 } },
			GRIP,
			{ size = { 0.62, 0.05, 0.34 }, at = { 0, 0.02, -0.78 } }, -- petals
			{ size = { 0.05, 0.62, 0.34 }, at = { 0, 0.02, -0.78 } },
			{ size = { 0.5, 0.05, 0.3 }, at = { 0, 0.02, -0.82 }, turn = 45 },
			{
				size = { 0.18, 0.18, 0.18 },
				at = { 0, 0.02, -0.84 },
				glow = true,
				shape = Enum.PartType.Ball,
			},
		},
	},
}

local Viewmodel = {}

local player = Players.LocalPlayer
local model = Instance.new("Model")
model.Name = "Scanner"
local pieces: { Piece } = {}
local housing: { Part } = {}
local glows: { Part } = {}
local rim: Highlight
local light: Part
local builtModel = ""
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

-- Builds the parts of one scanner model, replacing whatever was there.
local function build(modelId: string)
	local def = MODELS[modelId] or MODELS.classic
	builtModel = if MODELS[modelId] then modelId else "classic"
	model:ClearAllChildren()
	table.clear(pieces)
	table.clear(housing)
	table.clear(glows)
	for _, spec in def.specs do
		local size = Vector3.new(spec.size[1], spec.size[2], spec.size[3]) * SCALE
		local material = if spec.glow then Enum.Material.Neon else Enum.Material.Metal
		local part = newPart(size, rgb(spec.color or DEFAULT_HOUSING), material, spec.shape)
		local offset = CFrame.new(spec.at[1] * SCALE, spec.at[2] * SCALE, spec.at[3] * SCALE)
			* CFrame.Angles(math.rad(spec.pitch or 0), math.rad(spec.turn or 0), 0)
		table.insert(pieces, { part = part, offset = offset })
		if spec.glow then
			part.Transparency = GLOW_TRANSPARENCY
			table.insert(glows, part)
		elseif spec.color == nil then
			table.insert(housing, part)
		end
	end
	light = newPart(Vector3.one * LIGHT_SIZE, READY_LIGHT, Enum.Material.Neon, Enum.PartType.Ball)
	table.insert(pieces, { part = light, offset = def.light })
	-- A faint rim light in the skin's colour: the housing is dark metal, so without an outline
	-- the gun's shape would be lost in the dark. It colours only the gun, never the world.
	rim = Instance.new("Highlight")
	rim.Name = "Rim"
	rim.Adornee = model
	rim.FillTransparency = 1
	rim.OutlineTransparency = RIM_TRANSPARENCY
	rim.DepthMode = Enum.HighlightDepthMode.Occluded
	rim.Parent = model
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
	-- (A safe place in the dark has no light, so the scanner stays up there.)
	local visible = firstPerson
		and Atmosphere.lit < LOWERED_ABOVE
		and (stage == "tutorial" or stage == "level" or stage == "lore" or stage == "passage")
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

-- Wears the equipped Phosphor skin: its model (the gun's shape), housing colour and glow.
local function applySkin()
	local skin = Skins.byId[State.profile.skin]
	local wanted = if skin then skin.model else "classic"
	if wanted ~= builtModel then
		build(wanted)
	end
	local housingColor = rgb(if skin then skin.gun else DEFAULT_HOUSING)
	for _, part in housing do
		part.Color = housingColor
	end
	local glowColor = rgb(if skin then skin.wall else PLAIN_DOTS)
	for _, part in glows do
		part.Color = glowColor
	end
	rim.OutlineColor = glowColor
end

function Viewmodel.start()
	build("classic")
	Lidar.ignore(model)
	State.onProfile(applySkin)
	applySkin()
	RunService:BindToRenderStep("LidarViewmodel", Enum.RenderPriority.Camera.Value + 2, update)
end

return Viewmodel
