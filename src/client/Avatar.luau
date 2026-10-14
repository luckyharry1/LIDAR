--!strict
-- The local character: walk, sprint and crouch speeds, the slower wade through flooded cells,
-- the lowered view while crouched, a gentle camera bob, and the spectator camera used while
-- downed in co-op.
-- Speed is set locally (the client owns its character's physics); the server never trusts
-- it and works out how loud a player is from the velocity it observes. A claimed crouch is
-- only believed while the player is actually moving slowly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Atmosphere = require(script.Parent.Atmosphere)
local Config = require(ReplicatedStorage.Shared.Config)
local Input = require(script.Parent.Input)
local State = require(script.Parent.State)

local settings = Config.Player
local WADE_SPEED_SCALE = 0.8
local WATER_CHECK_HZ = 5
local WATER_PROBE = 8 -- studs straight down
local BOB_BLEND = 8
local CROUCH_BLEND = 9 -- how quickly the view drops and rises
local SPECTATE_ZOOM = 12

local Avatar = {}

Avatar.wading = false -- true while standing in a flooded cell
Avatar.moving = false
Avatar.crouching = false -- crouch is actually applied (not downed, not lit, no menu open)

local player = Players.LocalPlayer
local waterTimer = 0
local bobTime = 0
local bobAmount = 0
local crouchAmount = 0 -- 0 standing, 1 fully down: eases the camera rather than snapping it
local spectating: Player? = nil
local probe = RaycastParams.new()
probe.FilterType = Enum.RaycastFilterType.Exclude

local function humanoidOf(character: Model?): Humanoid?
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function stopSpectating()
	if spectating == nil then
		return
	end
	spectating = nil
	local camera = workspace.CurrentCamera
	local humanoid = humanoidOf(player.Character)
	if camera and humanoid then
		camera.CameraSubject = humanoid
	end
	player.CameraMaxZoomDistance = 0.5
	player.CameraMinZoomDistance = 0.5
	player.CameraMode = Enum.CameraMode.LockFirstPerson
end

-- While downed, watch the nearest teammate who is still standing.
local function spectate()
	local camera = workspace.CurrentCamera
	local root = if player.Character
		then player.Character:FindFirstChild("HumanoidRootPart")
		else nil
	if camera == nil or root == nil or not root:IsA("BasePart") then
		return
	end
	local best: Player? = nil
	local bestDistance = math.huge
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local otherRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if
			other ~= player
			and character
			and otherRoot
			and otherRoot:IsA("BasePart")
			and character:GetAttribute("Downed") ~= true
		then
			local distance = (otherRoot.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	if best ~= spectating then
		local humanoid = if best then humanoidOf(best.Character) else nil
		if best and humanoid then
			spectating = best
			player.CameraMode = Enum.CameraMode.Classic
			player.CameraMaxZoomDistance = SPECTATE_ZOOM
			player.CameraMinZoomDistance = SPECTATE_ZOOM
			camera.CameraSubject = humanoid
		end
	end
end

local function update(dt: number)
	local character = player.Character
	local humanoid = humanoidOf(character)
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if character == nil or humanoid == nil or root == nil or not root:IsA("BasePart") then
		Avatar.crouching = false
		return
	end

	local stage = State.server.stage
	if stage == "downed" then
		spectate()
	else
		stopSpectating()
	end

	waterTimer -= dt
	if waterTimer <= 0 then
		waterTimer = 1 / WATER_CHECK_HZ
		probe.FilterDescendantsInstances = { character }
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -WATER_PROBE, 0), probe)
		Avatar.wading = hit ~= nil and hit.Instance:GetAttribute("Flooded") == true
	end

	local velocity = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	Avatar.moving = velocity.Magnitude > 1

	local downed = character:GetAttribute("Downed") == true
	local lit = Atmosphere.lit > 0.5
	Avatar.crouching = Input.crouching
		and not downed
		and not lit
		and not State.menuOpen
		and stage ~= "title"

	if not downed then
		local speed = settings.walkSpeed
		if lit then
			speed = settings.litWalkSpeed
		elseif Avatar.crouching then
			speed = settings.crouchSpeed
		elseif Input.sprinting and not State.menuOpen then
			speed = settings.sprintSpeed
		end
		if Avatar.wading then
			speed *= WADE_SPEED_SCALE
		end
		if State.menuOpen then
			speed = 0
		end
		humanoid.WalkSpeed = speed
	end

	-- Camera bob: subtle, scaled by speed, and eased so stopping does not snap. Crouching
	-- lowers the view by easing toward the drop rather than jumping to it.
	local target = if Avatar.moving and spectating == nil
		then math.min(velocity.Magnitude / settings.walkSpeed, 1.6)
		else 0
	bobAmount += (target - bobAmount) * math.min(1, dt * BOB_BLEND)
	bobTime += dt * settings.cameraBobFrequency * (0.6 + 0.4 * bobAmount)
	local crouchTarget = if Avatar.crouching and spectating == nil then 1 else 0
	crouchAmount += (crouchTarget - crouchAmount) * math.min(1, dt * CROUCH_BLEND)
	local amplitude = settings.cameraBobAmplitude * bobAmount
	humanoid.CameraOffset = Vector3.new(
		math.sin(bobTime * 0.5) * amplitude * 0.6,
		math.abs(math.sin(bobTime)) * amplitude - crouchAmount * settings.crouchCameraDrop,
		0
	)
end

function Avatar.start()
	RunService:BindToRenderStep("LidarAvatar", Enum.RenderPriority.Character.Value + 1, update)
end

return Avatar
