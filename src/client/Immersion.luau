--!strict
-- Ties the places together: leaving a level fades the world out and dulls the sound, the next
-- place comes up out of the black, each floor has its own colour, echo and ambience, and the
-- view narrows a little when something is close.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Atmosphere = require(script.Parent.Atmosphere)
local Audio = require(script.Parent.Audio)
local Dots = require(script.Parent.Dots)
local Hud = require(script.Parent.Hud)
local Lidar = require(script.Parent.Lidar)
local Lore = require(ReplicatedStorage.Shared.data.Lore)
local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.State)

type Mood = { tint: Color3, speed: number, drips: number, reverb: Enum.ReverbType }

local FADE_OUT_SECONDS = 0.8 -- quick: it is a step through a doorway into the dark
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
	reverb = Enum.ReverbType.GenericReverb,
}

-- Found points of interest keep calling: a ring of gold dots rises from each every few
-- seconds and a faint tone plays, so the player is drawn back toward what they have found.
local POI_GRID = 6 -- studs; scans of one item count as one point
local POI_RANGE = 90
local POI_PERIOD = 2.6
local POI_MAX = 5 -- the nearest few pulse; the rest wait
local POI_RING_DOTS = 10
local POI_RING_RADIUS = 1.6
local POI_RISE = 3.5
local POI_DOT_SIZE = 0.09
local POI_DOT_SECONDS = 1.4

-- Distant wrong sounds: how often (seconds) at a calm distance and with a monster close.
local WRONG_CALM = { 22, 45 }
local WRONG_TENSE = { 6, 12 }
local WRONG_KINDS = { "door", "run", "crackle", "bump" }
local WRONG_DISTANCE = { 35, 70 }

-- Lights that stutter when a monster is near.
local FLICKER_THREAT = 0.15
local FLICKER_RANGE = 45
local LIGHT_REFRESH_SECONDS = 4
local STUTTER_GAP = { 0.8, 4 } -- seconds between stutters: right on top of you, and at the edge
local STUTTER_PATTERN = { 0.07, 0.05, 0.14, 0.06, 0.25 } -- off, on, off, on, off, then back

-- Lanterns and the patches of floor and wall around them are built visible, but the player
-- must find them by scanning: they start dark and everything within CONCEAL_REACH of a part
-- the gun lands on comes back, with its lights.
local CONCEAL_REACH = 16
local CONCEAL_DELAYS = { 1, 3 } -- seconds after arriving; the level streams in

type Concealed = { part: BasePart, transparency: number }
type Switch = { light: Instance, brightness: number }

local Immersion = {}

local concealed: { [BasePart]: Concealed } = {}
local concealedList: { Concealed } = {}
local switches: { Switch } = {}
local processed: { [Instance]: boolean } = {} -- each part or light is hidden at most once

local pois: { [string]: Vector3 } = {}
local poiTimer = 0
local wrongTimer = 30
local baseBrightness: { [Light]: number } = {}
local stuttering: { [Light]: boolean } = {}
local stutterTimer = 0
local lightTimer = 0

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

local function poiKey(position: Vector3): string
	return `{math.floor(position.X / POI_GRID)}:{math.floor(position.Y / POI_GRID)}:{math.floor(
		position.Z / POI_GRID
	)}`
end

