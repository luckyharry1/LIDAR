--!strict
-- Sound is half of the LIDAR mechanic: you hear the dark before you see it.
--  * Scan ticks, pitched by how far the dots landed, with a different tone per dot class.
--  * A low drone and a heartbeat that rise as an enemy gets close.
--  * Positional enemy sounds, each kind distinct: Wanderers shuffle, Listeners click,
--    Stalkers hiss only while they move (so only while you are not looking), Mimics are
--    silent until revealed, and real stranded surveyors tap on the wall.
-- Every clip is one of a handful that ship inside the Roblox client (see Config.Audio),
-- reshaped with playback speed and equalisation, so the game needs no uploaded audio.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local Lidar = require(script.Parent.Lidar)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

type EnemyVoice = { model: Model, kind: string, loop: Sound?, click: Sound?, nextClick: number }
type Tapper = { part: BasePart, sound: Sound, nextTap: number }

local audio = Config.Audio
local TICK_VOICES = 6
local NEAR_PITCH, FAR_PITCH = 1.7, 0.75 -- scan tick pitch for the closest and farthest dots
local THREAT_HZ = 8
local DRONE_SPEED_CALM, DRONE_SPEED_TENSE = 0.3, 0.46
local HEART_SLOW, HEART_FAST = 1.15, 0.42 -- seconds per beat
local HEART_GAP = 0.16 -- between the two thumps of one beat
local WANDERER_RANGE = 75
local LISTENER_RANGE = 85
local STALKER_RANGE = 60
local TAP_RANGE = 70
local TAP_PATTERN = { 0, 0.22, 0.75 } -- tap, tap ... tap
local TAP_PERIOD = 2.8
local LIT_FADE_PER_SECOND = 1.2

local Audio = {}

local group = Instance.new("SoundGroup")
group.Name = "Lidar"
local holder = Instance.new("Folder")
holder.Name = "LidarAudio"

local tickVoices: { Sound } = {}
local nextTick = 1
local tickTimer = 0
local drone: Sound
local heartA: Sound
local heartB: Sound
local heartTimer = 0
local threat = 0 -- 0 calm, 1 an enemy is on top of you
local litMix = 0
local voices: { [Model]: EnemyVoice } = {}
local tappers: { [Instance]: Tapper } = {}
local threatTimer = 0
local lit = false

local function make(
	parent: Instance,
	id: string,
	volume: number,
	speed: number,
	looped: boolean
): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.Looped = looped
	sound.SoundGroup = group
	sound.Parent = parent
	return sound
end

local function positional(sound: Sound, maxDistance: number)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = maxDistance
end

-- One-shot interface sounds, all from the same short tick so the game has one voice.
function Audio.blip(speed: number, volume: number)
	local voice = tickVoices[nextTick]
	nextTick = nextTick % TICK_VOICES + 1
	voice.PlaybackSpeed = speed
	voice.Volume = volume
	voice:Play()
end

function Audio.sequence(speeds: { number }, gap: number, volume: number)
	task.spawn(function()
		for _, speed in speeds do
			Audio.blip(speed, volume)
			task.wait(gap)
		end
	end)
end

function Audio.click()
	Audio.blip(1.5, 0.3)
end

function Audio.pickup()
	Audio.sequence({ 1.4, 1.9 }, 0.09, 0.5)
end

function Audio.levelCleared()
	Audio.sequence({ 1.0, 1.25, 1.5, 2.0 }, 0.12, 0.5)
end

function Audio.relief()
	Audio.sequence({ 1.3, 1.1, 0.9 }, 0.22, 0.35)
end

function Audio.overheat()
	local thud = make(holder, audio.thud, 0.5, 0.6, false)
	thud:Play()
	thud.Ended:Once(function()
		thud:Destroy()
	end)
end

function Audio.caught()
	local rumble = make(holder, audio.rumble, 0.8, 0.45, false)
	rumble:Play()
	rumble.Ended:Once(function()
		rumble:Destroy()
	end)
end

local function onBatch(
	_count: number,
	meanDistance: number,
	enemy: boolean,
	friend: boolean,
	objective: boolean
)
	if tickTimer > 0 then
		return
	end
	tickTimer = audio.tickInterval
	local t = math.clamp(meanDistance / Config.Lidar.maxRange, 0, 1)
	local pitch = NEAR_PITCH + (FAR_PITCH - NEAR_PITCH) * t
	if enemy then
		Audio.blip(0.5, audio.tickVolume * 2.6) -- low and wrong
	elseif friend then
		Audio.blip(2.3, audio.tickVolume * 1.4)
	elseif objective then
		Audio.blip(1.95, audio.tickVolume * 1.5)
	else
		Audio.blip(pitch * (0.96 + math.random() * 0.08), audio.tickVolume)
	end
end

local function attachVoice(model: Instance)
	if not model:IsA("Model") or voices[model] ~= nil then
		return
	end
	local root = model.PrimaryPart or model:WaitForChild("Root", 5)
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local kind = model:GetAttribute("Kind")
	local voice: EnemyVoice = {
		model = model,
		kind = if type(kind) == "string" then kind else "",
		loop = nil,
		click = nil,
		nextClick = 0,
	}
	if voice.kind == "wanderer" or voice.kind == "mimic" then
		local loop = make(root, audio.steps, 0, if voice.kind == "mimic" then 1.35 else 0.62, true)
		positional(loop, WANDERER_RANGE)
		loop:Play()
		voice.loop = loop
	elseif voice.kind == "stalker" then
		local loop = make(root, audio.air, 0, 1.7, true)
		positional(loop, STALKER_RANGE)
		loop:Play()
		voice.loop = loop
	elseif voice.kind == "listener" then
		local click = make(root, audio.tick, 0.9, 0.55, false)
		positional(click, LISTENER_RANGE)
		voice.click = click
	end
	voices[model] = voice
