--!strict
-- Sound is half of the LIDAR mechanic: you hear the dark before you see it.
--  * Scan ticks, pitched by how far the dots landed, with a different tone per dot class;
--    a falling run of ticks for the sweep and a soft ping for the Pulse Radar.
--  * A low room tone and dripping water underneath everything in the dark, and far-off
--    bumps from random directions, so silence is never quite silent.
--  * Breathing and a heartbeat that rise as a monster gets close, and a low sting the first
--    time one arrives near you.
--  * Positional monster voices, each kind distinct: the Wanderer breathes and its steps are
--    heavy, the Listener clicks, the Stalker whines only while it moves (so only while nobody
--    is looking), and the Mimic is silent until it is revealed. Real stranded surveyors tap
--    on the wall: two taps, a wait, one.
-- Clips are listed in Config.Audio; every sound, including the ones the server makes, plays
-- through one group so the volume setting covers all of it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Avatar = require(script.Parent.Avatar)
local Config = require(ReplicatedStorage.Shared.Config)
local Lidar = require(script.Parent.Lidar)
local Reach = require(script.Parent.Reach)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

type EnemyVoice = { model: Model, root: BasePart, kind: string, loop: Sound? }
type Tapper = { part: BasePart, sound: Sound, nextTap: number }

local audio = Config.Audio
local TICK_VOICES = 6
local EMITTERS = 8 -- pooled invisible parts for one-shot positional sounds
local NEAR_PITCH, FAR_PITCH = 1.7, 0.75 -- scan tick pitch for the closest and farthest dots
local THREAT_HZ = 8
local VOICE_RANGE = 80
local STEP_RANGE = 70
local TAP_RANGE = 70
local TAP_PATTERN = { 0, 0.22, 0.75 } -- tap, tap ... tap
local TAP_PERIOD = 2.8
local BUMP_DISTANCE = 45 -- studs from the listener a distant bump is placed
local LIT_FADE_PER_SECOND = 1.2
local SWEEP_TICKS = 9
local ONE_SHOT_MAX_SECONDS = 12
local HEART_SPEED_CALM, HEART_SPEED_TENSE = 0.85, 1.45
local STEP_SPEED: { [string]: number } =
	{ wanderer = 0.85, listener = 1.35, stalker = 0.7, mimic = 1.2 }
local STEP_VOLUME: { [string]: number } =
	{ wanderer = 0.9, listener = 0.45, stalker = 1, mimic = 0.8 }

local Audio = {}

local group = Instance.new("SoundGroup")
group.Name = "Lidar"
local holder = Instance.new("Folder")
holder.Name = "LidarAudio"
local emitterFolder = Instance.new("Folder")
emitterFolder.Name = "LidarAudioEmitters"

local tickVoices: { Sound } = {}
local nextTick = 1
local tickTimer = 0
local ambience: Sound
local drips: Sound
local presence: Sound
local heartbeat: Sound
local wade: Sound
local emitters: { { part: Part, sound: Sound } } = {}
local nextEmitter = 1
local threat = 0 -- 0 calm, 1 a monster is on top of you
local nearest = math.huge
local litMix = 0
local voices: { [Model]: EnemyVoice } = {}
local tappers: { [Instance]: Tapper } = {}
local threatTimer = 0
local bumpTimer = 0
local stingArmedAt = 0
local stingNear = false
local lit = false
local equalizer: EqualizerSoundEffect
local muffled = false -- the world goes dull and far away while a level is left behind
local muffleMix = 0
local moodSpeed, moodDrips = 1, 1
local moodReverb = Enum.ReverbType.NoReverb
local MUFFLE_PER_SECOND = 0.9

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

-- A one-shot (non-positional) clip that cleans up after itself.
local function oneShot(id: string, volume: number, speed: number)
	if id == "" then
		return
	end
	local sound = make(holder, id, volume, speed, false)
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	-- A clip that never loads never ends: clean it up anyway.
	task.delay(ONE_SHOT_MAX_SECONDS, function()
		if sound.Parent ~= nil then
			sound:Destroy()
		end
	end)
	sound:Play()