local function pulsePois(camera: Camera)
	local here = camera.CFrame.Position
	local near: { { position: Vector3, distance: number } } = {}
	for _, position in pois do
		local distance = (position - here).Magnitude
		if distance <= POI_RANGE then
			table.insert(near, { position = position, distance = distance })
		end
	end
	table.sort(near, function(a, b)
		return a.distance < b.distance
	end)
	for index = 1, math.min(#near, POI_MAX) do
		local position = near[index].position
		for dot = 1, POI_RING_DOTS do
			local angle = dot / POI_RING_DOTS * math.pi * 2
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * POI_RING_RADIUS
			Dots.mark(
				position + offset + Vector3.new(0, POI_RISE * (dot % 3) / 3, 0),
				"objective",
				POI_DOT_SIZE,
				POI_DOT_SECONDS
			)
		end
		Audio.poiHum(position)
	end
end

local function wrongSound(camera: Camera)
	local angle = math.random() * math.pi * 2
	local distance = WRONG_DISTANCE[1] + math.random() * (WRONG_DISTANCE[2] - WRONG_DISTANCE[1])
	local position = camera.CFrame.Position
		+ Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	Audio.wrong(WRONG_KINDS[math.random(#WRONG_KINDS)], position)
end

local function refreshLights()
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("PointLight") or descendant:IsA("SpotLight") then
			local light = descendant :: Light
			-- A light mid-stutter keeps the brightness it had before, not its dimmed one.
			if descendant.Enabled and baseBrightness[light] == nil then
				baseBrightness[light] = light.Brightness
			end
		end
	end
end

-- One stutter: the light cuts and catches a few times, and every catch crackles from the
-- bulb itself, so what you see and what you hear are the same event.
local function stutter(light: Light, holder: BasePart)
	stuttering[light] = true
	task.spawn(function()
		local base = baseBrightness[light] or light.Brightness
		for index, seconds in STUTTER_PATTERN do
			if light.Parent == nil then
				break
			end
			local off = index % 2 == 1
			light.Brightness = if off then 0 else base
			Audio.spark(holder.Position, off)
			task.wait(seconds * (0.7 + math.random() * 0.6))
		end
		if light.Parent ~= nil then
			light.Brightness = base
		end
		stuttering[light] = nil
	end)
end

local function flickerLights(camera: Camera, threat: number, dt: number)
	if threat < FLICKER_THREAT then
		stutterTimer = math.min(stutterTimer, STUTTER_GAP[1])
		return
	end
	stutterTimer -= dt
	if stutterTimer > 0 then
		return
	end
	-- Closer monsters, more often.
	stutterTimer = STUTTER_GAP[1] + (STUTTER_GAP[2] - STUTTER_GAP[1]) * (1 - threat) * math.random()
	local here = camera.CFrame.Position
	local choices: { { light: Light, holder: BasePart } } = {}
	for light in baseBrightness do
		local holder = light.Parent
		if holder == nil or not holder:IsA("BasePart") then
			baseBrightness[light] = nil
		elseif
			not stuttering[light]
			and light.Enabled
			and (holder.Position - here).Magnitude <= FLICKER_RANGE
		then
			table.insert(choices, { light = light, holder = holder })
		end
	end
	if #choices > 0 then
		local pick = choices[math.random(#choices)]
		stutter(pick.light, pick.holder)
	end
end

local function concealLevelLights()
	for _, model in workspace:GetDescendants() do
		if
			model:IsA("Model")
			and model.Name == "Lit"
			and model.Parent ~= nil
			and model.Parent:GetAttribute("AllowPlate") ~= nil
		then
			for _, descendant in model:GetDescendants() do
				if processed[descendant] then
					continue
				end
				processed[descendant] = true
				if descendant:IsA("BasePart") then
					local record = { part = descendant, transparency = descendant.Transparency }
					concealed[descendant] = record
					table.insert(concealedList, record)
					descendant.Transparency = 1
				elseif
					(
						descendant:IsA("Light")
						or descendant:IsA("ParticleEmitter")
						or descendant:IsA("SurfaceGui")
					) and (descendant :: any).Enabled
				then
					local light: any = descendant
					table.insert(switches, { light = descendant, brightness = light.Brightness })
					light.Enabled = false
				end
			end
		end
	end
	refreshLights()
end

local function showNear(seen: BasePart)
	local record = concealed[seen]
	if record == nil then
		return
	end
	local center = seen.Position
	for index = #concealedList, 1, -1 do
		local other = concealedList[index]
		if (other.part.Position - center).Magnitude <= CONCEAL_REACH then
			other.part.Transparency = other.transparency
			concealed[other.part] = nil
			table.remove(concealedList, index)
		end
	end
	for index = #switches, 1, -1 do
		local switch = switches[index]
		local holder = switch.light.Parent
		if holder ~= nil and holder:IsA("BasePart") then
			if (holder.Position - center).Magnitude <= CONCEAL_REACH then
				(switch.light :: any).Enabled = true
				table.remove(switches, index)
			end
		else
			table.remove(switches, index)
		end
	end
	refreshLights()
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

	Lidar.onSeen(showNear)
	Lidar.onPoi(function(position: Vector3)
		pois[poiKey(position)] = position
	end)

	State.onState(function(server, previous)
		if server.stage == "title" then
			applyMood(0)
			comeUp(false)
			return
		end
		if server.stage ~= "level" and server.stage ~= "lore" and server.stage ~= "passage" then
			return
		end
		applyMood(server.tier)
		if server.stage == "passage" then
			-- A stairwell rings: long echo, ambience slowed, the floor's drips dry.
			Audio.setMood(0.8, 0.4, Enum.ReverbType.Cave)
		end
		local arrived = server.epoch ~= previous.epoch
			or server.stage ~= previous.stage and previous.stage ~= "downed"
		if arrived then
			comeUp(server.stage == "lore")
			if server.stage == "level" then
				table.clear(concealed)
				table.clear(concealedList)
				table.clear(switches)
				table.clear(processed)
				for _, delay in CONCEAL_DELAYS do
					task.delay(delay, concealLevelLights)
				end
			end
		end
	end)

	State.onLevel(function()
		table.clear(pois)
		wrongTimer = WRONG_CALM[1]
		lightTimer = 0
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
		if not playing then
			return
		end
		poiTimer -= dt
		if poiTimer <= 0 then
			poiTimer = POI_PERIOD
			pulsePois(current)
		end
		wrongTimer -= dt
		if wrongTimer <= 0 and State.server.stage == "level" then
			local range = if threat > FLICKER_THREAT then WRONG_TENSE else WRONG_CALM
			wrongTimer = range[1] + math.random() * (range[2] - range[1])
			wrongSound(current)
		end
		lightTimer -= dt
		if lightTimer <= 0 then
			lightTimer = LIGHT_REFRESH_SECONDS
			refreshLights()
		end
		flickerLights(current, threat, dt)
	end)
end

return Immersion
