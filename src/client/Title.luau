--!strict
-- The title screen's backdrop: a small corridor that exists only on this client, slowly
-- scanning itself. A sweeping beam builds the scene out of dots, in all four colours, so the
-- first thing a new player sees is what the game is. Like the maze, the corridor itself is
-- invisible: only its dots are drawn, and they show through walls.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Atmosphere = require(script.Parent.Atmosphere)
local Config = require(ReplicatedStorage.Shared.Config)
local Dots = require(script.Parent.Dots)
local Lidar = require(script.Parent.Lidar)
local State = require(script.Parent.State)

local ORIGIN = Vector3.new(6000, 0, 0) -- far from anything the server builds
local HALF_WIDTH = 9
local LENGTH = 110
local HEIGHT = 11
local CAMERA_HEIGHT = 5.2
local DOTS_PER_SECOND = 170
local CONE_DEGREES = 10
local SWEEP_YAW = 40 -- degrees either side
local SWEEP_PITCH = 25 -- with the cone, reaches the top and bottom of a 70 degree view
local YAW_SPEED = 0.37
local PITCH_SPEED = 0.23
local DRIFT = 0.25 -- camera sway, in studs
local MAX_RAYS_PER_FRAME = 12

local Title = {}

local set: Model? = nil
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
local accumulator = 0
local elapsed = 0
local connection: RBXScriptConnection? = nil

local function block(
	parent: Instance,
	size: Vector3,
	position: Vector3,
	tag: string?,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Size = size
	part.Position = ORIGIN + position
	part.Color = Color3.fromRGB(40, 40, 40)
	part.Transparency = 1
	part.Shape = shape or Enum.PartType.Block
	if tag then
		CollectionService:AddTag(part, tag)
	end
	part.Parent = parent
	return part
end

local function build(): Model
	local model = Instance.new("Model")
	model.Name = "TitleSet"
	local middle = -LENGTH / 2
	block(model, Vector3.new(HALF_WIDTH * 2, 1, LENGTH), Vector3.new(0, -0.5, middle))
	block(model, Vector3.new(HALF_WIDTH * 2, 1, LENGTH), Vector3.new(0, HEIGHT + 0.5, middle))
	block(model, Vector3.new(1, HEIGHT, LENGTH), Vector3.new(-HALF_WIDTH, HEIGHT / 2, middle))
	block(model, Vector3.new(1, HEIGHT, LENGTH), Vector3.new(HALF_WIDTH, HEIGHT / 2, middle))
	block(model, Vector3.new(HALF_WIDTH * 2, HEIGHT, 1), Vector3.new(0, HEIGHT / 2, -LENGTH))
	-- Pillars and an arch give the corridor rhythm.
	for index = 1, 4 do
		local z = -14 - index * 18
		block(model, Vector3.new(2, HEIGHT, 2), Vector3.new(-HALF_WIDTH + 3, HEIGHT / 2, z))
		block(model, Vector3.new(2, HEIGHT, 2), Vector3.new(HALF_WIDTH - 3, HEIGHT / 2, z - 9))
	end
	block(model, Vector3.new(HALF_WIDTH * 2, 2, 1.6), Vector3.new(0, HEIGHT - 1, -44))
	block(model, Vector3.new(3, 3, 3), Vector3.new(HALF_WIDTH - 2.5, 1.5, -22))
	block(model, Vector3.new(2.2, 2.2, 2.2), Vector3.new(HALF_WIDTH - 2.8, 4.1, -22.4))
	block(
		model,
		Vector3.new(12, 0.8, 0.8),
		Vector3.new(-HALF_WIDTH + 1, 8.4, -30),
		nil,
		Enum.PartType.Cylinder
	).Orientation =
		Vector3.new(0, 90, 0)
	-- The door at the far end (gold), someone waiting by the wall (green), something tall (red).
	local objective = Config.Tags.objective
	block(model, Vector3.new(5, 8.4, 0.5), Vector3.new(0, 4.2, -LENGTH + 0.8), objective)
	block(model, Vector3.new(0.8, 9.2, 0.9), Vector3.new(-2.9, 4.6, -LENGTH + 0.9), objective)
	block(model, Vector3.new(0.8, 9.2, 0.9), Vector3.new(2.9, 4.6, -LENGTH + 0.9), objective)
	local friend = Config.Tags.friend
	block(model, Vector3.new(1.8, 2.4, 1), Vector3.new(-HALF_WIDTH + 1.6, 1.6, -52), friend)
	block(
		model,
		Vector3.new(1.2, 1.2, 1.2),
		Vector3.new(-HALF_WIDTH + 1.6, 3.3, -52),
		friend,
		Enum.PartType.Ball
	)
	block(model, Vector3.new(0.7, 1.6, 2), Vector3.new(-HALF_WIDTH + 2.4, 0.9, -52), friend)
	local enemy = Config.Tags.enemy
	block(model, Vector3.new(1.3, 8, 0.8), Vector3.new(4.4, 4, -84), enemy)
	block(model, Vector3.new(0.9, 0.9, 0.9), Vector3.new(4.4, 8.6, -84), enemy, Enum.PartType.Ball)
	block(model, Vector3.new(0.4, 7, 0.4), Vector3.new(2.8, 4.4, -84), enemy)
	block(model, Vector3.new(0.4, 7, 0.4), Vector3.new(6, 4.4, -84), enemy)
	model.Parent = workspace
	return model
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	elapsed += dt
	local eye = ORIGIN
		+ Vector3.new(
			math.sin(elapsed * 0.11) * DRIFT * 4,
			CAMERA_HEIGHT + math.sin(elapsed * 0.17) * DRIFT,
			-2
		)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(eye, ORIGIN + Vector3.new(0, CAMERA_HEIGHT - 0.4, -60))

	local yaw = math.rad(math.sin(elapsed * YAW_SPEED) * SWEEP_YAW)
	local pitch = math.rad(math.sin(elapsed * PITCH_SPEED) * SWEEP_PITCH)
	local beam = camera.CFrame * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	accumulator += DOTS_PER_SECOND * dt
	local count = math.min(math.floor(accumulator), MAX_RAYS_PER_FRAME)
	accumulator -= math.floor(accumulator)
	if count > 0 then
		Lidar.cast(beam, count, CONE_DEGREES, params)
	end
end

local function show()
	if set ~= nil then
		return
	end
	local model = build()
	set = model
	params.FilterDescendantsInstances = { model }
	Atmosphere.forceDark(true)
	Dots.clear()
	connection = RunService.RenderStepped:Connect(update)
end

local function hide()
	local model = set
	if model == nil then
		return
	end
	set = nil
	if connection then
		connection:Disconnect()
		connection = nil
	end
	model:Destroy()
	Dots.clear()
	Atmosphere.forceDark(false)
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		local character = Players.LocalPlayer.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

function Title.start()
	State.onState(function(server)
		if server.stage == "title" then
			show()
		else
			hide()
		end
	end)
	if State.server.stage == "title" then
		show()
	end
end

return Title