end

-- A one-shot clip played from a point in the world, through a small pool of emitters.
local function playAt(position: Vector3, id: string, volume: number, speed: number, range: number)
	if id == "" then
		return
	end
	local emitter = emitters[nextEmitter]
	nextEmitter = nextEmitter % EMITTERS + 1
	emitter.part.Position = position
	local sound = emitter.sound
	sound:Stop()
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.RollOffMaxDistance = range
	sound:Play()
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

function Audio.caught()
	oneShot(audio.caughtRoar, 0.9, 1)
	oneShot(audio.rumble, 0.5, 0.45)
end

-- Studs from the camera to the nearest monster that is not pretending to be one of ours;
-- math.huge when there is none.
function Audio.nearestEnemy(): number
	return nearest
end

-- One footstep of a monster, at the footprint Presence just placed.
function Audio.monsterStep(kind: string, position: Vector3)
	playAt(
		position,
		audio.wandererStep,
		STEP_VOLUME[kind] or 0.8,
		(STEP_SPEED[kind] or 1) * (0.94 + math.random() * 0.12),
		STEP_RANGE
	)
end

-- An alarm plate went off: the crew's bell, loud, from where it rang.
function Audio.alarm(position: Vector3)
	task.spawn(function()
		for _ = 1, 4 do
			playAt(position, audio.ping, 1, 0.62, 160)
			task.wait(0.32)
		end
	end)
end

-- The local player fell into a pit.
function Audio.fall()
	oneShot(audio.air, 0.8, 1.1)
	task.delay(0.6, function()
		oneShot(audio.thud, 0.9, 0.55)
	end)
end

-- A hidden recorder revealed itself: a click, then the tape starts.
function Audio.echo(position: Vector3)
	playAt(position, audio.tick, 0.8, 0.55, 60)
	Audio.sequence({ 0.8, 0.95, 1.1 }, 0.09, 0.35)
end

-- The exit opened.
function Audio.door()
	oneShot(audio.door, 0.8, 1)
end

-- Lit rooms are quiet: the dark's sounds fade out and a small falling phrase plays.
function Audio.setLit(value: boolean)
	if value and not lit then
		Audio.relief()
	end
	lit = value
end

-- Per-floor sound: the ambience's pitch, how much the drips carry, and the room's echo.
function Audio.setMood(speed: number, dripScale: number, reverb: Enum.ReverbType)
	moodSpeed, moodDrips, moodReverb = speed, dripScale, reverb
end

-- Dulls everything (a lowpass) while the screen goes black between levels.
function Audio.muffle(on: boolean)
	muffled = on
end

-- A low hit as a new place comes up out of the black: heavy for a level, soft for a haven.
function Audio.arrive(haven: boolean)
	if haven then
		Audio.relief()
	else
		oneShot(audio.rumble, 0.5, 0.5)
	end
end

-- A faint tone from a point of interest the player has found: it draws the ear to it.
function Audio.poiHum(position: Vector3)
	playAt(position, audio.ping, 0.14, 0.5, 45)
end

-- Something is wrong somewhere out of sight. `kind` picks the sound; `position` is where it
-- seems to come from.
function Audio.wrong(kind: string, position: Vector3)
	if kind == "door" then
		playAt(position, audio.door, 0.7, 0.7, 120)
	elseif kind == "run" then
		task.spawn(function()
			for _ = 1, 7 do
				playAt(position, audio.wandererStep, 0.6, 1.5, 100)
				task.wait(0.22)
			end
		end)
	elseif kind == "crackle" then
		task.spawn(function()
			for _ = 1, 9 do
				playAt(position, audio.tick, 0.5, 0.4 + math.random() * 1.6, 70)
				task.wait(0.04 + math.random() * 0.06)
			end
		end)
	else
		playAt(position, audio.bumps, 0.8, 0.8 + math.random() * 0.4, 120)
	end