end

local function attachTapper(model: Instance)
	if not model:IsA("Model") or tappers[model] ~= nil then
		return
	end
	local part = model.PrimaryPart or model:WaitForChild("Root", 5)
	if part == nil or not part:IsA("BasePart") then
		return
	end
	local sound = make(part, audio.thud, 0.55, 1.5, false)
	positional(sound, TAP_RANGE)
	tappers[model] =
		{ part = part, sound = sound, nextTap = os.clock() + math.random() * TAP_PERIOD }
end

local function updateVoices(now: number, dt: number)
	for model, voice in voices do
		if model.Parent == nil then
			voices[model] = nil
			continue
		end
		local moving = model:GetAttribute("Moving") == true
		local loop = voice.loop
		if loop then
			local target = 0
			if voice.kind == "wanderer" then
				target = if moving then 0.55 else 0
			elseif voice.kind == "stalker" then
				target = if moving then 0.5 else 0
			elseif voice.kind == "mimic" then
				local disguised = CollectionService:HasTag(model, Config.Tags.disguised)
				target = if moving and not disguised then 0.7 else 0
			end
			loop.Volume += (target - loop.Volume) * math.min(1, dt * 6)
		end
		local click = voice.click
		if click and now >= voice.nextClick then
			click.PlaybackSpeed = 0.5 + math.random() * 0.15
			click:Play()
			-- Slow, patient clicks while it drifts; quick ones while it hunts.
			voice.nextClick = now
				+ (if moving then 0.28 + math.random() * 0.2 else 1.1 + math.random() * 1.4)
		end
	end
	for model, tapper in tappers do
		if model.Parent == nil then
			tappers[model] = nil
			continue
		end
		if now >= tapper.nextTap then
			tapper.nextTap = now + TAP_PERIOD + math.random()
			task.spawn(function()
				local last = 0
				for _, offset in TAP_PATTERN do
					task.wait(offset - last)
					last = offset
					if tapper.sound.Parent then
						tapper.sound:Play()
					end
				end
			end)
		end
	end
end

local function measureThreat(): number
	local camera = workspace.CurrentCamera
	if camera == nil or not State.inLevel() then
		return 0
	end
	local nearest = math.huge
	local position = camera.CFrame.Position
	for model in voices do
		local root = model.PrimaryPart
		if root then
			nearest = math.min(nearest, (root.Position - position).Magnitude)
		end
	end
	return math.clamp(1 - nearest / audio.heartbeatDistance, 0, 1)
end

local function update(dt: number)
	local now = os.clock()
	tickTimer -= dt

	threatTimer -= dt
	if threatTimer <= 0 then
		threatTimer = 1 / THREAT_HZ
		threat = measureThreat()
	end
	litMix = math.clamp(litMix + (if lit then 1 else -1) * LIT_FADE_PER_SECOND * dt, 0, 1)
	local dark = 1 - litMix
	local active = State.server.stage ~= "title"

	-- Drone: always there in the dark, heavier and higher as something closes in.
	local droneTarget = if active
		then audio.droneVolume * (0.55 + 1.1 * threat) * dark
		else audio.droneVolume * 0.4
	drone.Volume += (droneTarget - drone.Volume) * math.min(1, dt * 2)
	drone.PlaybackSpeed = DRONE_SPEED_CALM + (DRONE_SPEED_TENSE - DRONE_SPEED_CALM) * threat

	-- Heartbeat: lub-dub, faster and louder with threat, silent when nothing is near.
	heartTimer -= dt
	if threat > 0.02 and dark > 0.5 and heartTimer <= 0 then
		heartTimer = HEART_SLOW + (HEART_FAST - HEART_SLOW) * threat
		local volume = audio.heartbeatVolume * (0.25 + 0.75 * threat)
		heartA.Volume = volume
		heartB.Volume = volume * 0.7
		heartA:Play()
		task.delay(HEART_GAP, function()
			heartB:Play()
		end)
	end

	updateVoices(now, dt)
	group.Volume = audio.masterVolume * State.profile.settings.volume
end

-- Lit rooms are quiet: the drone and heartbeat fade out and a small falling phrase plays.
function Audio.setLit(value: boolean)
	if value and not lit then
		Audio.relief()
	end
	lit = value
end

function Audio.threat(): number
	return threat
end

function Audio.start()
	group.Parent = SoundService
	holder.Parent = SoundService
	for index = 1, TICK_VOICES do
		tickVoices[index] = make(holder, audio.tick, audio.tickVolume, 1, false)
	end
	drone = make(holder, audio.air, 0, DRONE_SPEED_CALM, true)
	local equalizer = Instance.new("EqualizerSoundEffect")
	equalizer.HighGain = -40
	equalizer.MidGain = -14
	equalizer.LowGain = 5
	equalizer.Parent = drone
	drone:Play()
	heartA = make(holder, audio.thud, 0, 0.55, false)
	heartB = make(holder, audio.thud, 0, 0.48, false)

	Lidar.onBatch(onBatch)
	Ui.onClick(Audio.click)

	for _, model in CollectionService:GetTagged(Config.Tags.enemy) do
		task.spawn(attachVoice, model)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.enemy):Connect(function(model)
		task.spawn(attachVoice, model)
	end)
	for _, model in CollectionService:GetTagged(Config.Tags.rescue) do
		task.spawn(attachTapper, model)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.rescue):Connect(function(model)
		task.spawn(attachTapper, model)
	end)

	RunService.Heartbeat:Connect(update)
end

return Audio
