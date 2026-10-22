--!strict
-- Ties the places together: leaving a level fades the world out and dulls the sound, the next
-- place comes up out of the black, each floor has its own colour, echo and ambience, and the
-- view narrows a little when something is close.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Atmosphere = require(script.Parent.Atmosphere)
local Audio = require(script.Parent.Audio)
local Hud = require(script.Parent.Hud)
local Lore = require(ReplicatedStorage.Shared.data.Lore)
local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.State)

type Mood = { tint: Color3, speed: number, drips: number, reverb: Enum.ReverbType }

local FADE_OUT_SECONDS = 2.4
local FADE_IN_SECONDS = 2.2
local FADE_GIVE_UP_SECONDS = 9 -- the black never outstays a lost message
local THREAT_FOV_NARROWING = 7 -- degrees lost when something is on top of you
local FOV_EASE_PER_SECOND = 3

-- The four floors (by the first tier of each); past them, the Relay keeps the last mood.
local MOODS: { [number]: Mood } = {
	[1] = {
		tint = Color3.fromRGB(240, 255, 234),
		speed = 1,
		drips = 0.5,
		reverb = Enum.ReverbType.Hallway,
	},
	[3] = {
		tint = Color3.fromRGB(215, 240, 255),
		speed = 0.85,
		drips = 1.6,
		reverb = Enum.ReverbType.SewerPipe,
	},
	[5] = {
		tint = Color3.fromRGB(226, 255, 220),
		speed = 1.1,
		drips = 1,
		reverb = Enum.ReverbType.Forest,
	},
	[7] = {
		tint = Color3.fromRGB(255, 236, 218),
		speed = 0.7,
		drips = 0.8,
		reverb = Enum.ReverbType.StoneCorridor,
	},
}
local DEFAULT_MOOD: Mood = {
	tint = Color3.new(1, 1, 1),
	speed = 1,
	drips = 1,
	reverb = Enum.ReverbType.GenericRoom,
}

local Immersion = {}

local baseFov = 70
local fov = 70
local blackToken = 0 -- identifies the latest fade to black, so an old timeout cannot lift a new one
local blackedOut = false

local function comeUp(haven: boolean)
	blackToken += 1
	if not blackedOut then
		return
	end
	blackedOut = false
	Hud.fade(0, FADE_IN_SECONDS)
	Audio.muffle(false)
	Audio.arrive(haven)
end

local function goBlack()
	blackToken += 1
	local token = blackToken
	blackedOut = true
	Hud.fade(1, FADE_OUT_SECONDS)
	Audio.muffle(true)
	task.delay(FADE_GIVE_UP_SECONDS, function()
		if blackToken == token then
			comeUp(false)
		end
	end)
end

local function applyMood(tier: number)
	local section = Lore.sectionFor(tier)
	local mood = if section ~= nil then MOODS[section.first] or DEFAULT_MOOD else DEFAULT_MOOD
	Atmosphere.setTint(mood.tint)
	Audio.setMood(mood.speed, mood.drips, mood.reverb)
end

function Immersion.start()
	local camera = workspace.CurrentCamera
	if camera then
		baseFov = camera.FieldOfView
		fov = baseFov
	end

	(Net.get("Objective") :: RemoteEvent).OnClientEvent:Connect(function(kind: string)
		if kind == "exit" then
			goBlack()
		end
	end)

	State.onState(function(server, previous)
		if server.stage == "title" then
			applyMood(0)
			comeUp(false)
			return
		end
		if server.stage ~= "level" and server.stage ~= "lore" then
			return
		end
		applyMood(server.tier)
		local arrived = server.epoch ~= previous.epoch
			or server.stage ~= previous.stage and previous.stage ~= "downed"
		if arrived then
			comeUp(server.stage == "lore")
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local current = workspace.CurrentCamera
		if current == nil then
			return
		end
		local playing = State.inLevel()
		local threat = if playing then Audio.threat() else 0
		local target = baseFov - THREAT_FOV_NARROWING * threat * threat
		fov += (target - fov) * math.min(1, dt * FOV_EASE_PER_SECOND)
		current.FieldOfView = fov
	end)
end

return Immersion