end

function Audio.threat(): number
	return threat
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

-- The sweep: a run of ticks that falls in pitch as the line travels down the view. It is
-- meant to sound loud, because to anything listening it is.
local function onSweep()
	local speeds = {}
	for index = 1, SWEEP_TICKS do
		speeds[index] = 2.1 - (index - 1) / (SWEEP_TICKS - 1) * 1.2
	end
	Audio.sequence(speeds, Config.Lidar.sweepSeconds / SWEEP_TICKS, audio.tickVolume * 3)
	oneShot(audio.air, 0.35, 2.4)
end

local function onRadar()
	oneShot(audio.ping, 0.18, 0.7)
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
		root = root,
		kind = if type(kind) == "string" then kind else "",
		loop = nil,
	}
	local id, speed = "", 1
	if voice.kind == "wanderer" then
		id, speed = audio.wandererVoice, 1
	elseif voice.kind == "listener" then
		id, speed = audio.listenerVoice, 1
	elseif voice.kind == "stalker" then
		id, speed = audio.stalkerVoice, 1
	elseif voice.kind == "mimic" then
		id, speed = audio.wandererVoice, 1.4
	end
	if id ~= "" then
		local loop = make(root, id, 0, speed, true)
		positional(loop, VOICE_RANGE)
		loop:Play()
		voice.loop = loop
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

-- Server-made loops (the waterfall, machinery) go through the same volume setting.
local function adoptSound(instance: Instance)
	if instance:IsA("Sound") then
		instance.SoundGroup = group
	end
end

local function updateVoices(now: number, dt: number)
	for model, voice in voices do
		if model.Parent == nil then
			voices[model] = nil
			continue
		end
		local moving = model:GetAttribute("Moving") == true
		local frozen = model:GetAttribute("Frozen") == true
		local loop = voice.loop
		if loop then
			local target = 0
			if voice.kind == "wanderer" then
				target = if moving then 0.6 else 0.3 -- it breathes even when it stops
			elseif voice.kind == "listener" then
				target = if moving then 0.75 else 0.35
			elseif voice.kind == "stalker" then
				target = if moving and not frozen then 0.7 else 0
			elseif voice.kind == "mimic" then
				local disguised = CollectionService:HasTag(model, Config.Tags.disguised)
				target = if moving and not disguised then 0.7 else 0
			end
			loop.Volume += (target - loop.Volume) * math.min(1, dt * 6)
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

local function measureNearest(): number
	local camera = workspace.CurrentCamera
	if camera == nil or not State.inLevel() then
		return math.huge
	end
	local closest = math.huge
	local position = camera.CFrame.Position
	for model, voice in voices do
		-- A Mimic that is still pretending gives nothing away: no breath, no heartbeat.
		if not CollectionService:HasTag(model, Config.Tags.disguised) then
			closest = math.min(closest, Reach.distance(position, voice.root.Position))
		end
	end
	return closest
end

-- A far-off bump from a random direction, now and then.
local function bump()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local angle = math.random() * math.pi * 2
	local offset = Vector3.new(math.cos(angle), (math.random() - 0.5) * 0.4, math.sin(angle))
	playAt(
		camera.CFrame.Position + offset * BUMP_DISTANCE,
		audio.bumps,
		0.7,
		0.85 + math.random() * 0.3,
		BUMP_DISTANCE * 3
	)
end

local function fadeTo(sound: Sound, target: number, dt: number, rate: number)
	sound.Volume += (target - sound.Volume) * math.min(1, dt * rate)
end

