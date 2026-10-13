--!strict
-- Server entry point: prepares the dark world, then starts the services in dependency order.

local Lighting = game:GetService("Lighting")

local Data = require(script.Parent.Data)
local Director = require(script.Parent.Director)
local Enemies = require(script.Parent.Enemies)

-- Things a default Studio baseplate ships with that would leak light or let players wander
-- outside the game. Removed at run time only; the saved place is not touched.
local TEMPLATE_INSTANCES = { "Baseplate", "SpawnLocation" }

local function prepareWorld()
	for _, name in TEMPLATE_INSTANCES do
		local instance = workspace:FindFirstChild(name)
		if instance then
			instance:Destroy()
		end
	end
	-- The true world is never visible: no sun, no ambient, no sky, no environment light.
	Lighting:ClearAllChildren()
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.new(0, 0, 0)
	Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	Lighting.GlobalShadows = false
	Lighting.ClockTime = 0
	Lighting.FogColor = Color3.new(0, 0, 0)
	local sky = Instance.new("Sky")
	sky.Name = "BlackSky"
	sky.StarCount = 0
	sky.CelestialBodiesShown = false
	for _, face in { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" } do
		(sky :: any)[face] = ""
	end
	sky.Parent = Lighting
end

prepareWorld()
Data.start()
Enemies.start()
Director.start()
