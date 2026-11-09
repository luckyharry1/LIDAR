--!strict
-- The close encounter. Now and then, deep in a dark level, the maze goes silent. Heavy steps
-- come toward you out of the dark, each one leaving a red print. They stop. Nothing. Then, a few
-- studs in front of your face, a thing made of red dots lurches at you and is gone, running.
-- It never catches you: it is only ever a scare, so it can be rare and cruel. When one happens
-- is decided by pure/Dread (a coin toss per level, dread that builds while you walk in the dark
-- and builds faster with something real near, a long cooldown). Each player has their own, and
-- nothing about it touches the server.
--
-- In Studio, `workspace:SetAttribute("DevScare", os.clock())` from the command bar plays it now
-- (any new value does; setting the same value twice changes nothing).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Atmosphere = require(script.Parent.Atmosphere)
local Audio = require(script.Parent.Audio)
local Avatar = require(script.Parent.Avatar)
local Config = require(ReplicatedStorage.Shared.Config)
local Cutscene = require(script.Parent.Cutscene)
local Dots = require(script.Parent.Dots)
local Dread = require(ReplicatedStorage.Shared.pure.Dread)
local Effects = require(script.Parent.Effects)
local Hud = require(script.Parent.Hud)
local Immersion = require(script.Parent.Immersion)
local State = require(script.Parent.State)

local settings = Config.Scare
local DEV_ATTRIBUTE = "DevScare"
local STEP_GAP = { 0.95, 0.55 } -- seconds between steps: it speeds up as it nears
local PRINT_SIZE = 0.2
local PRINT_LIFETIME = 9
local PRINT_SIDE = 0.4
local FLOOR_PROBE = 8
local DIRECTIONS = 12 -- headings tried for the steps' approach
local FACING_BONUS = 6 -- studs of preference for a heading the player is already looking along
local MIN_APPROACH = 6
local LURCH_FRAMES = 6
local LURCH_FROM = 1 -- the thing's distance from the camera: strikeDistance ...
local LURCH_TO = 0.55 -- ... closing to this share of it by the last frame
local SHIVER = 0.05 -- studs each dot is knocked about per frame
local FACE_LIFETIME = 0.2
local LAST_FRAME_LIFETIME = 0.6
local HEAD_DOT = 0.14
local EYE_DOT = 0.22
local AFTERMATH_SECONDS = 2.4
local FLEE_DISTANCE = 9

local player = Players.LocalPlayer
local dread = Dread.new(settings)
local token = 0 -- identifies the scare in progress, so a level change can cancel it
local running = false
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local Scare = {}

-- The shape of the thing in its own space: x to the viewer's right, y up, z toward the viewer.
-- A long head, a screaming mouth, hollow shoulders and arms reaching out with spread fingers.
local function shape(): { { point: Vector3, size: number } }
	local dots: { { point: Vector3, size: number } } = {}
	local function add(x: number, y: number, z: number, size: number)
		table.insert(dots, { point = Vector3.new(x, y, z), size = size })
	end
	-- The head: an oval outline, and a second, smaller one in front of it for depth.
	for index = 0, 31 do
		local angle = index / 32 * math.pi * 2
		add(math.cos(angle) * 0.72, 0.25 + math.sin(angle) * 1.05, 0, HEAD_DOT)
		if index % 2 == 0 then
			add(math.cos(angle) * 0.5, 0.2 + math.sin(angle) * 0.8, 0.25, HEAD_DOT * 0.8)
		end
	end
	-- Eyes: two bright filled sockets, a little uneven.
	for side = -1, 1, 2 do
		add(side * 0.3, 0.55 + side * 0.04, 0.1, EYE_DOT * 1.4)
		for index = 0, 7 do
			local angle = index / 8 * math.pi * 2
			add(side * 0.3 + math.cos(angle) * 0.17, 0.55 + math.sin(angle) * 0.13, 0.1, EYE_DOT)
		end
	end
	-- The mouth: a long open oval with a ragged row of teeth along the top.
	for index = 0, 19 do
		local angle = index / 20 * math.pi * 2
		add(math.cos(angle) * 0.34, -0.42 + math.sin(angle) * 0.38, 0.1, HEAD_DOT)
	end
	for index = 0, 6 do
		add(-0.27 + index * 0.09, -0.12 - (index % 2) * 0.1, 0.1, HEAD_DOT * 0.6)
	end
	-- The neck and the shoulders.
	for index = 0, 4 do
		add(-0.3, -0.85 - index * 0.1, 0, HEAD_DOT)
		add(0.3, -0.85 - index * 0.1, 0, HEAD_DOT)
	end
	for index = -10, 10 do
		add(index * 0.13, -1.45 - math.abs(index) * 0.02, 0, HEAD_DOT)
	end
	-- Arms stretched toward the viewer, and fingers spread at the ends.
	for side = -1, 1, 2 do
		for index = 0, 13 do
			local t = index / 13
			add(side * (1.3 - 0.4 * t), -1.45 + 1.2 * t, 0.2 + 1.7 * t, HEAD_DOT * (1 + 0.5 * t))
		end
		for finger = -2, 2 do
			for index = 1, 3 do
				add(side * (0.9 + finger * 0.1), -0.25 + index * 0.12, 1.9 + index * 0.3, HEAD_DOT)
			end
		end
	end
	return dots
end

local figure = shape()

local function alive(mine: number): boolean
	return token == mine and State.server.stage == "level"
end

local function stop()
	token += 1
	running = false
	Audio.setScare(0)
end

local function floorUnder(position: Vector3): Vector3?
	local start = position + Vector3.new(0, 2, 0)
	local hit = workspace:Raycast(start, Vector3.new(0, -FLOOR_PROBE, 0), params)
	return if hit then hit.Position + hit.Normal * 0.04 else nil