local function update(dt: number)
	local now = os.clock()
	tickTimer -= dt

	threatTimer -= dt
	if threatTimer <= 0 then
		threatTimer = 1 / THREAT_HZ
		nearest = measureNearest()
		threat = math.clamp(1 - nearest / audio.heartbeatDistance, 0, 1)
		-- The sting: a low hit the first time something arrives close, then a rest.
		local near = nearest <= audio.stingDistance
		if near and not stingNear and now >= stingArmedAt and litMix < 0.5 then
			stingArmedAt = now + audio.stingRearmSeconds
			oneShot(audio.rumble, 0.4, 0.6)
		end
		stingNear = near
	end
	litMix = math.clamp(litMix + (if lit then 1 else -1) * LIT_FADE_PER_SECOND * dt, 0, 1)
	local dark = 1 - litMix
	local playing = State.server.stage ~= "title"
	local inDark = if playing then dark else 0.5

	fadeTo(ambience, audio.ambienceVolume * inDark, dt, 2)
	fadeTo(drips, audio.dripsVolume * inDark * moodDrips, dt, 2)
	ambience.PlaybackSpeed += (moodSpeed - ambience.PlaybackSpeed) * math.min(1, dt * 0.5)
	muffleMix = math.clamp(muffleMix + (if muffled then 1 else -1) * MUFFLE_PER_SECOND * dt, 0, 1)
	equalizer.HighGain = -muffleMix * 28
	equalizer.MidGain = -muffleMix * 8
	local reverb = if lit then Enum.ReverbType.LivingRoom else moodReverb
	if SoundService.AmbientReverb ~= reverb then
		SoundService.AmbientReverb = reverb
	end
	fadeTo(presence, audio.presenceVolume * threat * dark, dt, 3)
	fadeTo(heartbeat, audio.heartbeatVolume * threat * dark, dt, 3)
	heartbeat.PlaybackSpeed = HEART_SPEED_CALM + (HEART_SPEED_TENSE - HEART_SPEED_CALM) * threat
	fadeTo(wade, if Avatar.wading and Avatar.moving then 0.5 else 0, dt, 5)

	if playing and State.inLevel() and dark > 0.5 then
		bumpTimer -= dt
		if bumpTimer <= 0 then
			local range = audio.bumpSeconds
			bumpTimer = range[1] + math.random() * (range[2] - range[1])
			bump()
		end
	end

	updateVoices(now, dt)
	group.Volume = audio.masterVolume * State.profile.settings.volume
end

function Audio.start()
	group.Parent = SoundService
	equalizer = Instance.new("EqualizerSoundEffect")
	equalizer.Parent = group
	holder.Parent = SoundService
	emitterFolder.Parent = workspace
	for index = 1, TICK_VOICES do
		tickVoices[index] = make(holder, audio.tick, audio.tickVolume, 1, false)
	end
	for index = 1, EMITTERS do
		local part = Instance.new("Part")
		part.Name = "Emitter"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.one * 0.2
		part.Parent = emitterFolder
		local sound = make(part, "", 0, 1, false)
		positional(sound, 80)
		emitters[index] = { part = part, sound = sound }
	end
	ambience = make(holder, audio.ambience, 0, 1, true)
	drips = make(holder, audio.drips, 0, 1, true)
	presence = make(holder, audio.presence, 0, 1, true)
	heartbeat = make(holder, audio.heartbeat, 0, HEART_SPEED_CALM, true)
	wade = make(holder, audio.wade, 0, 0.9, true)
	for _, loop in { ambience, drips, presence, heartbeat, wade } do
		if loop.SoundId ~= "" then
			loop:Play()
		end
	end
	bumpTimer = audio.bumpSeconds[1]

	Lidar.onBatch(onBatch)
	Lidar.onSweep(onSweep)
	Lidar.onRadar(onRadar)
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
	for _, sound in CollectionService:GetTagged(Config.Tags.sound) do
		adoptSound(sound)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.sound):Connect(adoptSound)

	RunService.Heartbeat:Connect(update)
end

return Audio
