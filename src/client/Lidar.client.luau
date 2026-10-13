--!strict
-- LIDAR gun: scatters raycast dots inside a cone; dots are client-side pooled Neon parts.
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local DotRules = require(ReplicatedStorage.Shared.pure.DotRules)

local settings = Config.Lidar
local palette = Config.Colors.default
local player = Players.LocalPlayer

type Dot = { part: Part, born: number, life: number, class: DotRules.DotClass }

local dotFolder = Instance.new("Folder")
dotFolder.Name = "LidarDots"
dotFolder.Parent = workspace

-- Ring buffer of dots: the oldest is recycled once the cap is reached.
local dots: { Dot } = {}
local nextSlot = 1

local function makeDotPart(): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * settings.dotSize
	p.Transparency = 1
	p.Parent = dotFolder
	return p
end

local lifetimes = {
	terrain = settings.terrainLifetime,
	friend = settings.friendLifetime,
	enemy = settings.enemyLifetime,
}

local function classOf(instance: Instance): DotRules.DotClass
	local tags: { string } = {}
	local node: Instance? = instance
	while node and node ~= workspace do
		for _, t in CollectionService:GetTags(node) do
			table.insert(tags, t)
		end
		node = node.Parent
	end
	return DotRules.classify(tags, Config.Tags, false)
end

local function spawnDot(position: Vector3, class: DotRules.DotClass, now: number)
	local dot = dots[nextSlot]
	if not dot then
		dot = { part = makeDotPart(), born = now, life = 0, class = class }
		dots[nextSlot] = dot
	end
	nextSlot = nextSlot % settings.maxLiveDots + 1
	dot.born = now
	dot.life = DotRules.lifetime(class, lifetimes)
	dot.class = class
	dot.part.Position = position
	dot.part.Color = palette[class]
	local scale = if class == "terrain" then 1 else 1.8
	dot.part.Size = Vector3.one * settings.dotSize * scale
	dot.part.Transparency = 0
end

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function coneDirection(look: CFrame, halfAngleDeg: number): Vector3
	local theta = math.rad(halfAngleDeg) * math.sqrt(math.random())
	local phi = math.random() * math.pi * 2
	local offset = look * CFrame.Angles(0, 0, phi) * CFrame.Angles(theta, 0, 0)
	return -offset.ZVector
end

-- Input state
local firing = false
local focusing = false
local heat = 0
local lockedUntil = 0
local accumulator = 0

local function onFire(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	firing = state == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Sink
end

local function onFocus(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	focusing = state == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction(
	"LidarFire",
	onFire,
	true,
	Enum.UserInputType.MouseButton1,
	Enum.KeyCode.ButtonR2
)
ContextActionService:BindAction(
	"LidarFocus",
	onFocus,
	true,
	Enum.UserInputType.MouseButton2,
	Enum.KeyCode.LeftShift,
	Enum.KeyCode.ButtonL2
)
ContextActionService:SetTitle("LidarFire", "SCAN")
ContextActionService:SetTitle("LidarFocus", "FOCUS")
ContextActionService:SetPosition("LidarFire", UDim2.new(1, -120, 1, -140))
ContextActionService:SetPosition("LidarFocus", UDim2.new(1, -210, 1, -90))

-- Heat bar
local gui = Instance.new("ScreenGui")
gui.Name = "LidarHud"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.Parent = player:WaitForChild("PlayerGui")
local barBack = Instance.new("Frame")
barBack.Size = UDim2.fromOffset(160, 8)
barBack.Position = UDim2.new(0.5, -80, 1, -30)
barBack.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
barBack.BorderSizePixel = 0
barBack.Parent = gui
local bar = Instance.new("Frame")
bar.Size = UDim2.fromScale(0, 1)
bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
bar.BorderSizePixel = 0
bar.Parent = barBack

UserInputService.MouseIconEnabled = true

RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	-- Fade and retire dots.
	for _, dot in dots do
		if dot.part.Transparency < 1 then
			local age = (now - dot.born) / dot.life
			if age >= 1 then
				dot.part.Transparency = 1
			else
				dot.part.Transparency = age * age
			end
		end
	end

	-- Heat
	local locked = now < lockedUntil
	local isFocus = focusing and not locked
	heat = DotRules.stepHeat(
		heat,
		isFocus and firing,
		dt,
		settings.heatPerSecondFocus,
		settings.coolPerSecond
	)
	if heat >= 1 and not locked then
		lockedUntil = now + settings.overheatLockSeconds
		heat = 1
	end
	bar.Size = UDim2.fromScale(heat, 1)
	bar.BackgroundColor3 = if locked then palette.enemy else palette.terrain

	if not firing or locked then
		accumulator = 0
		return
	end

	local character = player.Character
	raycastParams.FilterDescendantsInstances = if character
		then { character, dotFolder }
		else { dotFolder }

	local rate = if isFocus then settings.focusDotsPerSecond else settings.dotsPerSecond
	local halfAngle = if isFocus then settings.focusConeHalfAngleDeg else settings.coneHalfAngleDeg
	accumulator += rate * dt
	local count = math.floor(accumulator)
	accumulator -= count
	local look = camera.CFrame
	for _ = 1, count do
		local direction = coneDirection(look, halfAngle)
		local result =
			workspace:Raycast(look.Position, direction * settings.maxRange, raycastParams)
		if result then
			spawnDot(result.Position, classOf(result.Instance), now)
		end
	end
end)
