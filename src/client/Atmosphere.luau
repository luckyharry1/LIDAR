--!strict
-- Client-side lighting. The maze is pitch black; lit lore rooms are warm and bright. Rooms
-- mark themselves with a tagged zone part, and this controller eases the whole look across
-- as the player's camera enters or leaves one: the "exhale" after the dark.
-- Lighting changes made here are local, so each player sees the light for where they are.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local EASE_IN_SECONDS = 1.6 -- dark to lit
local EASE_OUT_SECONDS = 0.9 -- lit to dark
local DARK_FOG_START = 36
local DARK_FOG_END = 210 -- black fog: distant dots dim with range, which reads as depth
local LIT_FOG = 100000
local LIT_AMBIENT_SCALE = 0.8
local DARK_BLOOM = { intensity = 0.55, size = 14, threshold = 1 }
local LIT_BLOOM = { intensity = 0.15, size = 18, threshold = 1.6 }
local LIT_ZOOM = 14
local FIRST_PERSON_ZOOM = 0.5

local Atmosphere = {}

Atmosphere.lit = 0 -- 0 in the dark, 1 fully inside a lit room

local player = Players.LocalPlayer
local bloom: BloomEffect
local correction: ColorCorrectionEffect
local currentZone: BasePart? = nil
local zoneListeners: { (zone: BasePart?) -> () } = {}
local litColor = Color3.fromRGB(255, 220, 180)
local forcedDark = false

-- Called with the zone part when the player enters a lit room, and nil when they leave.
function Atmosphere.onZone(listener: (zone: BasePart?) -> ())
	table.insert(zoneListeners, listener)
end

function Atmosphere.zone(): BasePart?
	return currentZone
end

-- The title screen keeps the world dark and the camera scripted regardless of zones.
function Atmosphere.forceDark(value: boolean)
	forcedDark = value
end

-- A dark zone is a safe place built in the dark like the maze: it only marks where the player
-- is (for the title card and the calm), and brings no light of its own.
local function isDark(zone: BasePart?): boolean
	return zone ~= nil and zone:GetAttribute("Dark") == true
end

local function findZone(position: Vector3): BasePart?
	for _, zone in CollectionService:GetTagged(Config.Tags.litZone) do
		if zone:IsA("BasePart") then
			local localPosition = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2
			if
				math.abs(localPosition.X) <= half.X
				and math.abs(localPosition.Y) <= half.Y
				and math.abs(localPosition.Z) <= half.Z
			then
				return zone
			end
		end
	end
	return nil
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function apply(t: number)
	local eased = t * t * (3 - 2 * t)
	local ambient = Color3.new(0, 0, 0):Lerp(
		Color3.new(
			litColor.R * LIT_AMBIENT_SCALE,
			litColor.G * LIT_AMBIENT_SCALE,
			litColor.B * LIT_AMBIENT_SCALE
		),
		eased
	)
	Lighting.Ambient = ambient
	Lighting.OutdoorAmbient = ambient
	Lighting.FogStart = lerp(DARK_FOG_START, LIT_FOG, eased)
	Lighting.FogEnd = lerp(DARK_FOG_END, LIT_FOG, eased)
	bloom.Intensity = lerp(DARK_BLOOM.intensity, LIT_BLOOM.intensity, eased)
	bloom.Size = lerp(DARK_BLOOM.size, LIT_BLOOM.size, eased)
	bloom.Threshold = lerp(DARK_BLOOM.threshold, LIT_BLOOM.threshold, eased)
	correction.Saturation = lerp(-0.05, -0.1, eased)
	correction.Contrast = lerp(0.08, 0.02, eased)
	correction.Brightness = lerp(0, 0.04, eased)
end

local function setCamera(lit: boolean)
	if lit then
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMinZoomDistance = FIRST_PERSON_ZOOM
		player.CameraMaxZoomDistance = LIT_ZOOM
	else
		player.CameraMaxZoomDistance = FIRST_PERSON_ZOOM
		player.CameraMinZoomDistance = FIRST_PERSON_ZOOM
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	end
end

function Atmosphere.start()
	bloom = Instance.new("BloomEffect")
	bloom.Name = "LidarBloom"
	bloom.Parent = Lighting
	correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "LidarGrade"
	correction.Parent = Lighting
	Lighting.FogColor = Color3.new(0, 0, 0)
	apply(0)
	setCamera(false)

	RunService.RenderStepped:Connect(function(dt: number)
		local camera = workspace.CurrentCamera
		local zone = if camera and not forcedDark then findZone(camera.CFrame.Position) else nil
		if zone ~= currentZone then
			currentZone = zone
			if zone then
				local light = zone:GetAttribute("Light")
				if typeof(light) == "Color3" then
					litColor = light
				end
			end
			setCamera(zone ~= nil and not isDark(zone))
			for _, listener in zoneListeners do
				task.spawn(listener, zone)
			end
		end
		-- Studio playtest aid (see server/Dev): light the maze so its geometry can be inspected.
		local devLit = RunService:IsStudio() and workspace:GetAttribute("DevLit") == true
		local target = if (zone and not isDark(zone)) or devLit then 1 else 0
		if Atmosphere.lit ~= target then
			local rate = if target == 1 then 1 / EASE_IN_SECONDS else 1 / EASE_OUT_SECONDS
			Atmosphere.lit = math.clamp(
				Atmosphere.lit + (target - Atmosphere.lit > 0 and rate or -rate) * dt,
				0,
				1
			)
			apply(Atmosphere.lit)
		end
	end)
end

return Atmosphere