end

local function clearDistance(origin: Vector3, direction: Vector3, limit: number): number
	local hit = workspace:Raycast(origin, direction * limit, params)
	return if hit then hit.Distance else limit
end

local function refreshFilter()
	local list: { Instance } = { Dots.folder() }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	params.FilterDescendantsInstances = list
end

-- The heading the steps come from: the clearest way to the player's own view, so they can
-- hear it come out of the dark in front of them. Returns a flat unit vector and how far it runs.
local function approach(eye: Vector3, look: Vector3): (Vector3, number)
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local best, bestScore, bestRun = flat, -math.huge, 0
	for index = 0, DIRECTIONS - 1 do
		local direction = CFrame.Angles(0, index / DIRECTIONS * math.pi * 2, 0) * flat
		local run = clearDistance(eye, direction, settings.stepStartDistance)
		local score = run + direction:Dot(flat) * FACING_BONUS + math.random() * 0.5
		if score > bestScore then
			best, bestScore, bestRun = direction, score, run
		end
	end
	return best, bestRun
end

-- One red print on the floor where a step lands.
local function printAt(position: Vector3, sideways: Vector3, left: boolean)
	local offset = sideways * PRINT_SIDE * (if left then 1 else -1)
	local spot = floorUnder(position + offset)
	if spot ~= nil then
		Dots.mark(spot, "enemy", PRINT_SIZE, PRINT_LIFETIME)
	end
end

-- Draws the thing once, `distance` studs in front of the camera and facing it.
local function drawFigure(camera: Camera, distance: number, lifetime: number)
	local eye = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local centre = eye + look * distance
	local frame = CFrame.lookAt(centre, eye)
	for _, dot in figure do
		local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		local spot = frame:PointToWorldSpace(dot.point) + jitter * SHIVER * 2
		Dots.mark(spot, "enemy", dot.size, lifetime)
	end
end

local function play()
	if running then
		return
	end
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	running = true
	token += 1
	local mine = token
	refreshFilter()

	-- 1. The dark goes quiet. The heartbeat is all that is left.
	Audio.setScare(1)
	task.wait(settings.hushSeconds)
	if not alive(mine) then
		return stop()
	end

	-- 2. Steps, out of the dark and toward you, quicker as they come.
	local eye = camera.CFrame.Position
	local direction, run = approach(eye, camera.CFrame.LookVector)
	local start = math.max(MIN_APPROACH, run * 0.92)
	local sideways = Vector3.new(-direction.Z, 0, direction.X)
	for step = 1, settings.steps do
		local t = (step - 1) / math.max(1, settings.steps - 1)
		local distance = start + (settings.stepEndDistance - start) * t
		local position = eye + direction * distance
		local ground = floorUnder(position) or position - Vector3.new(0, 2.4, 0)
		Audio.scareStep(ground, t)
		printAt(position, sideways, step % 2 == 0)
		task.wait(STEP_GAP[1] + (STEP_GAP[2] - STEP_GAP[1]) * t)
		if not alive(mine) then
			return stop()
		end
	end

	-- 3. Nothing.
	task.wait(settings.silenceSeconds)
	if not alive(mine) then
		return stop()
	end

	-- 4. It is there. It stays in front of whatever you look at, and lurches.
	Audio.scareStrike()
	Hud.flash(Color3.fromRGB(255, 30, 30), 0.7)
	Effects.shake(settings.strikeSeconds, 1.1)
	Effects.pulse(1, 0.5)
	Immersion.kickFov(settings.fovKick)
	for frame = 1, LURCH_FRAMES do
		local current = workspace.CurrentCamera
		if current == nil then
			break
		end
		local progress = (frame - 1) / (LURCH_FRAMES - 1)
		local last = frame == LURCH_FRAMES
		drawFigure(
			current,
			settings.strikeDistance * (LURCH_FROM + (LURCH_TO - LURCH_FROM) * progress),
			if last then LAST_FRAME_LIFETIME else FACE_LIFETIME
		)
		task.wait(settings.strikeSeconds / LURCH_FRAMES)
		if token ~= mine then
			return stop()
		end
	end

	-- 5. It is gone, running the way it came. The dark comes back slowly.
	local current = workspace.CurrentCamera
	if current ~= nil then
		Audio.wrong("run", current.CFrame.Position + direction * FLEE_DISTANCE)
	end
	task.wait(AFTERMATH_SECONDS)
	stop()
end

-- Whether a scare would land well right now.
local function eligible(): boolean
	return not running
		and State.server.stage == "level"
		and Atmosphere.lit < 0.02
		and not State.menuOpen
		and not Cutscene.playing
		and not Dots.isFrozen()
		and Audio.threat() < settings.clearThreat
end

local function update(dt: number)
	if running or not settings.enabled then
		return
	end
	if
		Dread.step(dread, settings, dt, eligible(), Avatar.moving, Audio.threat(), math.random())
	then
		task.spawn(play)
	end
end

function Scare.start()
	State.onLevel(function()
		stop()
		-- Only a level proper holds one; the lit rooms and stairwells in between do not.
		if State.server.stage == "level" then
			Dread.enterLevel(dread, settings, State.server.tier, math.random())
		else
			dread.armed = false
		end
	end)
	State.onState(function(server)
		if running and server.stage ~= "level" then
			stop()
		end
	end)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal(DEV_ATTRIBUTE):Connect(function()
			if workspace:GetAttribute(DEV_ATTRIBUTE) ~= nil and State.server.stage == "level" then
				task.spawn(play)
			end
		end)
	end
	RunService.Heartbeat:Connect(update)
	player.CharacterAdded:Connect(stop)
end

return Scare
